"""backend 카드 생성 worker가 부르는 진입점과 단계 잇기. context를 받아 카드 12장을 돌려줌. DB를 읽거나 쓰지 않음.

① 조사(research) → ② 연결 판정(match) → 주제가 모자라면 ①로 다시 → ③ 선정(select) → ④ 문안(write).

    from card_generation import CardGenerationError, GenerationRequest, generate_cards

    result = await asyncio.to_thread(generate_cards, GenerationRequest.model_validate(payload),
                                     api_key=settings.ml_api_key)

모델은 요청의 model(backend 설정 card_generation_model)을 씀. 주소는 common/llm.py의 ENDPOINTS에서 찾음.

1~2분 걸리는 동기 함수라 비동기 worker에서는 별도 스레드로 부름. context를 읽는 트랜잭션과 결과를 저장하는 트랜잭션 사이에 부름.
전체가 time_limit(기본 240초)을 넘으면 실패. worker 임대는 이보다 길게 잡음(#99 설정 300초).
실패는 CardGenerationError. code를 card_sets.error_code에 그대로 남김.
"""

from __future__ import annotations

__all__ = ["generate_cards", "recommend", "Recommendation", "RecommendFailed"]

import random
import time
from dataclasses import dataclass, field

from langchain_core.language_models import BaseChatModel

from card_generation._steps.match import MatchOutcome, run_match
from card_generation._steps.research.agent import AgentRun, AgentSession
from card_generation._steps.research.candidates import evidence_refs
from card_generation._steps.research.store import ProfileStore
from card_generation._steps.select import Picked, Selection, SelectionFailed, select_cards
from card_generation._steps.write import WritingFailed, write_cards
from card_generation._versions import VERSIONS
from card_generation._versions.base import Version
from card_generation.contract import (
    CardExtra,
    CardGenerationError,
    CardOut,
    GenerationRequest,
    GenerationResult,
    TopicOut,
)
from common.llm import ENDPOINTS, ChatConfig, chat_model, llm_down

_MAX_REFILLS = 2  # 판정 뒤 주제가 모자랄 때 다시 찾게 하는 횟수
_SOURCE = {"factId": "lifeFact", "photoId": "photo", "profileField": "profile"}


@dataclass
class Recommendation:
    """recommend의 결과. ①조사, ②판정, ③추첨 결과와 다시 찾기 때 에이전트에게 보낸 글.
    generate_cards가 카드를 만들고 결과 로그(log)를 채울 때 씀.
    """
    agent: AgentRun
    match: MatchOutcome
    selection: Selection
    refills: list[str] = field(default_factory=list)  # 에이전트에게 다시 찾으라고 보낸 글

    @property
    def picked(self) -> list[Picked]:
        """추첨으로 고른 12장. selection.picked를 짧게 부르는 이름."""
        return self.selection.picked


class RecommendFailed(RuntimeError):
    """다시 찾기를 다 써도 서로 다른 주제로 12장을 못 채운 실패. generate_cards가 NOT_ENOUGH_TOPICS로 바꿈."""
    pass


def generate_cards(request: GenerationRequest, *, api_key: str, time_limit: float = 240.0,
                   seed: int | None = None) -> GenerationResult:
    """모델은 backend 요청(request.model)을, 키는 backend 설정을 그대로 씀.
    seed는 선정 추첨용. 없으면 새로 정하고 log.selectionSeed에 남김.
    """
    v = VERSIONS.get(request.prompt_version)
    if v is None:
        raise CardGenerationError("INVALID_CONTEXT", f"모르는 promptVersion: {request.prompt_version}")
    if request.model not in ENDPOINTS:
        raise CardGenerationError("INVALID_CONTEXT", f"모르는 model: {request.model}")
    seed = random.SystemRandom().randrange(2**32) if seed is None else seed
    started = time.monotonic()
    config = ChatConfig(model=request.model, api_key=api_key, timeout=int(min(time_limit, 120)))
    store = ProfileStore(request.context, v.decay)
    titles = {t.topic_id: (t.title, t.description) for t in request.context.topics}
    model = chat_model(config)

    def over_time(stage: str) -> None:
        """시작부터 time_limit초를 넘었으면 LLM_UNAVAILABLE로 실패. 단계가 끝날 때마다 부름."""
        if time.monotonic() - started > time_limit:
            raise CardGenerationError("LLM_UNAVAILABLE", f"{stage} 뒤 {time_limit:.0f}초를 넘김")

    try:
        rec = recommend(store, model, v, rng=random.Random(seed))
        over_time("후보 찾기와 선정")
        drafts, writing = [], []
        for pos, picked in enumerate(rec.picked, 1):
            m, c = picked.matched, picked.matched.candidate
            refs = evidence_refs(c)
            if m.topic_id:
                topic = TopicOut(topic_id=m.topic_id)
                title, description = titles[m.topic_id]
            else:
                new = rec.match.new_topics[m.new_key]
                topic = TopicOut(title=new.title, description=new.description, evidence=refs)
                title, description = new.title, new.description
            drafts.append((pos, picked, topic, refs))
            writing.append({"position": pos, "card_title": c.card_title, "angle": c.angle, "kind": c.kind,
                            "evidence_texts": [t for t in store.evidence_texts(refs) if t],
                            "topic": {"title": title, "description": description}})
        texts, first_problems = write_cards(model, {"age_band": store.get_profile().age_band}, writing, v.writing_prompt())
        over_time("문안 작성")
    except CardGenerationError:
        raise
    except WritingFailed as error:
        raise CardGenerationError("TEXT_CHECK_FAILED", str(error)) from error
    except (RecommendFailed, SelectionFailed) as error:
        raise CardGenerationError("NOT_ENOUGH_TOPICS", str(error)) from error
    except Exception as error:
        if llm_down(error):
            raise CardGenerationError("LLM_UNAVAILABLE", f"{type(error).__name__}: {error}") from error
        raise CardGenerationError("CARD_GENERATION_FAILED", f"{type(error).__name__}: {error}") from error

    by_pos = {t.position: t for t in texts.cards}
    cards = []
    for pos, picked, topic, refs in drafts:
        c, text = picked.matched.candidate, by_pos[pos]
        cards.append(CardOut(position=pos, topic=topic, card_title=c.card_title, description=text.description,
                             primary_question=text.primary_question, follow_up_questions=text.follow_up_questions,
                             # 근거는 한 종류만 받으므로 첫 근거의 종류가 카드의 근거 종류
                             evidence_source=_SOURCE[next(iter(refs[0]))] if refs else "none", evidence=refs,
                             extra=CardExtra(kind=c.kind, bucket=picked.bucket, angle=c.angle, pick_reason=picked.reason,
                                             agent_reason=c.reason, match_reason=picked.matched.reason)))
    log = {"candidates": len(rec.agent.candidates), "toolCalls": len(rec.agent.tool_calls),
           "rejectedSubmissions": len(rec.agent.rejected), "refills": rec.refills,
           "dropped": rec.selection.dropped + rec.match.dropped, "selectionSeed": seed,
           "writingFirstProblems": first_problems, "seconds": round(time.monotonic() - started, 1)}
    return GenerationResult(model=request.model, prompt_version=request.prompt_version, cards=cards, log=log)


def recommend(store: ProfileStore, model: BaseChatModel, v: Version, rng: random.Random | None = None) -> Recommendation:
    """rng는 선정 추첨용. 없으면 매번 다르게 뽑음."""
    rules = v.selection
    session = AgentSession(model, store, v)
    agent = session.ask()
    refills: list[str] = []
    while True:
        match = run_match(model, store, agent.candidates, v.match_prompt())
        if _distinct_topics(match) >= rules.card_count or len(refills) >= _MAX_REFILLS:
            break
        refills.append(_refill_request(store, match, rules.card_count))
        agent = session.ask(refills[-1])
    try:
        selection = select_cards(match, store.all_topics(), rules, rng)
    except SelectionFailed as error:
        raise RecommendFailed(f"{error}(다시 찾기 {len(refills)}번 뒤)") from error
    return Recommendation(agent, match, selection, refills)


def _refill_request(store: ProfileStore, match: MatchOutcome, need: int) -> str:
    """판정 결과를 에이전트에게 알리는 글. 주제는 번호표로, 후보는 낸 순서로 가리킴."""
    aliases = store.aliases()
    titles = {t.topic_id: t.title for t in store.all_topics()}
    groups: dict[str, list] = {}
    for m in match.kept:
        groups.setdefault(m.topic_id or f"new:{m.new_key}", []).append(m)
    lines = [f"연결 판정을 거치니 서로 다른 주제가 {_distinct_topics(match)}개뿐이다. 카드는 주제마다 한 장이라 "
             f"{need}개 이상이 필요하다."]
    for key, ms in groups.items():
        if len(ms) < 2:
            continue
        name = (f"새 주제 '{match.new_topics[key[4:]].title}'" if key.startswith("new:")
                else f"{aliases.alias(key)} '{titles.get(key, '')}'")
        lines.append(f"- 같은 이야기로 묶임: {', '.join(f'{m.no}번 {m.candidate.card_title}' for m in ms)} → {name}")
    for d in match.dropped:
        lines.append(f"- 빠짐: {d['no']}번 {d['card_title']} ({d['reason']})")
    lines.append("이미 쓴 이야기와 겹치지 않는 다른 이야기를 더 찾아서, 고친 후보 전체를 다시 제출하라.")
    return "\n".join(lines)


def _distinct_topics(match: MatchOutcome) -> int:
    """판정 뒤 남은 후보의 서로 다른 주제 수. 기존 주제는 topic_id, 새 주제는 new_key로 셈."""
    return len({m.topic_id or f"new:{m.new_key}" for m in match.kept})
