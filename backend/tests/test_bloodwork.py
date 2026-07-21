"""Tests for blood work upload/list/delete, using a stubbed vision extractor."""

from __future__ import annotations

import pytest

from enhale_backend.api.main import app
from enhale_backend.bloodwork.extractor import BloodWorkExtractor
from enhale_backend.deps import get_bloodwork_extractor

PANEL_JSON = """
{"collected_on":"2026-07-01","markers":[
  {"name":"Hemoglobin A1c","value":"5.4","value_num":5.4,"unit":"%","reference_range":"4.0-5.6","flag":"normal"},
  {"name":"LDL Cholesterol","value":"160","value_num":160,"unit":"mg/dL","reference_range":"<100","flag":"high"}
],"note":null}
"""


class StubVisionClient:
    def __init__(self, response: str) -> None:
        self.response = response
        self.last_media_type: str | None = None

    async def extract(self, system, user, media_type, data_b64) -> str:
        self.last_media_type = media_type
        return self.response


@pytest.fixture
def stub_extractor():
    def _set(response: str = PANEL_JSON) -> StubVisionClient:
        stub = StubVisionClient(response)
        app.dependency_overrides[get_bloodwork_extractor] = lambda: BloodWorkExtractor(stub)
        return stub
    return _set


def _upload(client, headers, filename="report.pdf", content=b"%PDF-1.4 fake", content_type="application/pdf"):
    return client.post(
        "/bloodwork/upload",
        files={"file": (filename, content, content_type)},
        headers=headers,
    )


def test_upload_requires_auth(client, stub_extractor):
    stub_extractor()
    assert _upload(client, {}).status_code == 401


def test_upload_extracts_and_stores(client, stub_extractor, auth):
    stub_extractor()
    headers = auth()

    r = _upload(client, headers)
    assert r.status_code == 200
    panel = r.json()
    assert panel["collected_on"] == "2026-07-01"
    assert len(panel["markers"]) == 2
    ldl = next(m for m in panel["markers"] if m["name"] == "LDL Cholesterol")
    assert ldl["flag"] == "high" and ldl["value_num"] == 160

    listed = client.get("/bloodwork", headers=headers).json()
    assert len(listed) == 1
    assert listed[0]["source_filename"] == "report.pdf"


def test_png_upload_uses_image_block(client, stub_extractor, auth):
    stub = stub_extractor()
    headers = auth()
    r = _upload(client, headers, filename="labs.png", content=b"\x89PNG fake", content_type="image/png")
    assert r.status_code == 200
    assert stub.last_media_type == "image/png"  # not treated as a document


def test_unsupported_type_rejected(client, stub_extractor, auth):
    stub_extractor()
    headers = auth()
    r = _upload(client, headers, filename="notes.txt", content=b"hello", content_type="text/plain")
    assert r.status_code == 415


def test_bloodwork_isolated_and_deletable(client, stub_extractor, auth):
    stub_extractor()
    alice = auth(email="ba@y.com")
    bob = auth(email="bb@y.com")

    panel_id = _upload(client, alice).json()["id"]
    assert len(client.get("/bloodwork", headers=alice).json()) == 1
    assert client.get("/bloodwork", headers=bob).json() == []

    # Bob can't delete Alice's panel.
    assert client.delete(f"/bloodwork/{panel_id}", headers=bob).status_code == 404
    # Alice can.
    assert client.delete(f"/bloodwork/{panel_id}", headers=alice).status_code == 204
    assert client.get("/bloodwork", headers=alice).json() == []
