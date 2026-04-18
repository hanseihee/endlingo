-- C2a: user_subscriptions 테이블의 클라이언트 직접 INSERT/UPDATE 차단.
--
-- 이전 migration 20260418000000에서 webhook 지연 대비 클라 upsert 허용 정책을 추가했으나,
-- 악의적 사용자가 본인 JWT로 REST API를 직접 호출해 tier='premium' 위조가 가능한 보안 허점.
-- RLS 정책만 제거하고, 합법적 upsert 경로는 모두 service_role을 쓰는 Edge Function에 맡긴다:
--   - revenuecat-webhook (Apple/RC 서명 검증된 이벤트)
--   - sync-subscription (클라 요청을 받아 서버에서 직접 RevenueCat 검증 후 upsert 예정)
-- SELECT 정책은 그대로 유지 (사용자 본인 구독 상태 조회는 정상 기능).

DROP POLICY IF EXISTS "users insert own subscription" ON user_subscriptions;
DROP POLICY IF EXISTS "users update own subscription" ON user_subscriptions;
