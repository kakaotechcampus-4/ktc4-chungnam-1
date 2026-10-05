"""initial schema

재설계한 새록 PostgreSQL 스키마(backend/database/init.sql)를 Alembic이 소유하는
initial migration으로 옮긴다. 이전 스키마의 두 migration(db2bf9003e7f,
a8c31f17d902)을 이 하나로 교체했으므로, 이전 migration을 적용한 DB는 지우고
다시 만든 뒤 `alembic upgrade head`를 실행한다.

init.sql의 개발 편의용 `DROP ... CASCADE`는 옮기지 않는다. 이 migration은 빈
DB에 스키마를 새로 만드는 것만 책임진다. 나머지 SQL은 init.sql과 같다. 스키마를
바꿀 때는 이 파일을 고치지 않고 새 migration을 추가한다.

`ON DELETE SET NULL (column)` 구문을 쓰므로 PostgreSQL 15 이상이 필요하다.

Revision ID: f8fd6d0e862c
Revises:
Create Date: 2026-10-04 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'f8fd6d0e862c'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    # -----------------------------------------------------------------
    # S3 삭제 대기열
    # -----------------------------------------------------------------
    op.execute("""
CREATE TABLE storage_deletion_request_queue (
    s3_object_key VARCHAR(255) PRIMARY KEY,
    requested_at  TIMESTAMPTZ NOT NULL DEFAULT now()
)
""")
    op.execute("""
CREATE FUNCTION queue_storage_deletion() RETURNS trigger AS $$
BEGIN
    INSERT INTO storage_deletion_request_queue (s3_object_key) VALUES (OLD.s3_object_key)
    ON CONFLICT DO NOTHING;
    RETURN OLD;
END $$ LANGUAGE plpgsql
""")

    # -----------------------------------------------------------------
    # 계정과 동의 이력
    # -----------------------------------------------------------------
    op.execute("""
CREATE TABLE users (
    user_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_sub   VARCHAR(255) NOT NULL UNIQUE CHECK (length(btrim(google_sub)) > 0),
    display_name VARCHAR(50),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
)
""")
    op.execute("""
CREATE TABLE consent_records (
    record_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id             UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    terms_version       VARCHAR(20) NOT NULL,
    service_data        BOOLEAN     NOT NULL CHECK (service_data),
    sensitive_data      BOOLEAN     NOT NULL CHECK (sensitive_data),
    service_improvement BOOLEAN     NOT NULL,
    push_notification   BOOLEAN     NOT NULL,
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT now()
)
""")
    op.execute("""
CREATE INDEX idx_consent_records_latest
    ON consent_records(user_id, recorded_at DESC, record_id DESC)
""")
    op.execute("""
CREATE VIEW current_consents AS
SELECT DISTINCT ON (user_id) *
  FROM consent_records
 ORDER BY user_id, recorded_at DESC, record_id DESC
""")

    # -----------------------------------------------------------------
    # 프로필과 생애 정보
    # -----------------------------------------------------------------
    op.execute("""
CREATE TABLE profiles (
    profile_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    name            VARCHAR(50) NOT NULL,
    gender          VARCHAR(10) NOT NULL CHECK (gender IN ('male', 'female')),
    birth_date      DATE        NOT NULL,
    condition_stage VARCHAR(30) NOT NULL CHECK (condition_stage IN
                      ('mildCognitiveImpairment', 'mildDementia', 'unknown')),
    symptom_note    TEXT,
    occupation      TEXT CHECK (length(btrim(occupation)) > 0),
    hometown        TEXT CHECK (length(btrim(hometown)) > 0),
    hobby           TEXT CHECK (length(btrim(hobby)) > 0),
    family          TEXT CHECK (length(btrim(family)) > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
)
""")
    op.execute("CREATE INDEX idx_profiles_user ON profiles(user_id, created_at)")

    # source_proposal_id의 FK는 life_fact_proposals가 아직 없어 뒤에서 ALTER로
    # 붙인다(init.sql과 같은 순서).
    op.execute("""
CREATE TABLE life_facts (
    fact_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id     UUID         NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    title          VARCHAR(100) NOT NULL CHECK (length(btrim(title)) > 0),
    content        TEXT         NOT NULL CHECK (length(btrim(content)) > 0),
    source_proposal_id UUID     UNIQUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
)
""")
    op.execute(
        "CREATE INDEX idx_life_facts_profile ON life_facts(profile_id, created_at)"
    )

    # -----------------------------------------------------------------
    # 면회 회차 (평가와 리포트 포함)
    # -----------------------------------------------------------------
    op.execute("""
CREATE TABLE visit_sessions (
    session_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id              UUID        NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    started_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    evaluation_satisfaction SMALLINT    CHECK (evaluation_satisfaction BETWEEN 1 AND 5),
    evaluation_reaction     VARCHAR(15) CHECK (evaluation_reaction IN
                              ('pleased', 'calm', 'angry', 'lowEnergy', 'unknown')),
    evaluation_note         TEXT,
    evaluated_at            TIMESTAMPTZ,
    report_title            VARCHAR(200),
    report_body             TEXT,
    report_model            VARCHAR(100),
    report_prompt_version   VARCHAR(50),
    report_generated_at     TIMESTAMPTZ,
    UNIQUE (session_id, profile_id),
    CHECK (CASE WHEN evaluated_at IS NULL
                THEN evaluation_satisfaction IS NULL AND evaluation_reaction IS NULL AND evaluation_note IS NULL
                ELSE evaluation_satisfaction IS NOT NULL AND evaluation_reaction IS NOT NULL END),
    CHECK (CASE WHEN report_generated_at IS NULL
                THEN report_title IS NULL AND report_body IS NULL
                     AND report_model IS NULL AND report_prompt_version IS NULL
                ELSE report_title IS NOT NULL AND report_body IS NOT NULL
                     AND report_model IS NOT NULL AND report_prompt_version IS NOT NULL
                     AND evaluated_at IS NOT NULL END)
)
""")
    op.execute(
        "CREATE INDEX idx_visit_sessions_profile "
        "ON visit_sessions(profile_id, started_at DESC)"
    )

    # -----------------------------------------------------------------
    # 카드 생성 작업, 주제와 대화 카드
    # -----------------------------------------------------------------
    op.execute("""
CREATE TABLE card_sets (
    set_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id     UUID         NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    session_id     UUID         UNIQUE,
    status         VARCHAR(10)  NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
    error_code     VARCHAR(50),
    model          VARCHAR(100) NOT NULL,
    prompt_version VARCHAR(50)  NOT NULL,
    generation_log JSONB        CHECK (jsonb_typeof(generation_log) = 'object' AND generation_log ? 'input'),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    FOREIGN KEY (session_id, profile_id)
        REFERENCES visit_sessions(session_id, profile_id) ON DELETE CASCADE,
    UNIQUE (set_id, profile_id),
    CHECK ((status = 'failed') = (error_code IS NOT NULL)),
    CHECK ((status = 'running') = (generation_log IS NULL)),
    CHECK (session_id IS NULL OR status = 'completed')
)
""")
    op.execute(
        "CREATE INDEX idx_card_sets_profile ON card_sets(profile_id, created_at DESC)"
    )
    op.execute(
        "CREATE UNIQUE INDEX uq_card_sets_running ON card_sets(profile_id) "
        "WHERE status = 'running'"
    )

    op.execute("""
CREATE TABLE profile_topics (
    topic_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id        UUID         NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    title             VARCHAR(100) NOT NULL CHECK (length(btrim(title)) > 0),
    description       TEXT         NOT NULL CHECK (length(btrim(description)) > 0),
    evidence          JSONB        NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(evidence) = 'array'),
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (topic_id, profile_id)
)
""")
    op.execute(
        "CREATE INDEX idx_profile_topics_profile "
        "ON profile_topics(profile_id, created_at)"
    )

    op.execute("""
CREATE TABLE conversation_cards (
    card_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    set_id              UUID     NOT NULL,
    profile_id          UUID     NOT NULL,
    topic_id            UUID     NOT NULL,
    card_title          VARCHAR(100) NOT NULL,
    position            SMALLINT NOT NULL CHECK (position BETWEEN 1 AND 12),
    description         TEXT     NOT NULL,
    primary_question    TEXT     NOT NULL,
    follow_up_questions TEXT[]   NOT NULL CHECK (cardinality(follow_up_questions) >= 1),
    evidence_source     VARCHAR(10) NOT NULL CHECK (evidence_source IN ('life_fact', 'photo', 'none')),
    evidence            JSONB    NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(evidence) = 'array'),
    selected            BOOLEAN  NOT NULL DEFAULT false,
    review_reaction     VARCHAR(10) CHECK (review_reaction IN ('positive', 'neutral', 'negative', 'notUsed')),
    report_summary      TEXT     CHECK (length(btrim(report_summary)) > 0),
    FOREIGN KEY (set_id, profile_id)
        REFERENCES card_sets(set_id, profile_id) ON DELETE CASCADE,
    FOREIGN KEY (topic_id, profile_id)
        REFERENCES profile_topics(topic_id, profile_id),
    UNIQUE (set_id, position),
    UNIQUE (set_id, topic_id),
    UNIQUE (card_id, topic_id, profile_id),
    CHECK (review_reaction IS NULL OR selected),
    CHECK (report_summary IS NULL OR coalesce(review_reaction IN ('positive', 'neutral', 'negative'), false)),
    CHECK (CASE WHEN jsonb_typeof(evidence) <> 'array' THEN false
                WHEN evidence_source IN ('life_fact', 'photo') THEN jsonb_array_length(evidence) > 0
                ELSE evidence = '[]'::jsonb END)
)
""")
    op.execute(
        "CREATE INDEX idx_conversation_cards_topic ON conversation_cards(topic_id)"
    )

    # -----------------------------------------------------------------
    # 사진 (프로필 사진과 면회 사진)
    # -----------------------------------------------------------------
    op.execute("""
CREATE TABLE photos (
    photo_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID         NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    session_id      UUID,
    s3_object_key   VARCHAR(255) NOT NULL UNIQUE,
    description     TEXT,
    analysis_status VARCHAR(12)  NOT NULL DEFAULT 'pending'
                      CHECK (analysis_status IN ('pending', 'processing', 'completed', 'failed')),
    error_code      VARCHAR(50),
    model           VARCHAR(100),
    prompt_version  VARCHAR(50),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    FOREIGN KEY (session_id, profile_id)
        REFERENCES visit_sessions(session_id, profile_id) ON DELETE CASCADE,
    CHECK ((analysis_status = 'failed') = (error_code IS NOT NULL)),
    CHECK (CASE WHEN analysis_status = 'completed'
                THEN description IS NOT NULL AND model IS NOT NULL AND prompt_version IS NOT NULL
                ELSE description IS NULL AND model IS NULL AND prompt_version IS NULL END)
)
""")
    op.execute("CREATE INDEX idx_photos_profile ON photos(profile_id, created_at)")
    op.execute(
        "CREATE INDEX idx_photos_pending ON photos(created_at) "
        "WHERE analysis_status = 'pending'"
    )
    op.execute(
        "CREATE UNIQUE INDEX uq_photos_session ON photos(session_id) "
        "WHERE session_id IS NOT NULL"
    )
    op.execute("""
CREATE TRIGGER photos_queue_storage_deletion
    AFTER DELETE ON photos
    FOR EACH ROW EXECUTE FUNCTION queue_storage_deletion()
""")

    # -----------------------------------------------------------------
    # 비동기 음성 분석 작업
    # -----------------------------------------------------------------
    op.execute("""
CREATE TABLE speech_analysis_jobs (
    analysis_id       UUID PRIMARY KEY,
    session_id        UUID         NOT NULL REFERENCES visit_sessions(session_id) ON DELETE CASCADE,
    status            VARCHAR(20)  NOT NULL CHECK (status IN
                        ('uploading', 'queued', 'transcribing', 'sttCompleted',
                         'generatingReport', 'completed', 'failed')),
    participant_count SMALLINT     NOT NULL CHECK (participant_count BETWEEN 1 AND 8),
    s3_object_key     VARCHAR(255) NOT NULL,
    size_bytes        BIGINT,
    sha256            VARCHAR(64),
    data_expires_at   TIMESTAMPTZ  NOT NULL,
    attempt_count     SMALLINT     NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    lease_expires_at  TIMESTAMPTZ,
    error_code        VARCHAR(50),
    audio_deleted_at  TIMESTAMPTZ,
    stt_completed_at  TIMESTAMPTZ,
    transcript            JSONB CHECK (jsonb_typeof(transcript) = 'object'),
    transcript_expires_at TIMESTAMPTZ,
    transcript_deleted_at TIMESTAMPTZ,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    completed_at      TIMESTAMPTZ,
    CHECK (CASE WHEN status = 'uploading' THEN size_bytes IS NULL AND sha256 IS NULL
                WHEN status = 'failed' AND size_bytes IS NULL THEN sha256 IS NULL
                ELSE size_bytes IS NOT NULL AND size_bytes > 0
                     AND sha256 IS NOT NULL AND sha256 ~ '^[0-9a-f]{64}$' END),
    CHECK (status <> 'failed' OR error_code IS NOT NULL),
    CHECK (status NOT IN ('uploading', 'transcribing', 'generatingReport') OR lease_expires_at IS NOT NULL),
    CHECK (transcript IS NULL OR status IN ('sttCompleted', 'generatingReport')),
    CHECK (status <> 'sttCompleted' OR transcript IS NOT NULL),
    CHECK (transcript IS NULL OR transcript_expires_at IS NOT NULL),
    CHECK (transcript_deleted_at IS NULL OR transcript IS NULL)
)
""")
    op.execute("""
CREATE UNIQUE INDEX uq_speech_analysis_jobs_session
    ON speech_analysis_jobs(session_id) WHERE status <> 'failed'
""")
    op.execute("""
CREATE UNIQUE INDEX uq_speech_analysis_jobs_object
    ON speech_analysis_jobs(s3_object_key) WHERE status <> 'failed'
""")
    op.execute(
        "CREATE INDEX idx_speech_analysis_jobs_session "
        "ON speech_analysis_jobs(session_id, created_at DESC)"
    )
    op.execute("""
CREATE INDEX idx_speech_analysis_jobs_queue
    ON speech_analysis_jobs(created_at) WHERE status = 'queued'
""")
    op.execute("""
CREATE INDEX idx_speech_analysis_jobs_lease
    ON speech_analysis_jobs(lease_expires_at) WHERE status IN ('uploading', 'transcribing', 'generatingReport')
""")
    op.execute("""
CREATE INDEX idx_speech_analysis_jobs_transcript_expiry
    ON speech_analysis_jobs(transcript_expires_at) WHERE transcript IS NOT NULL
""")
    op.execute("""
CREATE INDEX idx_speech_analysis_jobs_expiry
    ON speech_analysis_jobs(data_expires_at) WHERE audio_deleted_at IS NULL
""")
    op.execute("""
CREATE TRIGGER speech_analysis_jobs_queue_storage_deletion
    AFTER DELETE ON speech_analysis_jobs
    FOR EACH ROW WHEN (OLD.audio_deleted_at IS NULL)
    EXECUTE FUNCTION queue_storage_deletion()
""")

    # -----------------------------------------------------------------
    # 변경 제안과 주제 피드백
    # -----------------------------------------------------------------
    op.execute("""
CREATE TABLE life_fact_proposals (
    proposal_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  UUID         NOT NULL,
    profile_id  UUID         NOT NULL,
    title       VARCHAR(100) NOT NULL CHECK (length(btrim(title)) > 0),
    content     TEXT         NOT NULL CHECK (length(btrim(content)) > 0),
    reason      TEXT         NOT NULL,
    status      VARCHAR(10)  NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'settled')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    FOREIGN KEY (session_id, profile_id)
        REFERENCES visit_sessions(session_id, profile_id) ON DELETE CASCADE,
    UNIQUE (proposal_id, profile_id)
)
""")
    op.execute(
        "CREATE INDEX idx_life_fact_proposals_session "
        "ON life_fact_proposals(session_id) WHERE status = 'pending'"
    )

    op.execute("""
CREATE TABLE topic_proposals (
    proposal_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  UUID         NOT NULL,
    profile_id  UUID         NOT NULL,
    card_id     UUID         NOT NULL,
    topic_id    UUID         NOT NULL,
    suggested_action VARCHAR(10) NOT NULL
        CHECK (suggested_action IN ('more', 'less', 'exclude')),
    reason      TEXT         NOT NULL,
    status      VARCHAR(10)  NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'settled')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),

    FOREIGN KEY (session_id, profile_id)
        REFERENCES visit_sessions(session_id, profile_id) ON DELETE CASCADE,
    FOREIGN KEY (card_id, topic_id, profile_id)
        REFERENCES conversation_cards(card_id, topic_id, profile_id) ON DELETE CASCADE,
    UNIQUE (session_id, card_id),
    UNIQUE (proposal_id, topic_id, profile_id)
)
""")
    op.execute(
        "CREATE INDEX idx_topic_proposals_session "
        "ON topic_proposals(session_id) WHERE status = 'pending'"
    )

    op.execute("""
CREATE TABLE topic_feedback (
    feedback_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    profile_id  UUID        NOT NULL,
    topic_id    UUID        NOT NULL,
    proposal_id UUID        NOT NULL UNIQUE,
    action      VARCHAR(10) NOT NULL CHECK (action IN ('more', 'less', 'exclude')),
    decided_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (topic_id, profile_id)
        REFERENCES profile_topics(topic_id, profile_id) ON DELETE CASCADE,
    FOREIGN KEY (proposal_id, topic_id, profile_id)
        REFERENCES topic_proposals(proposal_id, topic_id, profile_id) ON DELETE CASCADE
)
""")
    op.execute(
        "CREATE INDEX idx_topic_feedback_topic "
        "ON topic_feedback(topic_id, decided_at, feedback_id)"
    )

    op.execute("""
CREATE FUNCTION delete_orphan_topic() RETURNS trigger AS $$
BEGIN
    DELETE FROM profile_topics t
     WHERE t.topic_id = OLD.topic_id
       AND NOT EXISTS (SELECT 1 FROM conversation_cards c WHERE c.topic_id = t.topic_id);
    RETURN NULL;
END $$ LANGUAGE plpgsql
""")
    op.execute("""
CREATE CONSTRAINT TRIGGER conversation_cards_delete_orphan_topic
    AFTER DELETE ON conversation_cards DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION delete_orphan_topic()
""")

    op.execute("""
ALTER TABLE life_facts
    ADD CONSTRAINT life_facts_source_proposal_fk
    FOREIGN KEY (source_proposal_id, profile_id)
    REFERENCES life_fact_proposals(proposal_id, profile_id) ON DELETE SET NULL (source_proposal_id)
""")

    # -----------------------------------------------------------------
    # 탈퇴 이유 (계정과 연결하지 않음)
    # -----------------------------------------------------------------
    op.execute("""
CREATE TABLE withdrawal_feedback (
    feedback_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reasons      VARCHAR(30)[] NOT NULL,
    other_text   TEXT,
    submitted_on DATE NOT NULL DEFAULT current_date,
    CHECK (cardinality(reasons) >= 1),
    CHECK (reasons <@ ARRAY['conditionChanged', 'cardsNotHelpful', 'infrequentVisits',
                            'hardToUse', 'recordingBurden', 'other']::VARCHAR(30)[]),
    CHECK (('other' = ANY (reasons)) = (other_text IS NOT NULL))
)
""")


def downgrade() -> None:
    """Downgrade schema.

    FK와 trigger가 의존하는 순서의 역순으로 제거한다. 인덱스와 trigger는
    테이블과 함께 제거된다.
    """
    op.execute("DROP TABLE withdrawal_feedback")
    op.execute("ALTER TABLE life_facts DROP CONSTRAINT life_facts_source_proposal_fk")
    op.execute("DROP TABLE topic_feedback")
    op.execute("DROP TABLE topic_proposals")
    op.execute("DROP TABLE life_fact_proposals")
    op.execute("DROP TABLE speech_analysis_jobs")
    op.execute("DROP TABLE photos")
    op.execute("DROP TABLE conversation_cards")
    op.execute("DROP FUNCTION delete_orphan_topic()")
    op.execute("DROP TABLE profile_topics")
    op.execute("DROP TABLE card_sets")
    op.execute("DROP TABLE visit_sessions")
    op.execute("DROP TABLE life_facts")
    op.execute("DROP TABLE profiles")
    op.execute("DROP VIEW current_consents")
    op.execute("DROP TABLE consent_records")
    op.execute("DROP TABLE users")
    op.execute("DROP FUNCTION queue_storage_deletion()")
    op.execute("DROP TABLE storage_deletion_request_queue")

    # pgcrypto는 이 migration 하나만의 소유물이 아니라 DB 전체에 걸리는
    # extension이다. 같은 DB의 다른 스키마나 객체가 gen_random_uuid() 등을
    # 이미 쓰고 있을 수 있으므로 downgrade에서 임의로 제거하지 않는다.
