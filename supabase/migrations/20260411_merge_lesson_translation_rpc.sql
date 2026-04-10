-- translate-lessons Edge Function에서 병렬 호출 시 race condition 방지용 atomic merge RPC.
-- 문제: 두 개의 translate 호출(ko, ja)이 거의 동시에 같은 row의 translations JSONB를 읽고,
--      각자 자신의 언어를 머지한 뒤 전체를 덮어쓰면 먼저 쓴 쪽의 번역이 사라짐.
-- 해결: Postgres의 `||` JSONB concat 연산자로 서버 측 원자 merge를 수행.

CREATE OR REPLACE FUNCTION public.merge_lesson_translation(
    p_id uuid,
    p_lang text,
    p_payload jsonb
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
    UPDATE public.daily_lessons_v2
    SET translations = translations || jsonb_build_object(p_lang, p_payload)
    WHERE id = p_id;
$$;

GRANT EXECUTE ON FUNCTION public.merge_lesson_translation(uuid, text, jsonb) TO service_role;
