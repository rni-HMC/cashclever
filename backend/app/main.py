from fastapi import FastAPI

from app.routers import ping

app = FastAPI(title="Scaffold", description="Empty starter -- nix + OpenAPI + FastAPI + Postgres")

app.include_router(ping.router)


@app.get("/health", operation_id="healthCheck")
def health():
    return {"status": "ok"}
