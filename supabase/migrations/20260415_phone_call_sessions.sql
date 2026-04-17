-- AI 전화영어 통화 기록 테이블
CREATE TABLE IF NOT EXISTS phone_call_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    scenario_id TEXT NOT NULL,
    scenario_title TEXT NOT NULL,
    persona_name TEXT NOT NULL,
    persona_emoji TEXT,
    duration_seconds INT NOT NULL DEFAULT 0,
    transcript JSONB NOT NULL DEFAULT '[]'::jsonb,
    started_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE phone_call_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own phone call sessions"
    ON phone_call_sessions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own phone call sessions"
    ON phone_call_sessions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own phone call sessions"
    ON phone_call_sessions FOR DELETE
    USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_phone_call_sessions_user_started
    ON phone_call_sessions (user_id, started_at DESC);
