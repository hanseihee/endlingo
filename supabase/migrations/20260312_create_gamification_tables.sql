-- 학습 기록 (하루 1회)
CREATE TABLE learning_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    date TEXT NOT NULL,
    level TEXT NOT NULL,
    environment TEXT NOT NULL,
    xp_earned INTEGER NOT NULL DEFAULT 10,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, date)
);

ALTER TABLE learning_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own records" ON learning_records FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own records" ON learning_records FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 퀴즈 결과
CREATE TABLE quiz_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    date TEXT NOT NULL,
    quiz_type TEXT NOT NULL,
    word_id UUID NOT NULL,
    word TEXT NOT NULL,
    is_correct BOOLEAN NOT NULL,
    xp_earned INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE quiz_results ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own results" ON quiz_results FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own results" ON quiz_results FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 획득 배지
CREATE TABLE earned_badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    badge_type TEXT NOT NULL,
    earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, badge_type)
);

ALTER TABLE earned_badges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own badges" ON earned_badges FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own badges" ON earned_badges FOR INSERT WITH CHECK (auth.uid() = user_id);
