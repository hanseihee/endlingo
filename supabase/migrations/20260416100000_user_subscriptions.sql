-- RevenueCat webhook으로 동기화되는 사용자별 구독 상태.
-- realtime-session Edge Function이 이 테이블을 조회해 tier를 결정.
CREATE TABLE IF NOT EXISTS user_subscriptions (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    tier TEXT NOT NULL DEFAULT 'free',          -- 'free' | 'premium'
    is_active BOOLEAN NOT NULL DEFAULT false,
    product_id TEXT,                             -- com.realmasse.yeongeohaja.pro.monthly 등
    expires_at TIMESTAMPTZ,
    last_event TEXT,                             -- INITIAL_PURCHASE / RENEWAL / EXPIRATION 등
    last_event_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users read own subscription"
    ON user_subscriptions FOR SELECT
    USING (auth.uid() = user_id);

-- pending cleanup: 24시간 이상 pending 상태인 phone_call_sessions 자동 삭제
SELECT cron.schedule(
    'cleanup-pending-sessions',
    '0 */6 * * *',
    $$DELETE FROM phone_call_sessions WHERE status = 'pending' AND started_at < now() - interval '24 hours'$$
);
