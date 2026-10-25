import json
from pathlib import Path
import unittest
from fios_agent.web.types import RunSearchInput
from fios_agent.web.query import validate_query, eligible_terms


def provenance(current,previous=None,attached=False):
    return RunSearchInput(current_text=current,previous_text=previous,current_has_attachments=attached,
        previous_has_attachments=False,current_elided=False,previous_elided=False)


class QueryTests(unittest.TestCase):
    def test_shared_cases(self):
        data=json.loads((Path(__file__).resolve().parents[1]/'fixtures/web/queries.json').read_text())
        for case in data['allowed']:
            self.assertEqual(validate_query(case['query'],provenance(case['current'],case.get('previous'))),case['query'])
        for case in data['denied']:
            with self.subTest(case=case),self.assertRaises(ValueError):
                validate_query(case['query'],provenance(case['current'],case.get('previous')))

    def test_attachments_never_eligible_and_no_generic_only_query(self):
        for p in [None,provenance('Python release',attached=True),provenance(None),provenance('```Python```')]:
            self.assertFalse(eligible_terms(p))
            with self.assertRaises(ValueError): validate_query('Python release',p)
        for query in ['latest official release','-Python release','"Python" release','Python OR release']:
            with self.assertRaises(ValueError):validate_query(query,provenance('Python release'))

    def test_prior_ineligible_text_not_exported(self):
        p=provenance('Python release','secret: attachmentcanary2026')
        with self.assertRaises(ValueError): validate_query('attachmentcanary2026 release',p)
        self.assertEqual(validate_query('Python release',p),'Python release')
