"""The ENSA data assistant: Claude with read-only tools over the aggregate tables."""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

import anthropic

from . import tools

MODEL = os.environ.get("ENSA_AGENT_MODEL", "claude-opus-5-5")
EFFORT = os.environ.get("ENSA_AGENT_EFFORT", "high")
SYSTEM = (Path(__file__).with_name("system_prompt.md")).read_text(encoding="utf-8")


@dataclass
class Answer:
    text: str
    tool_calls: list[dict] = field(default_factory=list)
    input_tokens: int = 0
    output_tokens: int = 0
    refused: bool = False


class EnsaAgent:
    """Multi-turn assistant. Each question runs a tool loop; earlier questions and answers are kept
    as conversation history so follow-ups ("and in Batha?") work."""

    def __init__(self, client: anthropic.Anthropic | None = None, max_iterations: int = 15):
        self.client = client or anthropic.Anthropic()
        self.max_iterations = max_iterations
        self.history: list[dict] = []

    def ask(self, question: str) -> Answer:
        tools.TRACE.clear()
        messages = self.history + [{"role": "user", "content": question}]
        runner = self.client.beta.messages.tool_runner(
            model=MODEL,
            max_tokens=16000,
            # The fixed system prompt (and the tool definitions before it) is cached across questions.
            system=[{"type": "text", "text": SYSTEM, "cache_control": {"type": "ephemeral"}}],
            tools=tools.TOOLS,
            messages=messages,
            output_config={"effort": EFFORT},
            # If the model declines a request, the API retries it on a fallback model automatically.
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            max_iterations=self.max_iterations,
        )
        last, n_in, n_out = None, 0, 0
        for message in runner:
            last = message
            n_in += message.usage.input_tokens + (message.usage.cache_read_input_tokens or 0) \
                + (message.usage.cache_creation_input_tokens or 0)
            n_out += message.usage.output_tokens

        if last is None:
            return Answer("No response from the model.")
        if last.stop_reason == "refusal":
            text = "The model declined this request."
            refused = True
        else:
            text = "\n".join(b.text for b in last.content if b.type == "text").strip()
            refused = False
            if last.stop_reason == "max_tokens":
                text += "\n\n[Answer cut off at the token limit.]"
        # Keep only the question and the final answer in the history (append-only).
        self.history += [{"role": "user", "content": question}, {"role": "assistant", "content": text or "(no text)"}]
        return Answer(text, list(tools.TRACE), n_in, n_out, refused)

    def reset(self) -> None:
        self.history.clear()
