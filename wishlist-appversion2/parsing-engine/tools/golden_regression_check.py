# -*- coding: utf-8 -*-
"""
로컬에서 띄운 서버(main.py)에 golden_catalog.json 36개 상품 URL을 전부 던져서, 서버로
포팅한 뒤에도 engine-ai-prototype의 배치 스크립트(bakeoff.py) 결과와 같은 수준의 정확도가
나오는지 확인한다 (요구사항 3 — run6 기준선: 완전 일치 21/36=58%, 그라운딩 통과 31/36=86%).

golden_catalog.json / bakeoff_results_run6_final.json은 원래 engine-ai-prototype
폴더(2026-softstudio-project 저장소 밖)에 있었으나, 이 저장소로 이관하면서
parsing-engine/ 바로 아래로 같이 옮겨왔다 — 이 스크립트는 그 파일들을 읽기만 한다.

사용법 (서버를 먼저 `uvicorn main:app`으로 띄운 상태에서, parsing-engine/tools에서 실행):
    python golden_regression_check.py \\
        --server http://127.0.0.1:8000 \\
        --golden-catalog ../golden_catalog.json \\
        --baseline ../bakeoff_results_run6_final.json
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

SERVER_DIR = Path(__file__).resolve().parent.parent / "server"
sys.path.insert(0, str(SERVER_DIR))

from compare import compare_to_golden  # noqa: E402  (server/compare.py 재사용)


def call_extract(server: str, url: str, timeout: float) -> dict:
    payload = json.dumps({"url": url}).encode("utf-8")
    req = urllib.request.Request(
        f"{server}/extract", data=payload, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return {"status": resp.status, "body": json.loads(resp.read())}
    except urllib.error.HTTPError as e:
        return {"status": e.code, "body": json.loads(e.read()) if e.fp else {"detail": str(e)}}
    except Exception as exc:  # noqa: BLE001
        return {"status": 0, "body": {"detail": f"{type(exc).__name__}: {exc}"}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", default="http://127.0.0.1:8000")
    parser.add_argument("--golden-catalog", required=True, help="golden_catalog.json 경로(parsing-engine/golden_catalog.json)")
    parser.add_argument("--baseline", default=None, help="비교 기준선 JSON(bakeoff_results_run6_final.json) — 선택")
    parser.add_argument("--mall", default=None, help="특정 몰만 실행")
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--out", default="golden_regression_result.json")
    args = parser.parse_args()

    catalog = json.loads(Path(args.golden_catalog).read_text(encoding="utf-8"))
    cases = []
    for mall_entry in catalog:
        if args.mall and mall_entry["mall"] != args.mall:
            continue
        for p in mall_entry["products"]:
            cases.append({"mall": mall_entry["mall"], **p})

    print(f"대상 상품 수: {len(cases)} (서버: {args.server})")
    results = []
    for i, case in enumerate(cases, 1):
        t0 = time.monotonic()
        res = call_extract(args.server, case["url"], args.timeout)
        wall_ms = int((time.monotonic() - t0) * 1000)
        status, body = res["status"], res["body"]

        record = {"mall": case["mall"], "url": case["url"], "golden": case, "http_status": status, "wall_ms": wall_ms}
        if status == 200:
            cmp = compare_to_golden(body, case)
            record["extracted"] = body
            record["compare"] = cmp
            tag = "MATCH" if cmp["full_match"] else "MISMATCH"
            print(f"[{i}/{len(cases)}] {case['mall']:8s} {tag:8s} "
                  f"price={body.get('price', {}).get('unconditional_price')} "
                  f"ambiguous={body.get('ambiguous')} "
                  f"grounded={body.get('grounding', {}).get('all_grounded')} "
                  f"({wall_ms}ms, peak_rss={body.get('metrics', {}).get('peak_rss_mb')}MB)")
        else:
            print(f"[{i}/{len(cases)}] {case['mall']:8s} HTTP {status}: {body.get('detail')}")
        results.append(record)

    ok_results = [r for r in results if r["http_status"] == 200]
    full_match = sum(1 for r in ok_results if r["compare"]["full_match"])
    grounded = sum(1 for r in ok_results if r["extracted"].get("grounding", {}).get("all_grounded"))
    n = len(results)

    print("\n" + "=" * 60)
    print(f"완전 일치(MATCH): {full_match}/{n} ({full_match/n:.0%})")
    print(f"그라운딩 통과: {grounded}/{n} ({grounded/n:.0%})")
    print(f"HTTP 비정상 응답: {n - len(ok_results)}/{n}")

    if args.baseline:
        baseline = json.loads(Path(args.baseline).read_text(encoding="utf-8"))
        base_match = sum(
            1 for r in baseline
            if r.get("providers", {}).get("gemini", {}).get("compare", {}).get("full_match")
        )
        base_grounded = sum(
            1 for r in baseline
            if r.get("providers", {}).get("gemini", {}).get("grounding", {}).get("all_grounded")
        )
        print(f"\n기준선(run6): 완전 일치 {base_match}/{len(baseline)}, 그라운딩 {base_grounded}/{len(baseline)}")
        if full_match < base_match:
            print(f"⚠️  회귀 발생: 완전 일치가 기준선보다 {base_match - full_match}건 낮음 — 원인 조사 필요")
        else:
            print("회귀 없음 (기준선 이상)")

    Path(args.out).write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n결과 저장: {args.out}")


if __name__ == "__main__":
    main()
