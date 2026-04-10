-- 4주 후 자동 정리 스케줄 (2026-05-09 01:00 KST = 16:00 UTC)
-- pg_cron은 원샷 예약을 지원하지 않으므로 매일 실행하되, 날짜 체크로 1회만 동작하도록 구성.
-- 작업 본체는 자가 제거까지 포함하여 완료 후 스케줄에서 사라짐.
--
-- 안전장치:
--   1. CURRENT_DATE >= '2026-04-25' 체크 (그 이전에는 noop)
--   2. daily_lessons_v2에 최근 3일치(각 30 row 이상) 데이터가 있어야 진행 — v2 파이프라인 건전성 확인
--   3. 실패 시 v1 cron은 그대로 유지 (데이터 손실 방지)
--   4. v1 테이블은 DROP하지 않고 rename만 수행 (롤백 가능)
--   5. 이 cleanup 작업은 자가 해제되어 다음날 재실행되지 않음

CREATE OR REPLACE FUNCTION public.cleanup_v1_dualwrite()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
    target_date DATE := DATE '2026-05-09';
    recent_v2_coverage INT;
    v1_jobname TEXT;
BEGIN
    -- 1) 날짜 체크: 목표일 이전이면 아무것도 안 함
    IF CURRENT_DATE < target_date THEN
        RAISE NOTICE 'cleanup-v1: target date % not reached (today=%)', target_date, CURRENT_DATE;
        RETURN;
    END IF;

    -- 2) v2 건전성 체크: 최근 3일 각각 30 row 이상 존재해야 함
    SELECT COUNT(*) INTO recent_v2_coverage
    FROM (
        SELECT date, COUNT(*) AS cnt
        FROM public.daily_lessons_v2
        WHERE date >= CURRENT_DATE - INTERVAL '3 days'
          AND date < CURRENT_DATE
        GROUP BY date
        HAVING COUNT(*) >= 30
    ) t;

    IF recent_v2_coverage < 3 THEN
        RAISE WARNING 'cleanup-v1: v2 health check failed (only % complete days in last 3). Aborting cleanup.', recent_v2_coverage;
        RETURN;
    END IF;

    -- 3) v1 cron 해제
    FOR v1_jobname IN
        SELECT jobname FROM cron.job
        WHERE jobname IN (
            'generate-a1', 'generate-a2', 'generate-b1',
            'generate-b2', 'generate-c1', 'generate-c2',
            'generate-a1-ja', 'generate-a2-ja', 'generate-b1-ja',
            'generate-b2-ja', 'generate-c1-ja', 'generate-c2-ja'
        )
    LOOP
        PERFORM cron.unschedule(v1_jobname);
        RAISE NOTICE 'cleanup-v1: unscheduled %', v1_jobname;
    END LOOP;

    -- 4) v1 테이블 rename (DROP이 아닌 비활성화 — 롤백 가능)
    --    이미 rename되어 있으면 에러 무시
    BEGIN
        EXECUTE format(
            'ALTER TABLE public.daily_lessons RENAME TO daily_lessons_deprecated_%s',
            to_char(CURRENT_DATE, 'YYYYMMDD')
        );
        RAISE NOTICE 'cleanup-v1: renamed daily_lessons → daily_lessons_deprecated_%', to_char(CURRENT_DATE, 'YYYYMMDD');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'cleanup-v1: table rename failed: %', SQLERRM;
    END;

    -- 5) 자가 제거: 이 cleanup 작업 자체를 스케줄에서 해제
    PERFORM cron.unschedule('cleanup-v1-dualwrite');
    RAISE NOTICE 'cleanup-v1: self-unscheduled';

    RAISE NOTICE 'cleanup-v1: complete. Next manual steps: (a) DROP daily_lessons_deprecated_% after verification, (b) delete generate-daily-lessons Edge Function via dashboard', to_char(CURRENT_DATE, 'YYYYMMDD');
END;
$func$;

-- 보안: PUBLIC/anon/authenticated 에서 EXECUTE 회수. service_role 만 호출 가능.
-- (이 함수는 매일 cron 으로만 실행되며, 외부 호출 경로는 제거)
REVOKE EXECUTE ON FUNCTION public.cleanup_v1_dualwrite() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cleanup_v1_dualwrite() FROM anon;
REVOKE EXECUTE ON FUNCTION public.cleanup_v1_dualwrite() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_v1_dualwrite() TO service_role;

-- 기존 cleanup job 제거 (idempotent)
DO $$
BEGIN
    PERFORM cron.unschedule('cleanup-v1-dualwrite');
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- 매일 16:00 UTC (01:00 KST)에 체크. 목표일 이전에는 noop, 도달 후 1회만 정리하고 자가 해제.
-- 01:00 KST는 신규 cron 완료 후 (00:32 KST 번역 완료 후 28분 여유) 시점.
SELECT cron.schedule(
    'cleanup-v1-dualwrite',
    '0 16 * * *',
    $$SELECT public.cleanup_v1_dualwrite();$$
);

-- ========================================================
-- 수동 확인용 쿼리
-- ========================================================
-- 1) 스케줄 확인
-- SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'cleanup-v1-dualwrite';
--
-- 2) 실행 로그 확인 (2026-04-25 이후)
-- SELECT start_time, return_message FROM cron.job_run_details
-- WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'cleanup-v1-dualwrite')
-- ORDER BY start_time DESC LIMIT 10;
--
-- 3) 수동으로 즉시 실행 (테스트용, 날짜 체크 때문에 그 이전에는 noop)
-- SELECT public.cleanup_v1_dualwrite();
--
-- 4) 정리 이후 남은 작업 (수동):
--    - 2주 더 관찰 후: DROP TABLE public.daily_lessons_deprecated_20260509;
--    - Supabase 대시보드에서 Edge Function `generate-daily-lessons` 삭제
