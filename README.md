# ⚠️ TEST REPOSITORY

# A First Course in Quantitative Economics with Python

> **🧪 This is a test repository for QuantEcon Actions development**  
> **Do not use for production purposes**  
> Production repository: [lecture-python-intro](https://github.com/QuantEcon/lecture-python-intro)

An Undergraduate Lecture Series for the Foundations of Computational Economics

## Purpose

This repository is the **canary** for [QuantEcon/actions](https://github.com/QuantEcon/actions) — stage 2 of [actions#100](https://github.com/QuantEcon/actions/issues/100). It is a clone of `lecture-python-intro` wired to the composite actions at the floating `@v0` tag, so that a real lecture-shaped build exercises the parts of the chain that the in-repo PR harness structurally cannot reach.

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
