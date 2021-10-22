#!/usr/bin/bash
set -x

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --values ingress/values.yaml -n ingress-nginx


