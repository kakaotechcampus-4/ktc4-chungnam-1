import importlib

import pytest
from pydantic import ValidationError

from photo_analysis import PhotoAnalysisError, PhotoDescription, analyze_photo

module = importlib.import_module("photo_analysis.generate")


class FakeModel:
    def __init__(self, result):
        self.result = result
        self.messages = None

    def with_structured_output(self, schema, **kwargs):
        assert schema is PhotoDescription
        assert kwargs == {"method": "json_schema", "strict": True}
        return self

    def invoke(self, messages):
        self.messages = messages
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


def test_multimodal_call_has_no_profile_or_metadata(monkeypatch):
    fake = FakeModel({"description": "  합성 그림에 나무가 보입니다.  "})
    configs = []
    monkeypatch.setattr(module, "chat_model", lambda config: configs.append(config) or fake)
    result = analyze_photo("https://synthetic.invalid/photo?signature=test",
                           model="gpt-5.6-luna", api_key="synthetic")
    assert result.description == "합성 그림에 나무가 보입니다."
    assert len(fake.messages) == 2
    assert fake.messages[1].content[1]["image_url"]["url"].startswith("https://synthetic.invalid/")
    assert "EXIF" in fake.messages[0].content
    assert fake.messages[0].content == module.PROMPT.read_text(encoding="utf-8")
    assert configs[0].timeout == 120


@pytest.mark.parametrize("url", ["http://localhost/photo", "file:///photo.jpg", "https://"])
def test_invalid_url_never_calls_model(monkeypatch, url):
    monkeypatch.setattr(module, "chat_model", lambda _: pytest.fail("호출하면 안 됨"))
    with pytest.raises(PhotoAnalysisError, match="INVALID_IMAGE_REQUEST"):
        analyze_photo(url, model="gpt-5.6-luna", api_key="synthetic")


@pytest.mark.parametrize("result", [{"description": "  "}, {"description": "ok", "extra": 1},
                                   RuntimeError("secret signed url and image content")])
def test_invalid_output_or_provider_error_is_sanitized(monkeypatch, result):
    monkeypatch.setattr(module, "chat_model", lambda _: FakeModel(result))
    with pytest.raises(PhotoAnalysisError) as caught:
        analyze_photo("https://synthetic.invalid/photo", model="gpt-5.6-luna", api_key="synthetic")
    assert str(caught.value) == "INVALID_IMAGE_ANALYSIS_RESULT"
    assert "secret" not in str(caught.value)


def test_blank_description_rejected():
    with pytest.raises(ValidationError):
        PhotoDescription(description="\n\t ")


def test_photo_prompt_checks_each_person_and_visible_action():
    text = module.PROMPT.read_text(encoding="utf-8")
    assert module.PROMPT_VERSION == "photo-2"
    for rule in ("인물별 위치", "다른 사람에게 옮기거나", "조명이나 가림", "실제로 보고 있거나 하고 있는 일"):
        assert rule in text
