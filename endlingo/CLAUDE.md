# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a native iOS SwiftUI project (Xcode 16, iOS 17+). Open `endlingo.xcodeproj` in Xcode to build and run. Dependencies are managed via Swift Package Manager within Xcode (no `Package.swift` at root).

```bash
# Build from command line
xcodebuild -project endlingo.xcodeproj -scheme endlingo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -project endlingo.xcodeproj -scheme endlingo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Supabase Edge Functions (TypeScript/Deno) live in `supabase/functions/`. Deploy with:
```bash
supabase functions deploy generate-daily-lessons --no-verify-jwt
supabase functions deploy delete-account --no-verify-jwt
```

## Architecture

**MVVM + Singleton Services** with `@Observable` (iOS 17+) and `@MainActor` isolation throughout.

```
View (@State var viewModel)
  → ViewModel (@Observable, async/await)
    → Services (singletons, .shared)
      → Supabase REST API / Local JSON files
```

### Key patterns
- All services are `@Observable @MainActor final class` singletons accessed via `.shared`
- `SupabaseAPI` is a generic HTTP wrapper (not the Supabase Swift client SDK) — uses raw URLSession + REST
- Guest mode: data persists to Documents directory JSON files. On login: local data syncs to Supabase then local files are cleared
- Widget shares data via App Groups (`group.com.realmasse.yeongeohaja`) UserDefaults
- All dates use `Asia/Seoul` timezone (KST)

### Services (15 singletons)
- **AuthService** — email auth, session restore, deep links
- **LessonService** — fetch daily lessons with in-memory cache per date/language
- **VocabularyService / GrammarService** — save/load with local-first + remote sync
- **GamificationService** — XP, streaks (2x at ≥7 days), badges, learning records
- **SpeechRecognitionService** — AVAudioEngine + SFSpeechRecognizer, auto-stop after word recognition
- **SpeechService** — AVSpeechSynthesizer TTS with word-level highlight callback
- **BuiltInWordBank** — loads `builtin_words.json` / `builtin_words_ja.json` by locale
- **WidgetDataService** — syncs lesson data to widget via shared UserDefaults

### Data models
All models implement `Codable` with `CodingKeys` mapping to snake_case for Supabase compatibility.

## Localization

Uses XCStrings format (`Localizable.xcstrings`). Three languages: Korean (source), Japanese, English. Use `String(localized:)` macro for all user-facing strings. Comments are written in Korean.

Built-in word banks are locale-aware: `builtin_words.json` (Korean meanings) and `builtin_words_ja.json` (Japanese meanings).

### Rules
- **UI 문자열을 추가하거나 변경할 때 반드시 한국어와 일본어 번역을 함께 제공해야 한다.**
- 하드코딩 한국어 금지 — 반드시 `String(localized:)` 또는 SwiftUI `Text("...")` (LocalizedStringKey) 사용
- 새 키를 추가하면 `Localizable.xcstrings`에 `"ja"` 번역을 즉시 추가할 것
- 위젯(`YeongeohajaWidget`)은 별도 xcstrings가 없으므로 로케일 분기(`Locale.current.language.languageCode`)로 처리

## Supabase Backend

- **daily_lessons** table: UNIQUE(date, level, environment), scenarios as JSONB
- **pg_cron**: 6 jobs (A1–C2) staggered at 15:00–15:05 UTC generating 5 environments each
- Edge Functions use OpenAI `gpt-4o-mini` for lesson content generation
- RLS: public read, service_role insert

## Commit Style

Korean commit messages with conventional prefix: `feat:`, `fix:`, `style:`, `release:`.
