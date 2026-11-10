"""저장된 합성 출력의 구조와 안전 규칙 일부를 재검사한다. 모델 호출과 파일 쓰기 없음.

직접 경험을 지어냈는지 등 의미 검사는 함께 둔 결과 문서에서 별도로 다룬다.
"""

import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "ai"))
sys.path.insert(0, str(HERE.parent / "2026-11-03-real-model-spot-check"))

import inputs
from common.medical_claims import has_medical_effect_claim
from common.visit_report import ReportResult, ProposalResult
from card_generation.contract import GenerationResult
from card_generation._steps.write import _BANNED, _QUIZ


def read(name, folder="outputs"):
    return json.loads((HERE / folder / f"{name}.json").read_text(encoding="utf-8"))


def main():
    for folder, count in (("outputs", 8), ("backend-sdk-outputs", 6)):
        ledger = read("calls", folder)
        assert len(ledger["runs"]) == count
        for run in ledger["runs"]:
            assert run["requested_model"] == "gpt-6-luna"
            assert run["max_output_tokens"] == 16000
            assert not run["error"]
            assert all(c["ok"] and c["model_name"] == "gpt-6-luna" for c in run["calls"])
    for kind, payload in (("rich", inputs.CARD_RICH_UUID), ("sparse", inputs.CARD_SPARSE_UUID)):
        data = read(f"card-{kind}-uuid")
        GenerationResult.model_validate(data)
        assert [c["position"] for c in data["cards"]] == list(range(1, 13))
        known_facts = {f["factId"] for f in payload["context"]["lifeFacts"]}
        known_photos = {p["photoId"] for p in payload["context"]["photos"]}
        for card in data["cards"]:
            questions = [card["primaryQuestion"], *card["followUpQuestions"]]
            assert len(card["followUpQuestions"]) == 3
            for q in questions:
                assert not any(re.search(p, q) for p in _BANNED)
                assert not any(p.search(q) for p in _QUIZ)
            for text in [card["cardTitle"], card["description"], *questions]:
                assert not has_medical_effect_claim(text)
            for evidence in card["evidence"]:
                if "factId" in evidence:
                    assert evidence["factId"] in known_facts
                elif "photoId" in evidence:
                    assert evidence["photoId"] in known_photos
                else:
                    assert payload["context"]["profileFacts"][evidence["profileField"]]
        if kind == "rich":
            assert all(c["topic"]["topicId"] != inputs.RICH_ID_MAP["t-refuge"] for c in data["cards"])
            displayed = json.dumps([{k: c[k] for k in ("cardTitle", "description", "primaryQuestion", "followUpQuestions")} for c in data["cards"]], ensure_ascii=False)
            assert "통영" not in displayed
        print(f"card-{kind}: 12 cards, 3 follow-ups each, references and text checks passed")
    for folder in ("outputs", "backend-sdk-outputs"):
        for name, payload in (("clear", inputs.REPORT_CLEAR), ("merged", inputs.REPORT_MERGED), ("third", inputs.REPORT_THIRD)):
            report, proposals = read(f"report-{name}", folder), read(f"proposals-{name}", folder)
            ReportResult.model_validate(report)
            ProposalResult.model_validate(proposals)
            reactions = {c["cardId"]: c["reaction"] for c in payload["cards"]}
            assert all(reactions[s["cardId"]] in ("positive", "neutral", "negative") for s in report["cardSummaries"])
            for p in proposals["topicProposals"]:
                assert p["cardId"] in reactions
                if p["suggestedAction"] in ("less", "exclude"):
                    assert reactions[p["cardId"]] not in (None, "notUsed")
            assert not has_medical_effect_claim(report["body"])
            print(f"{folder}/{name}: report and proposals validated")
    print("Structural checks passed; semantic quality requires the accompanying review.")


if __name__ == "__main__":
    main()
