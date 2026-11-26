#!/usr/bin/env bash
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")" && pwd)}"
RESOURCES="$ROOT/Resources"
OUTPUT="$RESOURCES/adhan.caf"
SOURCE="$RESOURCES/minshawi-source.mp3"
URL="https://raw.githubusercontent.com/Kiwifu/adhan-mp3/main/Mohamed_Siddiq_El-Minshawi_-_Egypt_1_%28%D9%85%D8%AD%D9%85%D8%AF_%D8%B5%D8%AF%D9%8A%D9%82_%D8%A7%D9%84%D9%85%D9%86%D8%B4%D8%A7%D9%88%D9%8A_-_%D9%85%D8%B5%D8%B1%29.mp3"

mkdir -p "$RESOURCES"
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required to prepare the short iOS notification sound. Install it with: brew install ffmpeg" >&2
  exit 1
fi

curl --fail --location --retry 3 --connect-timeout 20 --max-time 180 "$URL" --output "$SOURCE"
ffmpeg -hide_banner -loglevel error -y -i "$SOURCE" -t 29 -vn -ac 1 -ar 44100 -c:a pcm_s16le "$OUTPUT"
rm -f "$SOURCE"

DURATION="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT")"
awk -v duration="$DURATION" 'BEGIN { if (duration <= 0 || duration >= 30) exit 1 }' || {
  echo "Prepared notification sound must be shorter than 30 seconds; got $DURATION seconds." >&2
  exit 1
}
echo "Prepared Minshawi notification sound: $DURATION seconds"
