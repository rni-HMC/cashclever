# nix/landing.nix
#
# bun2nix-based hermetic dependency fetch for landing/ (plain TanStack Start site).
# `nix run .#landing` starts the real Vite dev server using node_modules materialized
# entirely from bun2nix.fetchBunDeps against the committed landing/bun.lock -- not a
# live `bun install`. A production build is out of scope here: this wrapper's job is
# "one nix command, view at localhost", not a deployable artifact.
{ inputs, ... }:
{
  perSystem = { system, ... }:
    let
      bun2nix = inputs.bun2nix.packages.${system}.default;

      landingApp = bun2nix.writeBunApplication {
        pname = "cashclever-landing";
        version = "0.0.0"; # landing/package.json has no version field

        packageJson = ../landing/package.json;
        src = ../landing;

        bunDeps = bun2nix.fetchBunDeps {
          bunNix = ../landing/bun.nix;
        };

        # No compiled artifact: this app runs the real Vite dev server via startScript,
        # so the default writeBunApplication buildPhase (bare `bun build`, needs an
        # entrypoint we don't have) is skipped entirely.
        buildPhase = "true";

        # $PWD here is $out/share/cashclever-landing (set by writeBunApplication's
        # makeWrapper --chdir), a read-only Nix store path. Vite's config loader writes a
        # temp `vite.config.ts.timestamp-*.mjs` file next to vite.config.ts when starting
        # -- that write fails EACCES straight out of the store, so copy to a writable tmp
        # dir first (node_modules' package entries stay as symlinks into the store; only
        # the copy's own directory needs to be writable).
        startScript = ''
          workdir="$(mktemp -d)"
          cp -r . "$workdir"/
          chmod -R u+w "$workdir"
          cd "$workdir"
          exec bun run dev
        '';
      };
    in {
      packages.landing = landingApp;
      apps.landing.program = "${landingApp}/bin/cashclever-landing";
    };
}
