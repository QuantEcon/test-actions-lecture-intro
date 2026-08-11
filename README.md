# ⚠️ TEST REPOSITORY

# A First Course in Quantitative Economics with Python

> **🧪 This is a test repository for QuantEcon Actions development**  
> **Do not use for production purposes**  
> Production repository: [lecture-python-intro](https://github.com/QuantEcon/lecture-python-intro)

An Undergraduate Lecture Series for the Foundations of Computational Economics

## Purpose

This repository is the **experiment and integration sandbox** for [QuantEcon/actions](https://github.com/QuantEcon/actions), and its post-release canary — stage 2 of [actions#100](https://github.com/QuantEcon/actions/issues/100). It is a clone of `lecture-python-intro` wired to the composite actions at the floating `@v0` tag, so that a real lecture-shaped build exercises the parts of the chain that the in-repo PR harness structurally cannot reach.

The question it answers is **"does this work against a real-ish lecture repo?"** — try a new action, a new version, a new workflow shape, and find out end to end. Its history is exactly that: PR-scoped build caching (#36), PDF and notebook builds in CI preview (#35), the `@v0` migration (#26).

### This repo is not the release gate

It cannot be, and that is deliberate rather than a gap to close here. A gate has to mean *red stops the release*, and three properties of this repo make red ambiguous — all three of which are the right properties for a sandbox:

- it runs `ghcr.io/quantecon/quantecon-build:latest`, so the environment moves underneath it;
- Dependabot is enabled and its PRs change build behaviour;
- it pins `@v0`, which is the tag a release *moves* — so it always exercises the previous release, never the candidate.

The first two are how upstream breakage gets discovered early, which is a sandbox's job and the opposite of a gate's. Release gating lives in a separate frozen fixture, `test-actions-release` — see [actions#136](https://github.com/QuantEcon/actions/issues/136) and [actions#135](https://github.com/QuantEcon/actions/issues/135).

So: **experiment here; gate there.** If you are about to add something to this repo to make a release safer, it probably belongs in `test-actions-release` instead.

It is the only place `publish-gh-pages` and `preview-netlify` are exercised at all. Neither is testable inside the actions repo: a composite action is all-or-nothing, so `uses: ./publish-gh-pages` dies at `configure-pages` before reaching any of its own logic, and testing the previews there would need live deploy credentials on a `pull_request` workflow.

**The lecture set is deliberately small.** `lectures/_toc.yml` carries five self-contained lectures rather than the full book, chosen mechanically: no build-time network access, no heavy or optional imports, no local `{doc}` cross-references, no citations. The other lectures stay on disk but are not built (`only_build_toc_files: true`).

That trim is the point, not a shortcut. Carrying the full book meant this repo went red in April 2026 because a cell in `inequality.md` raised — content drift, nothing to do with the actions — and it stayed red and unwatched for months. A canary whose failures are usually *not* about the thing it tests is a canary nobody reads. With the trimmed set, a red run means an action regression.

Because it pins `@v0` rather than a fixed release, this repo sees each release as consumers see it — which also means it can only find a regression *after* the floating tag moves. Pre-release coverage lives in the actions repo's own PR harness.

## Jupyter notebooks

Jupyter notebook versions of each lecture are available for download
via the website.

## Contributions

To comment on the lectures please add to or open an issue in the issue tracker (see above).
We welcome pull requests!  

Please read the [QuantEcon style guide](https://manual.quantecon.org/intro.html) first, so that you can match our style.
