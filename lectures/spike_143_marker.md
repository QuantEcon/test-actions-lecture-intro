# Spike 143 marker (not a lecture)

THROWAWAY file on branch `spike/143-local-uses` (QuantEcon/actions#143); never merge.

It is not in `_toc.yml`, so `only_build_toc_files: true` keeps it out of every build.
It exists so the spike's draft pull request adds exactly one lecture-shaped file:
the preview actions' change detection (`$GITHUB_ACTION_PATH/../scripts/detect-changed-lectures.sh`)
must report `lectures/spike_143_marker.md` (anything else it lists comes from
lecture commits that reached main after the branch was cut).
