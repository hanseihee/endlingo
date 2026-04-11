#!/usr/bin/env python3
"""
builtin_words.json (ko) → builtin_words_vi.json 생성.

OpenAI API 로 2,009 단어의 meaning 필드를 베트남어로 배치 번역.
재실행 가능: 출력 파일에 이미 존재하는 단어는 스킵.

사용법:
    export OPENAI_API_KEY=sk-...
    python3 scripts/translate_wordbank_vi.py

옵션:
    --batch-size N  (기본 25)
    --model NAME    (기본 gpt-4o-mini)
    --dry-run       실제 호출 없이 건수만 출력
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "endlingo" / "Resources" / "builtin_words.json"
DST = ROOT / "endlingo" / "Resources" / "builtin_words_vi.json"

SYSTEM_PROMPT = """You are a professional Korean→Vietnamese translator specializing in dictionary entries for English-learning apps targeting Vietnamese learners.

Your task: given a batch of entries containing English word, Korean meaning, and English definition, produce a natural Vietnamese translation of the "meaning" field.

Rules:
- Translate the Korean meaning into natural Vietnamese, NOT word-by-word.
- Preserve multiple senses separated by comma. Example: "접근, 이용" → "tiếp cận, sử dụng"
- Use the English definition as context to pick the right Vietnamese word for ambiguous cases.
- Keep it concise — dictionary-entry style. Usually 1-3 words per sense.
- Do NOT add parts of speech labels.
- Do NOT include the English word or definition in the output.
- Output JSON only."""


def build_prompt(batch: list[dict[str, Any]]) -> str:
    items = [
        {
            "rank": e["rank"],
            "word": e["word"],
            "ko_meaning": e["meaning"],
            "en_definition": e.get("definition", ""),
        }
        for e in batch
    ]
    return (
        "Translate the 'ko_meaning' field of each entry into natural Vietnamese. "
        "Use 'en_definition' as disambiguation context.\n\n"
        "Output JSON: {\"translations\": [{\"rank\": 801, \"vi_meaning\": \"...\"}, ...]} "
        "with the same order and rank values as input.\n\n"
        f"Input:\n{json.dumps(items, ensure_ascii=False, indent=1)}"
    )


def call_openai(api_key: str, model: str, prompt: str) -> dict[str, Any]:
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        data=json.dumps(
            {
                "model": model,
                "temperature": 0.3,
                "response_format": {"type": "json_object"},
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": prompt},
                ],
            }
        ).encode("utf-8"),
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    content = result["choices"][0]["message"]["content"]
    return json.loads(content)


def load_existing() -> dict[int, dict[str, Any]]:
    if not DST.exists():
        return {}
    with open(DST, "r", encoding="utf-8") as f:
        data = json.load(f)
    return {entry["rank"]: entry for entry in data}


def save(entries: list[dict[str, Any]]) -> None:
    entries.sort(key=lambda e: e["rank"])
    with open(DST, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-size", type=int, default=25)
    parser.add_argument("--model", default="gpt-4o-mini")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key and not args.dry_run:
        print("ERROR: OPENAI_API_KEY not set", file=sys.stderr)
        return 1

    with open(SRC, "r", encoding="utf-8") as f:
        source = json.load(f)

    existing = load_existing()
    todo = [e for e in source if e["rank"] not in existing]
    print(f"Source: {len(source)} entries")
    print(f"Already done: {len(existing)}")
    print(f"To translate: {len(todo)}")

    if args.dry_run:
        return 0

    if not todo:
        print("Nothing to do.")
        return 0

    all_entries: list[dict[str, Any]] = list(existing.values())
    batch_count = (len(todo) + args.batch_size - 1) // args.batch_size

    for i in range(0, len(todo), args.batch_size):
        batch = todo[i : i + args.batch_size]
        batch_num = i // args.batch_size + 1
        print(f"[{batch_num}/{batch_count}] translating {len(batch)} entries...", flush=True)

        prompt = build_prompt(batch)
        try:
            result = call_openai(api_key, args.model, prompt)
        except (urllib.error.HTTPError, urllib.error.URLError) as e:
            print(f"  ERROR: {e}. saving progress and exiting.", file=sys.stderr)
            save(all_entries)
            return 2

        translations = {t["rank"]: t["vi_meaning"] for t in result.get("translations", [])}

        missing: list[int] = []
        for entry in batch:
            vi = translations.get(entry["rank"])
            if not vi:
                missing.append(entry["rank"])
                continue
            all_entries.append(
                {
                    "word": entry["word"],
                    "meaning": vi,
                    "definition": entry.get("definition", ""),
                    "rank": entry["rank"],
                }
            )

        if missing:
            print(f"  WARN: missing translations for ranks: {missing[:5]}{'...' if len(missing) > 5 else ''}")

        save(all_entries)
        time.sleep(0.3)  # 가벼운 throttle

    print(f"\nDone. {len(all_entries)} total entries saved to {DST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
