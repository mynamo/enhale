"""Auth dependency: resolve the current user from a Bearer token."""

from __future__ import annotations

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..db_models import User
from .security import decode_access_token

_bearer = HTTPBearer(auto_error=True)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> User:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        subject = decode_access_token(credentials.credentials)
    except jwt.PyJWTError:
        raise unauthorized

    user = await session.get(User, int(subject))
    if user is None:
        raise unauthorized
    return user
