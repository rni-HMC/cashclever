# cashclever

Empty starter repo derived from fairweek's infrastructure — see `README.md` for what's
carried over. No product logic yet; this is the monorepo skeleton to build the next
thing on top of.

## Branch / Merge Workflow

Follows the samsaria/fairweek pattern, not the `~/projects` workspace default (which
stops at push + hands the user a compare URL). Self-merge here:

1. Worktree per feature/phase: `git worktree add ../cashclever-<short-name> -b user/rni/feat-<short-name> main`
2. Work and commit on the branch in the worktree.
3. Verify (`nix run .#test`, `nix flake check`) before merging.
4. Squash merge from the main worktree (`~/projects/cashclever`, checked out on `main`):
   ```bash
   cd ~/projects/cashclever
   git merge --squash user/rni/feat-<short-name>
   git commit -m "..."
   git push origin main
   ```
5. **Do not remove the worktree or delete the branch** after merging — leave it until
   the user confirms.
6. Close beads only after the push succeeds.

## Nix Build Caveat: `nix build .#backend` Is Not Proof the App Code Runs

`backend/pyproject.toml` has a real `[build-system]` table (`setuptools`), so `cashclever`
is a genuine (non-virtual) uv project — `nix build .#backend` installs the `app` package
into the venv for real, `import app.main` works with zero `PYTHONPATH` tricks. That is
still not proof the application code is *correct*: a setuptools wheel build packages
`backend/app/` (copies files, reads metadata), it does not execute or import a single
line of it. **`nix run .#test` is the only thing that actually executes the test suite
against real app code.**

## Docs

`docs/SPEC.md` is the anchor for whatever gets built here. Each spec effort gets its own
`docs/<YYYY-MM-DD-HH-MM-SS>/` directory containing bare-named `SPEC.md`, `TASKS.md`,
`HANDOFF.md`, `VERIFICATION.md` as applicable — the directory is the namespace, no
`PHASE<N>` suffix needed. `docs/INDEX.md` lists every spec directory with a one-line
description.
