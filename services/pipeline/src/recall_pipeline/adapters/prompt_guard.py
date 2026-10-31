"""Llama Prompt Guard 2 (Meta, open weights) on the Mac: is a message trying to inject instructions?

Gated on Hugging Face (Llama 4 Community License): the owner accepts the licence there and puts HF_TOKEN in .env.
Without the weights it is unavailable, and Recall's A2A server refuses messages (it fails closed).

Checked 2026-10-31 with the 22M model: its config names the classes LABEL_0 / LABEL_1 and LABEL_1 is malicious
("Ignore your previous instructions." -> 0.998 on index 1; "where are my keys?" -> 0.002); the card's own example
calls it MALICIOUS. The window is 512 tokens: per the card, longer text is split into segments and each is checked.
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

        # the model reads 512 tokens: longer messages go in overlapping windows; any window that is an attack counts
        inputs = self._tokenizer(text, return_tensors="pt", truncation=True, max_length=512, padding=True,
                                 return_overflowing_tokens=True, stride=64)  # fmt: skip
        inputs.pop("overflow_to_sample_mapping", None)
        with torch.no_grad():
            all_probs = torch.softmax(self._model(**inputs).logits, dim=-1)
        labels = self._model.config.id2label
        attack_ids = [i for i, name in labels.items() if any(a in str(name).upper() for a in ATTACK_LABELS)]
        per_window = all_probs[:, attack_ids].sum(dim=-1)
        w = int(per_window.argmax())
        attack, probs = float(per_window[w]), all_probs[w]
        top = int(probs.argmax())
        return {
            "available": True,
            "attack": attack >= self.threshold,
            "label": str(labels[top]),
            "score": round(attack, 4),
        }
