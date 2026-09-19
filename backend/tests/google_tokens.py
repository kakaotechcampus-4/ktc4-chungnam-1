"""테스트용 구글 ID 토큰 생성기.

실제 구글 계정과 네트워크 없이 검증 경로를 확인하려고, 테스트에서 만든 RSA 키로
ID 토큰을 서명하고 그 공개키를 JWKS 문서로 돌려준다. 실제 사용자 계정은 쓰지 않는다.
"""

import json
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa

KEY_ID = "test-key-1"
CLIENT_ID = "test-client-id.apps.googleusercontent.com"
ISSUER = "https://accounts.google.com"

SIGNING_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
FOREIGN_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


def jwks_document() -> dict[str, Any]:
    jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(SIGNING_KEY.public_key()))
    jwk.update({"kid": KEY_ID, "alg": "RS256", "use": "sig"})
    return {"keys": [jwk]}


def id_token(
    *,
    subject: str = "google-sub-0001",
    audience: str = CLIENT_ID,
    issuer: str = ISSUER,
    expires_in: int = 3600,
    signing_key: rsa.RSAPrivateKey | None = None,
    email: str | None = None,
    name: str | None = None,
) -> str:
    issued_at = datetime.now(UTC)
    payload: dict[str, Any] = {
        "sub": subject,
        "aud": audience,
        "iss": issuer,
        "iat": issued_at,
        "exp": issued_at + timedelta(seconds=expires_in),
    }
    if email is not None:
        payload["email"] = email
    if name is not None:
        payload["name"] = name
    return jwt.encode(
        payload,
        signing_key or SIGNING_KEY,
        algorithm="RS256",
        headers={"kid": KEY_ID},
    )
