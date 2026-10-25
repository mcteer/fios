"""Strict ephemeral evidence and safe persistence contracts; no network operations."""
import hashlib
import json
import re
from typing import Literal
from uuid import UUID
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, StrictBool, StrictInt, StrictStr, field_validator, model_validator
def utf16_length(text):
    return len(text.encode('utf-16-le')) // 2

MAX_TIME = 9007199254740991
REASONS = {
    'pending': None, 'not_requested': 'no_tool_call', 'disabled': 'operator_disabled',
    'privacy_skipped': 'privacy_policy', 'retrieved': 'page_evidence',
    'partial': 'partial_evidence', 'snippets_only': 'snippet_evidence',
    'empty': 'no_results', 'blocked': 'provider_blocked', 'rate_limited': 'rate_limit',
    'timeout': 'tool_timeout', 'unavailable': 'retrieval_unavailable',
    'context_limit': 'context_budget', 'cancelled': 'run_cancelled', 'error': 'tool_error',
}
EVIDENCE = {'retrieved', 'partial', 'snippets_only'}
TOOL_OUTCOMES = EVIDENCE | {'empty','blocked','rate_limited','timeout','unavailable','privacy_skipped','context_limit'}
Outcome = Literal['pending','not_requested','disabled','privacy_skipped','retrieved','partial',
                  'snippets_only','empty','blocked','rate_limited','timeout','unavailable',
                  'context_limit','cancelled','error']


class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True, frozen=True)


def bounded(value, limit):
    # Reject lone surrogates as well as oversized UTF-16 input.
    value.encode('utf-8', errors='strict')
    if utf16_length(value) > limit:
        raise ValueError('text_limit')
    return value


def timestamp(value):
    if value is not None and not 0 <= value <= MAX_TIME:
        raise ValueError('timestamp_limit')
    return value


class RunSearchInput(StrictModel):
    current_text: StrictStr | None
    current_has_attachments: StrictBool
    previous_text: StrictStr | None
    previous_has_attachments: StrictBool
    current_elided: StrictBool
    previous_elided: StrictBool

    @field_validator('current_text','previous_text')
    @classmethod
    def text_limit(cls, value):
        return bounded(value, 2000) if value is not None else None

    @model_validator(mode='after')
    def elision(self):
        if (self.current_elided and self.current_text is not None) or (self.previous_elided and self.previous_text is not None):
            raise ValueError('elision_mismatch')
        return self


class SearchRunState(StrictModel):
    """Validated snapshot; lifecycle owner replaces it on each bounded transition.

    This carries no query, call ID or evidence text and is not a substitute
    for the eventual atomic tool/HTTP dispatch latch.
    """
    run_id: UUID
    model: StrictStr
    tool_attempts: StrictInt
    model_posts: StrictInt
    step: StrictInt

    @model_validator(mode='after')
    def counters(self):
        if not self.model or len(self.model.encode('utf-8')) > 1024:
            raise ValueError('model_limit')
        if not 0 <= self.tool_attempts <= 1 or not 0 <= self.model_posts <= 2 or self.step not in (1,2):
            raise ValueError('run_budget')
        if (self.model_posts == 2 or self.step == 2) and self.tool_attempts != 1:
            raise ValueError('unauthorized_continuation')
        return self


class SearchQuery(StrictModel):
    query: StrictStr

    @field_validator('query')
    @classmethod
    def limit(cls, value):
        bounded(value,256)
        if not value.strip() or len(value.split()) > 12:
            raise ValueError('query_limit')
        return value


class SafeSource(StrictModel):
    id: Literal['S1','S2','S3','S4','S5']
    url: StrictStr
    title: StrictStr
    kind: Literal['page','snippet']
    retrieved_at: StrictInt
    excerpt_sha256: StrictStr
    excerpt_units: StrictInt
    truncated: StrictBool

    @field_validator('url')
    @classmethod
    def url_shape(cls,value):
        bounded(value,2048)
        if any(ord(c)<33 or ord(c)==127 for c in value) or '\\' in value:
            raise ValueError('unsafe_url')
        u=urlsplit(value)
        if u.scheme not in ('http','https') or not u.hostname or u.username is not None or u.password is not None or u.fragment:
            raise ValueError('unsafe_url')
        if u.port not in (None,80 if u.scheme=='http' else 443):
            raise ValueError('unsafe_url')
        return value  # Public DNS/socket validation belongs to the retrieval transport.

    @field_validator('title')
    @classmethod
    def title_limit(cls,value):
        return bounded(value,300)

    @field_validator('retrieved_at')
    @classmethod
    def time_limit(cls,value):
        return timestamp(value)

    @field_validator('excerpt_sha256')
    @classmethod
    def hash_shape(cls,value):
        if re.fullmatch('[0-9a-f]{64}',value) is None:
            raise ValueError('invalid_hash')
        return value

    @field_validator('excerpt_units')
    @classmethod
    def units_limit(cls,value):
        if not 0<=value<=3000:
            raise ValueError('excerpt_limit')
        return value


class Source(SafeSource):
    excerpt: StrictStr

    @model_validator(mode='after')
    def excerpt_identity(self):
        bounded(self.excerpt,3000)
        if utf16_length(self.excerpt)!=self.excerpt_units or hashlib.sha256(self.excerpt.encode()).hexdigest()!=self.excerpt_sha256:
            raise ValueError('excerpt_identity')
        return self


def evidence_check(obj):
    if obj.reason != REASONS[obj.outcome]:
        raise ValueError('reason_mismatch')
    if len(obj.sources)>5 or [s.id for s in obj.sources]!=[f'S{i+1}' for i in range(len(obj.sources))]:
        raise ValueError('source_ids')
    timestamp(obj.retrieved_at)
    if bool(obj.sources)!=(obj.outcome in EVIDENCE):
        raise ValueError('outcome_sources')
    expected=max((s.retrieved_at for s in obj.sources),default=None)
    if obj.retrieved_at!=expected:
        raise ValueError('retrieval_time')
    kinds={s.kind for s in obj.sources}
    if obj.outcome=='retrieved' and kinds!={'page'}:
        raise ValueError('evidence_kind')
    if obj.outcome=='snippets_only' and kinds!={'snippet'}:
        raise ValueError('evidence_kind')
    if obj.outcome=='partial' and 'page' not in kinds:
        raise ValueError('evidence_kind')
    if len(json.dumps(obj.model_dump(),ensure_ascii=False,separators=(',',':')).encode())>65536:
        raise ValueError('manifest_limit')
    return obj


class ToolResult(StrictModel):
    v: StrictInt
    outcome: Outcome
    reason: StrictStr | None
    retrieved_at: StrictInt | None
    sources: list[Source]

    @model_validator(mode='after')
    def valid(self):
        if self.v!=1 or self.outcome not in TOOL_OUTCOMES:
            raise ValueError('tool_result')
        return evidence_check(self)


class Manifest(StrictModel):
    v: StrictInt
    phase: Literal['idle','searching','fetching','finished']
    outcome: Outcome
    reason: StrictStr | None
    tool_attempted: StrictBool
    evidence_state: Literal['none','retrieved_only','sent_to_model']
    retrieved_at: StrictInt | None
    sources: list[SafeSource]

    @model_validator(mode='after')
    def valid(self):
        if self.v!=1 or (self.phase=='finished')==(self.outcome=='pending'):
            raise ValueError('phase_outcome')
        if self.phase in ('searching','fetching') and not self.tool_attempted:
            raise ValueError('phase_attempt')
        if self.phase=='idle' and self.tool_attempted:
            raise ValueError('idle_attempt')
        if self.outcome in ('disabled','not_requested') and self.tool_attempted:
            raise ValueError('unexpected_attempt')
        if self.outcome in EVIDENCE|{'empty','blocked','rate_limited','timeout','unavailable'} and not self.tool_attempted:
            raise ValueError('missing_attempt')
        if (self.evidence_state=='none')!= (not self.sources):
            raise ValueError('evidence_state')
        return evidence_check(self)


def validate_transition(before: Manifest, after: Manifest):
    """Raises on replay, regression, latch reset or provenance mutation."""
    if before==after or (before.tool_attempted and not after.tool_attempted):
        raise ValueError('invalid_transition')
    if before.phase=='finished':
        expected=before.model_copy(update={'evidence_state':'sent_to_model'})
        if before.evidence_state!='retrieved_only' or after!=expected:
            raise ValueError('immutable_manifest')
    elif (before.phase,after.phase) not in {
        ('idle','searching'),('idle','finished'),('searching','fetching'),
        ('searching','finished'),('fetching','finished'),
    }:
        raise ValueError('phase_transition')
    return after
