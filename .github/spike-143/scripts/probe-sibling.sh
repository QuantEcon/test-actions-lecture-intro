#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike. The file the committed probe
# (.github/spike-143/probe) reaches as ../scripts/probe-sibling.sh, mirroring
# how preview-* reach ../scripts/detect-changed-lectures.sh. The probe only
# parses it (bash -n); it is never executed.
echo "spike-143 probe sibling reached: $0"
