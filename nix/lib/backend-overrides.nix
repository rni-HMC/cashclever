{ pkgs }:
final: prev: {
  # Dormant safety net -- psycopg[binary] loads unmodified under uv2nix with
  # sourcePreference = "wheel": the manylinux psycopg-binary wheel vendors its own
  # libpq, and pyproject-nix's default wheel build already runs autoPatchelfHook
  # against it (verified against fairweek, the repo this scaffold is derived from).
  #
  # Uncomment (a) or (b) below ONLY if a future nixpkgs/psycopg version bump
  # reintroduces the problem:
  #
  # (a) psycopg-binary = prev.psycopg-binary.overrideAttrs (old: {
  #       nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.autoPatchelfHook ];
  #       buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.postgresql.lib ];
  #     });
  #
  # (b) psycopg = prev.psycopg.overrideAttrs (old: {
  #       buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.postgresql.dev ];
  #     });
}
