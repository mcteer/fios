import base64
import unittest
from pydantic_ai.messages import BinaryContent, UserPromptPart, TextPart
from fios_agent.context import translate_context
from fios_agent.protocol import ContextItem


def item(role, content):
    return ContextItem(role=role, content=content)


class ContextTests(unittest.TestCase):
    def test_history_and_current_prompt_not_duplicated(self):
        history, prompt = translate_context([item('user', 'old <attached-document>source</attached-document>'),
            item('assistant', 'old answer'), item('user', 'new prompt')])
        self.assertEqual(len(history), 2)
        self.assertEqual(history[0].parts[0].content, 'old <attached-document>source</attached-document>')
        self.assertIsInstance(history[0].parts[0], UserPromptPart)
        self.assertIsInstance(history[1].parts[0], TextPart)
        self.assertEqual(prompt, 'new prompt')

    def test_image_bytes_are_inline_and_validated(self):
        image = b'\x89PNG\r\n\x1a\n' + b'x' * 16
        parts = [{'type':'text','text':'look'}, {'type':'image_url','image_url':{
            'url':'data:image/png;base64,' + base64.b64encode(image).decode()}}]
        history, prompt = translate_context([item('user', parts)])
        self.assertEqual(history, [])
        self.assertIsInstance(prompt[1], BinaryContent)
        self.assertEqual(prompt[1].data, image)
        for url in ['https://example.test/a.png', 'data:image/png;base64,!!!!', 'data:image/jpeg;base64,eA==']:
            parts[1]['image_url']['url'] = url
            with self.assertRaises(ValueError):
                translate_context([item('user', parts)])

    def test_context_limit_uses_utf16_units(self):
        translate_context([item('user', '🧵' * 200000)])
        with self.assertRaises(ValueError):
            translate_context([item('user', '🧵' * 200001)])
