-- Premium 시기에 발생한 통화를 Premium 만료 후 Free quota에서 제외하기 위해
-- 세션 발생 시점의 tier를 row에 기록.
--
-- gemini-session Edge Function이 pending row insert 시 그 시점 tier를 함께 저장.
-- quota 계산 시: Free 유저는 tier_at_session='free' 세션만 합산하고,
-- Premium 유저는 premium_activated_at 이후 세션 모두 합산(기존 정책 유지).
--
-- 기존 row는 default 'free'로 backfill — 정확한 historical tier는 알 수 없으므로
-- 보수적으로 free 처리(사용자에게 더 빡빡하지만 abuse 방지). 별도 핫픽스 UPDATE로
-- Premium 시기 세션을 수동 보정 가능.

ALTER TABLE phone_call_sessions
    ADD COLUMN IF NOT EXISTS tier_at_session TEXT NOT NULL DEFAULT 'free';

-- UPDATE guard 트리거에 tier_at_session immutable 추가.
-- 사용자가 자기 row를 PATCH해서 tier_at_session='premium'으로 위조 → quota 회피
-- 가능성을 차단.
CREATE OR REPLACE FUNCTION enforce_phone_call_session_update_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
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
    IF NEW.tier_at_session IS DISTINCT FROM OLD.tier_at_session THEN
        RAISE EXCEPTION 'tier_at_session cannot be changed' USING ERRCODE = 'check_violation';
    END IF;
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
