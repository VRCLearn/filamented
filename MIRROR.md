# VRCLearn VPM Mirror

This repository mirrors [s-ilent/Filamented](https://gitlab.com/s-ilent/filamented) and adds only the automation required to distribute it as a VPM repository.

## Synchronization policy

- `.github/workflows/sync-upstream.yml` checks the upstream `master` branch once per hour and prepares new commits on a temporary branch.
- A candidate must pass the mirror unit tests and VPM package build before the default branch is fast-forwarded.
- Upstream project files are not edited by the synchronization workflow.
- If upstream changes a mirror automation path, synchronization stops for manual review instead of executing or discarding the change.
- If the repository has no commits for 45 days, the scheduled workflow updates `.github/keepalive` so GitHub does not disable scheduling for inactivity.
- Failed or timed-out synchronization, release, and listing workflows create or update a GitHub Issue. Repeated failures for the same upstream state are reported once, and the issue closes automatically after recovery.

## Release policy

- The version in the upstream `package.json` is the VPM package version.
- A version is published once under the plain `<version>` tag from `package.json` and is never silently replaced.
- If upstream changes without bumping `package.json`, the source mirror still updates, but the existing VPM release remains immutable and the workflow emits a warning.
- The synchronization workflow calls the reusable release workflow with the exact validated mirror revision. Manual release runs remain available and may select an explicit revision.
- The release job excludes mirror-only files and supplements the staged `package.json` with the VPM URL, original author metadata, and SPDX license identifier.
- Each Release follows the official VRChat package template and attaches the VPM ZIP, UnityPackage, and staged `package.json`; the listing website uses the pinned official template.

The VPM listing is published at <https://vrclearn.github.io/filamented/index.json>.

Filamented remains licensed and attributed as described in the upstream `LICENSE.md` and `README.md`. VRCLearn is not the original author of Filamented.
