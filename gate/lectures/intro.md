# Release gate fixture

This site is the fixture of the release gate for
[QuantEcon/actions](https://github.com/QuantEcon/actions). It is not a lecture
series.

Before a release of the actions reaches the lecture sites, the gate builds these
pages with the release's actions, deploys them as previews and publishes them
here. A release moves on only if every step passes. The workflow is
[`gate.yml`](https://github.com/QuantEcon/test-actions-lecture-intro/blob/main/.github/workflows/gate.yml),
and the fixture's rules are in its
[README](https://github.com/QuantEcon/test-actions-lecture-intro/blob/main/gate/README.md).

Each page is here for a way the build has broken before:

- {doc}`figures`: a matplotlib figure and display mathematics, in every format;
- {doc}`plotly`: a plotly figure exported to an image through kaleido;
- {doc}`data`: a data file kept beside the pages, read and offered for download.

```{tableofcontents}
```
