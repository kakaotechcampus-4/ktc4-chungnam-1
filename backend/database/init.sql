-- 개발용 부트스트랩 스크립트.
--
-- 스키마의 소유권은 Alembic 마이그레이션에 있다. 이 파일은 빈 개발 DB를 한 번에
-- 세우기 위한 것이므로, 스키마가 바뀌면 Alembic을 기준으로 이 파일을 맞춘다.
-- 실제 사용자 자료와 마스킹한 실제 자료는 이 환경에서 사용하지 않는다
-- (`backend/README.md` 실행과 테스트).
--
-- `updated_at`은 DB가 자동으로 갱신하지 않는다. 트리거 대신 SQLAlchemy 모델의
-- `onupdate`가 값을 넣는다.

--  Postgres 확장 모듈 활성화
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 손으로 다시 실행할 수 있도록 기존 테이블을 먼저 지운다. 개발 DB 전용이다.
DROP TABLE IF EXISTS proposal_changes CASCADE;
DROP TABLE IF EXISTS change_proposals CASCADE;
DROP TABLE IF EXISTS report_card_summaries CASCADE;
DROP TABLE IF EXISTS visit_reports CASCADE;
DROP TABLE IF EXISTS card_reviews CASCADE;
DROP TABLE IF EXISTS caregiver_evaluations CASCADE;
DROP TABLE IF EXISTS card_evidence_refs CASCADE;
DROP TABLE IF EXISTS conversation_cards CASCADE;
DROP TABLE IF EXISTS card_generation_requests CASCADE;
DROP TABLE IF EXISTS session_consents CASCADE;
DROP TABLE IF EXISTS visit_sessions CASCADE;
DROP TABLE IF EXISTS profile_photo_tags CASCADE;
DROP TABLE IF EXISTS life_fact_collection_states CASCADE;
DROP TABLE IF EXISTS life_facts CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;
DROP TABLE IF EXISTS account_consents CASCADE;
DROP TABLE IF EXISTS users CASCADE;

---------------------------------------------------------------------------------------
-- 계정 (소셜로그인)
---------------------------------------------------------------------------------------
CREATE TABLE users (
    user_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider      VARCHAR(20)  NOT NULL CHECK (provider IN ('google')),
    -- 구글 계정의 sub. 앱이 보낸 ID 토큰을 구글 공개키로 검증한 뒤 이 값으로 사용자를 찾는다.
    -- 제공자 안에서만 유일한 값이라 provider 와 묶어서 유일성을 건다.
    social_id     VARCHAR(255) NOT NULL,
    email         VARCHAR(320),
    nickname      VARCHAR(100) NOT NULL,
    role          VARCHAR(20)  NOT NULL DEFAULT 'caregiver'
                    CHECK (role IN ('caregiver', 'admin')),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_login_at TIMESTAMPTZ,
    UNIQUE (provider, social_id)
);

CREATE TABLE account_consents (
    user_id         UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    consent_type    VARCHAR(30) NOT NULL CHECK (consent_type IN
                      ('serviceData', 'sensitiveData', 'serviceImprovement', 'pushNotification')),
    consent_version VARCHAR(20) NOT NULL,
    granted         BOOLEAN     NOT NULL,
    granted_at      TIMESTAMPTZ,
    PRIMARY KEY (user_id, consent_type),
    CHECK (granted = false OR granted_at IS NOT NULL)
);

---------------------------------------------------------------------------------------
-- 프로필과 생애 사실
---------------------------------------------------------------------------------------
CREATE TABLE profiles (
    profile_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    age_range              VARCHAR(10) NOT NULL,
    condition_stage        VARCHAR(30) NOT NULL CHECK (condition_stage IN
                             ('mildCognitiveImpairment', 'mildDementia', 'unknown')),
    condition_symptom_note TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_profiles_user ON profiles(user_id);

CREATE TABLE life_facts (
    fact_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id        UUID        NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    category          VARCHAR(20) NOT NULL CHECK (category IN
                        ('occupation', 'hometown', 'hobby', 'family')),
    text              TEXT        NOT NULL,
    source_type       VARCHAR(30) NOT NULL CHECK (source_type IN
                        ('caregiverVoiceInput', 'caregiverTextInput', 'visitConfirmed')),
    -- visit_sessions 가 아래에서 만들어지므로 외래키는 그 뒤에 ALTER 로 붙인다.
    source_session_id UUID,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (source_type = 'visitConfirmed' OR source_session_id IS NULL)
);
CREATE INDEX idx_life_facts_profile ON life_facts(profile_id, category);

-- pgvector를 켤 때 추가 (지금은 넣지 않음)
-- ALTER TABLE life_facts ADD COLUMN embedding vector(1536);
-- CREATE INDEX ON life_facts USING hnsw (embedding vector_cosine_ops);

CREATE TABLE life_fact_collection_states (
    profile_id    UUID        NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    category      VARCHAR(20) NOT NULL CHECK (category IN
                    ('occupation', 'hometown', 'hobby', 'family')),
    status        VARCHAR(20) NOT NULL CHECK (status IN
                    ('pending', 'collected', 'skipped', 'manualFallback')),
    attempt_count SMALLINT    NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    PRIMARY KEY (profile_id, category)
);

-- 사진 원본과 localUri는 단말에만 둔다. 카드 생성에 쓰이는 수락 태그만 서버로 온다.
CREATE TABLE profile_photo_tags (
    profile_id UUID        NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    photo_id   UUID        NOT NULL,
    tag        VARCHAR(50) NOT NULL,
    PRIMARY KEY (profile_id, photo_id, tag)
);

---------------------------------------------------------------------------------------
-- 면회 회차
---------------------------------------------------------------------------------------
CREATE TABLE visit_sessions (
    session_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID        NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    session_status  VARCHAR(20) NOT NULL CHECK (session_status IN
                      ('ready', 'recording', 'paused', 'ended', 'processing', 'completed', 'failed')),
    -- 사진 원본과 localUri 는 단말에만 둔다. 서버에는 ID 만 오므로 외래키가 없다.
    photo_id        UUID,
    consent_version VARCHAR(20),
    recording_authorization_granted    BOOLEAN NOT NULL DEFAULT false,
    recording_authorization_granted_at TIMESTAMPTZ,
    started_at      TIMESTAMPTZ,
    ended_at        TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (ended_at IS NULL OR started_at IS NOT NULL),
    CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX idx_visit_sessions_profile ON visit_sessions(profile_id, started_at DESC);

ALTER TABLE life_facts
    ADD CONSTRAINT life_facts_source_session_fk
    FOREIGN KEY (source_session_id) REFERENCES visit_sessions(session_id) ON DELETE SET NULL;

CREATE TABLE session_consents (
    session_id   UUID        NOT NULL REFERENCES visit_sessions(session_id) ON DELETE CASCADE,
    consent_type VARCHAR(30) NOT NULL CHECK (consent_type IN
                   ('serviceData', 'sensitiveData', 'careRecipientConfirmation')),
    granted      BOOLEAN     NOT NULL,
    granted_at   TIMESTAMPTZ,
    PRIMARY KEY (session_id, consent_type),
    CHECK (granted = false OR granted_at IS NOT NULL)
);


---------------------------------------------------------------------------------------
-- 대화 카드
---------------------------------------------------------------------------------------
CREATE TABLE card_generation_requests (
    request_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id        UUID        NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    generation_status VARCHAR(15) NOT NULL CHECK (generation_status IN
                        ('pending', 'processing', 'completed', 'failed')),
    error_code        VARCHAR(50),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at      TIMESTAMPTZ,
    CHECK (generation_status <> 'failed' OR error_code IS NOT NULL)
);

CREATE TABLE conversation_cards (
    card_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id          UUID         NOT NULL REFERENCES card_generation_requests(request_id) ON DELETE CASCADE,
    -- 카드를 선택해 회차를 만드는 시점에 채운다(계약 387행). 생성 요청 시점에는
    -- 회차가 없으므로 card_generation_requests 는 회차를 갖지 않는다.
    session_id          UUID REFERENCES visit_sessions(session_id) ON DELETE SET NULL,
    topic_key           VARCHAR(50)  NOT NULL,
    topic_title         VARCHAR(100) NOT NULL,
    topic_description   TEXT         NOT NULL,
    primary_question    TEXT         NOT NULL,
    follow_up_questions JSONB        NOT NULL DEFAULT '[]',
    display_order       SMALLINT     NOT NULL,
    selection_status    VARCHAR(15)  NOT NULL DEFAULT 'unselected'
                          CHECK (selection_status IN ('unselected', 'selected')),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (request_id, display_order)
);
CREATE INDEX idx_cards_session_selected ON conversation_cards(session_id)
    WHERE selection_status = 'selected';

CREATE TABLE card_evidence_refs (
    card_id UUID NOT NULL REFERENCES conversation_cards(card_id) ON DELETE CASCADE,
    fact_id UUID NOT NULL REFERENCES life_facts(fact_id) ON DELETE CASCADE,
    PRIMARY KEY (card_id, fact_id)
);

---------------------------------------------------------------------------------------
-- 평가와 리포트
---------------------------------------------------------------------------------------
CREATE TABLE caregiver_evaluations (
    review_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id                UUID        NOT NULL UNIQUE
                                REFERENCES visit_sessions(session_id) ON DELETE CASCADE,
    conversation_satisfaction SMALLINT    NOT NULL
                                CHECK (conversation_satisfaction BETWEEN 1 AND 5),
    care_recipient_reaction   VARCHAR(15) NOT NULL CHECK (care_recipient_reaction IN
                                ('pleased', 'calm', 'angry', 'lowEnergy', 'unknown')),
    free_note                 TEXT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE card_reviews (
    review_id          UUID        NOT NULL REFERENCES caregiver_evaluations(review_id) ON DELETE CASCADE,
    card_id            UUID        NOT NULL REFERENCES conversation_cards(card_id) ON DELETE CASCADE,
    was_used           BOOLEAN     NOT NULL,
    caregiver_reaction VARCHAR(10) NOT NULL CHECK (caregiver_reaction IN
                         ('positive', 'neutral', 'negative')),
    PRIMARY KEY (review_id, card_id)
);

CREATE TABLE visit_reports (
    report_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id    UUID         NOT NULL UNIQUE REFERENCES visit_sessions(session_id) ON DELETE CASCADE,
    review_id     UUID         NOT NULL UNIQUE REFERENCES caregiver_evaluations(review_id) ON DELETE CASCADE,
    report_status VARCHAR(15)  NOT NULL CHECK (report_status IN
                    ('generating', 'ready', 'reviewed', 'acknowledged')),
    title         VARCHAR(200),
    visit_date    DATE         NOT NULL,
    mood          VARCHAR(10)  CHECK (mood IN ('hard', 'normal', 'good')),
    -- visit_sessions.photo_id 와 같은 이유로 외래키가 없다.
    photo_id      UUID,
    summary_text  TEXT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (report_status = 'generating'
           OR (title IS NOT NULL AND summary_text IS NOT NULL AND mood IS NOT NULL))
);

CREATE TABLE report_card_summaries (
    report_id     UUID         NOT NULL REFERENCES visit_reports(report_id) ON DELETE CASCADE,
    card_id       UUID         NOT NULL REFERENCES conversation_cards(card_id) ON DELETE CASCADE,
    topic_title   VARCHAR(100) NOT NULL,
    summary       TEXT         NOT NULL,
    display_order SMALLINT     NOT NULL,
    PRIMARY KEY (report_id, card_id)
);


---------------------------------------------------------------------------------------
-- 변경 제안
---------------------------------------------------------------------------------------
CREATE TABLE change_proposals (
    proposal_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID        NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
    -- 리포트당 제안이 하나뿐인지 계약에서 확정되지 않아 UNIQUE 를 걸지 않았다.
    report_id       UUID        NOT NULL REFERENCES visit_reports(report_id) ON DELETE CASCADE,
    proposal_status VARCHAR(15) NOT NULL DEFAULT 'pendingReview'
                      CHECK (proposal_status IN ('pendingReview', 'reviewed')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE proposal_changes (
    change_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id     UUID         NOT NULL REFERENCES change_proposals(proposal_id) ON DELETE CASCADE,
    change_type     VARCHAR(20)  NOT NULL CHECK (change_type IN ('topicPriority', 'lifeFactAdd')),
    topic_key       VARCHAR(50),
    topic_title     VARCHAR(100),
    direction       VARCHAR(5)   CHECK (direction IN ('up', 'down')),
    text            TEXT,
    reason          TEXT         NOT NULL,
    review_status   VARCHAR(10)  NOT NULL DEFAULT 'pending'
                      CHECK (review_status IN ('pending', 'accepted', 'rejected', 'reverted')),
    applied_fact_id UUID REFERENCES life_facts(fact_id) ON DELETE SET NULL,
    display_order   SMALLINT     NOT NULL,

    -- 계약 533~534행: 타입별로 갖는 필드가 다르다
    CHECK (
        (change_type = 'topicPriority'
         AND topic_key IS NOT NULL AND topic_title IS NOT NULL
         AND direction IS NOT NULL AND text IS NULL)
     OR (change_type = 'lifeFactAdd'
         AND text IS NOT NULL
         AND topic_key IS NULL AND topic_title IS NULL AND direction IS NULL)
    )
);
