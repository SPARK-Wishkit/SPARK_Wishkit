# -*- coding: utf-8 -*-
"""
동시 요청 N건을 실제로 던져서 (a) 순차 대비 응답시간이 얼마나 늘어나는지, (b) 프로세스
트리 메모리(peak_rss_mb)가 동시성에 따라 어떻게 늘어나는지 잰다. ECS/Fargate 태스크 하나가
동시에 몇 건까지 감당할 수 있는지 감을 잡기 위한 실측 — design-doc/보고서의 "순차 1건
기준 실측이라 동시성 테스트가 더 필요하다"는 캐비어트를 메우는 용도.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import time

import httpx

URLS = [
    "https://www.musinsa.com/products/4341120",
    "https://kream.co.kr/products/1012767",
    "https://www.nike.com/kr/t/acg-%EB%8F%8C%EB%A1%9C%EB%AF%B8%ED%8B%B0-%EC%BD%94%EB%93%80%EB%A1%9C%EC%9D%B4-%EC%9E%AC%ED%82%B7-6afaYkrC/IM4254-104",
    "https://web.queenit.kr/product/421b849e05731238976b9f01d96c7e31",
    "https://www.ssfshop.com/GOOD-ON/GPCX21040888339/good",
    "https://posty.kr/products/169042232",
]


async def one_request(client: httpx.AsyncClient, url: str) -> dict:
    t0 = time.monotonic()
    try:
        resp = await client.post("/extract", json={"url": url}, timeout=90)
        wall_ms = int((time.monotonic() - t0) * 1000)
        body = resp.json()
        return {
            "url": url,
            "status": resp.status_code,
            "wall_ms": wall_ms,
            "server_metrics": body.get("metrics") if resp.status_code == 200 else body,
        }
    except Exception as exc:  # noqa: BLE001
        return {"url": url, "status": 0, "wall_ms": int((time.monotonic() - t0) * 1000), "error": str(exc)}


async def run_batch(base_url: str, concurrency: int) -> list[dict]:
    urls = (URLS * ((concurrency // len(URLS)) + 1))[:concurrency]
    async with httpx.AsyncClient(base_url=base_url) as client:
        t0 = time.monotonic()
        results = await asyncio.gather(*[one_request(client, u) for u in urls])
        batch_wall_ms = int((time.monotonic() - t0) * 1000)
    return results, batch_wall_ms


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", default="http://127.0.0.1:8000")
    parser.add_argument("--concurrency", type=int, nargs="+", default=[1, 3, 6])
    args = parser.parse_args()

    all_runs = {}
    for n in args.concurrency:
        print(f"\n=== 동시 요청 {n}건 ===")
        results, batch_wall_ms = await run_batch(args.server, n)
        for r in results:
            print(f"  status={r['status']} wall_ms={r['wall_ms']} "
                  f"peak_rss_mb={ (r.get('server_metrics') or {}).get('peak_rss_mb') }")
        ok = [r for r in results if r["status"] == 200]
        peaks = [r["server_metrics"]["peak_rss_mb"] for r in ok]
        print(f"  배치 전체 소요: {batch_wall_ms}ms / 성공 {len(ok)}/{n} / "
              f"peak_rss_mb 최댓값: {max(peaks) if peaks else 'N/A'}")
        all_runs[n] = {"batch_wall_ms": batch_wall_ms, "results": results}
        await asyncio.sleep(5)  # 배치 사이 쿨다운 (Gemini 429 누적 방지)

    with open("concurrency_load_test_result.json", "w", encoding="utf-8") as f:
        json.dump(all_runs, f, ensure_ascii=False, indent=2)
    print("\n결과 저장: concurrency_load_test_result.json")


if __name__ == "__main__":
    asyncio.run(main())
