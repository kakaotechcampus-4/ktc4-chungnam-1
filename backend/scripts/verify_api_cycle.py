"""Explicitly gated synthetic API exercise; no request is sent by default."""

from __future__ import annotations

import argparse
import io
import json
import time
import wave
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID

import httpx


STAGES = [
    "verify_test_account",
    "create_synthetic_profile",
    "first_cards",
    "first_visit",
    "evaluation",
    "speech_upload",
    "report",
    "approve_synthetic_story",
    "next_cards",
    "correct_story",
    "refresh_cards",
    "second_visit",
]


class CheckFailed(Exception):
    """Only a fixed local code, never response text or credentials."""


def require(condition: bool, code: str) -> None:
    if not condition:
        raise CheckFailed(code)


def identifier(value: object) -> str:
    try:
        return str(UUID(str(value)))
    except (ValueError, TypeError, AttributeError):
        raise CheckFailed("INVALID_RESOURCE_ID") from None


def validate_origin(value: str, allow_remote: bool) -> str:
    try:
        parsed = urlsplit(value)
        parsed.port
    except ValueError:
        raise CheckFailed("INVALID_BASE_URL") from None
    require(
        bool(parsed.hostname) and parsed.scheme in ("http", "https"), "INVALID_BASE_URL"
    )
    require(
        not parsed.username
        and not parsed.password
        and not parsed.query
        and not parsed.fragment
        and parsed.path in ("", "/"),
        "INVALID_BASE_URL",
    )
    local = parsed.hostname in ("127.0.0.1", "localhost", "::1")
    require(local or allow_remote, "REMOTE_EXECUTION_NOT_ACKNOWLEDGED")
    require(local or parsed.scheme == "https", "REMOTE_HTTPS_REQUIRED")
    return value.rstrip("/")


def read_wav(path: Path) -> bytes:
    # Read a bounded amount before parsing. Do not print the path or file name.
    with path.open("rb") as stream:
        data = stream.read(32 * 1024 * 1024 + 1)
    require(len(data) <= 32 * 1024 * 1024, "SYNTHETIC_WAV_TOO_LARGE")
    try:
        with wave.open(io.BytesIO(data), "rb") as audio:
            require(
                audio.getnchannels() == 1
                and audio.getsampwidth() == 2
                and audio.getframerate() == 16000
                and audio.getcomptype() == "NONE",
                "SYNTHETIC_WAV_FORMAT",
            )
            frames = audio.getnframes()
            require(0 < frames <= 900 * 16000, "SYNTHETIC_WAV_DURATION")
            require(
                len(audio.readframes(frames)) == frames * 2, "SYNTHETIC_WAV_TRUNCATED"
            )
    except (wave.Error, EOFError):
        raise CheckFailed("SYNTHETIC_WAV_FORMAT") from None
    return data


class Cycle:
    def __init__(
        self,
        client: httpx.Client,
        *,
        wait_seconds=1200,
        poll_seconds=2,
        clock=time.monotonic,
        sleep=time.sleep,
    ):
        self.client, self.wait, self.poll = client, wait_seconds, poll_seconds
        self.clock, self.sleep = clock, sleep
        self.result = {
            "mode": "synthetic_execute",
            "outcome": "incomplete",
            "stages": [],
            "resources": {},
            "limits": [
                "not_android_e2e",
                "semantic_quality_requires_review",
                "test_resources_retained_no_automatic_deletion",
            ],
        }
        self.stage = "not_started"
        self.stage_started = self.clock()

    def begin(self, stage):
        if self.stage != "not_started":
            self.result["stages"].append(
                {
                    "name": self.stage,
                    "outcome": "passed",
                    "seconds": round(self.clock() - self.stage_started, 3),
                }
            )
        self.stage, self.stage_started = stage, self.clock()

    def call(self, method, path, expected=200, **kwargs):
        try:
            response = self.client.request(method, path, **kwargs)
        except httpx.HTTPError:
            raise CheckFailed("NETWORK_ERROR") from None
        require(
            response.status_code == expected, f"UNEXPECTED_HTTP_{response.status_code}"
        )
        try:
            body = response.json()
        except ValueError:
            raise CheckFailed("INVALID_JSON") from None
        require(isinstance(body, dict), "INVALID_JSON_OBJECT")
        return body

    def wait_for(self, path, ready, pending):
        deadline = self.clock() + self.wait
        while True:
            body = self.call("GET", path)
            if body.get("status") == ready:
                return body
            require(body.get("status") in pending, "JOB_NOT_SUCCESSFUL")
            require(self.clock() < deadline, "POLL_TIMEOUT")
            self.sleep(min(self.poll, max(0, deadline - self.clock())))

    def cards(self, base):
        self.call("POST", base + "/card-generations", 202)
        self.wait_for(base + "/card-generations/status", "ready", {"running"})
        result = self.call("GET", base + "/card-generations/current")
        require(
            len(result["cards"]) == 12 and result.get("needsRefresh") is False,
            "CARDS_NOT_READY",
        )
        identifier(result["setId"])
        require(
            len({identifier(item["cardId"]) for item in result["cards"]}) == 12,
            "DUPLICATE_CARD_ID",
        )
        return result

    def start(self, cards, expected=201):
        return self.call(
            "POST",
            "/api/v1/visit-sessions",
            expected,
            json={
                "setId": cards["setId"],
                "selectedCardIds": [
                    identifier(card["cardId"]) for card in cards["cards"][:2]
                ],
            },
        )

    def run(self, account_id, wav, participant_count):
        try:
            self._run(identifier(account_id), wav, participant_count)
            self.result["stages"].append(
                {
                    "name": self.stage,
                    "outcome": "passed",
                    "seconds": round(self.clock() - self.stage_started, 3),
                }
            )
            self.result["outcome"] = "passed_api_flow"
        except CheckFailed as error:
            self.result["stages"].append(
                {"name": self.stage, "outcome": "incomplete", "code": str(error)}
            )
        except (KeyError, TypeError, IndexError, ValueError, AttributeError):
            self.result["stages"].append(
                {
                    "name": self.stage,
                    "outcome": "incomplete",
                    "code": "UNEXPECTED_RESPONSE_SHAPE",
                }
            )
        return self.result

    def _run(self, account_id, wav, participant_count):
        self.begin("verify_test_account")
        account = self.call("GET", "/auth/me")
        require(identifier(account["accountId"]) == account_id, "TEST_ACCOUNT_MISMATCH")
        require(
            all(
                account["consent"][key]["granted"] is True
                for key in ("serviceData", "sensitiveData")
            ),
            "REQUIRED_CONSENT_MISSING",
        )

        self.begin("create_synthetic_profile")
        profile = self.call(
            "POST",
            "/api/v1/profiles",
            201,
            json={
                "name": "합성 API 시험",
                "gender": "female",
                "birthDate": "1943-03-12",
                "condition": {"stage": "unknown"},
            },
        )
        profile_id = identifier(profile["profileId"])
        self.result["resources"]["profileId"] = profile_id
        base = f"/api/v1/profiles/{profile_id}"
        self.call("PATCH", base, json={"hobby": "합성 정원 가꾸기"})

        self.begin("first_cards")
        first = self.cards(base)
        self.begin("first_visit")
        session = identifier(self.start(first)["sessionId"])
        self.result["resources"]["firstSessionId"] = session
        visit = f"/api/v1/visit-sessions/{session}"
        self.begin("evaluation")
        self.call(
            "POST",
            visit + "/evaluation",
            201,
            json={
                "conversationSatisfaction": 4,
                "careRecipientReaction": "pleased",
                "freeNote": "합성 자료의 연결 검사입니다.",
                "cardReviews": [
                    {
                        "cardId": first["cards"][0]["cardId"],
                        "wasUsed": True,
                        "caregiverReaction": "positive",
                    },
                    {
                        "cardId": first["cards"][1]["cardId"],
                        "wasUsed": False,
                        "caregiverReaction": None,
                    },
                ],
            },
        )
        self.begin("speech_upload")
        submitted = self.call(
            "POST",
            visit + "/speech-analyses",
            202,
            data={"participantCount": str(participant_count)},
            files={"audio": ("synthetic.wav", wav, "audio/wav")},
        )
        analysis = identifier(submitted["analysisId"])
        self.result["resources"]["analysisId"] = analysis
        self.wait_for(
            f"/api/v1/speech-analyses/{analysis}",
            "completed",
            {"queued", "transcribing", "sttCompleted", "generatingReport"},
        )

        self.begin("report")
        report = self.call("GET", visit + "/report")
        require(bool(str(report.get("body", "")).strip()), "EMPTY_REPORT")
        require(self.call("GET", visit + "/report") == report, "REPORT_CHANGED_ON_READ")
        proposals = self.call("GET", visit + "/proposals")
        stories = proposals["lifeFactProposals"]
        # No artificial story insertion to turn an incomplete extraction into a pass.
        require(bool(stories), "NO_STORY_CANDIDATE_CYCLE_NOT_VERIFIED")
        require(self.call("GET", base)["lifeFacts"] == [], "UNAPPROVED_STORY_STORED")
        story = stories[0]
        require(
            isinstance(story["title"], str)
            and isinstance(story["content"], str)
            and bool(story["content"].strip()),
            "INVALID_STORY_CANDIDATE",
        )

        self.begin("approve_synthetic_story")
        # Only proposals of the profile created by this invocation are submitted.
        # Explicit execute acknowledgment is for synthetic material, never real-user facts.
        decisions = {"lifeFacts": [], "topics": []}
        for index, proposal in enumerate(stories):
            item = {
                "proposalId": identifier(proposal["proposalId"]),
                "reviewStatus": "accepted" if index == 0 else "rejected",
            }
            if index == 0:
                item.update(title=story["title"], content=story["content"])
            decisions["lifeFacts"].append(item)
        excluded = set()
        for proposal in proposals["topicProposals"]:
            # Explicit synthetic test choice, not an inference from unused cards.
            excluded.add(identifier(proposal["topic"]["topicId"]))
            decisions["topics"].append(
                {
                    "proposalId": identifier(proposal["proposalId"]),
                    "reviewStatus": "accepted",
                    "action": "exclude",
                }
            )
        self.call("POST", visit + "/proposals/review", json=decisions)
        facts = self.call("GET", base)["lifeFacts"]
        require(
            len(facts) == 1 and facts[0]["content"] == story["content"],
            "APPROVED_STORY_NOT_STORED",
        )
        fact_id = identifier(facts[0]["factId"])
        self.result["resources"]["factId"] = fact_id
        self.result["topicExclusionChecked"] = bool(excluded)

        self.begin("next_cards")
        prepared = self.cards(base)
        require(
            not excluded.intersection(
                identifier(card["topic"]["topicId"]) for card in prepared["cards"]
            ),
            "EXCLUDED_TOPIC_RETURNED",
        )
        self.begin("correct_story")
        correction = "합성 시험의 정정: 정원이 아니라 합성 강가에서 꽃을 길렀습니다."
        self.call(
            "PATCH", f"/api/v1/life-facts/{fact_id}", json={"content": correction}
        )
        facts = self.call("GET", base)["lifeFacts"]
        require(
            len(facts) == 1 and facts[0]["content"] == correction,
            "CORRECTION_NOT_STORED",
        )
        require(
            self.call("GET", base + "/card-generations/current")["needsRefresh"]
            is True,
            "CORRECTED_CARDS_NOT_MARKED",
        )
        require(
            self.start(prepared, 409).get("errorCode") == "CARD_SET_NEEDS_REFRESH",
            "STALE_CARDS_NOT_BLOCKED",
        )
        self.begin("refresh_cards")
        refreshed = self.cards(base)
        require(refreshed["setId"] != prepared["setId"], "OLD_CARD_SET_REUSED")
        require(
            not excluded.intersection(
                identifier(card["topic"]["topicId"]) for card in refreshed["cards"]
            ),
            "EXCLUDED_TOPIC_RETURNED",
        )
        self.begin("second_visit")
        second = identifier(self.start(refreshed)["sessionId"])
        require(second != session, "FIRST_SESSION_REUSED")
        self.result["resources"]["secondSessionId"] = second


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--execute-synthetic-test", action="store_true")
    parser.add_argument("--allow-remote", action="store_true")
    parser.add_argument("--token-file", type=Path)
    parser.add_argument("--test-account-id")
    parser.add_argument("--synthetic-wav", type=Path)
    parser.add_argument("--participant-count", type=int, choices=range(1, 9), default=2)
    parser.add_argument("--wait-seconds", type=int, default=1200)
    args = parser.parse_args(argv)
    if not args.execute_synthetic_test:
        print(
            json.dumps(
                {
                    "mode": "plan",
                    "requestsSent": 0,
                    "stages": STAGES,
                    "warning": "Execution creates test records and may incur model/S3 costs."
                    " It approves only newly created synthetic proposals; no cleanup is automatic.",
                }
            )
        )
        return 0
    try:
        origin = validate_origin(args.base_url, args.allow_remote)
        require(
            bool(args.token_file and args.synthetic_wav and args.test_account_id),
            "TEST_INPUT_REQUIRED",
        )
        require(1 <= args.wait_seconds <= 3600, "INVALID_WAIT_SECONDS")
        account_id = identifier(args.test_account_id)
        token = args.token_file.read_text(encoding="utf-8-sig").strip()
        require(
            bool(token)
            and len(token) <= 16384
            and not any(char.isspace() for char in token),
            "INVALID_TOKEN_FILE",
        )
        wav = read_wav(args.synthetic_wav)
        with httpx.Client(
            base_url=origin,
            headers={"Authorization": f"Bearer {token}"},
            timeout=30,
            follow_redirects=False,
            trust_env=False,
        ) as client:
            result = Cycle(client, wait_seconds=args.wait_seconds).run(
                account_id, wav, args.participant_count
            )
    except CheckFailed as error:
        result = {"outcome": "not_executed", "code": str(error)}
    except (OSError, UnicodeError):
        result = {"outcome": "not_executed", "code": "LOCAL_INPUT_UNREADABLE"}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("outcome") == "passed_api_flow" else 1


if __name__ == "__main__":
    raise SystemExit(main())
