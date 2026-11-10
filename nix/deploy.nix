# nix/deploy.nix
#
# Docker/OCI image for the backend, built with pkgs.dockerTools.buildLayeredImage.
{ ... }:
{
  perSystem = { pkgs, lib, config, ... }: {
    packages = lib.optionalAttrs pkgs.stdenv.isLinux {
      backend-image =
        let
          backend = config.packages.backend; # prod closure only — no pytest/httpx

          entrypoint = pkgs.writeShellApplication {
            name = "entrypoint";
            runtimeInputs = [ backend ];
            text = ''
              cd /app

              echo "==> [entrypoint] running init_db.py (schema init)..." >&2
              if ! python scripts/init_db.py; then
                echo "==> [entrypoint] FATAL: init_db.py failed (see traceback above). Not starting the server." >&2
                exit 1
              fi
              echo "==> [entrypoint] init_db.py completed successfully." >&2

              echo "==> [entrypoint] starting uvicorn on port ''${PORT:-8000}..." >&2
              exec uvicorn app.main:app --host 0.0.0.0 --port "''${PORT:-8000}"
            '';
          };
        in pkgs.dockerTools.buildLayeredImage {
          name = "backend-image"; # not "render-image" — portable to ECS/k8s later
          contents = [ backend pkgs.cacert ]; # cacert: sslmode=require TLS trust
          extraCommands = ''
            # backend/scripts/ isn't part of the installed `app*` package (see
            # backend/pyproject.toml's [tool.setuptools.packages.find]), so init_db.py
            # has to be copied in explicitly -- unlike app/, which config.packages.backend
            # (already in `contents` above) installs into the venv's site-packages for real.
            mkdir -p app/scripts
            cp ${../backend/scripts/init_db.py} app/scripts/init_db.py
          '';
          config = {
            Entrypoint = [ "${entrypoint}/bin/entrypoint" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-certificates.crt"
              "PYTHONUNBUFFERED=1"
            ];
            Labels = {
              # TODO: replace with this cashclever's real GitHub org/repo once it has one.
              "org.opencontainers.image.source" = "https://github.com/<org>/cashclever";
            };
          };
        };
    };
  };
}
