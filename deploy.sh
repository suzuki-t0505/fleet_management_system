#!/bin/sh
set -eu

echo GCPデプロイ実行

IMAGE_TAG="v1"
if [ $# -eq 1 ]; then
  IMAGE_TAG=$1
fi

gcloud auth login
docker build -t fleet-management-system --no-cache .
docker tag fleet-management-system asia-northeast1-docker.pkg.dev/dulcet-radar-464207-v2/fleet-management-system/fleet-management-system:v1
docker push asia-northeast1-docker.pkg.dev/dulcet-radar-464207-v2/fleet-management-system/fleet-management-system:v1