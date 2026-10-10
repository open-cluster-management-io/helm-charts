#!/usr/bin/env bash
# Copyright Contributors to the Open Cluster Management project
#
# Saves cluster state after a failed run: test/upgrade-downgrade/collect-debug.sh <output dir>
set -uo pipefail
source "$(dirname "$0")/lib.sh"
trap - EXIT

out=${1:?usage: collect.sh <output dir>}
mkdir -p "$out"

helm list -A > "$out/helm-releases.txt" 2>&1
kubectl get clustermanager,klusterlet,managedcluster -o yaml > "$out/ocm-resources.yaml" 2>&1
kubectl get manifestwork -A -o yaml > "$out/manifestworks.yaml" 2>&1
kubectl get csr > "$out/csr.txt" 2>&1
kubectl get crd -o custom-columns='NAME:.metadata.name,OPERATOR-VERSION:.metadata.annotations.operator\.open-cluster-management\.io/version' \
  > "$out/crd-versions.txt" 2>&1
kubectl get events -A --sort-by=.lastTimestamp > "$out/events.txt" 2>&1
deployment_images > "$out/deployment-images.txt"

for ns in "${NAMESPACES[@]}"; do
  kubectl -n "$ns" get all -o wide > "$out/$ns.txt" 2>&1
  kubectl -n "$ns" describe pods > "$out/$ns-pods-describe.txt" 2>&1
  for pod in $(kubectl -n "$ns" get pods -o name 2>/dev/null); do
    kubectl -n "$ns" logs "$pod" --all-containers --prefix > "$out/$ns-${pod#pod/}.log" 2>&1
    kubectl -n "$ns" logs "$pod" --all-containers --prefix --previous > "$out/$ns-${pod#pod/}.previous.log" 2>/dev/null \
      || rm -f "$out/$ns-${pod#pod/}.previous.log"
  done
done
echo "saved to $out"
