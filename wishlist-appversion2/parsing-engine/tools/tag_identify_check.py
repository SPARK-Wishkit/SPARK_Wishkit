"""
태그 사진 정확도 검사 — 로컬 서버(POST /identify-tag)에 실제 태그 사진을 보내 정답과 비교한다.

준비:
  photos/ 폴더에 태그 사진을 넣고, 같은 폴더에 answers.csv를 만든다.
    file,product_code,expected_host
    nike_af1.jpg,DV1234-100,nike.com
    musinsa_tee.jpg,801474YB2FT1000,
  - product_code: 태그에 실제로 적힌 품번(정답). 없으면 비워둔다.
  - expected_host: 찾아야 하는 사이트(공식몰 도메인). 비우면 "어디서든 맞는 상품이면 정답".

실행(서버가 떠 있어야 함):
  python tag_identify_check.py --photos ./photos --server http://localhost:8000

결과는 4가지로 센다 — 품번 읽기 정확도와 페이지 찾기 정확도를 따로 본다.
  정답       : 품번을 맞게 읽었고, 기대한 사이트에서 그 상품을 찾음
  다른 사이트 : 상품은 맞지만 기대한 공식몰이 아닌 곳(쇼핑몰)에서 찾음
  못 찾음     : not_found — 앱은 태그 이름만 채우고 사용자가 입력 (안전한 실패)
  품번 오독   : 태그 품번을 잘못 읽음 (가장 위험 — 다른 상품을 찾을 수 있음)
"""
from __future__ import annotations

import argparse
import base64
import csv
import json
import mimetypes
import re
import sys
import time
import urllib.request
from pathlib import Path


def _norm(s: str | None) -> str:
    return re.sub(r"[^0-9a-z]+", "", (s or "").lower())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--photos", required=True, type=Path)
    ap.add_argument("--server", default="http://localhost:8000")
    ap.add_argument("--out", type=Path, default=Path("tag_identify_result.json"))
    args = ap.parse_args()

    with (args.photos / "answers.csv").open(encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    results, counts = [], {"정답": 0, "다른 사이트": 0, "못 찾음": 0, "품번 오독": 0, "오류": 0}
    for row in rows:
        path = args.photos / row["file"]
        mime = mimetypes.guess_type(path.name)[0] or "image/jpeg"
        payload = json.dumps({
            "image_base64": base64.b64encode(path.read_bytes()).decode(),
            "mime_type": mime,
        }).encode()
        started = time.monotonic()
        try:
            req = urllib.request.Request(f"{args.server}/identify-tag", data=payload,
                                         headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=70) as resp:
                body = json.load(resp)
        except Exception as exc:  # noqa: BLE001
            counts["오류"] += 1
            results.append({"file": row["file"], "error": str(exc)})
            print(f"[오류]       {row['file']}: {exc}")
            continue
        elapsed = time.monotonic() - started

        expected_code = _norm(row.get("product_code"))
        read_code = _norm((body.get("tag") or {}).get("product_code"))
        match = body.get("match") or {}
        host = match.get("host") or ""
        expected_host = (row.get("expected_host") or "").strip().lower()

        if expected_code and read_code and read_code != expected_code:
            verdict = "품번 오독"
        elif body.get("status") != "found":
            verdict = "못 찾음"
        elif expected_host and not (host == expected_host or host.endswith("." + expected_host)):
            verdict = "다른 사이트"
        else:
            verdict = "정답"
        counts[verdict] += 1
        results.append({"file": row["file"], "verdict": verdict, "elapsed_s": round(elapsed, 1), "response": body})
        print(f"[{verdict}] {row['file']:30s} {elapsed:5.1f}s  품번={read_code or '-':16s} {match.get('url', '')}")

    if not rows:
        print("answers.csv에 사진이 없습니다.")
        return 1
    print("\n" + "  ".join(f"{k} {v}" for k, v in counts.items()) + f"  (총 {len(rows)}장)")
    args.out.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"자세한 결과: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
