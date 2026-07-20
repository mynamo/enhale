"""Shared test fixtures: an isolated temp-file DB and a TestClient.

Uses a per-test SQLite file with NullPool so connections are opened fresh in
whatever event loop is running — avoids the cross-loop aiosqlite pitfalls of an
in-memory DB shared between the setup coroutine and the TestClient's loop.
"""

from __future__ import annotations

import asyncio
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from enhale_backend.api.main import app
from enhale_backend.db import Base, get_session
from enhale_backend.deps import get_parser
from enhale_backend.parsing.meal_parser import MealParser


class StubLLMClient:
    """Deterministic stand-in for the real LLM in route tests."""

    def __init__(self, response: str) -> None:
        self.response = response

    async def complete(self, system: str, user: str) -> str:
        return self.response


@pytest.fixture
def client(tmp_path) -> Iterator[TestClient]:
    db_url = f"sqlite+aiosqlite:///{tmp_path / 'test.db'}"
    engine = create_async_engine(db_url, poolclass=NullPool)

    async def _create() -> None:
        import enhale_backend.db_models  # noqa: F401 — register tables
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(_create())

    TestSession = async_sessionmaker(engine, expire_on_commit=False)

    async def override_session():
        async with TestSession() as session:
            yield session

    # Lifespan runs init_db against the real engine; that's harmless (separate
    # file), but our override is what the routes actually use.
    app.dependency_overrides[get_session] = override_session

    with TestClient(app) as test_client:
        yield test_client

    app.dependency_overrides.clear()
    asyncio.run(engine.dispose())


@pytest.fixture
def stub_parser():
    """Returns a setter that points the parser at a canned LLM response."""
    def _set(response: str) -> None:
        app.dependency_overrides[get_parser] = lambda: MealParser(StubLLMClient(response))
    return _set


@pytest.fixture
def auth(client):
    """Returns a factory that registers a fresh user and yields an auth header."""
    def _register(email: str = "a@b.com", password: str = "pw12345") -> dict:
        resp = client.post("/auth/register", json={"email": email, "password": password})
        assert resp.status_code == 201, resp.text
        return {"Authorization": f"Bearer {resp.json()['access_token']}"}
    return _register
