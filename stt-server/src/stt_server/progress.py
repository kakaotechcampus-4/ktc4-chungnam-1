"""Pipeline progress without request contents or exception messages."""

from contextlib import contextmanager
import logging
import os
from time import perf_counter


logger = logging.getLogger("stt_server.progress")


def configure_logging() -> None:
    level = os.getenv("SAEROK_STT_LOG_LEVEL", "INFO").strip().upper()
    if level not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
        raise ValueError("Invalid SAEROK_STT_LOG_LEVEL")
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(handler)
    logger.setLevel(level)
    logger.propagate = False


@contextmanager
def progress(stage: str, trace: str = "startup"):
    started = perf_counter()
    logger.info("trace=%s stage=%s status=started", trace, stage)
    try:
        yield
    except Exception:
        # Exception messages and tracebacks can contain URLs, paths or transcripts.
        logger.error(
            "trace=%s stage=%s status=failed elapsed_s=%.3f",
            trace, stage, perf_counter() - started,
        )
        raise
    else:
        logger.info(
            "trace=%s stage=%s status=completed elapsed_s=%.3f",
            trace, stage, perf_counter() - started,
        )
