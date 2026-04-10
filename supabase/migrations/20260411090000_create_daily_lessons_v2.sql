-- daily_lessons_v2: 영어 콘텐츠 단일 생성 + 다국어 번역 확장 구조
-- 기존 daily_lessons(v1)와 공존, 무중단 마이그레이션을 위해 새 테이블로 분리

CREATE TABLE IF NOT EXISTS daily_lessons_v2 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL,
    level TEXT NOT NULL,
    environment TEXT NOT NULL,

    -- 영어 전용 콘텐츠 (언어 추가 시에도 불변)
    theme_en TEXT NOT NULL,
    scenarios JSONB NOT NULL,
    -- scenarios 구조:
    -- [
    --   {
    --     "order": 1,
    --     "title_en": "Asking a Question in Class",
    --     "sentence_en": "Could you explain that part again?",
    --     "grammar": [
    --       { "pattern": "Could you + verb", "example": "Could you open the window?" }
    --     ]
    --   }
    -- ]

    -- 언어별 번역 맵 (append-only). 키는 ISO 639-1 코드 (ko, ja, zh, ...)
    translations JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- translations 구조:
    -- {
    --   "ko": {
    --     "theme": "오늘의 학교 영어",
    --     "scenarios": [
    --       {
    --         "order": 1,
    --         "title": "수업 중 질문하기",
    --         "context": "교수님 설명을 다시 듣고 싶을 때",
    --         "sentence": "그 부분 다시 설명해 주실 수 있나요?",
    --         "grammar_explanations": ["공손하게 요청할 때 쓰는 표현입니다..."]
    --       }
    --     ]
    --   },
    --   "ja": { ... }
    -- }

    english_generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    translations_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(date, level, environment)
);

-- 조회 인덱스 (클라이언트 쿼리: date + level + environment)
CREATE INDEX IF NOT EXISTS idx_lessons_v2_date_level_env
    ON daily_lessons_v2(date, level, environment);

-- 번역 누락 필터용 GIN 인덱스 (translate-lessons 함수에서 `WHERE NOT (translations ? 'ja')` 사용)
CREATE INDEX IF NOT EXISTS idx_lessons_v2_translations_gin
    ON daily_lessons_v2 USING GIN (translations);

-- RLS: 공개 읽기, service_role만 쓰기
ALTER TABLE daily_lessons_v2 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can read lessons v2" ON daily_lessons_v2;
CREATE POLICY "Public can read lessons v2"
    ON daily_lessons_v2 FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Service role can write lessons v2" ON daily_lessons_v2;
CREATE POLICY "Service role can write lessons v2"
    ON daily_lessons_v2 FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- 번역 업데이트 시 자동 타임스탬프 갱신 트리거
CREATE OR REPLACE FUNCTION touch_translations_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.translations IS DISTINCT FROM OLD.translations THEN
        NEW.translations_updated_at = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_lessons_v2_touch_translations ON daily_lessons_v2;
CREATE TRIGGER trg_lessons_v2_touch_translations
    BEFORE UPDATE ON daily_lessons_v2
    FOR EACH ROW
    EXECUTE FUNCTION touch_translations_updated_at();

-- 확인 쿼리 (수동 실행용)
-- SELECT date, level, environment, jsonb_object_keys(translations) AS lang
-- FROM daily_lessons_v2 WHERE date = CURRENT_DATE ORDER BY level, environment;
