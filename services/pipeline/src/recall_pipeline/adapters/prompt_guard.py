"""Llama Prompt Guard 2 (Meta, open weights) on the Mac: is a message trying to inject instructions?

Gated on Hugging Face (Llama 4 Community License): the owner accepts the licence there and puts HF_TOKEN in .env.
Without the weights it is unavailable, and Recall's A2A server refuses messages (it fails closed).

TODO(verify) on the model card once the weights are reachable: the label names in `config.id2label` (this treats a
label containing MALICIOUS, INJECTION or JAILBREAK, or "LABEL_1", as an attack) and the recommended threshold.
"""

from __future__ import annotations

import os
import threading

# the 22M model is the one granted to this project (2026-10-31); PROMPT_GUARD_MODEL picks another
MODEL = "meta-llama/Llama-Prompt-Guard-2-22M"
ATTACK_LABELS = ("MALICIOUS", "INJECTION", "JAILBREAK", "LABEL_1")


class PromptGuard:
    def __init__(self, model: str | None = None, threshold: float = 0.5) -> None:
        self.model_id = model or os.environ.get("PROMPT_GUARD_MODEL") or MODEL  # read when the server starts
        self.threshold = threshold
        self._model = self._tokenizer = None
        self._lock = threading.Lock()
        self.error: str | None = None

    def _load(self) -> bool:
        with self._lock:
            if self._model is not None:
                return True
            try:
                from transformers import AutoModelForSequenceClassification, AutoTokenizer

                token = os.environ.get("HF_TOKEN")
                self._tokenizer = AutoTokenizer.from_pretrained(self.model_id, token=token)
                self._model = AutoModelForSequenceClassification.from_pretrained(self.model_id, token=token).eval()
                self.error = None
                return True
            except Exception as e:  # gated, offline, no token: unavailable, never "allowed"
                self.error = f"{type(e).__name__}: {str(e).splitlines()[0][:200]}"
                return False

    def screen(self, text: str) -> dict:
        """{"available": bool, "attack": bool, "label": str, "score": float}; attack scores the attack labels."""
        if not self._load():
            return {"available": False, "attack": None, "label": None, "score": None, "error": self.error}
        import torch

        inputs = self._tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
        with torch.no_grad():
            probs = torch.softmax(self._model(**inputs).logits[0], dim=-1)
        labels = self._model.config.id2label
        attack = sum(float(p) for i, p in enumerate(probs) if any(a in str(labels[i]).upper() for a in ATTACK_LABELS))
        top = int(probs.argmax())
        return {
            "available": True,
            "attack": attack >= self.threshold,
            "label": str(labels[top]),
            "score": round(attack, 4),
        }
