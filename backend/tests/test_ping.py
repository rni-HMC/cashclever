from app import models


def test_ping_writes_a_row_and_returns_it(client, db):
    resp = client.post("/v1/ping")
    assert resp.status_code == 200

    body = resp.json()
    assert body["message"] == "pong"
    assert body["count"] == 1
    assert db.query(models.PingLog).count() == 1


def test_ping_count_increments_across_calls(client):
    first = client.post("/v1/ping").json()
    second = client.post("/v1/ping").json()
    assert second["count"] == first["count"] + 1
