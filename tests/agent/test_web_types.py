"""Strict search contracts; no provider/model network access."""
import hashlib
import json
from pathlib import Path
import unittest
from uuid import uuid4
from pydantic import ValidationError
from fios_agent.web.types import REASONS, RunSearchInput, SearchRunState, SearchQuery, Source, Manifest, ToolResult, validate_transition


def source():
    return dict(id='S1', url='https://www.python.org/doc/', title='Python', kind='page',
                retrieved_at=1234, excerpt='fixture evidence',
                excerpt_sha256=hashlib.sha256(b'fixture evidence').hexdigest(),
                excerpt_units=16, truncated=False)


def initial():
    return dict(v=1, phase='idle', outcome='pending', reason=None, tool_attempted=False,
                evidence_state='none', retrieved_at=None, sources=[])


class WebTypesTests(unittest.TestCase):
    def test_shared_fixture_reason_parity(self):
        fixture = json.loads((Path(__file__).resolve().parents[1] / 'fixtures/web/contracts.json').read_text())
        self.assertEqual(REASONS, fixture['status_reasons'])
        self.assertEqual(Manifest(**fixture['initial']).model_dump(), fixture['initial'])
        for outcome, reason in REASONS.items():
            if outcome in ('pending','retrieved','partial','snippets_only'):
                continue
            attempted = outcome in ('empty','blocked','rate_limited','timeout','unavailable')
            value = {**initial(), 'phase':'finished', 'outcome':outcome, 'reason':reason,
                     'tool_attempted':attempted}
            Manifest(**value)
            with self.assertRaises(ValidationError):
                Manifest(**{**value, 'reason':'untrusted raw exception'})

    def test_run_counter_and_exact_model_snapshot(self):
        value = dict(run_id=uuid4(), model='mlx/model@studio-a', tool_attempts=0, model_posts=1, step=1)
        self.assertEqual(SearchRunState(**value).model, value['model'])
        SearchRunState(**{**value, 'tool_attempts':1, 'model_posts':2, 'step':2})
        for patch in [dict(model_posts=3), dict(tool_attempts=2), dict(model_posts=True),
                      dict(model_posts=2), dict(step=2), dict(step=0), dict(model='é' * 513)]:
            with self.assertRaises(ValidationError):
                SearchRunState(**{**value, **patch})

    def test_query_utf16_and_strictness(self):
        self.assertEqual(SearchQuery(query='Python release notes').query, 'Python release notes')
        for q in ['', ' ', 'x ' * 13, 'x' * 257, '😀' * 129, 4, True]:
            with self.subTest(q=type(q).__name__), self.assertRaises(ValidationError):
                SearchQuery(query=q)
        with self.assertRaises(ValidationError):
            SearchQuery(query='Python', engine='other')

    def test_provenance_no_silent_truncation(self):
        good = dict(current_text='Python', current_has_attachments=False, previous_text=None,
                    previous_has_attachments=False, current_elided=False, previous_elided=False)
        RunSearchInput(**good)
        for patch in [dict(current_text='x' * 2001), dict(current_elided=True),
                      dict(current_has_attachments=0), dict(extra='private')]:
            with self.assertRaises(ValidationError):
                RunSearchInput(**{**good, **patch})

    def test_source_hash_lengths_and_url(self):
        Source(**source())
        for patch in [dict(excerpt_sha256='0' * 64), dict(excerpt_units=1),
                      dict(retrieved_at=True), dict(retrieved_at=None),
                      dict(title='😀' * 151), dict(url='file:///etc/passwd'),
                      dict(url='https://user:password@example.com/'), dict(extra='hidden')]:
            with self.assertRaises(ValidationError):
                Source(**{**source(), **patch})

    def test_manifest_empty_and_pending(self):
        Manifest(**initial())
        for patch in [dict(v=True), dict(outcome='not_requested'), dict(reason='raw exception'),
                      dict(retrieved_at=123), dict(evidence_state='sent_to_model'),
                      dict(phase='finished'), dict(tool_attempted=1)]:
            with self.assertRaises(ValidationError):
                Manifest(**{**initial(), **patch})

    def test_manifest_source_delivery_and_immutable_transition(self):
        safe = {k:v for k,v in source().items() if k != 'excerpt'}
        value = dict(v=1, phase='finished', outcome='retrieved', reason='page_evidence',
                     tool_attempted=True, evidence_state='retrieved_only', retrieved_at=1234,
                     sources=[safe])
        first = Manifest(**value)
        second = Manifest(**{**value, 'evidence_state':'sent_to_model'})
        validate_transition(first, second)
        with self.assertRaises(ValueError):
            validate_transition(second, first)
        changed = {**safe, 'title':'changed'}
        with self.assertRaises(ValueError):
            validate_transition(first, Manifest(**{**value, 'sources':[changed], 'evidence_state':'sent_to_model'}))
        for patch in [dict(retrieved_at=None), dict(retrieved_at=999), dict(sources=[]),
                      dict(sources=[{**safe, 'excerpt':'must not persist'}]),
                      dict(outcome='empty', reason='no_results')]:
            with self.assertRaises(ValidationError):
                Manifest(**{**value, **patch})

    def test_tool_result_failures_and_evidence(self):
        ToolResult(v=1, outcome='retrieved', reason='page_evidence', retrieved_at=1234, sources=[source()])
        ToolResult(v=1, outcome='timeout', reason='tool_timeout', retrieved_at=None, sources=[])
        for outcome, reason in [('pending', None), ('cancelled','run_cancelled'), ('error','tool_error')]:
            with self.assertRaises(ValidationError):
                ToolResult(v=1, outcome=outcome, reason=reason, retrieved_at=None, sources=[])

    def test_monotonic_phase_and_latch(self):
        a = Manifest(**initial())
        b = Manifest(**{**initial(), 'phase':'searching', 'tool_attempted':True})
        validate_transition(a,b)
        with self.assertRaises(ValueError):
            validate_transition(b,a)
        with self.assertRaises(ValueError):
            validate_transition(a,a)
