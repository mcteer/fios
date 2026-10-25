"""Translate the canonical Node context without storing a second transcript."""
import base64
import binascii
import re
from pydantic_ai.messages import BinaryContent, ModelRequest, ModelResponse, TextPart, UserPromptPart
from .protocol import utf16_length


class ContextError(ValueError):
    pass


def image_content(url):
    match = re.fullmatch(r'data:(image/(?:png|jpeg|webp|gif));base64,([A-Za-z0-9+/]*={0,2})', url)
    if not match:
        raise ContextError('Invalid image context.')
    mime, encoded = match.groups()
    if len(encoded) > ((10 * 1024 * 1024 + 2) // 3) * 4:
        raise ContextError('Image context exceeds limit.')
    try:
        data = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError):
        raise ContextError('Invalid image context.') from None
    valid = {
        'image/png': data.startswith(b'\x89PNG\r\n\x1a\n'),
        'image/jpeg': data.startswith(b'\xff\xd8\xff'),
        'image/gif': data.startswith((b'GIF87a', b'GIF89a')),
        'image/webp': data[:4] == b'RIFF' and data[8:12] == b'WEBP',
    }
    if not valid[mime] or len(data) > 10 * 1024 * 1024:
        raise ContextError('Invalid image context.')
    return BinaryContent(data=data, media_type=mime)


def translate_context(context):
    if not context or context[-1].role != 'user':
        raise ContextError('Invalid context.')
    history, current = [], None
    text_units = image_bytes = 0
    for index, item in enumerate(context):
        if isinstance(item.content, str):
            prompt = item.content
            text_units += utf16_length(prompt)
        else:
            prompt = []
            for part in item.content:
                if part.type == 'text':
                    text_units += utf16_length(part.text)
                    prompt.append(part.text)
                else:
                    image = image_content(part.image_url.url)
                    image_bytes += len(image.data)
                    prompt.append(image)
        if text_units > 400000 or image_bytes > 20 * 1024 * 1024:
            raise ContextError('Context exceeds limit.')
        if index == len(context) - 1:
            current = prompt
        elif item.role == 'user':
            history.append(ModelRequest(parts=[UserPromptPart(content=prompt)]))
        else:
            history.append(ModelResponse(parts=[TextPart(content=prompt)]))
    return history, current
