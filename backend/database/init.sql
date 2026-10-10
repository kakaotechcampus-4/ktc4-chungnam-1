CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP VIEW IF EXISTS current_consents;
DROP TABLE IF EXISTS
    proposal_changes, change_proposals, card_evidence_refs, card_generation_requests, session_consents,
    profile_photo_tags, life_fact_collection_states, account_consents,
    report_card_summaries, card_reviews, visit_reports, caregiver_evaluations
    CASCADE;
DROP TABLE IF EXISTS
    topic_feedback, topic_proposals, life_fact_proposals, profile_topics, speech_analysis_jobs, photos,
    conversation_cards, card_sets, visit_sessions, life_facts, profiles, withdrawal_feedback, consent_records,
    users, storage_deletion_request_queue
    CASCADE;
DROP FUNCTION IF EXISTS queue_storage_deletion();
DROP FUNCTION IF EXISTS delete_orphan_topic();

CREATE TABLE storage_deletion_request_queue (
    s3_object_key VARCHAR(255) PRIMARY KEY,
    requested_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE FUNCTION queue_storage_deletion() RETURNS trigger AS $$
BEGIN
    INSERT INTO storage_deletion_request_queue (s3_object_key) VALUES (OLD.s3_object_key)
    ON CONFLICT DO NOTHING;
    RETURN OLD;
END $$ LANGUAGE plpgsql;

CREATE TABLE users (
    user_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_sub   VARCHAR(255) NOT NULL UNIQUE CHECK (length(btrim(google_sub)) > 0),
    display_name VARCHAR(50),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE consent_records (
    record_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id             UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    terms_version       VARCHAR(20) NOT NULL,
    service_data        BOOLEAN     NOT NULL CHECK (service_data),
    sensitive_data      BOOLEAN     NOT NULL CHECK (sensitive_data),
    service_improvement BOOLEAN     NOT NULL,
    push_notification   BOOLEAN     NOT NULL,
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_consent_records_latest
    ON consent_records(user_id, recorded_at DESC, record_id DESC);

CREATE VIEW current_consents AS
SELECT DISTINCT ON (user_id) *
  FROM consent_records
 ORDER BY user_id, recorded_at DESC, record_id DESC;

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
);
CREATE INDEX idx_profiles_user ON profiles(user_id, created_at);

CREATE TABLE life_facts (
    fact_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id     UUID         NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    title          VARCHAR(100) NOT NULL CHECK (length(btrim(title)) > 0),
    content        TEXT         NOT NULL CHECK (length(btrim(content)) > 0),
    source_proposal_id UUID     UNIQUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_life_facts_profile ON life_facts(profile_id, created_at);

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
);
CREATE INDEX idx_visit_sessions_profile ON visit_sessions(profile_id, started_at DESC);

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
    lease_expires_at TIMESTAMPTZ,
    attempt_count    SMALLINT   NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    FOREIGN KEY (session_id, profile_id)
        REFERENCES visit_sessions(session_id, profile_id) ON DELETE CASCADE,
    UNIQUE (set_id, profile_id),
    CHECK ((status = 'failed') = (error_code IS NOT NULL)),
    CHECK ((status = 'running') = (generation_log IS NULL)),
    CHECK (session_id IS NULL OR status = 'completed'),
    CONSTRAINT card_sets_lease_check CHECK (lease_expires_at IS NULL OR status = 'running')
);
CREATE INDEX idx_card_sets_profile ON card_sets(profile_id, created_at DESC);

CREATE UNIQUE INDEX uq_card_sets_running ON card_sets(profile_id) WHERE status = 'running';
CREATE INDEX idx_card_sets_waiting
    ON card_sets(created_at) WHERE status = 'running' AND lease_expires_at IS NULL;

CREATE TABLE profile_topics (
    topic_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id        UUID         NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    title             VARCHAR(100) NOT NULL CHECK (length(btrim(title)) > 0),
    description       TEXT         NOT NULL CHECK (length(btrim(description)) > 0),
    evidence          JSONB        NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(evidence) = 'array'),
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (topic_id, profile_id)
);
CREATE INDEX idx_profile_topics_profile ON profile_topics(profile_id, created_at);

CREATE TABLE conversation_cards (
    card_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    set_id              UUID     NOT NULL,
    profile_id          UUID     NOT NULL,
    topic_id            UUID     NOT NULL,
    card_title          VARCHAR(100) NOT NULL CHECK (card_title ~ '\S'),
    position            SMALLINT NOT NULL CHECK (position BETWEEN 1 AND 12),
    description         TEXT     NOT NULL CHECK (description ~ '\S'),
    primary_question    TEXT     NOT NULL CHECK (primary_question ~ '\S'),
    follow_up_questions TEXT[]   NOT NULL CHECK (
        cardinality(follow_up_questions) = 3
        AND coalesce(follow_up_questions[1] ~ '\S' AND follow_up_questions[2] ~ '\S'
                     AND follow_up_questions[3] ~ '\S', false)),
    evidence_source     VARCHAR(10) NOT NULL CHECK (evidence_source IN ('life_fact', 'photo', 'profile', 'none')),
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
                WHEN evidence_source IN ('life_fact', 'photo', 'profile') THEN jsonb_array_length(evidence) > 0
                ELSE evidence = '[]'::jsonb END)
);
CREATE INDEX idx_conversation_cards_topic ON conversation_cards(topic_id);

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
    lease_expires_at TIMESTAMPTZ,
    attempt_count    SMALLINT    NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    FOREIGN KEY (session_id, profile_id)
        REFERENCES visit_sessions(session_id, profile_id) ON DELETE CASCADE,
    CHECK ((analysis_status = 'failed') = (error_code IS NOT NULL)),
    CHECK (CASE WHEN analysis_status = 'completed'
                THEN description IS NOT NULL AND model IS NOT NULL AND prompt_version IS NOT NULL
                ELSE description IS NULL AND model IS NULL AND prompt_version IS NULL END),
    CONSTRAINT photos_lease_check
        CHECK ((analysis_status = 'processing') = (lease_expires_at IS NOT NULL))
);
CREATE INDEX idx_photos_profile ON photos(profile_id, created_at);
CREATE INDEX idx_photos_pending ON photos(created_at) WHERE analysis_status = 'pending';

CREATE UNIQUE INDEX uq_photos_session ON photos(session_id) WHERE session_id IS NOT NULL;

CREATE TRIGGER photos_queue_storage_deletion
    AFTER DELETE ON photos
    FOR EACH ROW EXECUTE FUNCTION queue_storage_deletion();

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
);
CREATE UNIQUE INDEX uq_speech_analysis_jobs_session
    ON speech_analysis_jobs(session_id) WHERE status <> 'failed';
CREATE UNIQUE INDEX uq_speech_analysis_jobs_object
    ON speech_analysis_jobs(s3_object_key) WHERE status <> 'failed';
CREATE INDEX idx_speech_analysis_jobs_session ON speech_analysis_jobs(session_id, created_at DESC);
CREATE INDEX idx_speech_analysis_jobs_queue
    ON speech_analysis_jobs(created_at) WHERE status = 'queued';

CREATE INDEX idx_speech_analysis_jobs_lease
    ON speech_analysis_jobs(lease_expires_at) WHERE status IN ('uploading', 'transcribing', 'generatingReport');
CREATE INDEX idx_speech_analysis_jobs_transcript_expiry
    ON speech_analysis_jobs(transcript_expires_at) WHERE transcript IS NOT NULL;
CREATE INDEX idx_speech_analysis_jobs_expiry
    ON speech_analysis_jobs(data_expires_at) WHERE audio_deleted_at IS NULL;

CREATE TRIGGER speech_analysis_jobs_queue_storage_deletion
    AFTER DELETE ON speech_analysis_jobs
    FOR EACH ROW WHEN (OLD.audio_deleted_at IS NULL)
    EXECUTE FUNCTION queue_storage_deletion();

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
);
CREATE INDEX idx_life_fact_proposals_session ON life_fact_proposals(session_id) WHERE status = 'pending';

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
);
CREATE INDEX idx_topic_proposals_session ON topic_proposals(session_id) WHERE status = 'pending';

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
);
CREATE INDEX idx_topic_feedback_topic ON topic_feedback(topic_id, decided_at, feedback_id);

CREATE FUNCTION delete_orphan_topic() RETURNS trigger AS $$
BEGIN
    DELETE FROM profile_topics t
     WHERE t.topic_id = OLD.topic_id
       AND NOT EXISTS (SELECT 1 FROM conversation_cards c WHERE c.topic_id = t.topic_id);
    RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER conversation_cards_delete_orphan_topic
    AFTER DELETE ON conversation_cards DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION delete_orphan_topic();

ALTER TABLE life_facts
    ADD CONSTRAINT life_facts_source_proposal_fk
    FOREIGN KEY (source_proposal_id, profile_id)
    REFERENCES life_fact_proposals(proposal_id, profile_id) ON DELETE SET NULL (source_proposal_id);

CREATE TABLE withdrawal_feedback (
    feedback_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reasons      VARCHAR(30)[] NOT NULL,
    other_text   TEXT,
    submitted_on DATE NOT NULL DEFAULT current_date,
    CHECK (cardinality(reasons) >= 1),
    CHECK (reasons <@ ARRAY['conditionChanged', 'cardsNotHelpful', 'infrequentVisits',
                            'hardToUse', 'recordingBurden', 'other']::VARCHAR(30)[]),
    CHECK (('other' = ANY (reasons)) = (other_text IS NOT NULL))
);
