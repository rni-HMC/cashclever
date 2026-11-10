# CashClever

Consumer lending marketplace prototype. Matches borrowers with loan products from credit
unions they're eligible for but don't know about, plus traditional lenders.

Built from the [scaffold](https://github.com/rni-HMC/scaffold) template.

## Stack

- **Backend**: FastAPI + SQLAlchemy + Postgres, spec-first OpenAPI codegen
- **Frontend**: TanStack Start + Tailwind + shadcn/ui, Vite dev server
- **Infra**: Nix flakes (flake-parts, uv2nix, bun2nix), process-compose for local Postgres
- **Deploy**: GitHub Actions → GHCR → Render (backend); Vercel (frontend)

## Setup

```bash
nix develop .#backend
cp .env.example backend/.env
nix run .#init-db
```

## Tests

```bash
nix run .#test
```

## Frontend

```bash
nix run .#landing
```

## Structure

```
cashclever/
├── backend/          FastAPI app, OpenAPI spec, tests
│   ├── app/
│   ├── openapi.yaml
│   └── tests/
├── landing/          TanStack Start frontend
│   ├── src/
│   └── app/
├── nix/              Nix build definitions
└── render.yaml       Render deploy config
```
