"""
Phase 8 — LLM provider abstraction.

ALL LLM calls go through this module.

Non-negotiable constraints enforced here:
  • LLM output is NEVER inserted into Judgment / Review tables.
  • Every call records provider, model, prompt_version, and timestamp.
  • The caller controls what's stored; this module only returns text + metadata.

Supported providers (set via env vars):
  LLM_PROVIDER  = "openai" | "anthropic" | "deepseek" | "stub" (default: "stub")
  LLM_MODEL     = model string (e.g. "gpt-4o", "claude-opus-4-7", "deepseek-v4-flash")
  LLM_API_KEY   = API key (optional for "stub")
  LLM_BASE_URL  = OpenAI-compatible base URL (optional; defaults for "deepseek")
"""
from __future__ import annotations

import os
import json
import time
from dataclasses import dataclass, field
from typing import Any

# ──────────────────────────────────────────────────────────────────────────────
# Configuration (read once at import time)
# ──────────────────────────────────────────────────────────────────────────────
LLM_PROVIDER: str = os.environ.get("LLM_PROVIDER", "stub").lower()
LLM_MODEL: str    = os.environ.get("LLM_MODEL", "stub-model-v1")
LLM_API_KEY: str  = os.environ.get("LLM_API_KEY", "")
LLM_BASE_URL: str = os.environ.get("LLM_BASE_URL", "")


# ──────────────────────────────────────────────────────────────────────────────
# Result dataclass
# ──────────────────────────────────────────────────────────────────────────────
@dataclass
class LLMResult:
    text: str
    provider: str
    model: str
    prompt_version: str
    duration_ms: int
    raw: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "text":           self.text,
            "provider":       self.provider,
            "model":          self.model,
            "prompt_version": self.prompt_version,
            "duration_ms":    self.duration_ms,
        }


# ──────────────────────────────────────────────────────────────────────────────
# Internal dispatchers
# ──────────────────────────────────────────────────────────────────────────────
def _call_openai_compatible(prompt: str, system: str, model: str, *, base_url: str = "") -> tuple[str, dict]:
    try:
        from openai import OpenAI  # type: ignore
    except ImportError as exc:
        raise RuntimeError("openai package not installed") from exc

    kwargs = {"api_key": LLM_API_KEY}
    if base_url:
        kwargs["base_url"] = base_url

    client = OpenAI(**kwargs)
    resp = client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": system},
            {"role": "user",   "content": prompt},
        ],
        temperature=0,
    )
    return resp.choices[0].message.content or "", resp.model_dump()


def _call_openai(prompt: str, system: str, model: str) -> tuple[str, dict]:
    return _call_openai_compatible(prompt, system, model, base_url=LLM_BASE_URL)


def _call_deepseek(prompt: str, system: str, model: str) -> tuple[str, dict]:
    return _call_openai_compatible(
        prompt,
        system,
        model,
        base_url=LLM_BASE_URL or "https://api.deepseek.com",
    )


def _call_anthropic(prompt: str, system: str, model: str) -> tuple[str, dict]:
    try:
        import anthropic  # type: ignore
    except ImportError as exc:
        raise RuntimeError("anthropic package not installed") from exc

    client = anthropic.Anthropic(api_key=LLM_API_KEY)
    msg = client.messages.create(
        model=model,
        max_tokens=1024,
        system=system,
        messages=[{"role": "user", "content": prompt}],
    )
    return msg.content[0].text, {}


def _call_stub(prompt: str, system: str, model: str) -> tuple[str, dict]:
    """Deterministic stub — no network call, used when no provider is configured."""
    return (
        json.dumps({
            "note": "LLM provider not configured (stub mode). "
                    "Set LLM_PROVIDER, LLM_MODEL, LLM_API_KEY env vars.",
            "prompt_preview": prompt[:200],
        }),
        {},
    )


# ──────────────────────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────────────────────
def call(
    prompt: str,
    *,
    system: str = "You are a rigorous inter-rater reliability analyst. "
                  "You must NEVER suggest labels that count as judgments. "
                  "Return structured JSON only.",
    prompt_version: str = "1.0",
) -> LLMResult:
    """
    Call the configured LLM provider and return an LLMResult.

    Safety contract:
      • Never call this with item content that would pre-label an item for a judge.
      • The caller is responsible for storing output in a clearly non-human field.
    """
    t0 = time.monotonic()

    dispatch = {
        "openai":    _call_openai,
        "anthropic": _call_anthropic,
        "deepseek":  _call_deepseek,
    }.get(LLM_PROVIDER, _call_stub)

    try:
        text, raw = dispatch(prompt, system, LLM_MODEL)
    except Exception as exc:  # noqa: BLE001
        text = json.dumps({"error": str(exc)})
        raw  = {}

    duration_ms = int((time.monotonic() - t0) * 1000)

    return LLMResult(
        text=text,
        provider=LLM_PROVIDER,
        model=LLM_MODEL,
        prompt_version=prompt_version,
        duration_ms=duration_ms,
        raw=raw,
    )
