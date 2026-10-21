#!/usr/bin/env bash
# Uploads the log of this run into the private draft (readable by the owner only).
JOB=$(jq -r .id ci/job.json)
VID=$(gh api "repos/$REPO/releases?per_page=100" --jq '.[] | select(.draft and .name=="genesys-ci-vault") | .id' | head -1)
[ -z "$VID" ] && { echo "nessuna cassaforte"; exit 0; }
N="log-$JOB.txt"; cp ci-log.txt "$N" 2>/dev/null || echo "(log mancante)" > "$N"
for a in $(gh api "repos/$REPO/releases/$VID/assets?per_page=100" --jq ".[] | select(.name==\"$N\") | .id"); do gh api -X DELETE "repos/$REPO/releases/assets/$a"; done
curl -sS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Content-Type: text/plain" --data-binary @"$N" "https://uploads.github.com/repos/$REPO/releases/$VID/assets?name=$N" -o /dev/null -w "log caricato %{http_code}\n"
