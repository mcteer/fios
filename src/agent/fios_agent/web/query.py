"""Conservative argument disclosure boundary, never an intent router.

Not perfect sensitive-prose detection. Attachments/assistant/page text never
supply eligibility, even when the model has legitimately seen them locally.
"""
import re
import unicodedata

from .types import SearchQuery

GENERIC=frozenset(('current','latest','official','documentation','release','releases','notes',
    'news','update','updates','version','versions','date','today','information','search','web',
    'the','a','an','of','for','and','in','on','about','is','what','when','how','to'))
# Deliberately reject, never redact-and-send. Overblocking is disclosed in UX.
PRIVATE=re.compile(r'(?i)(?:\b(?:private|confidential|secret|password|passwd|token|api[_ -]?key|authorization|bearer|cookie|ssh|credential)\b|https?://|www\.|\b[\w.+-]+@[\w.-]+\.[a-z]+\b|(?:\d{1,3}\.){3}\d{1,3}|localhost|\.local\b|\.lab\b|\.internal\b|(?:^|\s)[/~][\w./-]+|```|[{};=]|-----BEGIN|\b(?:sk|ghp|github_pat)[_-][A-Za-z0-9_-]+)')
TOKEN=re.compile(r"[^\W_]+(?:[.'-][^\W_]+)*",re.UNICODE)


def terms(text):
    normalized=unicodedata.normalize('NFKC',text)
    if any(unicodedata.category(c) in ('Cc','Cf','Cs') and c not in '\n\t\r' for c in normalized):
        raise ValueError('privacy_policy')
    if PRIVATE.search(normalized): raise ValueError('privacy_policy')
    result={s.casefold() for s in TOKEN.findall(normalized)}
    # Long opaque values and digit-heavy identifiers may be credentials/canaries.
    if any(len(t)>40 or (len(t)>16 and sum(c.isdigit() for c in t)>8) for t in result):
        raise ValueError('privacy_policy')
    return result


def eligible_terms(provenance):
    if (provenance is None or provenance.current_elided or provenance.current_has_attachments
        or not provenance.current_text or not provenance.current_text.strip()): return frozenset()
    try: current=terms(provenance.current_text)
    except ValueError: return frozenset()
    prior=set()
    if (provenance.previous_text and not provenance.previous_has_attachments and not provenance.previous_elided):
        try: prior=terms(provenance.previous_text)
        except ValueError: pass
    return frozenset(current|prior)


def validate_query(query,provenance):
    query=SearchQuery(query=query).query
    eligible=eligible_terms(provenance)
    if not eligible: raise ValueError('privacy_policy')
    proposed=terms(query)
    if (any(unicodedata.category(c) in ('Cc','Cf','Cs') for c in query)
        or re.fullmatch(r'\s*'+TOKEN.pattern+r'(?:\s+'+TOKEN.pattern+r')*\s*',query) is None
        or not proposed or not proposed <= eligible|GENERIC
        or not (proposed & (eligible-GENERIC))):
        raise ValueError('privacy_policy')
    return query
