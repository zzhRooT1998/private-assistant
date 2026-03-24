from __future__ import annotations

from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from app.schemas import RankedIntentCandidate, ScreenIntentResult
from app.services.vision import VisionIntentService


class IntentWorkflowState(TypedDict, total=False):
    image_path: str | None
    content_type: str | None
    text_input: str | None
    page_url: str | None
    source_app: str | None
    source_type: str | None
    forced_intent: str | None
    ranked_intents: list[RankedIntentCandidate]
    requires_confirmation: bool
    confirmation_reason: str | None
    parsed_result: ScreenIntentResult


class IntentWorkflowService:
    def __init__(self, vision: VisionIntentService) -> None:
        self.vision = vision
        graph = StateGraph(IntentWorkflowState)
        graph.add_node("rank_intents", self._rank_intents)
        graph.add_node("extract_intent", self._extract_intent)
        graph.add_edge(START, "rank_intents")
        graph.add_conditional_edges(
            "rank_intents",
            self._next_step,
            {
                "extract_intent": "extract_intent",
                "end": END,
            },
        )
        graph.add_edge("extract_intent", END)
        self.graph = graph.compile()

    def analyze(
        self,
        *,
        image_path: str | None = None,
        content_type: str | None = None,
        text_input: str | None = None,
        page_url: str | None = None,
        source_app: str | None = None,
        source_type: str | None = None,
        forced_intent: str | None = None,
    ) -> IntentWorkflowState:
        initial_state: IntentWorkflowState = {
            "image_path": image_path,
            "content_type": content_type,
            "text_input": text_input,
            "page_url": page_url,
            "source_app": source_app,
            "source_type": source_type,
            "forced_intent": forced_intent,
        }
        return self.graph.invoke(initial_state)

    def _rank_intents(self, state: IntentWorkflowState) -> dict[str, Any]:
        ranked_intents = self.vision.rank_intents(
            image_path=state.get("image_path"),
            content_type=state.get("content_type"),
            text_input=state.get("text_input"),
            page_url=state.get("page_url"),
            source_app=state.get("source_app"),
            source_type=state.get("source_type"),
            top_k=3,
        )
        requires_confirmation, confirmation_reason = self._should_require_confirmation(
            ranked_intents,
            forced_intent=state.get("forced_intent"),
        )
        return {
            "ranked_intents": ranked_intents,
            "requires_confirmation": requires_confirmation,
            "confirmation_reason": confirmation_reason,
        }

    def _extract_intent(self, state: IntentWorkflowState) -> dict[str, Any]:
        selected_intent = state.get("forced_intent") or state["ranked_intents"][0].intent
        parsed = self.vision.parse_input(
            image_path=state.get("image_path"),
            content_type=state.get("content_type"),
            text_input=state.get("text_input"),
            page_url=state.get("page_url"),
            source_app=state.get("source_app"),
            source_type=state.get("source_type"),
            forced_intent=selected_intent,
        )
        return {"parsed_result": parsed}

    @staticmethod
    def _next_step(state: IntentWorkflowState) -> str:
        if state.get("requires_confirmation"):
            return "end"
        return "extract_intent"

    @staticmethod
    def _should_require_confirmation(
        ranked_intents: list[RankedIntentCandidate],
        *,
        forced_intent: str | None,
    ) -> tuple[bool, str | None]:
        if forced_intent:
            return False, None
        if len(ranked_intents) < 2:
            return False, None

        first = ranked_intents[0]
        second = ranked_intents[1]
        confidence_gap = first.confidence - second.confidence

        if confidence_gap < 0.12 and second.confidence >= 0.35:
            return True, "Top intent candidates are too close. Human confirmation is required."
        if first.confidence < 0.6 and second.confidence >= 0.25:
            return True, "Model confidence is low. Human confirmation is required."
        return False, None
