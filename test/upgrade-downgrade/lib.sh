# Copyright Contributors to the Open Cluster Management project
# Helpers shared by the upgrade and downgrade test flows. Sourced by helm.sh and clusteradm.sh.

CLUSTER_NAME=${CLUSTER_NAME:-ocm-upgrade}
KIND_NODE_IMAGE=${KIND_NODE_IMAGE:-kindest/node:v1.29.2}
REGISTRY=quay.io/open-cluster-management
IMAGES=(registration-operator registration work placement addon-manager)
MANAGED_CLUSTER=cluster1
NAMESPACES=(open-cluster-management open-cluster-management-hub open-cluster-management-agent)
START=$(date +%s)
CURRENT_STEP=""
CURRENT_START=$START

# Results for the run summary (summary.sh): RESULT_DIR/steps.tsv has "<step> <passed|failed> <seconds>",
# RESULT_DIR/images.tsv has "<image> <digest> <reported version>". Nothing is written when RESULT_DIR is unset.
RESULT_DIR=${RESULT_DIR:-}
if [ -n "$RESULT_DIR" ]; then
  mkdir -p "$RESULT_DIR"
  : > "$RESULT_DIR/steps.tsv"
  : > "$RESULT_DIR/images.tsv"
fi
trap 'finish $?' EXIT

result() { # result <passed|failed>: record the current step
  [ -n "$RESULT_DIR" ] && [ -n "$CURRENT_STEP" ] || return 0
  printf '%s\t%s\t%s\n' "$CURRENT_STEP" "$1" $(( $(date +%s) - CURRENT_START )) >> "$RESULT_DIR/steps.tsv"
}

finish() {
  if [ "$1" -eq 0 ]; then result passed; else result failed; fi
  echo; echo "=== $([ "$1" -eq 0 ] && echo passed || echo failed) (t+$(( $(date +%s) - START ))s)"
}

# step <setup|install|upgrade|downgrade> <description>
step() {
  result passed
  CURRENT_STEP=$1
  CURRENT_START=$(date +%s)
  echo; echo "=== $2 (t+$(( CURRENT_START - START ))s)"
}

# wait_for <description> <expected output> <command...>
# Runs the command every 5s until it prints the expected output. Gives up after 5 minutes.
wait_for() {
  local desc=$1 want=$2 got=""
  shift 2
  for _ in $(seq 60); do
    got=$("$@" 2>/dev/null || true)
    if [ "$got" = "$want" ]; then echo "ok: $desc"; return 0; fi
    sleep 5
  done
  echo "FAIL: $desc: want '$want', got '$got'" >&2
  return 1
}

create_cluster() {
  kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
  kind create cluster --name "$CLUSTER_NAME" --image "$KIND_NODE_IMAGE" --wait 300s
}

# pull_images <tag>...: pull every OCM image for each tag into the kind node up front. Prints the
# digest and the version the operator binary reports, which is stamped at build time. The operator
# Deployments use imagePullPolicy IfNotPresent and start from this cache. The Deployments the
# operator creates set no pull policy, so :latest pods pull again (Always) and can get a newer
# digest if latest is pushed during the run.
pull_images() {
  local node=$CLUSTER_NAME-control-plane tag img ref
  for tag in "$@"; do
    for img in "${IMAGES[@]}"; do
      docker exec "$node" crictl pull "$REGISTRY/$img:$tag" >/dev/null
    done
    ref=$REGISTRY/registration-operator:$tag
    digest=$(docker exec "$node" crictl inspecti -o go-template --template '{{index .status.repoDigests 0}}' "$ref" | cut -d@ -f2)
    version=$(docker run --rm --pull always --entrypoint /registration-operator "$ref" --version 2>&1 | tail -1 | awk '{print $NF}')
    echo "$ref $digest reports $version"
    [ -z "$RESULT_DIR" ] || printf '%s\t%s\t%s\n' "${ref##*/}" "$digest" "$version" >> "$RESULT_DIR/images.tsv"
  done
}

# One line per OCM Deployment: "<namespace>/<name> <image> [<image>...]".
deployment_images() {
  local ns
  for ns in "${NAMESPACES[@]}"; do
    kubectl -n "$ns" get deploy -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{range .spec.template.spec.containers[*]}{" "}{.image}{end}{"\n"}{end}' 2>/dev/null
  done
}

# images_at <tag>: prints "all" when every OCM Deployment runs images with this tag.
images_at() {
  deployment_images | awk -v t=":$1" '
    { n++; for (i = 2; i <= NF; i++) if (substr($i, length($i) - length(t) + 1) != t) bad++ }
    END { if (n > 0 && bad == 0) print "all"; else print n " deployments, " bad + 0 " images not at tag" }'
}

wait_rollouts() {
  local ns d
  for ns in "${NAMESPACES[@]}"; do
    for d in $(kubectl -n "$ns" get deploy -o name 2>/dev/null); do
      kubectl -n "$ns" rollout status "$d" --timeout=300s >/dev/null
    done
  done
  echo "ok: rollouts done"
}

condition() { # condition <type> <kubectl get args...>
  local type=$1
  shift
  kubectl get "$@" -o jsonpath="{.status.conditions[?(@.type==\"$type\")].status}"
}

# wait_ready <tag>: the operators rolled every OCM Deployment to <tag> and the hub, the klusterlet
# and the managed cluster report healthy.
wait_ready() {
  wait_for "all Deployments on :$1" all images_at "$1"
  wait_rollouts
  wait_for "ClusterManager Applied" True condition Applied clustermanager/cluster-manager
  wait_for "Klusterlet Applied" True condition Applied klusterlet/klusterlet
  wait_for "ManagedCluster Available" True condition ManagedClusterConditionAvailable "managedcluster/$MANAGED_CLUSTER"
}

work_manifest() { # work_manifest <value>
  cat <<EOF
apiVersion: work.open-cluster-management.io/v1
kind: ManifestWork
metadata:
  name: upgrade-test
  namespace: $MANAGED_CLUSTER
spec:
  workload:
    manifests:
    - apiVersion: v1
      kind: ConfigMap
      metadata:
        name: upgrade-test
        namespace: default
      data:
        step: $1
EOF
}

# apply_work <value>: create or update a ManifestWork that writes <value> into a ConfigMap on the
# managed cluster, then wait until the ConfigMap has it and Applied is True for this generation.
# Right after the hub rolls out, the ManifestWork webhook can be unreachable for a few seconds
# ("failed calling webhook ... context deadline exceeded", 1 of 108 soak jobs), so the apply is
# retried and every failed attempt is logged.
apply_work() {
  local i err
  for i in $(seq 60); do
    if err=$(work_manifest "$1" | kubectl apply -f - 2>&1 >/dev/null); then
      [ "$i" -eq 1 ] || echo "ok: ManifestWork apply succeeded on try $i"
      wait_for "ManifestWork applied ($1)" "$1 True" work_state
      return
    fi
    echo "retry: ManifestWork apply failed: $err"
    sleep 5
  done
  echo "FAIL: ManifestWork apply ($1) did not succeed in 5 minutes" >&2
  return 1
}

work_state() { # "<ConfigMap value> <Applied status for the current generation>"
  local gen applied observed value
  gen=$(kubectl -n "$MANAGED_CLUSTER" get manifestwork upgrade-test -o jsonpath='{.metadata.generation}')
  applied=$(condition Applied -n "$MANAGED_CLUSTER" manifestwork/upgrade-test)
  observed=$(kubectl -n "$MANAGED_CLUSTER" get manifestwork upgrade-test \
    -o jsonpath='{.status.conditions[?(@.type=="Applied")].observedGeneration}')
  value=$(kubectl -n default get configmap upgrade-test -o jsonpath='{.data.step}')
  [ "$observed" = "$gen" ] || applied="stale(observed $observed, generation $gen)"
  echo "$value $applied"
}

report() {
  echo "-- Deployments"
  deployment_images | sort
  echo "-- CRD version annotations (operator.open-cluster-management.io/version)"
  kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.operator\.open-cluster-management\.io/version}{"\n"}{end}' \
    | grep open-cluster-management | awk -F'\t' '{print $2}' | sort | uniq -c
}
