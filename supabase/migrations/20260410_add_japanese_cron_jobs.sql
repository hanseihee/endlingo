-- 일본어 레슨 자동 생성 pg_cron 작업 추가
-- 기존 한국어(ko) 작업과 동일한 스케줄로 10분 지연 실행 (00:10~00:15 KST / 15:10~15:15 UTC)
-- 한국어 작업이 15:00~15:05 UTC에 실행되므로 동시 호출로 인한 OpenAI rate limit 부담을 피함

-- 기존 ja 작업이 있다면 제거 (재실행 가능하도록)
SELECT cron.unschedule(jobname)
FROM cron.job
WHERE jobname IN (
  'generate-ja-a1', 'generate-ja-a2', 'generate-ja-b1',
  'generate-ja-b2', 'generate-ja-c1', 'generate-ja-c2'
);

-- A1 일본어: 00:10 KST
SELECT cron.schedule(
  'generate-ja-a1',
  '10 15 * * *',
  $$
  SELECT net.http_post(
    url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{"level": "A1", "language": "ja"}'::jsonb
  );
  $$
);

-- A2 일본어: 00:11 KST
SELECT cron.schedule(
  'generate-ja-a2',
  '11 15 * * *',
  $$
  SELECT net.http_post(
    url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{"level": "A2", "language": "ja"}'::jsonb
  );
  $$
);

-- B1 일본어: 00:12 KST
SELECT cron.schedule(
  'generate-ja-b1',
  '12 15 * * *',
  $$
  SELECT net.http_post(
    url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{"level": "B1", "language": "ja"}'::jsonb
  );
  $$
);

-- B2 일본어: 00:13 KST
SELECT cron.schedule(
  'generate-ja-b2',
  '13 15 * * *',
  $$
  SELECT net.http_post(
    url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{"level": "B2", "language": "ja"}'::jsonb
  );
  $$
);

-- C1 일본어: 00:14 KST
SELECT cron.schedule(
  'generate-ja-c1',
  '14 15 * * *',
  $$
  SELECT net.http_post(
    url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{"level": "C1", "language": "ja"}'::jsonb
  );
  $$
);

-- C2 일본어: 00:15 KST
SELECT cron.schedule(
  'generate-ja-c2',
  '15 15 * * *',
  $$
  SELECT net.http_post(
    url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/generate-daily-lessons',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{"level": "C2", "language": "ja"}'::jsonb
  );
  $$
);

-- 확인 쿼리 (수동 실행용)
-- SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname LIKE '%ja-%' ORDER BY jobname;
