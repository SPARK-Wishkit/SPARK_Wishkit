"""
요청별 응답시간·메모리 실측용 (요구사항 6 — ECS/Fargate vs Lambda 결정에 쓰일 핵심 데이터).

`PeakRSSSampler`는 요청 처리 중 백그라운드에서 **프로세스 트리 전체**(uvicorn 파이썬
프로세스 + Playwright가 띄운 Chrome 브라우저 자식 프로세스들)의 RSS 합을 주기적으로 찍어서
그 요청이 진행되는 동안의 최댓값을 기록한다.

**처음엔 파이썬 프로세스 하나만(`psutil.Process().memory_info()`) 쟀는데, 이러면 Chrome
브라우저 프로세스(Playwright가 별도 OS 프로세스로 띄움 — 실제로 메모리를 가장 많이 먹는
부분)가 통째로 빠진다는 걸 뒤늦게 발견해서 자식 프로세스까지 합산하도록 고쳤다.** 이 실수를
그대로 뒀으면 AWS 용량 산정 수치가 실제보다 훨씬 낮게 나왔을 것 — 보고서에도 이 경위를
남겨둔다.

주의(정직하게 밝혀둠): 이 프로세스는 요청을 하나씩만 처리하지 않고 asyncio로 동시에 여러
요청을 처리할 수 있으므로, "요청 A의 peak_rss_mb"에는 그 순간 동시에 처리 중이던 다른
요청의 메모리 사용량도 섞여 들어갈 수 있다(프로세스 트리 전체 RSS를 측정하는 것이지,
요청별로 격리된 메모리를 측정하는 게 아니다). 동시 요청이 1건뿐인 상황(로컬 회귀
테스트처럼 순차 호출)에서는 이 값이 정확히 그 요청의 메모리 사용량에 가깝다 — 실측
보고서에도 이 조건을 명시한다.
"""
from __future__ import annotations

import asyncio
import time
from typing import Self

import psutil

_process = psutil.Process()


def _tree_rss_mb() -> float:
    """현재 프로세스 + 모든 자식 프로세스(브라우저, 브라우저의 zygote/gpu-process 등)의
    RSS 합을 MB로. 자식이 측정 순간 이미 종료됐으면(NoSuchProcess) 그 프로세스분만 0으로
    치고 넘어간다."""
    total = _process.memory_info().rss
    try:
        children = _process.children(recursive=True)
    except psutil.Error:
        children = []
    for child in children:
        try:
            total += child.memory_info().rss
        except psutil.Error:
            continue
    return total / (1024 * 1024)


class PeakRSSSampler:
    """`async with PeakRSSSampler(interval_ms=100) as sampler: ...` 형태로 쓴다.
    블록이 끝나면 `sampler.peak_rss_mb`에 그 구간 동안 관측된 최대 RSS(MB, 프로세스 트리
    전체 합)가 들어있다."""

    def __init__(self, interval_ms: int = 100):
        self._interval_s = interval_ms / 1000
        self._task: asyncio.Task | None = None
        self.peak_rss_mb: float = 0.0
        self.start_rss_mb: float = 0.0

    async def __aenter__(self) -> Self:
        self.start_rss_mb = _tree_rss_mb()
        self.peak_rss_mb = self.start_rss_mb
        self._task = asyncio.create_task(self._sample_loop())
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        # 종료 시점 값도 한 번 더 반영 (샘플링 주기 사이에 스파이크가 있었을 수 있어서
        # 마지막 값도 놓치지 않게).
        self.peak_rss_mb = max(self.peak_rss_mb, _tree_rss_mb())

    async def _sample_loop(self) -> None:
        while True:
            self.peak_rss_mb = max(self.peak_rss_mb, _tree_rss_mb())
            await asyncio.sleep(self._interval_s)


def now_ms() -> int:
    return int(time.monotonic() * 1000)
