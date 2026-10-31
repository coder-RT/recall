"""The Home Memory agent over A2A 1.0 (JSON-RPC), mounted in the FastAPI app at /a2a/home-memory. Mapping only: the
AnswerExternalQuery use case screens and answers. The card's source of truth is resources/agents/home-memory.card.json.
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path

from a2a.helpers import get_data_parts, get_message_text, new_data_part, new_message, new_text_part
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import AgentCard
from google.protobuf.json_format import ParseDict

PATH = "/a2a/home-memory"
CARD_PATH = f"{PATH}/.well-known/agent-card.json"


def load_card(source: Path, public_url: str) -> AgentCard:
    text = source.read_text().replace("{public_url}", public_url.rstrip("/"))
    return ParseDict(json.loads(text), AgentCard())


class HomeMemoryExecutor(AgentExecutor):
    """One request, one answer: a single Message with the sentence and, when there is one, the data part."""

    def __init__(self, answer, home_id: str) -> None:
        self.answer, self.home_id = answer, home_id

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        text = get_message_text(context.message).strip()
        if not text:  # a data part {"object": "keys"} works too
            data = next((d for d in get_data_parts(context.message.parts) if isinstance(d, dict)), {})
            text = str(data.get("object") or data.get("name") or "")
        result = await asyncio.to_thread(self.answer, self.home_id, text)
        parts = [new_text_part(result.text, media_type="text/plain")]
        if result.data:
            parts.append(new_data_part(result.data, media_type="application/json"))
        await event_queue.enqueue_event(new_message(parts, context_id=context.context_id, task_id=context.task_id))

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        raise NotImplementedError("Answers are immediate; there is nothing to cancel.")


def routes(answer, home_id: str, card: AgentCard) -> list:
    handler = DefaultRequestHandler(
        agent_executor=HomeMemoryExecutor(answer, home_id), task_store=InMemoryTaskStore(), agent_card=card
    )
    return [*create_agent_card_routes(card, card_url=CARD_PATH), *create_jsonrpc_routes(handler, PATH)]
