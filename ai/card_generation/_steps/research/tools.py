"""에이전트에게 주는 읽기 도구 6개와 도구가 돌려주는 값의 형식.

도구는 ProfileStore 하나에 묶여 있어 profile_id를 인자로 받지 않음. ID는 번호표(t1, f3, p2)로 주고받음.
도구 설명(_DESCRIPTIONS)은 모델이 그대로 읽음. 인자 스키마에 길이·범위 제한 키워드를 넣지 않음. 모델 API마다 받는 키워드가 다름.
상한은 ProfileStore가 자름. 시점은 면회 몇 번 전(visits_ago)으로 줌.
"""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any, Callable, Literal

from langchain_core.tools import StructuredTool
from pydantic import BaseModel, Field

if TYPE_CHECKING:
    from card_generation._steps.research.store import ProfileStore

Action = Literal["more", "less", "exclude"]
InitialField = Literal["occupation", "hometown", "hobby", "family"]
INITIAL_FIELDS: tuple[InitialField, ...] = ("occupation", "hometown", "hobby", "family")
FIELD_LABELS = {"occupation": "하시던 일", "hometown": "고향", "hobby": "취미", "family": "가족"}
_DESCRIPTIONS = {
    "get_profile": (
        "어르신의 기본 정보. 연령대(예: 80대), 초기 정보 네 칸(하시던 일·고향·취미·가족, 비어 있으면 null), "
        "비어 있는 칸 목록, 쌓아온 이야기·사진·주제·면회의 개수. 이름, 성별, 생년월일, 건강 정보는 없다. "
        "조사를 시작할 때 먼저 부른다."),
    "list_life_facts": (
        "보호자가 확인한 생애 이야기를 차례대로 본다. least_used는 카드로 덜 다룬 것부터, newest는 최근에 추가된 것부터 "
        "보여 준다. 이야기마다 카드 근거로 쓰인 횟수(times_offered: 면회 카드 묶음에 들어간 횟수, times_selected: "
        "면회에서 고른 횟수)와 마지막으로 고른 시점(last_selected_visits_ago: 면회 몇 번 전, 0은 가장 최근 면회)이 붙는다."),
    "get_life_facts": "번호표(f1 같은 값)로 이야기 원문과 사용 이력을 본다. 주제의 근거에 적힌 이야기를 확인할 때 쓴다.",
    "list_photos": "사진 설명 목록. 보호자가 앨범에서 확인하고 고친 설명이다. 사진마다 카드 근거로 쓰인 횟수가 붙는다.",
    "list_topics": (
        "이 어르신과 이미 나눈 대화 주제(이야기) 목록. 주제마다 title, description, 보호자 선호 점수(score), "
        "보호자가 추천하지 않기를 골랐는지(excluded), 카드 묶음에 들어간 횟수, 면회에서 고른 횟수, "
        "마지막으로 고른 시점과 마지막으로 보여 준 시점이 붙는다. score는 '더 자주'면 오르고 '덜 자주'면 내려가며 "
        "면회가 지날수록 0에 가까워진다. 새 카드가 이 가운데 하나와 같은 이야기면 그 topicId로 연결한다. "
        "excluded 주제와 같은 이야기는 카드로 내지 않는다."),
    "get_topic": (
        "주제 하나의 자세한 기록. 보호자 결정 이력(more·less·exclude와 면회 몇 번 전인지), 점수, 근거 글, "
        "이 주제로 나갔던 카드(카드 제목, 첫 질문, 면회에서 골랐는지, 보호자 반응). 같은 이야기를 이어 갈 때 "
        "지난 질문을 되풀이하지 않고 다른 장면을 고르려고 본다. 반응은 그날 카드 한 장에 대한 것이지 "
        "주제에 대한 평가가 아니다."),
}


# ── 도구 결과 ─────────────────────────────────────────
class Counts(BaseModel):
    """get_profile이 주는 데이터 개수."""
    life_facts: int
    photos: int
    topics: int
    visits: int


class ProfileView(BaseModel):
    """get_profile 결과. 이름·성별·생년월일·건강 정보는 없음."""
    age_band: str            # 예: "80대"
    initial_details: dict[InitialField, str | None]
    empty_fields: list[InitialField]
    counts: Counts


class Usage(BaseModel):
    """카드 근거로 쓰인 이력. offered는 면회에 쓰인 카드 묶음에 들어간 횟수, selected는 면회에서 고른 횟수."""
    times_offered: int = 0
    times_selected: int = 0
    last_selected_visits_ago: int | None = None  # 0은 가장 최근 면회


class LifeFactView(BaseModel):
    """이야기 하나와 그 사용 이력."""
    fact_id: str
    title: str
    content: str
    from_visit: bool         # 면회 기록에서 나온 제안을 보호자가 승인해 만든 이야기
    usage: Usage


class LifeFactPage(BaseModel):
    """list_life_facts 결과. total은 전체 개수, offset은 건너뛴 개수."""
    total: int
    offset: int
    facts: list[LifeFactView]


class PhotoView(BaseModel):
    """사진 하나와 그 사용 이력."""
    photo_id: str
    description: str
    usage: Usage


class PhotoPage(BaseModel):
    """list_photos 결과."""
    total: int
    offset: int
    photos: list[PhotoView]


class TopicView(BaseModel):
    """주제 하나. 점수, 제외 여부, 묶음에 들어간 횟수, 고른 횟수, 마지막으로 고른·보여 준 시점."""
    topic_id: str
    title: str
    description: str
    excluded: bool           # 보호자가 추천하지 않기를 고른 주제
    score: float
    times_offered: int
    times_selected: int
    last_selected_visits_ago: int | None
    last_offered_visits_ago: int | None = None  # 고르지 않았어도 카드 묶음에 들어갔던 마지막 시점


class TopicPage(BaseModel):
    """list_topics 결과."""
    total: int
    offset: int
    topics: list[TopicView]


class DecisionView(BaseModel):
    """get_topic이 주는 결정 하나. visits_ago는 이 결정 뒤에 시작한 면회 수."""
    action: Action
    visits_ago: int          # 이 결정 뒤에 시작한 면회 수


class EvidenceText(BaseModel):
    """get_topic이 주는 근거 하나와 그 지금 글."""
    ref: dict[str, str]      # {"factId": ...}, {"photoId": ...}, {"profileField": ...} 중 하나
    text: str | None         # 지워진 근거는 None


class PastCard(BaseModel):
    """get_topic이 주는 지난 카드 하나. 면회에서 골랐는지와 보호자 반응."""
    card_title: str
    primary_question: str
    visits_ago: int | None   # 면회에 쓰이지 않은 묶음의 카드는 None
    selected: bool
    review_reaction: Literal["positive", "neutral", "negative", "notUsed"] | None


class TopicDetail(BaseModel):
    """get_topic 결과. 근거가 있었는데 모두 지워졌으면 evidence_deleted."""
    found: bool
    topic: TopicView | None = None
    decisions: list[DecisionView] = Field(default_factory=list)
    evidence: list[EvidenceText] = Field(default_factory=list)
    evidence_deleted: bool = False   # 근거가 있었는데 지금은 모두 지워짐
    cards: list[PastCard] = Field(default_factory=list)


# 도구 인자 스키마. 모델이 읽는 형식이라 docstring을 두지 않음
# get_profile: 인자 없음
class _NoArgs(BaseModel):
    pass


# list_life_facts 인자
class _ListLifeFacts(BaseModel):
    order: Literal["least_used", "newest", "oldest"] = Field(
        "least_used", description="least_used: 카드로 덜 다룬 것부터, newest: 최근 추가된 것부터, oldest: 먼저 등록된 것부터")
    offset: int = Field(0, description="건너뛸 개수")
    limit: int = Field(20, description="가져올 개수. 최대 30")


# get_life_facts 인자
class _FactIds(BaseModel):
    fact_ids: list[str] = Field(description="볼 이야기 번호표(f1 같은 값) 목록. 최대 20개")


# list_photos 인자
class _Page(BaseModel):
    offset: int = Field(0, description="건너뛸 개수")
    limit: int = Field(20, description="가져올 개수. 최대 30")


# list_topics 인자
class _ListTopics(BaseModel):
    offset: int = Field(0, description="건너뛸 개수")
    limit: int = Field(50, description="가져올 개수. 최대 100")


# get_topic 인자
class _TopicId(BaseModel):
    topic_id: str = Field(description="list_topics가 돌려준 주제 번호표(t1 같은 값)")


def build_tools(store: ProfileStore) -> list[StructuredTool]:
    """이 저장소에 묶인 LangChain 도구 6개를 만듦. 이름, 설명(_DESCRIPTIONS), 인자 스키마를 짝지음."""
    aliases = store.aliases()

    def wrap(fn: Callable[..., Any]) -> Callable[..., str]:
        """저장소 메서드를 도구 함수로 감쌈. 번호표 ↔ UUID 변환과 JSON 변환을 여기서 함."""
        def run(**kwargs: Any) -> str:
            # 조회 전에 번호표를 UUID로, 결과의 UUID는 번호표로 바꿈
            """도구 호출 한 번. 인자의 번호표를 UUID로 바꿔 조회하고, 결과의 UUID는 번호표로 바꿔 JSON으로 돌려줌.
            잘못된 인자는 오류 JSON."""
            if "topic_id" in kwargs:
                kwargs["topic_id"] = aliases.uuid(kwargs["topic_id"])
            if "fact_ids" in kwargs:
                kwargs["fact_ids"] = [aliases.uuid(x) for x in kwargs["fact_ids"]]
            try:
                return json.dumps(aliases.hide(_plain(fn(**kwargs))), ensure_ascii=False)
            except ValueError as error:
                return json.dumps({"error": str(error)}, ensure_ascii=False)
        return run

    table: list[tuple[str, Callable[..., Any], type[BaseModel]]] = [
        ("get_profile", store.get_profile, _NoArgs),
        ("list_life_facts", store.list_life_facts, _ListLifeFacts),
        ("get_life_facts", store.get_life_facts, _FactIds),
        ("list_photos", store.list_photos, _Page),
        ("list_topics", store.list_topics, _ListTopics),
        ("get_topic", store.get_topic, _TopicId),
    ]
    return [StructuredTool.from_function(func=wrap(fn), name=name, description=_DESCRIPTIONS[name], args_schema=schema)
            for name, fn, schema in table]


def _plain(value: Any) -> Any:
    """Pydantic 모델(또는 그 목록)을 JSON으로 바꿀 수 있는 dict로."""
    if isinstance(value, BaseModel):
        return value.model_dump(mode="json")
    if isinstance(value, list):
        return [_plain(v) for v in value]
    return value
