# The release gate's fixture

This folder is the book that the release gate builds: `.github/workflows/gate.yml`, which runs [QuantEcon/actions](https://github.com/QuantEcon/actions) at a candidate commit before `v0` moves to it ([actions#135](https://github.com/QuantEcon/actions/issues/135)). The fixture itself is [actions#136](https://github.com/QuantEcon/actions/issues/136).

The rest of this repository is the actions' sandbox. Its lectures, its workflows and its `:latest` image move, and Dependabot proposes updates to them, which is how upstream breakage is found early. The gate needs the opposite: a build in which nothing has moved since the last run but the candidate, so that a red gate means the candidate. This folder keeps it that way.

## The rules it keeps

- **Nothing is read from the network at build time.** No intersphinx, no remote redirects, no bibliography, no data from a URL. A URL is only ever a link.
- **Nothing here is updated by Dependabot.** Its `conda` updates read the root `environment.yml` only. `gate/environment.yml` is installed by nothing: it exists so that the gate's caches have a key prefix of their own (see the file).
- **The image is pinned by digest**, in `gate.yml`, and moved by hand (below).
- **Every page is here for a way the build has broken before**, not to look like a lecture:

| Page | What it exercises |
|---|---|
| `intro` | The root page, and the table of contents |
| `figures` | A matplotlib figure, which reaches the page, the notebook and the PDF; display mathematics with a labelled equation, under pdflatex |
| `plotly` | A plotly figure exported to PNG through kaleido and its Chromium, which broke in the images once ([actions#85](https://github.com/QuantEcon/actions/pull/85)) |
| `data` | A CSV kept in `_static/`, read with pandas and offered with `{download}` |

Each code page prints `gate executed <page> 42`, from an expression whose value is not written in the source, and the gate looks for that line in the built page and in the PDF's LaTeX. So a build that executed nothing cannot pass. The notebooks a site offers for download carry no outputs, so for them the gate checks that each holds its page's code.

The PDF is built with jupyter-book's default engine, pdflatex, as seven of the eight lecture sites build theirs. The container smoke test in QuantEcon/actions builds xelatex.

**Adding a page** is a change to the gate: give the way it has broken, keep to the rules above, and make it print its line.

## The staged failure

`gate.yml`'s `self-test: build-fails` appends a cell that raises to `figures.md` before the build, so the gate can be shown to go red. Nothing in this folder needs changing for it.

## Moving the image

The gate runs `ghcr.io/quantecon/quantecon-build` at the digest in `gate.yml`. Move it after a promotion to `:latest` that the lecture matrix in QuantEcon/actions has passed, at most once per release cycle, and never in the same change as a new candidate, so that only one thing changes at a time:

1. In QuantEcon/actions, a pull request adds the new digest to `.github/container-pins.txt`, which keeps it from being pruned.
2. Here, a pull request from a `gate/` branch changes the digest in `gate.yml`. Dispatch the gate on that branch with `candidate` set to the commit `v0` points at: the jobs up to the deploys must pass. The deploy jobs fail on a branch, as below.
3. Once that is merged, dispatch the gate on `main` with the same candidate, to show the deploys.
4. In QuantEcon/actions, a pull request removes the old digest from `.github/container-pins.txt`.

## Running the gate

On `main`, for a release candidate:

```bash
gh workflow run gate.yml --repo QuantEcon/test-actions-lecture-intro --ref main -f candidate=vX.Y.Z
gh run watch <run id> --repo QuantEcon/test-actions-lecture-intro --exit-status
```

On any other branch the two deploy jobs are refused by their environments, which allow `main` only, so a branch run is always red. The jobs before the deploys still show whether the build works.
