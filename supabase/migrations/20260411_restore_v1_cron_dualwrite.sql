-- 핫픽스: 실사용자가 있어서 v1(daily_lessons) 테이블도 계속 채워야 함.
-- 전략: v1 cron 복원 + v2 cron 시간대 뒤로 밀어서 OpenAI rate limit 충돌 회피.
-- 구 iOS 앱 사용자가 충분히 신규 빌드로 업데이트될 때까지 (약 2주) dual-write 유지.
-- 이후 별도 마이그레이션으로 v1 cron 제거 예정.
--
-- 스케줄 (KST = UTC + 9h):
--   00:00 ~ 00:05 KST (15:00~15:05 UTC): v1 ko 생성 6개
--   00:10 ~ 00:15 KST (15:10~15:15 UTC): v1 ja 생성 6개
--   00:20 ~ 00:25 KST (15:20~15:25 UTC): v2 영어 생성 6개
--   00:30 KST        (15:30 UTC):        v2 ko 번역
--   00:32 KST        (15:32 UTC):        v2 ja 번역

-- ========================================================
-- 1) 기존 v2 cron 해제 (시간대 재배치를 위해)
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
-- 2) 기존 v1 cron도 한번 해제 (idempotent 재실행 지원)
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
            'generate-b2-ja', 'generate-c1-ja', 'generate-c2-ja'
        )
    LOOP
        PERFORM cron.unschedule(job_name);
    END LOOP;
END $$;

-- ========================================================
-- 3) v1 cron 복원 — ko (00:00~00:05 KST)
-- ========================================================
SELECT cron.schedule('generate-a1', '0 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "A1"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-a2', '1 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "A2"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-b1', '2 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "B1"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-b2', '3 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "B2"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-c1', '4 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "C1"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-c2', '5 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "C2"}'::jsonb
    );
$$);

-- ========================================================
-- 4) v1 cron 복원 — ja (00:10~00:15 KST)
-- ========================================================
SELECT cron.schedule('generate-a1-ja', '10 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "A1", "language": "ja"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-a2-ja', '11 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "A2", "language": "ja"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-b1-ja', '12 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "B1", "language": "ja"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-b2-ja', '13 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "B2", "language": "ja"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-c1-ja', '14 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "C1", "language": "ja"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-c2-ja', '15 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "C2", "language": "ja"}'::jsonb
    );
$$);

-- ========================================================
-- 5) v2 cron 재배치 — 영어 생성 (00:20~00:25 KST)
-- ========================================================
SELECT cron.schedule('generate-en-a1', '20 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "A1"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-en-a2', '21 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "A2"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-en-b1', '22 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "B1"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-en-b2', '23 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "B2"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-en-c1', '24 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "C1"}'::jsonb
    );
$$);

SELECT cron.schedule('generate-en-c2', '25 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"level": "C2"}'::jsonb
    );
$$);

-- ========================================================
-- 6) v2 cron 재배치 — 번역 (00:30 ko, 00:32 ja KST)
-- ========================================================
SELECT cron.schedule('translate-ko', '30 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/translate-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"language": "ko"}'::jsonb
    );
$$);

SELECT cron.schedule('translate-ja', '32 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/translate-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"language": "ja"}'::jsonb
    );
$$);

-- ========================================================
-- 확인 쿼리
-- ========================================================
-- SELECT jobname, schedule, active FROM cron.job ORDER BY substring(schedule from '^[0-9]+')::int;
