import os
from typing import Iterable

from .models import Message
from .timeutil import utcnow

# Map stored model names to OpenAI model IDs.
MODEL_ALIASES = {
    "clown 1.2": "gpt-3.5-turbo",
    "clown 1.3": "gpt-3.5-turbo",
    "clown 1.4": "gpt-4o-mini",
}


def generate_reply(model_name: str, history: Iterable[Message], user_input: str) -> str:
    """
    Try to get an assistant reply from OpenAI. If anything goes wrong (no API key, import
    error, request failure), return a deterministic stub so the UI keeps working offline.
    """
    api_key = os.getenv("OPENAI_API_KEY")
    target_model = MODEL_ALIASES.get(model_name, os.getenv("OPENAI_MODEL", "gpt-3.5-turbo"))

    if not api_key:
        return _stub_reply(model_name, user_input)

    try:
        from openai import OpenAI  # type: ignore
    except Exception:
        return _stub_reply(model_name, user_input)

    client = OpenAI(api_key=api_key)

    # Build a short transcript from history
    messages = []
    for m in history:
        role = "assistant" if m.sender_type != "user" else "user"
        messages.append({"role": role, "content": m.content})
    # ensure the latest user message is present
    if not messages or messages[-1]["role"] != "user":
        messages.append({"role": "user", "content": user_input})

    try:
        resp = client.chat.completions.create(
            model=target_model,
            messages=messages,
            temperature=0.7,
            max_tokens=512,
        )
        choice = resp.choices[0].message.content or ""
        return choice.strip() or _stub_reply(model_name, user_input)
    except Exception:
        return _stub_reply(model_name, user_input)


def _stub_reply(model_name: str, user_input: str) -> str:
    return f"[{model_name}] Echo: {user_input}\n\n(Offline mode at {utcnow().isoformat()})"
