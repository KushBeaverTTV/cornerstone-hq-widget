#!/usr/bin/env bash
# Prints one JSON object: HQ window count and each service's state.
set -u
win=$(app-summon --count '^(brave|chrome)-127\.0\.0\.1__-Default$' 2>/dev/null || echo 0)
units=(kbp-server:Server hq-bridge:Bridge kbp-bot:"Discord bot" streambot:Streambot lavalink:Lavalink yt-cipher:"YouTube decoder")
printf '{"windows":%d,"services":[' "${win:-0}"
first=1
for u in "${units[@]}"; do
  name=${u%%:*}; label=${u#*:}
  st=$(systemctl --user is-active "$name.service" 2>/dev/null); st=${st:-unknown}
  (( first )) || printf ','; first=0
  printf '{"unit":"%s","label":"%s","state":"%s"}' "$name" "$label" "$st"
done
printf ']}\n'
