#!/usr/bin/env bash
# Copyright Contributors to the Open Cluster Management project
#
# Prints one Markdown table for all jobs of a run, from the result-<flow>-<mode> directories that
# the jobs upload (see RESULT_DIR in lib.sh).
#
#   test/upgrade-downgrade/summary.sh <dir with result-* directories> <release>
set -uo pipefail

dir=${1:?usage: summary.sh <results dir> <release>}
release=${2:?usage: summary.sh <results dir> <release>}

cell() { # cell <steps.tsv> <step>: "✅ 62s", "❌ 30s" or "-" when the step did not run
  awk -F'\t' -v s="$2" '$1 == s { printf "%s %ss", ($2 == "passed" ? "✅" : "❌"), $3; found = 1 }
    END { if (!found) printf "-" }' "$1"
}

echo "### Upgrade and downgrade: $release → main → $release"
echo
echo "| Flow | Mode | Install $release | Upgrade to main | Downgrade to $release | Result |"
echo "|---|---|---|---|---|---|"
for result in "$dir"/result-*; do
  [ -d "$result" ] || continue
  name=${result##*/result-}
  flow=${name%%-*}
  mode=${name#*-}
  steps=$result/steps.tsv
  if [ ! -s "$steps" ]; then
    echo "| $flow | $mode | - | - | - | ❌ no result, see the job log |"
    continue
  fi
  if grep -q $'\tfailed\t' "$steps" || ! grep -q $'^downgrade\tpassed' "$steps"; then
    verdict="❌ failed"
  else
    verdict="✅ passed"
  fi
  echo "| $flow | $mode | $(cell "$steps" install) | $(cell "$steps" upgrade) | $(cell "$steps" downgrade) | $verdict |"
done

images=$(find "$dir" -name images.tsv -size +0 | head -1)
if [ -n "$images" ]; then
  echo
  echo "| Operator image | Digest | Reported version |"
  echo "|---|---|---|"
  awk -F'\t' '{ printf "| `%s` | `%s` | `%s` |\n", $1, substr($2, 1, 19), $3 }' "$images"
fi
