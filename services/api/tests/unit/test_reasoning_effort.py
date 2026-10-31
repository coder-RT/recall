import json

import httpx

from recall_api.adapters.outbound.llm.openai_compatible import OpenAICompatibleLlm, from_settings
from recall_api.adapters.outbound.safety.meta_model_screen import MetaModelScreener
from recall_api.config.settings import Settings


def _capture(reply):
    seen = []

    def handler(request):
        seen.append(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"message": reply}]})

    return seen, httpx.MockTransport(handler)


def test_the_guide_sends_reasoning_effort_only_when_set():
    for effort, expected in (("low", "low"), (None, None)):
        seen, transport = _capture({"content": "Your keys are on the desk."})
        llm = OpenAICompatibleLlm("https://x.test/v1", "k", "m", reasoning_effort=effort, transport=transport)
        llm.chat([{"role": "user", "content": "where are my keys?"}], [])
        assert seen[0].get("reasoning_effort") == expected


def test_only_baseten_gets_the_setting():
    base = {"BASETEN_API_KEY": "k", "LMSTUDIO_MODEL": "glimmer", "GUIDE_REASONING_EFFORT": "low"}
    assert from_settings(Settings(**base, llm_provider="baseten_spark_open")).reasoning_effort == "low"
    assert from_settings(Settings(**base, llm_provider="lmstudio")).reasoning_effort is None
    assert Settings(BASETEN_API_KEY="k").reasoning_effort == "low"  # the measured default


def test_the_screen_sends_it_too():
    seen, transport = _capture({"content": '{"verdict": "safe", "reason": "an object"}'})
    s = MetaModelScreener("https://x.test/v1", "k", "m", "muse-spark-open", transport=transport, reasoning_effort="low")
    assert s.screen("blue mug").safe and seen[0]["reasoning_effort"] == "low"
