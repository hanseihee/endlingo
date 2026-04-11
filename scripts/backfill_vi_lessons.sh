#!/usr/bin/env bash
# 최근 10일간 daily_lessons_v2 레슨에 베트남어 번역을 백필.
# translate-lessons Edge Function 을 (날짜 × 레벨) 단위로 호출.
# 한 호출당 5레슨만 처리하여 Supabase Edge Function WORKER_LIMIT 회피.

set -euo pipefail

URL="https://alvawqinuacabfnqduoy.supabase.co/functions/v1/translate-lessons"
AUTH="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFsdmF3cWludWFjYWJmbnFkdW95Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNjExNDgsImV4cCI6MjA4ODgzNzE0OH0.C-gnavFBHa-gIyvoGngaYfV6htDTiFyOmj5MemIlzhY"
LEVELS=("A1" "A2" "B1" "B2" "C1" "C2")

for i in 0 1 2 3 4 5 6 7 8 9; do
  DATE=$(date -v-${i}d +%Y-%m-%d)
  for LEVEL in "${LEVELS[@]}"; do
    printf "▶ %s / %s  " "$DATE" "$LEVEL"
    curl -s -X POST "$URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $AUTH" \
      -d "{\"language\":\"vi\",\"date\":\"$DATE\",\"level\":\"$LEVEL\"}"
    echo ""
  done
done

echo ""
echo "Done."
