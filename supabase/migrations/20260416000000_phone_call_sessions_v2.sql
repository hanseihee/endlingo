-- Phase 2: phone_call_sessions 확장
-- 1) status/completed_at: Edge Function이 OpenAI 호출 전에 pending row를 선삽입해
--    실패/짧은 통화도 quota에 반영되도록 함 (quota 회피 구멍 차단).
-- 2) review_issues: 영작 피드백을 영구 저장해 히스토리에서도 재열람 가능.

ALTER TABLE phone_call_sessions
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'completed',
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS review_issues JSONB;

-- 기존 row 보정
UPDATE phone_call_sessions
   SET completed_at = started_at + (duration_seconds || ' seconds')::interval
 WHERE completed_at IS NULL;

-- UPDATE 정책 (iOS가 자기 session을 complete로 전환하거나 review_issues 채우기 위함)
DROP POLICY IF EXISTS "Users can update own phone call sessions" ON phone_call_sessions;
CREATE POLICY "Users can update own phone call sessions"
    ON phone_call_sessions FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- pending cleanup용 부분 인덱스
CREATE INDEX IF NOT EXISTS idx_phone_call_sessions_pending
    ON phone_call_sessions (started_at)
    WHERE status = 'pending';
