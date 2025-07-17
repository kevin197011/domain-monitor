#!/usr/bin/env bash
set -e

helm upgrade --install domain-monitor . -n monitoring --create-namespace