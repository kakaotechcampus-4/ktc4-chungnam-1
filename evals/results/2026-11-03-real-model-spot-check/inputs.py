"""합성 입력. 실제 인물, 시설, 전사와 무관하게 이 점검을 위해 새로 지은 자료."""

from datetime import datetime, timezone

T = lambda d: datetime.fromisoformat(d).replace(tzinfo=timezone.utc)  # noqa: E731

# 카드 1: 정정과 추천하지 않기 반영. 이전 카드에는 정정 전 고향(통영)이 남아 있음.
CARD_RICH = {
    "model": "gpt-5.6-luna",
    "promptVersion": 1,
    "context": {
        "ageRange": "80s",
        "profileFacts": {"occupation": "양복점 재단사", "hometown": "전남 여수",
                         "hobby": "트로트 듣기, 베란다 화초 가꾸기", "family": "아들 둘, 딸 하나"},
        "lifeFacts": [
            {"factId": "f-anchovy", "title": "여수 바닷가에서 멸치 말리던 일",
             "content": "어린 시절 어머니와 함께 여수 바닷가에서 멸치를 널어 말렸다. (보호자 정정: 처음에 통영으로 적었으나 여수가 맞다)",
             "createdAt": "2026-09-01T00:00:00Z", "source": "caregiver"},
            {"factId": "f-refuge", "title": "부산 피란",
             "content": "전쟁 때 가족과 부산으로 피란 가서 한동안 천막에서 지냈다.",
             "createdAt": "2026-09-01T00:00:00Z", "source": "caregiver"},
            {"factId": "f-market", "title": "국제시장에서 원단 떼 오던 일",
             "content": "양복점을 하던 때 새벽 기차로 부산 국제시장에 가서 양복 원단을 떼어 왔다.",
             "createdAt": "2026-09-01T00:00:00Z", "source": "caregiver"},
            {"factId": "f-shop", "title": "여수에 양복점을 연 일",
             "content": "젊은 시절 여수 시내에 작은 양복점을 열었다. 간판은 형님이 써 주었다.",
             "createdAt": "2026-09-10T00:00:00Z", "source": "visit"},
        ],
        "photos": [
            {"photoId": "p-shopfront", "description": "흑백 사진. 양복 차림의 남성이 가게 앞에 서 있다. 간판 글자는 흐릿해 읽기 어렵다."},
        ],
        "topics": [
            {"topicId": "t-anchovy", "title": "바닷가에서 멸치 말리기", "description": "어린 시절 어머니와 바닷가에서 멸치를 말리던 이야기",
             "evidence": [{"factId": "f-anchovy"}], "createdAt": "2026-09-01T00:00:00Z",
             "feedback": [{"action": "more", "decidedAt": "2026-09-20T00:00:00Z"}]},
            {"topicId": "t-refuge", "title": "피란 시절 부산", "description": "전쟁 때 가족과 부산으로 피란 갔던 이야기",
             "evidence": [{"factId": "f-refuge"}], "createdAt": "2026-09-01T00:00:00Z",
             "feedback": [{"action": "exclude", "decidedAt": "2026-09-20T00:00:00Z"}]},
            {"topicId": "t-trot", "title": "좋아하는 트로트 가수", "description": "즐겨 듣던 트로트와 가수 이야기",
             "evidence": [{"profileField": "hobby"}], "createdAt": "2026-09-01T00:00:00Z",
             "feedback": [{"action": "less", "decidedAt": "2026-09-20T00:00:00Z"}]},
        ],
        "visits": [{"sessionId": "v-1", "startedAt": "2026-09-19T05:00:00Z", "setId": "s-1"}],
        "pastCards": [
            {"cardId": "pc-1", "setId": "s-1", "topicId": "t-anchovy", "position": 1, "cardTitle": "통영 바닷가의 멸치",
             "primaryQuestion": "통영 바닷가에서 멸치를 널 때 어떤 냄새가 났어요?", "evidence": [{"factId": "f-anchovy"}],
             "selected": True, "reviewReaction": "positive"},
            {"cardId": "pc-2", "setId": "s-1", "topicId": "t-refuge", "position": 2, "cardTitle": "피란 가던 길",
             "primaryQuestion": "부산으로 피란 가실 때 길은 어떠셨어요?", "evidence": [{"factId": "f-refuge"}],
             "selected": True, "reviewReaction": "negative"},
            {"cardId": "pc-3", "setId": "s-1", "topicId": "t-trot", "position": 3, "cardTitle": "즐겨 부르던 노래",
             "primaryQuestion": "흥얼거리시던 노래 한 소절 들려주실래요?", "evidence": [{"profileField": "hobby"}],
             "selected": True, "reviewReaction": "neutral"},
        ],
    },
}

# 카드 2: 입력이 거의 없는 프로필. 없는 사실을 지어내는지 본다.
CARD_SPARSE = {
    "model": "gpt-5.6-luna",
    "promptVersion": 1,
    "context": {
        "ageRange": "90s",
        "profileFacts": {"occupation": "초등학교 급식실 조리원", "hometown": None, "hobby": None, "family": None},
        "lifeFacts": [],
        "photos": [{"photoId": "p-garden", "description": "컬러 사진. 텃밭에 고추 모종이 줄지어 있고 밀짚모자가 놓여 있다. 사람은 보이지 않는다."}],
        "topics": [], "visits": [], "pastCards": [],
    },
}


def seg(t0, speaker, text):
    return {"startMs": t0 * 1000, "endMs": t0 * 1000 + 4000, "speakerLabel": speaker, "text": text}


# 리포트 1: 화자 2명이 분명함. 어르신이 대화 중 고향을 정정하고, 아픈 기억을 피함.
REPORT_CLEAR = {
    "analysisId": "a-synth-1", "visitDate": "2026-10-03",
    "evaluation": {"conversationSatisfaction": 4, "careRecipientReaction": "pleased",
                   "freeNote": "바닷가 얘기에 많이 웃으셨다. 부산 얘기 끝에 잠깐 표정이 어두워지셨다."},
    "cards": [
        {"cardId": "rc-1", "cardTitle": "바닷가의 멸치", "topic": {"topicId": "t-anchovy", "title": "바닷가에서 멸치 말리기"}, "reaction": "positive"},
        {"cardId": "rc-2", "cardTitle": "양복점 간판", "topic": {"topicId": "t-shop", "title": "양복점을 열던 때"}, "reaction": "positive"},
        {"cardId": "rc-3", "cardTitle": "새벽 기차와 원단", "topic": {"topicId": "t-market", "title": "국제시장 원단"}, "reaction": "neutral"},
        {"cardId": "rc-4", "cardTitle": "좋아하던 노래", "topic": {"topicId": "t-trot", "title": "좋아하는 트로트 가수"}, "reaction": "notUsed"},
    ],
    "profileFacts": {"occupation": "양복점 재단사", "hometown": "전남 여수", "hobby": "트로트 듣기", "family": "아들 둘, 딸 하나"},
    "lifeFacts": [
        {"factId": "f-anchovy", "title": "통영 바닷가에서 멸치 말리던 일", "content": "어린 시절 어머니와 함께 통영 바닷가에서 멸치를 널어 말렸다."},
        {"factId": "f-shop", "title": "양복점을 연 일", "content": "젊은 시절 작은 양복점을 열었다."},
    ],
    "transcript": {"durationMs": 60000, "segments": [
        seg(0, "SPEAKER_00", "아버지, 오늘은 바닷가 얘기 해 볼까요? 어릴 때 멸치 말리셨다면서요."),
        seg(5, "SPEAKER_01", "그럼, 어머니랑 바닷가에 멸치를 널었지. 근데 거기 통영 아니고 여수야. 통영은 고모네 집이 있던 데고."),
        seg(10, "SPEAKER_00", "아, 제가 예전에 통영이라고 적었었네요."),
        seg(15, "SPEAKER_01", "멸치 널 때 갈매기가 자꾸 와서 내가 장대 들고 쫓았어. 그게 내 일이었지. 하하."),
        seg(20, "SPEAKER_00", "양복점은 몇 살 때 여셨어요?"),
        seg(25, "SPEAKER_01", "스물아홉에 열었나, 서른이었나. 간판은 형님이 붓으로 써 줬어."),
        seg(30, "SPEAKER_00", "국제시장에서 원단 떼 오셨던 얘기도 해 주세요."),
        seg(35, "SPEAKER_01", "부산 가면 새벽 기차 타고 갔지. 근데 부산 얘기 하니까 피란 때 생각이 나네. 그건 그만하자."),
        seg(40, "SPEAKER_00", "네, 그럼 다른 얘기 해요."),
        seg(45, "SPEAKER_01", "응."),
    ]},
    "participantCount": 2,
}

# 리포트 2: 참여자는 2명인데 라벨이 하나로 합쳐짐. 보호자 본인의 경험이 섞여 있음.
REPORT_MERGED = {
    "analysisId": "a-synth-2", "visitDate": "2026-10-10",
    "evaluation": {"conversationSatisfaction": 3, "careRecipientReaction": "calm", "freeNote": None},
    "cards": [
        {"cardId": "rc-5", "cardTitle": "재봉틀 소리", "topic": {"topicId": "t-sewing", "title": "재봉틀 돌리던 시절"}, "reaction": "positive"},
        {"cardId": "rc-6", "cardTitle": "하숙집 반찬", "topic": {"topicId": "t-food", "title": "기억에 남는 반찬"}, "reaction": None},
    ],
    "profileFacts": {"occupation": "양장점 운영", "hometown": None, "hobby": None, "family": "딸 하나"},
    "lifeFacts": [],
    "transcript": {"durationMs": 40000, "segments": [
        seg(0, "SPEAKER_00", "엄마, 재봉틀 돌리던 얘기 좀 해 주세요."),
        seg(5, "SPEAKER_00", "나는 재봉틀 소리가 좋았어. 미싱 돌리면 하루가 금방 갔지."),
        seg(10, "SPEAKER_00", "저는 대학 때 서울에서 하숙했는데 하숙집 아주머니가 깍두기를 정말 잘 담그셨어요."),
        seg(15, "SPEAKER_00", "그랬구나. 깍두기는 무를 잘 골라야 해."),
        seg(20, "SPEAKER_00", "단골손님 중에 선생님이 한 분 계셨는데 꼭 감색 원피스만 맞췄어."),
    ]},
    "participantCount": 2,
}

# 리포트 3: 참여자 3명(보호자, 어르신, 직원), 화자를 정하지 못한 구간, 직원의 건강 관련 발언, 쓰지 않은 카드.
REPORT_THIRD = {
    "analysisId": "a-synth-3", "visitDate": "2026-10-17",
    "evaluation": {"conversationSatisfaction": 3, "careRecipientReaction": "calm",
                   "freeNote": "직원분 말씀 중에 기억력 얘기가 나와서 마음이 쓰였다. 꽃 얘기는 즐겁게 하셨다."},
    "cards": [
        {"cardId": "rc-7", "cardTitle": "겨울에 피는 군자란", "topic": {"topicId": "t-clivia", "title": "군자란 키우기"}, "reaction": "positive"},
        {"cardId": "rc-8", "cardTitle": "공장 다니던 시절", "topic": {"topicId": "t-factory", "title": "공장 다니던 시절"}, "reaction": "notUsed"},
        {"cardId": "rc-9", "cardTitle": "노래자랑", "topic": {"topicId": "t-singing", "title": "동네 노래자랑"}, "reaction": None},
    ],
    "profileFacts": {"occupation": None, "hometown": "충북 제천", "hobby": "화초 가꾸기", "family": None},
    "lifeFacts": [{"factId": "f-clivia", "title": "베란다 군자란", "content": "아파트 베란다에서 군자란을 오래 키웠다."}],
    "transcript": {"durationMs": 50000, "segments": [
        seg(0, "SPEAKER_02", "어르신 오후 약은 드셨어요. 요즘 기억력이 많이 떨어지셔서 저희가 챙겨 드리고 있어요."),
        seg(5, "SPEAKER_00", "감사합니다. 엄마, 오늘은 꽃 얘기 해요. 베란다에 군자란 키우셨잖아요."),
        seg(10, "SPEAKER_01", "군자란은 겨울에 꽃대가 올라와. 물을 너무 주면 뿌리가 썩어."),
        seg(15, None, "나 처녀 때 서울 방직공장 다녔어."),
        seg(20, "SPEAKER_01", "군자란 분갈이는 봄에 하는 거야. 주황색 꽃이 참 예뻐."),
        seg(25, "SPEAKER_00", "다음에 꽃 핀 사진 가져올게요."),
    ]},
    "participantCount": 3,
}


# 운영 DB의 ID는 UUID다. 카드 생성 번호표(f1, p1, t1)는 UUID 형식만 바꾸므로 같은 자료를 UUID로 바꾼 판을 둔다.
import json as _json
import re as _re
import uuid as _uuid

_NS = _uuid.UUID("6f1c2b1e-1160-4c3a-9b1e-2026110300ab")


def with_uuids(payload: dict) -> tuple[dict, dict]:
    text = _json.dumps(payload, ensure_ascii=False)
    ids = sorted(set(_re.findall(r'"(?:factId|photoId|topicId|setId|sessionId|cardId)": "([^"]+)"', text)))
    mapping = {i: str(_uuid.uuid5(_NS, i)) for i in ids}
    for old, new in mapping.items():
        text = text.replace(f'"{old}"', f'"{new}"')
    return _json.loads(text), mapping


CARD_RICH_UUID, RICH_ID_MAP = with_uuids(CARD_RICH)
CARD_SPARSE_UUID, SPARSE_ID_MAP = with_uuids(CARD_SPARSE)


if __name__ == "__main__":
    # 위 값을 그대로 inputs/*.json으로 저장한다. 실행에는 이 파일의 파이썬 값을 썼고 JSON은 읽기용 사본이다.
    from pathlib import Path as _Path

    _dir = _Path(__file__).resolve().parent / "inputs"
    _dir.mkdir(exist_ok=True)
    for _name, _value in {
        "card-rich": CARD_RICH, "card-rich-uuid": CARD_RICH_UUID,
        "card-sparse": CARD_SPARSE, "card-sparse-uuid": CARD_SPARSE_UUID,
        "report-clear": REPORT_CLEAR, "report-merged": REPORT_MERGED, "report-third": REPORT_THIRD,
        "id-map-rich": RICH_ID_MAP, "id-map-sparse": SPARSE_ID_MAP,
    }.items():
        (_dir / f"{_name}.json").write_text(_json.dumps(_value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
