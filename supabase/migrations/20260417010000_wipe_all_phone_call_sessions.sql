-- 개발 단계 초기화:
-- 테스트 중 실패한 session.update로 인해 모든 사용자 quota가 소진되어
-- 테스트 불가. phone_call_sessions 테이블 전체 truncate.
-- 실제 운영 배포 시에는 이 migration을 건너뛰어야 함 (이미 applied 상태로 기록됨).
TRUNCATE TABLE phone_call_sessions;
