#!/bin/bash
set -euo pipefail

fixture="$(mktemp -d /tmp/macterm-container.XXXXXXXX)"
archive="$fixture/nerdctl.tar.gz"
curl -fsSL --retry 3   https://github.com/containerd/nerdctl/releases/download/v2.4.2/nerdctl-2.4.2-linux-amd64.tar.gz   -o "$archive"
printf '%s  %s\n' 41a66995888043c0ba05f8061574eaba1b9e06b9b21c2a238215179df2728d3f "$archive" | sha256sum -c -
tar -xzf "$archive" -C "$fixture" nerdctl
sudo systemctl start containerd
sudo "$fixture/nerdctl" --namespace macterm-ci info
sudo "$fixture/nerdctl" --namespace macterm-ci ps -a
sudo "$fixture/nerdctl" --namespace macterm-ci images
sudo "$fixture/nerdctl" --namespace macterm-ci volume create ci-volume
sudo "$fixture/nerdctl" --namespace macterm-ci volume rm ci-volume

export KUBECONFIG="$fixture/kubeconfig"
kind create cluster --name macterm --wait 120s --kubeconfig "$KUBECONFIG"
trap 'kind delete cluster --name macterm' EXIT
kube=(kubectl "--kubeconfig=$KUBECONFIG" --context=kind-macterm --request-timeout=15s)
"${kube[@]}" get nodes
"${kube[@]}" create namespace macterm
kube+=(--namespace=macterm)
"${kube[@]}" create secret generic test-mask --from-literal=marker=ci-fixture-value
"${kube[@]}" get secrets -o 'custom-columns=NAME:.metadata.name,TYPE:.type' > "$fixture/secrets"
grep -q test-mask "$fixture/secrets"
! grep -q ci-fixture-value "$fixture/secrets"
"${kube[@]}" create deployment smoke --image=busybox:1.36 -- /bin/sh -c 'echo cluster-ready; sleep 300'
"${kube[@]}" wait --for=condition=available --timeout=120s deployment/smoke
"${kube[@]}" logs --tail=200 deployment/smoke | grep -q cluster-ready
"${kube[@]}" exec deployment/smoke -- /bin/sh -c 'echo exec-ok' | grep -q exec-ok
"${kube[@]}" scale deployment/smoke --replicas=0
test "$("${kube[@]}" get deployment smoke -o jsonpath='{.spec.replicas}')" = 0
