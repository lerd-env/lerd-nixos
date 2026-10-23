# Updating the Lerd package

`package.nix` pins a specific Lerd release: the source revision plus three
Nix fixed-output hashes (`srcHash`, `npmDepsHash`, `vendorHash`) that all go
stale the moment the pinned version changes. Those four values are the default
arguments at the top of `package.nix` (`version ? "…"`, `srcHash ? "…"`, and
so on). `beta.nix` carries the same four names for the beta channel.

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

## Automatic beta: `.github/workflows/update-lerd-beta.yml`

A second workflow, half an hour later, maintains `beta.nix`. It looks at the
latest stable release and the prereleases in the newest 100 GitHub releases,
and picks the newer of the two by semver (a stable `1.37.1` outranks
`1.37.0-beta.3` and `1.37.1-beta.2`; `1.38.0-beta.1` outranks `1.37.1`). When
that version differs from the pin in `beta.nix`, it runs:

```
./update-package.sh <version> beta.nix lerd-beta
```

and, if the build succeeds, commits `beta.nix` to `main` and tags `v<version>`
when that tag does not already exist. A stable release that the beta channel
has caught up to keeps the tag the stable workflow already pushed.

It has the same permissions requirements and the same admin-only manual
trigger as the stable workflow. A failed beta build commits nothing and does
not block the stable update; the two workflows push different files. The beta
job rebases before pushing, so a stable bump that landed during the build is
replayed on top of rather than rejected.

`scripts/newest-lerd-version.py` is the comparison. `sort -V` is wrong here:
it orders `1.37.1-beta.2` after `1.37.1`.

## Manual: `./update-package.sh <version>`

Run locally with the new version number (no leading `v`):

```
./update-package.sh 1.27.1
./update-package.sh 1.38.0-beta.1 beta.nix
```

The second form updates the beta pin and builds `.#lerd-beta`. The first
updates the stable defaults and builds `.#default`.

It will:

1. Bump `version` in the pins file (`version ?` in `package.nix`, `version =`
   in `beta.nix`).
2. Run `nix build`, read the "hash mismatch" error, and patch `srcHash`.
3. Rebuild - if `npmDepsHash` or `vendorHash` also changed (new/updated JS or
   Go dependencies), it patches those too from the next round of mismatch
   errors, repeating up to 5 times.
4. On success, print the resolved store path and run `lerd --version` to
   confirm the binary reports the expected version.

Nothing is committed - review `git diff` for that pins file and commit yourself.

## Manual steps, by hand

If you'd rather not run the script (or it can't converge):

1. Edit the version in the pins file, without the `v` prefix: the `version ?`
   default in `package.nix`, or `version` in `beta.nix`.
2. Set `srcHash` to `""` and run `nix build .#default` (or `.#lerd-beta`). It
   will fail with a `hash mismatch` error showing `got: sha256-...`; copy that
   value back into `srcHash`.
3. Run the build again. If `npmDepsHash` or `vendorHash` are also now wrong,
   you'll get the same kind of mismatch error for the `lerd-ui-*-npm-deps` or
   `lerd-*-go-modules` derivation - repeat the empty-string-then-copy-the-hash
   trick for whichever one(s) fail.
4. Once the build succeeds, sanity-check the binary:
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
