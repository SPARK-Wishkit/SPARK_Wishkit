#!/bin/bash
# 커밋하려는 파일에 비밀 정보가 섞였는지 검사한다. 걸리면 커밋을 막는다.
# git 의 pre-commit 훅으로 자동 실행된다. (scripts/prepare_repo.sh 가 설치)
# 직접 실행: bash scripts/check_secrets.sh
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1
files=$(git diff --cached --name-only --diff-filter=ACM)
[ -z "$files" ] && exit 0
bad=0

while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    *amplify_outputs.dart|*amplify_outputs.json)
      echo "🚫 $f — 사람마다 다른 AWS 설정 파일이에요. 올리지 마세요."; bad=1 ;;
    *.csv)
      if grep -qiE "access key id|secret access key" "$f"; then
        echo "🚫 $f — AWS 액세스 키 파일이에요!"; bad=1
      fi ;;
    *.pem|*.p8|*.p12|*.jks|*.keystore|*key.properties|.env|.env.*|*/.env|*/.env.*)
      echo "🚫 $f — 비밀 키/설정 파일이에요."; bad=1 ;;
  esac
  size=$(wc -c < "$f")
  if [ "$size" -gt 20000000 ]; then
    echo "🚫 $f — 20MB 넘는 큰 파일이에요 ($((size/1000000))MB)."; bad=1
  fi
done <<< "$files"

# 파일 내용 속 AWS 키 모양 검사 (AKIA로 시작하는 20자, 비밀 키 이름, 개인 키 블록)
# (검사 문구를 쪼개 적어서, 이 파일 자체가 걸리지 않게 한다)
pat="AKIA[0-9A-Z]{16}|aws_secret""_access_key|-----BEGIN [A-Z ]*PRIVATE"" KEY-----"
hits=$(git diff --cached -U0 --diff-filter=ACM | grep -E '^\+' | grep -nE "$pat" || true)
if [ -n "$hits" ]; then
  echo "🚫 커밋 내용에 AWS 키나 개인 키로 보이는 줄이 있어요:"
  echo "$hits" | head -5 | cut -c1-120
  bad=1
fi

if [ "$bad" -ne 0 ]; then
  echo ""
  echo "커밋을 멈췄어요. 위 파일을 빼려면: git restore --staged <파일>"
  exit 1
fi
echo "✅ 비밀 정보 검사 통과"
