# Updating the Lerd package

`package.nix` pins a specific Lerd release: the source revision plus three
Nix fixed-output hashes (`src.hash`, `npmDepsHash`, `vendorHash`) that all go
stale the moment the pinned version changes.

## Automatic: `.github/workflows/update-lerd.yml`

A scheduled GitHub Action checks the
[lerd-env/lerd releases API](https://api.github.com/repos/lerd-env/lerd/releases/latest)
once a day. When it finds a version newer than the one in `package.nix`, it
runs `update-package.sh`, and if the build succeeds, commits and pushes the
bump straight to `main` - no PR, no manual step.

Requirements for this to work:

- Repo setting **Settings → Actions → General → Workflow permissions** must
  be set to "Read and write permissions" (needed for the workflow's `git
  push`).
- Branch protection on `main`, if any, must allow the `github-actions[bot]`
  actor to push directly (no required PR reviews on this branch).

You can also trigger it on demand from the Actions tab ("Run workflow") if
you don't want to wait for the next scheduled run. GitHub's own gate on
`workflow_dispatch` only requires *write* access, so the workflow adds an
explicit check that fails the run unless the triggering user's repo
permission is `admin` - repo write-access holders (e.g. the maintainers
team) can't manually kick it off, only admins.

If the Nix build fails during the update (e.g. a new Lerd release adds a Go
or npm dependency in a way the script can't reconcile automatically - see
below), the workflow run fails and nothing is committed. Check the failed
run's logs and fall back to the manual steps.

## Manual: `./update-package.sh <version>`

Run locally with the new version number (no leading `v`):

```
./update-package.sh 1.27.1
```

It will:

1. Bump `version` in `package.nix`.
2. Run `nix build`, read the "hash mismatch" error, and patch `src.hash`.
3. Rebuild - if `npmDepsHash` or `vendorHash` also changed (new/updated JS or
   Go dependencies), it patches those too from the next round of mismatch
   errors, repeating up to 5 times.
4. On success, print the resolved store path and run `lerd --version` to
   confirm the binary reports the expected version.

Nothing is committed - review `git diff package.nix` and commit yourself.

## Manual steps, by hand

If you'd rather not run the script (or it can't converge):

1. Edit `version` in `package.nix` to the new release tag, without the `v`
   prefix.
2. Set `src.hash` to `""` and run `nix build .#default`. It will fail with a
   `hash mismatch` error showing `got: sha256-...`; copy that value back into
   `src.hash`.
3. Run `nix build .#default` again. If `npmDepsHash` or `vendorHash` are
   also now wrong, you'll get the same kind of mismatch error for the
   `lerd-ui-*-npm-deps` or `lerd-*-go-modules` derivation - repeat the
   empty-string-then-copy-the-hash trick for whichever one(s) fail.
4. Once `nix build .#default` succeeds, sanity-check the binary:
   `./result/bin/lerd --version`.

### The vendored inlang plugin (rarely needs touching)

`messageFormatPlugin` vendors a pinned version of
`@inlang/plugin-message-format` from jsDelivr, because the UI build fetches
it over the network during `paraglide-js compile`, which the Nix sandbox
blocks. This is pinned independently of the Lerd version and only needs
updating if upstream bumps the `@inlang/plugin-message-format` major version
in `project.inlang/settings.json` (i.e. the `@4` in
`messageFormatPluginUrl` changes). If a Lerd update ever fails inside the UI
build step with a fetch error, check that file first - bump the URL's
version and refetch with `nix store prefetch-file <url>` (or the same
empty-hash trick) to get the new `hash`.
