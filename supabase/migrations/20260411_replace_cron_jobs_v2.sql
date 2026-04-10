-- cron 교체: 기존 generate-daily-lessons (v1) 12개 job → 신규 v2 파이프라인 8개 job
-- 기존: generate-a1 ~ generate-c2 (ko) + generate-a1-ja ~ generate-c2-ja (ja) = 12개
-- 신규: generate-en-a1 ~ generate-en-c2 (영어 생성) + translate-ko/ja = 8개
--
-- 스케줄:
--   15:00 ~ 15:05 UTC (00:00 ~ 00:05 KST): 영어 생성 (6 jobs, 1분 간격)
--   15:10 UTC (00:10 KST): 한국어 번역 (영어 생성 완료 후 5분 여유)
--   15:12 UTC (00:12 KST): 일본어 번역 (한국어 번역과 2분 간격, rate limit 배려)
--
-- 새 언어 추가 시: LANGUAGE_RULES에 블록 추가 + 이 파일에 cron 한 줄 추가 + 과거 데이터 한 번 백필

-- ========================================================
-- 1) 기존 v1 job 제거
-- ========================================================
DO $$
DECLARE
    job_name TEXT;
BEGIN
    FOR job_name IN
        SELECT jobname FROM cron.job
        WHERE jobname IN (
            'generate-a1', 'generate-a2', 'generate-b1',
            'generate-b2', 'generate-c1', 'generate-c2',
            'generate-a1-ja', 'generate-a2-ja', 'generate-b1-ja',
            'generate-b2-ja', 'generate-c1-ja', 'generate-c2-ja',
            'generate-ja-a1', 'generate-ja-a2', 'generate-ja-b1',
            'generate-ja-b2', 'generate-ja-c1', 'generate-ja-c2'
        )
    LOOP
        PERFORM cron.unschedule(job_name);
    END LOOP;
END $$;

-- ========================================================
-- 2) 기존 v2 job 제거 (idempotent 재실행 지원)
-- ========================================================
DO $$
DECLARE
    job_name TEXT;
BEGIN
    FOR job_name IN
        SELECT jobname FROM cron.job
        WHERE jobname LIKE 'generate-en-%' OR jobname LIKE 'translate-%'
    LOOP
        PERFORM cron.unschedule(job_name);
    END LOOP;
END $$;

-- ========================================================
-- 3) 신규 영어 생성 job (6개)
-- ========================================================
SELECT cron.schedule(
    'generate-en-a1',
    '0 15 * * *',
    $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "A1"}'::jsonb
    );
    $$
);

SELECT cron.schedule(
    'generate-en-a2',
    '1 15 * * *',
    $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "A2"}'::jsonb
    );
    $$
);

SELECT cron.schedule(
    'generate-en-b1',
    '2 15 * * *',
    $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "B1"}'::jsonb
    );
    $$
);

SELECT cron.schedule(
    'generate-en-b2',
    '3 15 * * *',
    $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "B2"}'::jsonb
    );
    $$
);

SELECT cron.schedule(
    'generate-en-c1',
    '4 15 * * *',
    $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "C1"}'::jsonb
    );
    $$
);

SELECT cron.schedule(
    'generate-en-c2',
    '5 15 * * *',
    $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "C2"}'::jsonb
    );
    $$
);

-- ========================================================
-- 4) 신규 번역 job (2개, 영어 생성 완료 후 실행)
-- ========================================================
SELECT cron.schedule(
    'translate-ko',
    '10 15 * * *',  -- 00:10 KST
    $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/translate-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"language": "ko"}'::jsonb
    );
    $$
);

SELECT cron.schedule(
    'translate-ja',
    '12 15 * * *',  -- 00:12 KST
    $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/translate-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"language": "ja"}'::jsonb
    );
    $$
);

-- ========================================================
-- 확인 쿼리 (수동 실행용)
-- ========================================================
-- SELECT jobname, schedule, active FROM cron.job ORDER BY jobname;
