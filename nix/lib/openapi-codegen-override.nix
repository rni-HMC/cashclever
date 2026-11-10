# nix/lib/openapi-codegen-override.nix
#
# Bakes backend/openapi.yaml -> app/generated_models.py into the `cashclever` package's own
# Nix build (postPatch), so every consumer (packages.backend, backend-dev, backend-image)
# gets a real, importable app.generated_models with zero reliance on local on-disk state.
# This is necessary, not cosmetic: Nix flakes only see git-tracked (or at least staged)
# content for their own local source -- a gitignored file present on disk (e.g. from
# `nix run .#generate-openapi-models`) is invisible to any real `nix build`. `nix run
# .#test`'s pytest process is unaffected by any of this: it execs directly against the
# live on-disk working tree (see nix/postgres.nix), never through Nix's derivation graph.
#
# Kept in its own file rather than folded into backend-overrides.nix, which is
# explicitly scoped to psycopg[binary] fixups only (see that file's own comment).
#
# Acyclic by construction: `codegenToolEnv` below is built from ONLY
# datamodel-code-generator + its own transitive deps (an explicit deps selection, NOT
# workspace.deps.all) -- it does not pull in the `cashclever` package itself. backendDevEnv
# (workspace.deps.all) DOES include cashclever, so using it here instead would create a
# real cashclever -> backendDevEnv -> cashclever cycle.
{ pkgs }:
final: prev: {
  cashclever = prev.cashclever.overrideAttrs (old:
    let
      codegenToolEnv = final.mkVirtualEnv "cashclever-openapi-codegen-tool" {
        datamodel-code-generator = [ ];
      };
      openapiModels = pkgs.runCommand "cashclever-openapi-generated-models" {
        nativeBuildInputs = [ codegenToolEnv ];
      } ''
        mkdir -p "$out"
        # HOME must be writable: datamodel-codegen's black/isort formatters want a
        # cache dir, and Nix's build sandbox defaults HOME to a nonexistent path.
        export HOME="$TMPDIR"
        datamodel-codegen \
          --input ${../../backend/openapi.yaml} --input-file-type openapi \
          --output "$out/generated_models.py" \
          --output-model-type pydantic_v2.BaseModel \
          --target-python-version 3.11 \
          --use-standard-collections --use-union-operator \
          --enum-field-as-literal one
      '';
    in {
      postPatch = (old.postPatch or "") + ''
        cp ${openapiModels}/generated_models.py app/generated_models.py
      '';
    });
}
