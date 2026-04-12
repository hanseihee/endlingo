-- Edge Function 호출에 x-cron-secret 헤더 추가.
-- 외부 무단 호출에 의한 OpenAI API 비용 폭증 방지.
-- CRON_SECRET 은 supabase secrets 에 등록됨.

-- ========================================================
-- 1) 기존 v1 cron 재설정 — ko (00:00~00:05 KST)
-- ========================================================
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-a1') THEN PERFORM cron.unschedule('generate-a1'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-a2') THEN PERFORM cron.unschedule('generate-a2'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-b1') THEN PERFORM cron.unschedule('generate-b1'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-b2') THEN PERFORM cron.unschedule('generate-b2'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-c1') THEN PERFORM cron.unschedule('generate-c1'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-c2') THEN PERFORM cron.unschedule('generate-c2'); END IF; END $$;

SELECT cron.schedule('generate-a1', '0 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "A1"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-a2', '1 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "A2"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-b1', '2 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "B1"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-b2', '3 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "B2"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-c1', '4 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "C1"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-c2', '5 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "C2"}'::jsonb
    );
$$);

-- ========================================================
-- 2) 기존 v1 cron 재설정 — ja (00:10~00:15 KST)
-- ========================================================
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-a1-ja') THEN PERFORM cron.unschedule('generate-a1-ja'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-a2-ja') THEN PERFORM cron.unschedule('generate-a2-ja'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-b1-ja') THEN PERFORM cron.unschedule('generate-b1-ja'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-b2-ja') THEN PERFORM cron.unschedule('generate-b2-ja'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-c1-ja') THEN PERFORM cron.unschedule('generate-c1-ja'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-c2-ja') THEN PERFORM cron.unschedule('generate-c2-ja'); END IF; END $$;

SELECT cron.schedule('generate-a1-ja', '10 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "A1", "language": "ja"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-a2-ja', '11 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "A2", "language": "ja"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-b1-ja', '12 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "B1", "language": "ja"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-b2-ja', '13 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "B2", "language": "ja"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-c1-ja', '14 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "C1", "language": "ja"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-c2-ja', '15 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "C2", "language": "ja"}'::jsonb
    );
$$);

-- ========================================================
-- 3) v2 cron 재설정 — 영어 생성 (00:20~00:25 KST)
-- ========================================================
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-en-a1') THEN PERFORM cron.unschedule('generate-en-a1'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-en-a2') THEN PERFORM cron.unschedule('generate-en-a2'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-en-b1') THEN PERFORM cron.unschedule('generate-en-b1'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-en-b2') THEN PERFORM cron.unschedule('generate-en-b2'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-en-c1') THEN PERFORM cron.unschedule('generate-en-c1'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-en-c2') THEN PERFORM cron.unschedule('generate-en-c2'); END IF; END $$;

SELECT cron.schedule('generate-en-a1', '20 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "A1"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-en-a2', '21 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "A2"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-en-b1', '22 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "B1"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-en-b2', '23 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "B2"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-en-c1', '24 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "C1"}'::jsonb
    );
$$);
SELECT cron.schedule('generate-en-c2', '25 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-english-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"level": "C2"}'::jsonb
    );
$$);

-- ========================================================
-- 4) v2 cron 재설정 — 번역 (00:30 ko, 00:32 ja, 00:34 vi KST)
-- ========================================================
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'translate-ko') THEN PERFORM cron.unschedule('translate-ko'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'translate-ja') THEN PERFORM cron.unschedule('translate-ja'); END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'translate-vi') THEN PERFORM cron.unschedule('translate-vi'); END IF; END $$;

SELECT cron.schedule('translate-ko', '30 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/translate-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"language": "ko"}'::jsonb
    );
$$);

SELECT cron.schedule('translate-ja', '32 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/translate-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"language": "ja"}'::jsonb
    );
$$);

SELECT cron.schedule('translate-vi', '34 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/translate-lessons',
        headers := '{"Content-Type": "application/json", "x-cron-secret": "36f1ed88806046e587c0a24c9620939f"}'::jsonb,
        body := '{"language": "vi"}'::jsonb
    );
$$);
