"""providers.generate()의 429 재시도 — Gemini는 가짜 클라이언트로 바꾼다."""
import json
import types

import providers


def _fake_client(monkeypatch, errors: int, delay_s: int):
    calls = {"n": 0, "slept": []}

    class Models:
        def generate_content(self, **_):
            calls["n"] += 1
            if calls["n"] <= errors:
                raise Exception(f"429 RESOURCE_EXHAUSTED retryDelay': '{delay_s}s'")  # noqa: TRY002 — 실제 SDK 예외 메시지 모양만 흉내
            return types.SimpleNamespace(text=json.dumps({"ok": 1}))

    monkeypatch.setattr(providers, "_client", lambda: types.SimpleNamespace(models=Models()))
    monkeypatch.setattr(providers.time, "sleep", lambda s: calls["slept"].append(s))
    return calls


def test_retries_after_waiting_when_no_wait_cap(monkeypatch):
    calls = _fake_client(monkeypatch, errors=1, delay_s=20)
    r = providers.generate("t", "x", max_retries=1)
    assert r.ok and calls["n"] == 2 and calls["slept"] == [21.0]


def test_gives_up_immediately_when_retry_wait_exceeds_cap(monkeypatch):
    calls = _fake_client(monkeypatch, errors=1, delay_s=20)
    r = providers.generate("t", "x", max_retries=1, max_retry_wait_s=10)
    assert not r.ok and "429" in r.error and calls["n"] == 1 and calls["slept"] == []


def test_retries_when_wait_fits_in_cap(monkeypatch):
    calls = _fake_client(monkeypatch, errors=1, delay_s=3)
    r = providers.generate("t", "x", max_retries=1, max_retry_wait_s=10)
    assert r.ok and calls["slept"] == [4.0]
