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

# Plotly

A plotly figure becomes a static image through kaleido, which drives a headless
Chromium. That export failed in the images once, when kaleido 1.0 stopped
bundling its own Chromium (QuantEcon/actions#85). This page exports a figure
and shows the image, so the page, the notebook and the PDF all carry it.

```{code-cell} ipython3
import numpy as np
import plotly.graph_objects as go
from IPython.display import Image

x = np.linspace(0, 2 * np.pi, 200)
fig = go.Figure()
fig.add_trace(go.Scatter(x=x, y=np.sin(x), name="sin"))
fig.add_trace(go.Scatter(x=x, y=np.cos(x), name="cos"))
fig.update_layout(title="Exported by kaleido", width=640, height=400)

png = fig.to_image(format="png")
assert png.startswith(b"\x89PNG\r\n\x1a\n"), "kaleido did not return a PNG"
Image(png)
```

```{code-cell} ipython3
# gate.yml looks for this line in the built page and the PDF (see figures).
print("gate executed plotly", 6 * 7)
```
