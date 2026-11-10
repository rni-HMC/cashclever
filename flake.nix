{
  description = "cashclever monorepo — backend (FastAPI), landing (TanStack Start). Empty starter, nix + spec-first OpenAPI + FastAPI codegen scaffolding derived from fairweek.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"; # verify current stable branch at implementation time — do not use nixpkgs-unstable
    flake-parts.url = "github:hercules-ci/flake-parts";

    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    uv2nix.inputs = { nixpkgs.follows = "nixpkgs"; pyproject-nix.follows = "pyproject-nix"; };
    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";

    # github:nix-community/bun2nix (v2: mkDerivation + fetchBunDeps) — NOT baileyluTCD/bun2nix
    # (v1, deprecated API, different org). Pinned per bun2nix's own template guidance (its
    # bun.nix schema has no stability guarantees between versions) — bump deliberately.
    bun2nix.url = "github:nix-community/bun2nix/2.1.1";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";

    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      imports = [
        inputs.process-compose-flake.flakeModule   # global — makes `perSystem.process-compose.<stack>` valid
        ./nix/backend.nix
        ./nix/postgres.nix
        ./nix/deploy.nix
        ./nix/landing.nix
      ];
      # NOTE: inputs.services-flake.flakeModule does NOT go here. services.postgres is a
      # per-process-compose-stack option, imported inside each stack block in nix/postgres.nix.
    };
}
