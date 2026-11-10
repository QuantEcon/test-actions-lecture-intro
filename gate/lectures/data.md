---
jupytext:
  text_representation:
    extension: .md
    format_name: myst
    format_version: 0.13
    jupytext_version: 1.14.5
kernelspec:
  display_name: Python 3 (ipykernel)
  language: python
  name: python3
---

# Data

Lectures read data. This page reads a small file kept beside it, never a URL,
so the build reads nothing from the network, and the file is offered as a
download: {download}`gate-data.csv <_static/gate-data.csv>`.

```{code-cell} ipython3
import pandas as pd

df = pd.read_csv("_static/gate-data.csv")
df
```

```{code-cell} ipython3
# gate.yml looks for this line in the built page and the PDF (see figures).
# The values in the file sum to 42.
print("gate executed data", int(df["value"].sum()))
```
