#!/bin/bash


docker compose up -d --force-recreate --no-deps --build --remove-orphans
docker compose logs -f