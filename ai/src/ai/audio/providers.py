from __future__ import annotations

from collections.abc import Iterator, Mapping
from contextlib import AbstractContextManager, contextmanager
from datetime import datetime, timezone
import hashlib
import hmac
from pathlib import Path
import tempfile
from typing import Protocol
from urllib.parse import urlsplit

import httpx

from ai.api.schemas import AudioSource, LocalAudioSource, S3AudioSource


DEFAULT_LOCAL_AUDIO_DIRECTORY = (
    Path(__file__).resolve().parents[3]
    / "docs"
    / "stt-mobile-benchmark"
    / "data"
    / "kcsc"
    / "WAV"
)


class AudioSourceError(ValueError):
    """음성 입력을 안전한 로컬 파일로 준비할 수 없을 때 발생한다."""


class AudioProvider(Protocol):
    def materialize(self, source: AudioSource) -> AbstractContextManager[Path]:
        """음성을 로컬 경로로 준비하고 사용 후 필요한 정리를 수행한다."""

        ...


class AudioSourceResolver:
    """`audioSource.type`에 맞는 Provider를 선택한다."""

    def __init__(self, providers: Mapping[str, AudioProvider]) -> None:
        self._providers = dict(providers)

    @contextmanager
    def materialize(self, source: AudioSource) -> Iterator[Path]:
        provider = self._providers.get(source.type)
        if provider is None:
            raise AudioSourceError(
                f"지원하지 않는 음성 입력 방식입니다: {source.type}"
            )

        with provider.materialize(source) as audio_path:
            yield audio_path


class LocalAudioProvider:
    """고정된 로컬 테스트 폴더 안의 WAV 파일만 제공한다."""

    def __init__(self, root: Path, *, enabled: bool) -> None:
        self._root = root.resolve()
        self._enabled = enabled

    @contextmanager
    def materialize(self, source: AudioSource) -> Iterator[Path]:
        if not isinstance(source, LocalAudioSource):
            raise TypeError("LocalAudioProvider에는 localFile 입력이 필요합니다.")
        if not self._enabled:
            raise AudioSourceError(
                "현재 환경에서는 로컬 음성 입력을 허용하지 않습니다."
            )

        candidate = (self._root / source.audio_file_name).resolve()
        try:
            candidate.relative_to(self._root)
        except ValueError as error:
            raise AudioSourceError(
                "로컬 음성은 허가된 테스트 폴더 안에 있어야 합니다."
            ) from error

        if not candidate.is_file():
            raise AudioSourceError("로컬 음성 파일을 찾을 수 없습니다.")

        yield candidate


class S3AudioProvider:
    """S3 Presigned GET URL을 임시 WAV 파일로 스트리밍 다운로드한다."""

    def __init__(
        self,
        *,
        allowed_host_suffixes: tuple[str, ...] = ("amazonaws.com",),
        max_size_bytes: int = 512 * 1024 * 1024,
        timeout_seconds: float = 60.0,
        client: httpx.Client | None = None,
    ) -> None:
        if not allowed_host_suffixes:
            raise ValueError("허용할 S3 호스트 접미사가 하나 이상 필요합니다.")
        self._allowed_host_suffixes = tuple(
            suffix.lower().lstrip(".") for suffix in allowed_host_suffixes
        )
        self._max_size_bytes = max_size_bytes
        self._timeout = httpx.Timeout(timeout_seconds)
        self._client = client

    @contextmanager
    def materialize(self, source: AudioSource) -> Iterator[Path]:
        if not isinstance(source, S3AudioSource):
            raise TypeError("S3AudioProvider에는 s3PresignedGet 입력이 필요합니다.")

        self._validate_source(source)
        with tempfile.TemporaryDirectory(prefix="saerok-ai-audio-") as directory:
            audio_path = Path(directory) / "input.wav"
            if self._client is None:
                with httpx.Client(
                    timeout=self._timeout,
                    follow_redirects=False,
                ) as client:
                    self._download(client, source, audio_path)
            else:
                self._download(self._client, source, audio_path)
            yield audio_path

    def _validate_source(self, source: S3AudioSource) -> None:
        now = datetime.now(timezone.utc)
        if source.download_url_expires_at <= now:
            raise AudioSourceError("음성 다운로드 URL이 만료되었습니다.")
        if source.size_bytes > self._max_size_bytes:
            raise AudioSourceError("음성 파일이 허용된 최대 크기를 초과합니다.")

        hostname = (urlsplit(source.download_url).hostname or "").lower()
        if not any(
            hostname == suffix or hostname.endswith(f".{suffix}")
            for suffix in self._allowed_host_suffixes
        ):
            raise AudioSourceError("허용되지 않은 음성 다운로드 호스트입니다.")

    def _download(
        self,
        client: httpx.Client,
        source: S3AudioSource,
        destination: Path,
    ) -> None:
        digest = hashlib.sha256()
        downloaded_size = 0

        with client.stream("GET", source.download_url) as response:
            if response.is_redirect:
                raise AudioSourceError(
                    "음성 다운로드 리다이렉트는 허용하지 않습니다."
                )
            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as error:
                raise AudioSourceError(
                    "음성 파일 다운로드에 실패했습니다."
                ) from error

            with destination.open("wb") as output:
                for chunk in response.iter_bytes():
                    downloaded_size += len(chunk)
                    if downloaded_size > source.size_bytes:
                        raise AudioSourceError(
                            "다운로드한 음성 크기가 요청 값보다 큽니다."
                        )
                    if downloaded_size > self._max_size_bytes:
                        raise AudioSourceError(
                            "다운로드한 음성이 허용된 최대 크기를 초과합니다."
                        )
                    digest.update(chunk)
                    output.write(chunk)

        if downloaded_size != source.size_bytes:
            raise AudioSourceError("다운로드한 음성 크기가 요청 값과 다릅니다.")
        if not hmac.compare_digest(digest.hexdigest(), source.sha256.lower()):
            raise AudioSourceError(
                "다운로드한 음성의 SHA-256이 요청 값과 다릅니다."
            )
