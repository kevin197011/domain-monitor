#!/usr/bin/env bash
set -e

release_version='v1'

docker build -t domain-monitor:${release_version} .
docker tag domain-monitor:${release_version} harbor.devops.io/devops/domain-monitor:${release_version}
docker push harbor.devops.io/devops/domain-monitor:${release_version}