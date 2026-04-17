-- pending cleanup을 DELETE → UPDATE로 변경.
-- 삭제 대신 status='expired'로 전환해 감사/디버깅 로그 보존.
SELECT cron.unschedule('cleanup-pending-sessions');
SELECT cron.schedule(
    'cleanup-pending-sessions',
    '0 */6 * * *',
    $$UPDATE phone_call_sessions SET status = 'expired', duration_seconds = 0 WHERE status = 'pending' AND started_at < now() - interval '24 hours'$$
);
