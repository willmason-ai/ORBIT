"""
Entra ID bearer token validation (Phase 1: supervisor-only).

The React dashboard uses MSAL.js to acquire an access token for the
ORBIT API app registration. This module verifies the token using
Microsoft's OpenID Connect metadata and exposes two FastAPI dependencies:

    current_user       -> any authenticated user
    require_supervisor -> Supervisor app role required
"""
from __future__ import annotations

import logging
import os
import time
from dataclasses import dataclass
from typing import Any

import httpx
import jwt
from fastapi import Depends, Header, HTTPException, status
from jwt import PyJWKClient

log = logging.getLogger(__name__)

TENANT_ID = os.environ.get("ORBIT_TENANT_ID", "")
API_AUDIENCE = os.environ.get("ORBIT_API_AUDIENCE", "api://orbit-dashboard")
OIDC_URL = f"https://login.microsoftonline.com/{TENANT_ID}/v2.0/.well-known/openid-configuration"

_jwks_client: PyJWKClient | None = None
_jwks_uri: str | None = None
_issuer: str | None = None
_last_fetch: float = 0.0


@dataclass
class CurrentUser:
    object_id: str
    email: str
    name: str
    roles: list[str]

    @property
    def is_supervisor(self) -> bool:
        return "Supervisor" in self.roles


def _load_oidc_metadata() -> None:
    global _jwks_client, _jwks_uri, _issuer, _last_fetch
    if _jwks_client and (time.time() - _last_fetch) < 3600:
        return
    if not TENANT_ID:
        raise HTTPException(status_code=500, detail="ORBIT_TENANT_ID not configured")
    resp = httpx.get(OIDC_URL, timeout=10.0)
    resp.raise_for_status()
    meta = resp.json()
    _jwks_uri = meta["jwks_uri"]
    _issuer = meta["issuer"]
    _jwks_client = PyJWKClient(_jwks_uri)
    _last_fetch = time.time()


def _decode_token(token: str) -> dict[str, Any]:
    _load_oidc_metadata()
    assert _jwks_client and _issuer
    signing_key = _jwks_client.get_signing_key_from_jwt(token).key
    return jwt.decode(
        token,
        signing_key,
        algorithms=["RS256"],
        audience=API_AUDIENCE,
        issuer=_issuer,
        options={"require": ["exp", "iss", "aud"]},
    )


def current_user(authorization: str | None = Header(default=None)) -> CurrentUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        claims = _decode_token(token)
    except jwt.InvalidTokenError as exc:
        log.warning("Token validation failed: %s", exc)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid token") from exc

    return CurrentUser(
        object_id=claims.get("oid", ""),
        email=claims.get("preferred_username") or claims.get("upn") or claims.get("email", ""),
        name=claims.get("name", ""),
        roles=claims.get("roles", []),
    )


def require_supervisor(user: CurrentUser = Depends(current_user)) -> CurrentUser:
    if not user.is_supervisor:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Supervisor role required")
    return user
