# nix/backend.nix
#
# uv2nix-based build for backend/: a production venv (runtime deps only), a dev
# devShell (+ pytest/httpx/uv), and an `init-db` wrapper around backend/scripts/init_db.py.
{ inputs, ... }:
{
  perSystem = { pkgs, lib, ... }:
    let
      workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ../backend; };
      overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
      pythonSet = (pkgs.callPackage inputs.pyproject-nix.build.packages { python = pkgs.python311; })
        .overrideScope (lib.composeManyExtensions [
          inputs.pyproject-build-systems.overlays.default
          overlay
          (import ./lib/backend-overrides.nix { inherit pkgs; }) # psycopg[binary] fixups ONLY here
          (import ./lib/openapi-codegen-override.nix { inherit pkgs; }) # bakes generated_models.py into the cashclever build
        ]);

      backendEnv = pythonSet.mkVirtualEnv "cashclever-backend-env" workspace.deps.default; # prod: runtime deps only
      backendDevEnv = pythonSet.mkVirtualEnv "cashclever-backend-dev-env" workspace.deps.all; # dev: + pytest/httpx

      # Shared preflight + exec logic for the DB-management wrapper below (see
      # nix/postgres.nix for the matching pattern in the up/down wrappers). Distinguishes
      # failure modes that have genuinely different fixes instead of collapsing everything
      # into one generic "can't connect" error:
      #   1. No Postgres server answering at all on host:port.
      #   2. A server IS answering, but the `cashclever` role/database specifically aren't
      #      usable -- pg_isready alone does NOT prove this.
      #   3. Reachable and usable -- proceed to cd + exec the real script.
      mkDbWrapper = { name, scriptFile }:
        "${pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ pkgs.postgresql pkgs.git backendDevEnv ];
          text = ''
            PG_HOST="localhost"
            PG_PORT="5432"
            PG_USER="cashclever"
            PG_DB="cashclever"

            err() {
              echo "${name}: $*" >&2
            }

            if ! pg_isready -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1; then
              err "postgres-dev is not running (no response from $PG_HOST:$PG_PORT)."
              err "Run: nix run .#dev-up"
              exit 1
            fi

            if ! PGPASSWORD="''${PGPASSWORD:-cashclever}" \
                psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -At -c 'select 1' >/dev/null 2>&1; then
              err "postgres-dev is reachable at $PG_HOST:$PG_PORT, but connecting as user '$PG_USER' to database '$PG_DB' failed."
              err "The server is up, but the cashclever role/database aren't provisioned correctly."
              err "Run: nix run .#dev-up  (or check postgres-dev's init logs if it's already running)"
              exit 1
            fi

            repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
            if [ ! -f "$repo_root/backend/scripts/${scriptFile}" ]; then
              err "could not find backend/scripts/${scriptFile} under '$repo_root'."
              err "Run this from inside the cashclever repository checkout (or a subdirectory of it)."
              exit 1
            fi
            cd "$repo_root/backend" || exit 1

            export DATABASE_URL="''${DATABASE_URL:-postgresql+psycopg://cashclever:cashclever@localhost:5432/cashclever}"

            exec python "scripts/${scriptFile}"
          '';
        }}/bin/${name}";
    in {
      # backend/pyproject.toml has a real [build-system] table (setuptools), so this venv
      # genuinely installs the `app` package -- `import app` works with zero PYTHONPATH
      # tricks. That still isn't proof the app code is *correct*; see CLAUDE.md. Use
      # `nix run .#test` to actually validate application behavior.
      packages.backend = backendEnv;
      devShells.backend = pkgs.mkShell {
        packages = [ backendDevEnv pkgs.uv pkgs.ruff ];
      };

      apps.init-db.program = mkDbWrapper { name = "init-db"; scriptFile = "init_db.py"; };
      apps.reset-db.program = mkDbWrapper { name = "reset-db"; scriptFile = "reset_db.py"; };
      apps.seed-demo.program = mkDbWrapper { name = "seed-demo"; scriptFile = "seed_demo.py"; };

      # backend/openapi.yaml is the hand-authored source of truth -- app/generated_models.py
      # is generated FROM it via datamodel-code-generator and is gitignored, never
      # hand-edited. No DB preflight needed here (unlike mkDbWrapper above): this is a pure
      # text-to-text codegen step. `nix run .#test` (nix/postgres.nix) also runs this exact
      # command as a pre-step before every pytest invocation -- that regenerate-then-test
      # sequence IS the drift check, since there's no committed generated file to diff against.
      apps.generate-openapi-models.program =
        "${pkgs.writeShellApplication {
          name = "generate-openapi-models";
          runtimeInputs = [ pkgs.git backendDevEnv ];
          text = ''
            repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
            if [ ! -f "$repo_root/backend/openapi.yaml" ]; then
              echo "generate-openapi-models: could not find backend/openapi.yaml under '$repo_root'." >&2
              echo "generate-openapi-models: run this from inside the cashclever repository checkout." >&2
              exit 1
            fi
            cd "$repo_root/backend" || exit 1

            datamodel-codegen \
              --input openapi.yaml --input-file-type openapi \
              --output app/generated_models.py \
              --output-model-type pydantic_v2.BaseModel \
              --target-python-version 3.11 \
              --use-standard-collections --use-union-operator \
              --enum-field-as-literal one

            echo "generate-openapi-models: wrote backend/app/generated_models.py" >&2
          '';
        }}/bin/generate-openapi-models";

      # Exposed for nix/postgres.nix's `test` process-compose stack: its `pytest` process
      # needs the dev venv (workspace.deps.all, includes pytest) -- packages.backend above
      # is deliberately the prod-only venv (workspace.deps.default) and does not have pytest.
      packages.backend-dev = backendDevEnv;
    };
}
