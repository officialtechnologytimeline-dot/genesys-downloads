#!/usr/bin/env bash
# Uploads one file into the private draft (owner only).
F="$1"; N=$(basename "$F")
VID=$(echo 420089377)
for a in $(gh api "repos/$REPO/releases/$VID/assets?per_page=100" --jq ".[] | select(.name==\"$N\") | .id"); do gh api -X DELETE "repos/$REPO/releases/assets/$a"; done
curl -sS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Content-Type: application/octet-stream" --data-binary @"$F" "https://uploads.github.com/repos/$REPO/releases/$VID/assets?name=$N" -o /dev/null -w "caricato (privato) $N %{http_code}\n"
