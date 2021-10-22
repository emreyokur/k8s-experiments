#!/usr/bin/bash
set -x
kubectl label nodes node2 dedicated=prometheus
kubectl apply -f create-pv.yaml
kubectl apply -f create-pvc.yaml
chmod 777 /mnt/data
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/prometheus --values prometheus/values.yaml


