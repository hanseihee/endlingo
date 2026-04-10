-- 백필: daily_lessons(v1)의 ko/ja row를 daily_lessons_v2로 병합
-- 규칙:
--   1. ko row가 있으면 이를 기준으로 영어 콘텐츠 추출 (ko의 sentence_en/title_en/grammar.pattern/example)
--   2. ko row의 theme_ko/title_ko/context/sentence_ko/grammar.explanation → translations.ko
--   3. 동일 (date, level, env)의 ja row가 있으면 그 값들을 translations.ja로 추가
--   4. ON CONFLICT DO NOTHING → 이미 v2에 있는 row는 건드리지 않음 (재실행 안전)
--
-- 주의:
--   - v1의 영어 콘텐츠는 ko/ja 행에서 서로 조금 다를 수 있으나, 백필은 ko를 canonical로 사용
--   - ja-only row(ko 없음)는 이 스크립트가 스킵. 실제로는 거의 없을 것으로 가정
--   - 실행 전 반드시 DRY RUN (아래 SELECT) 으로 결과 확인 권장

-- ========================================================
-- DRY RUN: 백필 대상 확인 (실행 전 복사해서 SELECT만 돌려볼 것)
-- ========================================================
-- SELECT
--   ko.date, ko.level, ko.environment,
--   (ja.id IS NOT NULL) AS has_ja,
--   (v2.id IS NOT NULL) AS already_in_v2
-- FROM daily_lessons ko
-- LEFT JOIN daily_lessons ja
--   ON ja.date = ko.date AND ja.level = ko.level
--   AND ja.environment = ko.environment AND ja.language = 'ja'
-- LEFT JOIN daily_lessons_v2 v2
--   ON v2.date = ko.date::date AND v2.level = ko.level AND v2.environment = ko.environment
-- WHERE ko.language = 'ko'
-- ORDER BY ko.date DESC, ko.level, ko.environment;

-- ========================================================
-- 실제 백필
-- ========================================================
INSERT INTO daily_lessons_v2 (
    date, level, environment, theme_en, scenarios, translations,
    english_generated_at, translations_updated_at
)
SELECT
    ko.date::date AS date,
    ko.level,
    ko.environment,
    ko.theme_en,

    -- 영어 시나리오: order/title_en/sentence_en/grammar(pattern+example)만 추출
    (
        SELECT jsonb_agg(
            jsonb_build_object(
                'order', (s->>'order')::int,
                'title_en', s->>'title_en',
                'sentence_en', s->>'sentence_en',
                'grammar', COALESCE(
                    (
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'pattern', g->>'pattern',
                                'example', g->>'example'
                            )
                        )
                        FROM jsonb_array_elements(s->'grammar') g
                    ),
                    '[]'::jsonb
                )
            )
            ORDER BY (s->>'order')::int
        )
        FROM jsonb_array_elements(ko.scenarios) s
    ) AS scenarios,

    -- 번역 맵: translations.ko (항상) + translations.ja (있을 때)
    (
        jsonb_build_object(
            'ko',
            jsonb_build_object(
                'theme', ko.theme_ko,
                'scenarios', (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'order', (s->>'order')::int,
                            'title', s->>'title_ko',
                            'context', COALESCE(s->>'context', ''),
                            'sentence', s->>'sentence_ko',
                            'grammar_explanations', COALESCE(
                                (
                                    SELECT jsonb_agg(g->>'explanation')
                                    FROM jsonb_array_elements(s->'grammar') g
                                ),
                                '[]'::jsonb
                            )
                        )
                        ORDER BY (s->>'order')::int
                    )
                    FROM jsonb_array_elements(ko.scenarios) s
                )
            )
        )
        ||
        COALESCE(
            (
                SELECT jsonb_build_object(
                    'ja',
                    jsonb_build_object(
                        'theme', ja.theme_ko,  -- v1의 ja row는 theme_ko 컬럼에 일본어 저장
                        'scenarios', (
                            SELECT jsonb_agg(
                                jsonb_build_object(
                                    'order', (s->>'order')::int,
                                    'title', s->>'title_ko',
                                    'context', COALESCE(s->>'context', ''),
                                    'sentence', s->>'sentence_ko',
                                    'grammar_explanations', COALESCE(
                                        (
                                            SELECT jsonb_agg(g->>'explanation')
                                            FROM jsonb_array_elements(s->'grammar') g
                                        ),
                                        '[]'::jsonb
                                    )
                                )
                                ORDER BY (s->>'order')::int
                            )
                            FROM jsonb_array_elements(ja.scenarios) s
                        )
                    )
                )
                FROM daily_lessons ja
                WHERE ja.date = ko.date
                  AND ja.level = ko.level
                  AND ja.environment = ko.environment
                  AND ja.language = 'ja'
                LIMIT 1
            ),
            '{}'::jsonb
        )
    ) AS translations,

    NOW() AS english_generated_at,
    NOW() AS translations_updated_at

FROM daily_lessons ko
WHERE ko.language = 'ko'
ON CONFLICT (date, level, environment) DO NOTHING;

-- ========================================================
-- 검증 쿼리
-- ========================================================
-- 1) 백필된 row 수
-- SELECT COUNT(*) FROM daily_lessons_v2;
--
-- 2) 언어별 커버리지
-- SELECT
--   COUNT(*) FILTER (WHERE translations ? 'ko') AS ko_count,
--   COUNT(*) FILTER (WHERE translations ? 'ja') AS ja_count,
--   COUNT(*) AS total
-- FROM daily_lessons_v2;
--
-- 3) 스키마 검증: scenarios 첫 row
-- SELECT date, level, environment,
--   jsonb_pretty(scenarios) AS scenarios,
--   jsonb_pretty(translations) AS translations
-- FROM daily_lessons_v2
-- ORDER BY date DESC LIMIT 1;
--
-- 4) 번역이 누락된 row (translate-lessons 함수로 채워야 함)
-- SELECT date, level, environment
-- FROM daily_lessons_v2
-- WHERE NOT (translations ? 'ja')
-- ORDER BY date DESC;
