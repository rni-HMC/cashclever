# nix/postgres.nix
#
# Two process-compose stacks (dev, test), each a self-contained Postgres 16 instance managed
# via services-flake -- no hand-written health-check code, `services.postgres` generates the
# pg_isready-based readiness probe and the "<name>-init" one-shot setup process.
#
# `apps.test` is the one non-trivial piece: process-compose's `run` subcommand does NOT attach
# to an already-running server on the same unix socket -- it always tries to become the server
# itself and hard-fails ("unix socket ... already in use") if one is already listening there.
{ inputs, ... }:
{
  perSystem = { config, pkgs, lib, ... }:
    let
      devSocket = ".direnv/postgres-dev-pc.sock";
      testSocket = ".direnv/postgres-test-pc.sock";

      # process-compose-flake defaults `config.process-compose.<stack>.package` to
      # `pkgs.process-compose` anyway -- using it directly here is simpler and equally correct.
      processCompose = pkgs.process-compose;

      # Shared repo-root resolution: `nix run .#<app>` must work from any subdirectory of
      # the checkout, and these wrappers reference repo-relative paths (.direnv/...,
      # backend/...), not Nix store paths.
      cdRepoRoot = name: ''
        repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
        if [ -z "$repo_root" ]; then
          echo "${name}: not inside a git checkout of the cashclever repo (or git is unavailable)." >&2
          echo "${name}: run this from inside the cashclever repository checkout." >&2
          exit 1
        fi
        cd "$repo_root" || exit 1
      '';

      # Thin wrapper around `process-compose up <processes> -D -u <socket>`. Positional process
      # selection means only Postgres (+ its init process) ever starts here -- e.g. the `test`
      # stack's `pytest` process is never touched by *-up/-down.
      mkPostgresUp = { name, downName, socket, settingsFile, processes }:
        "${pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ processCompose pkgs.git ];
          text = ''
            ${cdRepoRoot name}
            # process-compose's UDS listener does NOT create the socket's parent directory --
            # on a fresh checkout (no .direnv/ yet) it fails with an opaque
            # "listen unix .../.sock: bind: no such file or directory" buried in its own log
            # file, not surfaced to this script's stderr. Pre-create it.
            mkdir -p "$(dirname "${socket}")"
            echo "${name}: starting ${lib.concatStringsSep " " processes} (socket: ${socket})..." >&2
            # -t=false: even with -D (detached), process-compose probes for a controlling TTY to
            # start its TUI and hard-fails in a true headless/CI shell that lacks one.
            PC_CONFIG_FILES=${settingsFile} process-compose up ${lib.concatStringsSep " " processes} -D -t=false -u ${socket}
            echo "${name}: started detached. Stop with: nix run .#${downName}" >&2
          '';
        }}/bin/${name}";

      mkPostgresDown = { name, socket }:
        "${pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ processCompose pkgs.git ];
          text = ''
            ${cdRepoRoot name}
            if [ ! -S "${socket}" ]; then
              echo "${name}: no socket at ${socket} -- nothing appears to be running. Nothing to do." >&2
              exit 0
            fi
            echo "${name}: stopping stack on socket ${socket}..." >&2
            if ! process-compose down -u ${socket}; then
              echo "${name}: 'process-compose down' failed against ${socket}." >&2
              echo "${name}: the socket file may be stale (server already dead) -- check for a leftover" >&2
              echo "${name}: file at ${socket} and remove it manually if no process is actually running." >&2
              exit 1
            fi
          '';
        }}/bin/${name}";
    in
    {
      process-compose."dev" = {
        imports = [ inputs.services-flake.processComposeModules.default ]; # per-stack import, see flake.nix note
        services.postgres."postgres-dev" = {
          enable = true;
          package = pkgs.postgresql_16;
          port = 5432;
          dataDir = "./.direnv/postgres-data-dev";
          initialScript.before = "CREATE USER cashclever WITH PASSWORD 'cashclever' SUPERUSER;";
          initialDatabases = [ { name = "cashclever"; } ];
        };
        cli.options.unix-socket = devSocket; # fixed socket enables standalone start/attach
      };

      process-compose."test" = {
        imports = [ inputs.services-flake.processComposeModules.default ];
        services.postgres."postgres-test" = {
          enable = true;
          package = pkgs.postgresql_16;
          port = 55432;
          dataDir = "./.direnv/postgres-data-test";
          initialScript.before = "CREATE USER cashclever WITH PASSWORD 'cashclever' SUPERUSER;";
          initialDatabases = [ { name = "cashclever"; } ];
        };
        cli.options.unix-socket = testSocket;

        settings.processes.pytest = {
          # config.packages.backend is deliberately the PROD-only venv (workspace.deps.default,
          # no pytest) -- config.packages.backend-dev (added in nix/backend.nix) is the dev venv
          # (workspace.deps.all) that actually has pytest installed.
          #
          # Regenerates app/generated_models.py from openapi.yaml (nix/backend.nix's
          # apps.generate-openapi-models, reused here rather than duplicating the
          # datamodel-codegen invocation) before every pytest run. app/generated_models.py is
          # gitignored, not committed, so this regenerate-then-test sequence IS the drift check
          # between openapi.yaml and what the routers actually import.
          command = "${config.apps.generate-openapi-models.program} && ${config.packages.backend-dev}/bin/pytest";
          working_dir = "backend";
          environment = {
            TEST_DATABASE_URL = "postgresql+psycopg://cashclever:cashclever@localhost:55432/cashclever";
          };
          depends_on."postgres-test".condition = "process_healthy";
        };
      };

      apps.dev-up.program = mkPostgresUp {
        name = "dev-up";
        downName = "dev-down";
        socket = devSocket;
        settingsFile = config.process-compose."dev".outputs.settingsFile;
        processes = [ "postgres-dev-init" "postgres-dev" ];
      };
      apps.dev-down.program = mkPostgresDown { name = "dev-down"; socket = devSocket; };

      apps.postgres-test-up.program = mkPostgresUp {
        name = "postgres-test-up";
        downName = "postgres-test-down";
        socket = testSocket;
        settingsFile = config.process-compose."test".outputs.settingsFile;
        processes = [ "postgres-test-init" "postgres-test" ];
      };
      apps.postgres-test-down.program = mkPostgresDown { name = "postgres-test-down"; socket = testSocket; };

      # `process-compose run` does NOT attach to an already-running server on the same
      # socket -- it always tries to become the server and hard-fails ("FTL unix socket ...
      # already in use") if one is already listening. The two cases genuinely need
      # different code paths:
      #   - no live server on the socket -> `process-compose run pytest -u <socket>` spawns
      #     one, runs pytest in the foreground with stdio + exit code propagated, tears down.
      #     Also correctly handles a *stale* socket file left behind by a crashed server --
      #     `run` treats a dead socket the same as no socket at all.
      #   - a live server already on the socket (e.g. from `nix run .#postgres-test-up`) ->
      #     attach via the CLIENT command `process-compose process start pytest -u <socket>`,
      #     which returns immediately ("started ok", NOT pytest's real exit code) -- so this
      #     branch has to poll `process list --output json` for pytest's `status`/`exit_code`
      #     fields until it reports "Completed".
      apps.test.program =
        "${pkgs.writeShellApplication {
          name = "test";
          runtimeInputs = [ processCompose pkgs.jq pkgs.git ];
          text = ''
            ${cdRepoRoot "test"}
            SOCK="${testSocket}"
            # Only needed by the `run` (server-starting) branch below -- the client-only calls
            # (`process list`, `process start`) just talk to an already-running server over the
            # socket and don't need the config.
            export PC_CONFIG_FILES="${config.process-compose."test".outputs.settingsFile}"

            # Poll budget for the attach-and-poll branch below: `process start` is a client call
            # that returns immediately, not pytest's real exit code, so completion can only be
            # observed by polling. 600 attempts * 0.5s = 5 minutes -- generous for this suite, but
            # bounded so a wedged pytest run fails loudly instead of hanging forever.
            poll_interval=0.5
            poll_max_attempts=600

            echo "test: checking for an existing process-compose server on $SOCK..." >&2
            if [ -S "$SOCK" ] && process-compose process list -u "$SOCK" >/dev/null 2>&1; then
              echo "test: found a live server on $SOCK (likely started via 'nix run .#postgres-test-up')." >&2
              echo "test: attaching -- starting pytest via 'process-compose process start' (client call, no stdio streaming)." >&2
              if ! process-compose process start pytest -u "$SOCK"; then
                echo "test: 'process-compose process start pytest' failed against $SOCK." >&2
                echo "test: the server may be unhealthy, or the 'pytest' process isn't defined in this stack's config." >&2
                exit 1
              fi

              echo "test: polling for pytest to reach status 'Completed' (up to $poll_max_attempts x ''${poll_interval}s)..." >&2
              status=""
              attempt=0
              while [ "$attempt" -lt "$poll_max_attempts" ]; do
                raw="$(process-compose process list -u "$SOCK" --output json 2>/dev/null || true)"
                status="$(printf '%s' "$raw" | jq -r '.[] | select(.name=="pytest") | .status' 2>/dev/null || true)"
                if [ -n "$status" ] && [ "$status" != "null" ] && [ "$status" = "Completed" ]; then
                  break
                fi
                attempt=$((attempt + 1))
                sleep "$poll_interval"
              done

              if [ "$status" != "Completed" ]; then
                echo "test: pytest did not reach 'Completed' on $SOCK after $poll_max_attempts polls (~5 minutes)." >&2
                echo "test: last observed status: [''${status:-<empty/unreadable>}]" >&2
                echo "test: inspect manually with: process-compose process list -u $SOCK --output json" >&2
                exit 1
              fi

              raw="$(process-compose process list -u "$SOCK" --output json 2>/dev/null || true)"
              exit_code="$(printf '%s' "$raw" | jq -r '.[] | select(.name=="pytest") | .exit_code' 2>/dev/null || true)"
              if [ -z "$exit_code" ] || [ "$exit_code" = "null" ]; then
                echo "test: pytest reported status 'Completed' but process-compose returned no readable exit_code." >&2
                echo "test: treating this as a failure rather than silently exiting 0 -- raw response was:" >&2
                echo "$raw" >&2
                exit 1
              fi

              echo "test: pytest completed (attached run) with exit_code=$exit_code." >&2
              exit "$exit_code"
            else
              echo "test: no live server found on $SOCK (either nothing started, or a stale socket file was left by a crashed server)." >&2
              echo "test: spawning a fresh ephemeral stack via 'process-compose run' -- exit code will be pytest's real exit code." >&2
              mkdir -p "$(dirname "$SOCK")"
              exec process-compose run pytest -u "$SOCK"
            fi
          '';
        }}/bin/test";
    };
}
