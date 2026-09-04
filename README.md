# dyna-kit-ci

Reusable GitHub Actions CI for DynaSpace **kit** repositories: build on top of a
published `dynaspace-os` release image, tangle the kit's Lepiter pages, run its
`<gtExample>`s, build a `.dynkit` and publish it as a GitHub release.

One source of truth: fix the pipeline here, re-tag `v1`, and every kit picks it
up on its next run.

## How a kit repo uses it

`.github/workflows/ci.yml` in the kit repo — identical in every kit, nothing to
fill in:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  ci:
    permissions:
      contents: write   # create releases (needed if the org defaults GITHUB_TOKEN to read-only)
    uses: blueplanelabs/dyna-kit-ci/.github/workflows/kit-ci.yml@v1
    secrets: inherit
```

## What the kit repo must provide

| File / method | Purpose |
|---|---|
| `.smalltalk.ston` | `#baseline`, `#testing`, `#preTesting : 'scripts/tangle-lepiter.st'`, `#postTesting : 'scripts/export-dynkit.st'`, `#loading` with `#registerInIceberg: true` loading **only the kit's own package(s)** — not `DynaSpaceOS` / `LepiterLiterate`, which the `dynaspace-os` image already provides |
| `VERSION` | e.g. `0.1.0` — drives the `vX.Y.Z` release tag and the `.dynkit` filename |
| `BaselineOf<X> class >> kit` | returns a fully built `DynOSKit` (metadata + live objects) |
| `BaselineOf<X> class >> loadLepiter` | registers `<repo>/lepiter` with the default logical database |

`scripts/tangle-lepiter.st` and `scripts/export-dynkit.st` are **not** committed
to the kit repo — this workflow copies them in from `scripts/` here before
`smalltalkci` runs. The kit's `.smalltalk.ston` just references those paths.

The kit baseline does **not** declare `DynaSpaceOS` or `LepiterLiterate` — the
`dynaspace-os` release image already carries both.

## Secrets

| Secret | Source | Needed for |
|---|---|---|
| `GITHUB_TOKEN` | automatic — always present in every run | creating the kit's releases (`gh release`) |
| `DYNA_DEPS_TOKEN` | repo (or org) secret, passed in via `secrets: inherit` | `Contents: Read` on `blueplanelabs/dynaspace-os`, to download its release image |

`GITHUB_TOKEN` is minted by GitHub Actions for every run — nobody creates or
stores it. Its write scope comes from the caller job's `permissions:` block
(`contents: write`); `secrets: inherit` is not what provides it.

`DYNA_DEPS_TOKEN` is a fine-grained PAT (a repo secret on each kit for now; an
org secret / GitHub App later). Pull requests **from a fork** do not receive it
and cannot run this workflow — the `dynaspace-os` image is required even for
PR-only validation. Kit repos are private within the org, so this does not apply
in practice.

## Inputs

| Input | Default | |
|---|---|---|
| `smalltalk-image` | `GToolkit64-release` | SmalltalkCI image alias (job name / `-s` flag only) |
| `dynaspace-os-release` | `latest` | `dynaspace-os` release tag to build on, or `latest` (newest `build-N`) |
| `gt-vm-version` | `v1.1.554` | GToolkit VM version; must match the VM that saved the `dynaspace-os` release image |
| `needs-opencv` | `false` | Install OpenCV 4.13 for kits whose examples call the camera-detection FFI (`LibOpenCV` / `DynIOArucoInputDetector` / `DynIOBlobInputDetector`) |
| `needs-mongo` | `false` | Start MongoDB (docker compose, from the `dynaspace-os` image) for kits whose examples use Voyage/Mongo stores |

### Kits that need extra services

Setting `needs-opencv` or `needs-mongo` in the caller `ci.yml` is the only case
where a kit's `ci.yml` is not identical to every other:

```yaml
jobs:
  ci:
    permissions:
      contents: write
    uses: blueplanelabs/dyna-kit-ci/.github/workflows/kit-ci.yml@v1
    with:
      needs-opencv: true   # kit examples use ArUco / blob detection
      needs-mongo: true    # kit examples use Voyage/Mongo stores
    secrets: inherit
```

- **OpenCV**: the `libWrapperOpenCVDetector` / `libOpenCVDetector` `.so` wrappers
  already ride in the `dynaspace-os` release image, so no extra token is needed —
  only OpenCV itself is installed (via conda, preinstalled on the runner) plus a
  `libopencv_viz` stub, and `LD_LIBRARY_PATH` is set for the test run.
- **Mongo**: the `docker/docker-compose.yml` is tangle-generated and ships in the
  `dynaspace-os` release image; `DynOSConfig` resolves `DYNASPACE_ENV` (unset →
  `dev`), which matches the credentials the compose file uses. The container is
  torn down (`down -v`) after the run.

## Pipeline

1. Checkout kit + this repo (pinned to the workflow version); stage shared `.st` scripts.
2. `setup-smalltalkCI`; patch `gtoolkit/run.sh` (`scripts/patch-smalltalkci.py`, Fixes 1/2/3 for `--headful` in CI).
3. Resolve the `dynaspace-os` release tag; download + unzip its image (fresh each run — `latest` moves too often to cache usefully).
4. Download + unzip the pinned GToolkit VM from `feenkcom/gtoolkit` (public, cached by version).
5. If `needs-opencv`: install OpenCV 4.13 + `libopencv_viz` stub, export `LD_LIBRARY_PATH`.
6. If `needs-mongo`: `docker compose up` MongoDB from the image's `docker/`.
7. Install Xvfb + `libxkbcommon-x11-0` (required by any `--interactive` GT run, not just camera kits — `winit` sets up XKB keyboard-state tracking when it opens the window); verify the `dynaspace-os` image boots.
8. `xvfb-run smalltalkci --headful --image <dynaspace-os image> --vm <pinned cli>` — `--image`/`--vm` make SmalltalkCI skip its own image download and use the `dynaspace-os` image. `#loading` loads only the kit's own package(s); `#preTesting` tangles Lepiter; `#testing` runs the examples; `#postTesting` builds and round-trips the `.dynkit`.
9. If `needs-mongo`: `docker compose down -v` (always).
10. On `push` to `main`: publish `build-<run_number>` (prerelease) with the `.dynkit` attached (a job re-run replaces the existing `build-N`).
11. On `push` that changes `VERSION`: also publish `v<VERSION>` (fails if that tag already exists — a published version is never overwritten).

Pull requests run steps 1–9 only (no release).
