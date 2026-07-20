"""Route tests: health, auth flow, and per-user meal persistence.

``client``, ``stub_parser``, and ``auth`` are fixtures from conftest.py.
"""

from __future__ import annotations

OATMEAL = (
    '{"items":[{"name":"oatmeal","calories":150,"estimated":true}],'
    '"meal_type":"breakfast","confidence":0.8}'
)


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


# --- auth --------------------------------------------------------------------


def test_register_login_me(client):
    r = client.post("/auth/register", json={"email": "x@y.com", "password": "secret1"})
    assert r.status_code == 201

    r = client.post("/auth/login", json={"email": "x@y.com", "password": "secret1"})
    assert r.status_code == 200
    token = r.json()["access_token"]

    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200
    assert r.json()["email"] == "x@y.com"


def test_duplicate_registration_conflicts(client):
    client.post("/auth/register", json={"email": "dup@y.com", "password": "secret1"})
    r = client.post("/auth/register", json={"email": "dup@y.com", "password": "other12"})
    assert r.status_code == 409


def test_login_wrong_password_rejected(client):
    client.post("/auth/register", json={"email": "z@y.com", "password": "secret1"})
    r = client.post("/auth/login", json={"email": "z@y.com", "password": "wrongpw"})
    assert r.status_code == 401


def test_me_requires_auth(client):
    assert client.get("/auth/me").status_code == 401  # no bearer credentials


# --- meals -------------------------------------------------------------------


def test_parse_requires_auth(client, stub_parser):
    stub_parser(OATMEAL)
    assert client.post("/meals/parse", json={"transcript": "oatmeal"}).status_code == 401


def test_parse_store_and_list(client, stub_parser, auth):
    stub_parser(OATMEAL)
    headers = auth()

    r = client.post("/meals/parse", json={"transcript": "a bowl of oatmeal"}, headers=headers)
    assert r.status_code == 200
    assert r.json()["items"][0]["name"] == "oatmeal"

    r = client.get("/meals", headers=headers)
    assert r.status_code == 200
    assert len(r.json()) == 1
    assert r.json()[0]["meal_type"] == "breakfast"


def test_no_food_returns_422(client, stub_parser, auth):
    stub_parser('{"items":[],"confidence":0}')
    headers = auth()
    r = client.post("/meals/parse", json={"transcript": "hello there"}, headers=headers)
    assert r.status_code == 422


def test_meals_are_isolated_per_user(client, stub_parser, auth):
    stub_parser(OATMEAL)
    alice = auth(email="alice@y.com")
    bob = auth(email="bob@y.com")

    client.post("/meals/parse", json={"transcript": "oatmeal"}, headers=alice)

    assert len(client.get("/meals", headers=alice).json()) == 1
    assert client.get("/meals", headers=bob).json() == []  # Bob sees nothing


def test_delete_meal(client, stub_parser, auth):
    stub_parser(OATMEAL)
    headers = auth()
    meal_id = client.post("/meals/parse", json={"transcript": "oatmeal"}, headers=headers).json()["id"]

    assert client.delete(f"/meals/{meal_id}", headers=headers).status_code == 204
    assert client.get("/meals", headers=headers).json() == []


def test_cannot_delete_another_users_meal(client, stub_parser, auth):
    stub_parser(OATMEAL)
    alice = auth(email="alice2@y.com")
    bob = auth(email="bob2@y.com")
    meal_id = client.post("/meals/parse", json={"transcript": "oatmeal"}, headers=alice).json()["id"]

    assert client.delete(f"/meals/{meal_id}", headers=bob).status_code == 404
    assert len(client.get("/meals", headers=alice).json()) == 1
