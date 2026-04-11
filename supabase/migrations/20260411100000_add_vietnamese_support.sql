-- 베트남어 (vi) 지원 추가
-- 1) app_config.update_message_vi 컬럼 추가 (강제 업데이트 메시지 vi 버전)
-- 2) v2 translate-lessons cron에 vi 번역 작업 추가 (00:34 KST)
--
-- v1 legacy cron 에는 vi 추가하지 않음 — v1 은 2주 내 제거 예정.
-- v2 파이프라인: en 생성 (00:20~00:25) → ko 번역 (00:30) → ja 번역 (00:32) → vi 번역 (00:34)

-- ========================================================
-- 1) app_config: update_message_vi 컬럼 추가
-- ========================================================
ALTER TABLE app_config
    ADD COLUMN IF NOT EXISTS update_message_vi TEXT;

-- 기존 iOS row 에 vi 메시지 세팅
UPDATE app_config
SET update_message_vi = E'Cần cập nhật phiên bản mới.\nVui lòng tải phiên bản mới nhất từ App Store.'
WHERE platform = 'ios' AND update_message_vi IS NULL;

-- ========================================================
-- 2) v2 cron: vi 번역 (00:34 KST = 15:34 UTC)
-- ========================================================
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'translate-vi') THEN
        PERFORM cron.unschedule('translate-vi');
    END IF;
END $$;

SELECT cron.schedule('translate-vi', '34 15 * * *', $$
    SELECT net.http_post(
        url := 'https://alvawqinuacabfnqduoy.supabase.co/functions/v1/translate-lessons',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{"language": "vi"}'::jsonb
    );
$$);

-- 확인 쿼리 (수동):
-- SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'translate-vi';
-- SELECT platform, update_message_vi FROM app_config;
