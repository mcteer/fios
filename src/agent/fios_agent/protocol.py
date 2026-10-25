"""Strict, bounded private JSON-lines protocol. Never include input in errors."""
from __future__ import annotations

import json
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, ValidationError, field_validator

REQUEST_LIMIT = 32 * 1024 * 1024
EVENT_LIMIT = 1024 * 1024
TEXT_CHUNK_UNITS = 32 * 1024
ERROR_CODES = (
    "busy", "invalid_request", "model_unavailable", "upstream_unavailable", "upstream_http",
    "upstream_timeout", "incomplete_stream", "invalid_stream",
    "unsupported_output", "output_limit", "internal_error",
)


class ProtocolError(ValueError):
    def __init__(self):
        super().__init__("Invalid agent protocol.")


def utf16_length(text: str) -> int:
    return len(text.encode("utf-16-le")) // 2


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class TextContent(StrictModel):
    type: Literal["text"]
    text: str


class ImageURL(StrictModel):
    url: str


class ImageContent(StrictModel):
    type: Literal["image_url"]
    image_url: ImageURL


ContentPart = Annotated[TextContent | ImageContent, Field(discriminator="type")]


class ContextItem(StrictModel):
    role: Literal["user", "assistant"]
    content: str | Annotated[list[ContentPart], Field(min_length=1)]

    @field_validator("content")
    @classmethod
    def assistant_is_text(cls, value, info):
        if info.data.get("role") == "assistant" and (not isinstance(value, str) or not value):
            raise ValueError("Invalid assistant content.")
        return value


class Envelope(StrictModel):
    v: Literal[1]

    @field_validator("v", mode="before")
    @classmethod
    def integer_version(cls, value):
        if type(value) is not int:
            raise ValueError("Invalid version.")
        return value


class Correlated(Envelope):
    run_id: str

    @field_validator("run_id")
    @classmethod
    def uuid_string(cls, value):
        if str(UUID(value)) != value:
            raise ValueError("Invalid run ID.")
        return value


class Run(Correlated):
    type: Literal["run"]
    model: str
    context: Annotated[list[ContextItem], Field(min_length=1)]

    @field_validator("model")
    @classmethod
    def exact_model(cls, value):
        if not value or len(value.encode("utf-8")) > 1024:
            raise ValueError("Invalid model ID.")
        return value

    @field_validator("context")
    @classmethod
    def final_user(cls, value):
        if value[-1].role != "user":
            raise ValueError("Invalid final role.")
        return value


class Cancel(Correlated):
    type: Literal["cancel"]


class Shutdown(Envelope):
    type: Literal["shutdown"]


class Ready(Envelope):
    type: Literal["ready"]


class Progress(Correlated):
    type: Literal["started", "activity"]


class Delta(Correlated):
    type: Literal["delta", "reasoning"]
    content: str

    @field_validator("content")
    @classmethod
    def chunk_bound(cls, value):
        if utf16_length(value) > TEXT_CHUNK_UNITS:
            raise ValueError("Chunk exceeded limit.")
        return value


class Done(Correlated):
    type: Literal["done"]
    status: Literal["complete", "interrupted"]


class Error(Correlated):
    type: Literal["error"]
    code: Literal[
        "busy", "invalid_request", "model_unavailable", "upstream_unavailable", "upstream_http",
        "upstream_timeout", "incomplete_stream", "invalid_stream",
        "unsupported_output", "output_limit", "internal_error",
    ]
    upstream_status: Annotated[int, Field(ge=400, le=599)] | None = None


_command = TypeAdapter(Annotated[Run | Cancel | Shutdown, Field(discriminator="type")])
_event = TypeAdapter(Annotated[Ready | Progress | Delta | Done | Error, Field(discriminator="type")])


def _parse(adapter, value):
    try:
        return adapter.validate_python(value)
    except (ValidationError, ValueError, TypeError, UnicodeError):
        raise ProtocolError() from None


def parse_command(value):
    return _parse(_command, value)


def parse_event(value):
    return _parse(_event, value)


def _unique_object(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ProtocolError()
        obj[key] = value
    return obj


class FrameDecoder:
    def __init__(self, limit: int):
        self.limit = limit
        self.buffer = bytearray()

    def feed(self, data: bytes):
        offset = 0
        while offset < len(data):
            end = data.find(b"\n", offset)
            boundary = len(data) if end < 0 else end
            # Permit a CR before LF, without relaxing the JSON-byte limit.
            segment = data[offset:boundary]
            if len(self.buffer) + len(segment) > self.limit + 1:
                raise ProtocolError()
            self.buffer.extend(segment)
            if end < 0:
                if len(self.buffer) > self.limit and not self.buffer.endswith(b"\r"):
                    raise ProtocolError()
                return
            raw = self.buffer.removesuffix(b"\r")
            self.buffer.clear()
            if not raw or len(raw) > self.limit:
                raise ProtocolError()
            try:
                value = json.loads(raw.decode("utf-8"), object_pairs_hook=_unique_object,
                                   parse_constant=lambda _: (_ for _ in ()).throw(ProtocolError()))
                if not isinstance(value, dict):
                    raise ProtocolError()
            except (ValueError, UnicodeError, RecursionError):
                raise ProtocolError() from None
            yield value
            offset = end + 1

    def finish(self):
        if self.buffer:
            raise ProtocolError()


def encode_frame(value, limit=EVENT_LIMIT) -> bytes:
    try:
        if isinstance(value, BaseModel):
            value = value.model_dump(exclude_none=True)
        raw = json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
        if len(raw) > limit:
            raise ProtocolError()
        return raw + b"\n"
    except (ValueError, TypeError, UnicodeError):
        raise ProtocolError() from None


def text_chunks(text: str):
    start = 0
    count = 0
    for index, character in enumerate(text):
        size = 2 if ord(character) > 0xFFFF else 1
        if count + size > TEXT_CHUNK_UNITS:
            yield text[start:index]
            start, count = index, 0
        count += size
    if start < len(text):
        yield text[start:]
