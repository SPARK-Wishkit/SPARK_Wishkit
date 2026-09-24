#!/bin/bash
# 깃허브에 처음 올리기 전 정리 + 준비. 레포 맨 위 폴더에서 실행한다.
# 사용법: bash scripts/prepare_repo.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ ! -d wishlist-appversion2/flutter_app ]; then
  echo "❌ 레포 맨 위 폴더(2026-softstudio-project-main)가 아니에요: $ROOT"; exit 1
fi

echo "① 필요 없는 파일 삭제"
for f in wishlist-appversion2/AUTH_README.md wishlist-appversion2/run_engine.sh; do
  [ -e "$f" ] && rm -f "$f" && echo "  🗑  $f"
done
n=$(find . -name .DS_Store -not -path "*/node_modules/*" | wc -l | tr -d ' ')
find . -name .DS_Store -not -path "*/node_modules/*" -delete
find . -type d -name __MACOSX -prune -exec rm -rf {} +
echo "  🗑  .DS_Store ${n}개, __MACOSX 폴더"

echo "② git 준비"
if [ ! -d .git ]; then git init -b main >/dev/null && echo "  ✓ git init (main 브랜치)"; else echo "  ✓ 이미 git 폴더가 있음"; fi
mkdir -p .git/hooks
cp scripts/check_secrets.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
echo "  ✓ 커밋할 때마다 비밀 정보 자동 검사 설치"

echo "③ 올릴 파일 담기"
git add -A
count=$(git diff --cached --name-only | wc -l | tr -d ' ')
echo "  ✓ ${count}개 파일"

echo "④ 확인"
for must_not in amplify_outputs.dart node_modules/ .amplify/ /build/ /Pods/; do
  # -F: 글자 그대로 비교 (점 · 슬래시를 특수문자로 보지 않음)
  if git diff --cached --name-only | grep -qF "$must_not"; then
    echo "  ❌ '$must_not' 이 담겼어요! 올리지 마세요."; exit 1
  fi
done
echo "  ✓ amplify_outputs.dart · node_modules · .amplify · build · Pods 제외됨"
if ! bash scripts/check_secrets.sh; then
  echo ""
  echo "❌ 비밀 정보가 섞여 있어서 멈췄어요. 위 파일을 빼고 다시 실행하세요."
  exit 1
fi
echo ""
echo "가장 큰 파일 5개:"
git diff --cached --name-only -z | xargs -0 du -k 2>/dev/null | sort -rn | head -5 | awk '{printf "  %6d KB  %s\n", $1, $2}'
echo ""
echo "✅ 준비 완료. 이제 commit → push 하세요."
