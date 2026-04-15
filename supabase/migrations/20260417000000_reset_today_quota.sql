-- 일회성: 테스트 중 실패/버그로 소진된 오늘 quota를 초기화
-- 대상: trixh@gmeremit.com (개발자 본인)
-- 조건: UTC 기준 오늘(00:00 이후)에 만든 phone_call_sessions 모두 삭제
DELETE FROM phone_call_sessions
 WHERE user_id = (SELECT id FROM auth.users WHERE email = 'trixh@gmeremit.com')
   AND started_at >= date_trunc('day', now() AT TIME ZONE 'UTC');
