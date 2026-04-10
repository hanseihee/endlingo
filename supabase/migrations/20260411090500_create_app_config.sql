-- app_config: 강제 업데이트 및 버전 제어용 설정 테이블
-- 클라이언트는 앱 시작 시 이 테이블을 조회하여 현재 빌드 버전과 비교.
-- current_version < min_supported_version 이면 차단 화면 표시.
--
-- 운영 시나리오:
--   1. 평소: min_supported_version 은 이미 배포된 최신 버전으로 유지
--   2. breaking change 릴리즈 직후: min_supported_version 을 새 버전으로 UPDATE
--      → 구버전 사용자 전원에게 즉시 강제 업데이트 통보
--   3. 긴급 보안 패치, 백엔드 비호환 등에도 재사용 가능

CREATE TABLE IF NOT EXISTS app_config (
    platform TEXT PRIMARY KEY,             -- 'ios', 'android' 확장 가능
    min_supported_version TEXT NOT NULL,   -- 이 미만의 current_version 은 차단
    latest_version TEXT NOT NULL,          -- 소프트 알림용 (현재 미사용, 추후 확장)
    update_message_ko TEXT NOT NULL,
    update_message_ja TEXT NOT NULL,
    app_store_url TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can read app_config" ON app_config;
CREATE POLICY "Public can read app_config"
    ON app_config FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Service role can write app_config" ON app_config;
CREATE POLICY "Service role can write app_config"
    ON app_config FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- 초기 row: iOS 플랫폼
-- min_supported_version 을 1.3.0 으로 설정 (이번 릴리즈와 동일)
-- → 1.3.0 사용자는 차단되지 않음
-- → 다음 breaking change 시 UPDATE app_config SET min_supported_version = '1.4.0'
-- E'...' 문법으로 실제 줄바꿈 문자(\n) 삽입. 일반 문자열은 리터럴 두 글자(\ + n)로 저장됨.
INSERT INTO app_config (
    platform,
    min_supported_version,
    latest_version,
    update_message_ko,
    update_message_ja,
    app_store_url
) VALUES (
    'ios',
    '1.3.0',
    '1.3.0',
    E'새로운 버전이 필요합니다.\n앱 스토어에서 최신 버전을 받아주세요.',
    E'新しいバージョンが必要です。\nApp Storeで最新版を入手してください。',
    'https://apps.apple.com/app/id6760590621'
)
ON CONFLICT (platform) DO NOTHING;
