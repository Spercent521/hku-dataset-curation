#!/bin/bash
set -euo pipefail
: "${MOCK_STATE:?}"
SCENARIO="${MOCK_SCENARIO:-success}"
printf '%s\n' "$*" >> "$MOCK_STATE/calls"

case "$1 $2" in
    "auth whoami")
        if [[ "$SCENARIO" == tty && -t 2 ]]; then
            stty -icrnl -icanon <&2
        fi
        printf 'user=test-account\n'
        ;;
    "datasets info")
        [[ "$SCENARIO" != inaccessible ]] || exit 1
        private=true
        [[ "$SCENARIO" != public ]] || private=false
        sha=before
        [[ ! -f "$MOCK_STATE/uploaded" ]] || sha=after
        printf '{"private":%s,"sha":"%s"}\n' "$private" "$sha"
        ;;
    "datasets list")
        if [[ -f "$MOCK_STATE/uploaded" ]]; then
            cat "$MOCK_STATE/after.json"
        elif [[ "$SCENARIO" == extras ]]; then
            printf '[{"path":"2014/old.jpg","size":3,"blob_id":"old"}]\n'
        else
            printf '[{"path":"README.md","size":4,"blob_id":"root-unchanged"}]\n'
        fi
        ;;
    upload*)
        [[ "$1" == upload && "$2" == AIMedrui/Spine_agentbench && "$4" == 2014 ]]
        payload="$3"
        printf '%s\n' "$payload" > "$MOCK_STATE/payload-path"
        [[ "$*" != *--delete* && "$*" == *--private* ]]
        : > "$MOCK_STATE/remote.tsv"
        while IFS= read -r -d '' file; do
            path="2014/${file#"$payload/"}"
            [[ "$path" != *2014/2014/* && "$path" != *.DS_Store && "$path" != *._* ]]
            bytes="$(wc -c < "$file" | tr -d ' ')"
            blob="$(git hash-object --no-filters -- "$file")"
            sha="$(shasum -a 256 "$file" | cut -d ' ' -f1)"
            printf '%s\t%s\t%s\t%s\n' "$path" "$bytes" "$blob" "$sha" >> "$MOCK_STATE/remote.tsv"
        done < <(find "$payload" -type f -print0)
        jq -Rn '[inputs | split("\t") |
          {path: .[0], size: (.[1] | tonumber), blob_id: .[2],
           lfs: (if (.[0] | endswith(".jpg")) then {sha256: .[3]} else null end)}] +
          [{path: "README.md", size: 4, blob_id: "root-unchanged"},
           {path: ".gitattributes", size: 10, blob_id: "managed-metadata"}]' \
            < "$MOCK_STATE/remote.tsv" > "$MOCK_STATE/after.json"
        if [[ "$SCENARIO" == corruption ]]; then
            jq '.[0].size += 1' "$MOCK_STATE/after.json" > "$MOCK_STATE/modified.json"
            mv "$MOCK_STATE/modified.json" "$MOCK_STATE/after.json"
        elif [[ "$SCENARIO" == checksum ]]; then
            jq 'map(if .lfs != null then .lfs.sha256 = "wrong" else . end)' \
                "$MOCK_STATE/after.json" > "$MOCK_STATE/modified.json"
            mv "$MOCK_STATE/modified.json" "$MOCK_STATE/after.json"
        elif [[ "$SCENARIO" == outside ]]; then
            jq 'map(if .path == "README.md" then .blob_id = "changed" else . end)' \
                "$MOCK_STATE/after.json" > "$MOCK_STATE/modified.json"
            mv "$MOCK_STATE/modified.json" "$MOCK_STATE/after.json"
        fi
        : > "$MOCK_STATE/uploaded"
        ;;
    *) printf 'Unexpected mocked hf arguments\n' >&2; exit 1 ;;
esac
