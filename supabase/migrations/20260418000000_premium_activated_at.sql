-- Premium 전환 시점 이후의 통화 세션만 Premium quota에서 합산하기 위한 컬럼.
-- Free → Premium 전환 시 "깨끗한 10분 재시작" UX를 위해 추가.
-- webhook 지연 대비 클라에서 직접 upsert할 수 있도록 RLS 정책도 함께 조정.

ALTER TABLE user_subscriptions
    ADD COLUMN IF NOT EXISTS premium_activated_at TIMESTAMPTZ;

-- 기존 premium row들의 premium_activated_at을 updated_at으로 보정.
-- NULL이면 '영구 premium'으로 해석될 수 있어 현재 행이 premium인 유저에만 backfill.
UPDATE user_subscriptions
   SET premium_activated_at = updated_at
 WHERE tier = 'premium' AND premium_activated_at IS NULL;

-- RLS 보강: 사용자 본인 row의 INSERT/UPDATE 허용.
-- 주의: tier='premium' 승격은 sync-subscription Edge Function(service role) 또는
-- revenuecat-webhook 경유가 정상. 클라 직접 upsert는 webhook 지연 대비 임시 보조.
DROP POLICY IF EXISTS "users insert own subscription" ON user_subscriptions;
CREATE POLICY "users insert own subscription"
    ON user_subscriptions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "users update own subscription" ON user_subscriptions;
CREATE POLICY "users update own subscription"
    ON user_subscriptions FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
