import unittest
from fios_agent.web.pages import parse_document


class ParserTests(unittest.IsolatedAsyncioTestCase):
    async def test_main_text_ignores_active_hidden_content(self):
        doc=b'<html><body><nav>ignore nav</nav><main>Hello <script>steal secrets</script><p>Python release</p><div hidden>hidden</div></main></body></html>'
        result=await parse_document(doc,'page')
        self.assertIn('Python release',result['text'])
        self.assertNotIn('steal',result['text'])
        self.assertNotIn('hidden',result['text'])
        self.assertNotIn('ignore nav',result['text'])

    async def test_organic_and_challenge_are_distinct(self):
        doc=b'<div class="result"><a class="result__a" href="https://www.python.org/">Python</a><a class="result__snippet">Official release notes</a></div>'
        result=await parse_document(doc,'provider')
        self.assertEqual(result['state'],'results')
        self.assertEqual(result['results'][0]['title'],'Python')
        self.assertEqual(result['results'][0]['snippet'],'Official release notes')
        result=await parse_document(b'<form id="challenge-form">Confirm human</form>','provider')
        self.assertEqual(result['state'],'blocked')
        result=await parse_document(b'<html>unknown layout</html>','provider')
        self.assertEqual(result['state'],'unavailable')

    async def test_parser_bound(self):
        with self.assertRaises(ValueError): await parse_document(b'x'*(1048576+1),'page')
        with self.assertRaises(ValueError): await parse_document(b'hello','exec')
