"""커밋된 출력(또는 SPOT_CHECK_OUT의 다시 실행한 출력)에 의료 효과 표현 검사, 카드 질문 금지어, 추가 키워드를 돌린다.

    uv run --offline --project ai python <이 폴더>/scan.py card-rich-uuid report-third ...

2026-11-03 실행 때와 다른 점은 경로뿐이다.
"""
import json, os, re, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "ai"))
OUT = os.environ.get("SPOT_CHECK_OUT") or str(HERE / "outputs")
from common.medical_claims import has_medical_effect_claim
from card_generation._steps.write import _BANNED
EXTRA = [r"통영", r"피란|피난|전쟁|6\.25|천막", r"기억", r"인지|치매|증상|치료|병원|약|건강|회복|효과|기억력"]
def texts(name, d):
    if name.startswith("card"):
        for c in d["cards"]:
            for k in ("cardTitle", "description", "primaryQuestion"):
                yield f"{c['position']}.{k}", c[k]
            for i, q in enumerate(c["followUpQuestions"]):
                yield f"{c['position']}.follow{i}", q
            if c["topic"].get("title"):
                yield f"{c['position']}.topicTitle", c["topic"]["title"]
                yield f"{c['position']}.topicDesc", c["topic"]["description"]
    else:
        for k in ("title", "body"):
            if k in d: yield k, d[k]
        for s in d.get("cardSummaries", []): yield "summary", s["summary"]
        for f in d.get("lifeFactProposals", []):
            for k in ("title", "content", "reason"): yield "fact." + k, f[k]
        for t in d.get("topicProposals", []): yield "topic." + t["suggestedAction"], t["reason"]
for name in sys.argv[1:]:
    d = json.load(open(OUT + "/" + name + ".json", encoding="utf-8"))
    hits = []
    for where, t in texts(name, d):
        if has_medical_effect_claim(t): hits.append((where, "MEDICAL_CLAIM", t))
        for b in _BANNED:
            if re.search(b, t): hits.append((where, "BANNED:" + b, t))
        for b in EXTRA:
            if re.search(b, t): hits.append((where, "KW:" + b, t))
    print("==", name, "hits:", len(hits))
    for h in hits: print("  ", h)
