-- C3: phone_call_sessions UPDATE 시 악의적 조작 차단.
--
-- RLS "Users can update own phone call sessions" 정책 때문에 사용자가 본인 JWT로
-- 자기 row를 REST PATCH할 수 있음. 이를 악용해 duration 감소/status 다운그레이드/
-- started_at 백데이팅으로 quota를 회피할 수 있는 허점을 차단.
--
-- 합법 경로는 모두 통과:
--   - PhoneCallController.finalizePendingSession: pending → completed, duration 0 → elapsed
--   - PhoneCallHistoryService.complete:          pending → completed, duration/transcript 세팅
--   - PhoneCallHistoryService.updateReview:      completed → completed, review_issues만
--   - pg_cron cleanup:                           pending → expired, duration 0 → 0
--
-- 한계: duration=0을 유지한 채 completed로 전환하는 공격은 트리거만으로 하한 강제 불가.
-- 완전 방어는 별도 Edge Function으로 UPDATE 경로를 이전하고 서버 측 elapsed 재계산 필요.

CREATE OR REPLACE FUNCTION enforce_phone_call_session_update_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Immutable 필드들
    IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'user_id cannot be changed' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
        RAISE EXCEPTION 'started_at cannot be changed' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.scenario_id IS DISTINCT FROM OLD.scenario_id THEN
        RAISE EXCEPTION 'scenario_id cannot be changed' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.scenario_title IS DISTINCT FROM OLD.scenario_title THEN
        RAISE EXCEPTION 'scenario_title cannot be changed' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.persona_name IS DISTINCT FROM OLD.persona_name THEN
        RAISE EXCEPTION 'persona_name cannot be changed' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.persona_emoji IS DISTINCT FROM OLD.persona_emoji THEN
        RAISE EXCEPTION 'persona_emoji cannot be changed' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'created_at cannot be changed' USING ERRCODE = 'check_violation';
    END IF;

    -- duration_seconds 제약: 음수 금지, completed 이후 불변, pending 동안 감소 금지
    IF NEW.duration_seconds < 0 THEN
        RAISE EXCEPTION 'duration_seconds must be non-negative' USING ERRCODE = 'check_violation';
    END IF;
    IF OLD.status IN ('completed', 'expired')
       AND NEW.duration_seconds <> OLD.duration_seconds THEN
        RAISE EXCEPTION 'duration_seconds is immutable after %', OLD.status
          USING ERRCODE = 'check_violation';
    END IF;
    IF OLD.status = 'pending' AND NEW.duration_seconds < OLD.duration_seconds THEN
        RAISE EXCEPTION 'duration_seconds cannot decrease' USING ERRCODE = 'check_violation';
    END IF;

    -- status 전환 규칙: 종결 상태에서는 변경 금지. pending에서는 허용된 라벨만.
    IF OLD.status IN ('completed', 'expired') AND NEW.status <> OLD.status THEN
        RAISE EXCEPTION 'status cannot change after %', OLD.status
          USING ERRCODE = 'check_violation';
    END IF;
    IF OLD.status = 'pending' AND NEW.status NOT IN ('pending', 'completed', 'expired') THEN
        RAISE EXCEPTION 'invalid status transition from pending' USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS phone_call_sessions_update_guard ON phone_call_sessions;
CREATE TRIGGER phone_call_sessions_update_guard
BEFORE UPDATE ON phone_call_sessions
FOR EACH ROW
EXECUTE FUNCTION enforce_phone_call_session_update_guard();
