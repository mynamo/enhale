"""Password hashing (argon2) and JWT creation/verification.

argon2 is used directly (via argon2-cffi) rather than through passlib — it's the
current best-practice password hash and avoids passlib/bcrypt version friction.
Never hash passwords by hand; never log or store the plaintext.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from ..config import get_settings

_ph = PasswordHasher()


def hash_password(plaintext: str) -> str:
    return _ph.hash(plaintext)


def verify_password(hashed: str, plaintext: str) -> bool:
    try:
        return _ph.verify(hashed, plaintext)
    except VerifyMismatchError:
        return False
    except Exception:
        # Malformed hash, etc. — treat as a failed verification, never raise.
        return False


def create_access_token(subject: str) -> str:
    settings = get_settings()
    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "iat": now,
        "exp": now + timedelta(minutes=settings.jwt_expire_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> str:
    """Return the subject (user id as str), or raise ``jwt.PyJWTError``."""
    settings = get_settings()
    payload = jwt.decode(
        token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
    )
    subject = payload.get("sub")
    if not subject:
        raise jwt.InvalidTokenError("missing subject")
    return str(subject)
