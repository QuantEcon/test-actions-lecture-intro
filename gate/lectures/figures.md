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

# Figures

A figure drawn by matplotlib reaches the page as an image, the notebook as an
output and the PDF as a graphic. This page draws one from seeded random draws,
so every build draws the same one.

```{code-cell} ipython3
import numpy as np
import matplotlib.pyplot as plt

rng = np.random.default_rng(1234)
walks = rng.standard_normal((250, 4)).cumsum(axis=0)

fig, ax = plt.subplots()
ax.plot(walks)
ax.set_xlabel("step")
ax.set_ylabel("position")
ax.set_title("Four seeded random walks")
plt.show()
```

The sum of a geometric series, for $0 < \beta < 1$, is

$$
\sum_{t=0}^{n-1} \beta^t = \frac{1 - \beta^n}{1 - \beta}
\quad \text{and} \quad
\sum_{t=0}^{\infty} \beta^t = \frac{1}{1 - \beta}.
$$ (geometric-sum)

Equation {eq}`geometric-sum` is checked numerically below.

```{code-cell} ipython3
beta, n = 0.9, 50
partial = sum(beta**t for t in range(n))
assert abs(partial - (1 - beta**n) / (1 - beta)) < 1e-12

# gate.yml looks for this line in the built page and in the PDF's LaTeX. It
# holds the value of the expression, never written out in this file, so it is
# there only if the page executed. Plain words, which LaTeX does not escape.
print("gate executed figures", 6 * 7)
```
