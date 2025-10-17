#!/usr/bin/env bash
set -euo pipefail

JOB_FILE="$1"
WORKDIR="/tmp/edit_work"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "Reading job file: $GITHUB_WORKSPACE/$JOB_FILE"
JJSON=$(cat "$GITHUB_WORKSPACE/$JOB_FILE")
INPUT_URL=$(echo "$JJSON" | jq -r '.input_url')
MOVIE_TITLE=$(echo "$JJSON" | jq -r '.movie_title')
PART_INDEX=$(echo "$JJSON" | jq -r '.part_index')
OUTPUT_FOLDER=$(echo "$JJSON" | jq -r '.output_folder')
JOB_ID=$(basename "$JOB_FILE" | sed 's/\.json$//')

echo "JOB_ID: $JOB_ID input: $INPUT_URL part: $PART_INDEX"

# 1) download input part
if echo "$INPUT_URL" | grep -q ":"; then
  rclone copy --progress "$INPUT_URL" . || (echo "rclone copy failed" && exit 2)
  FILE=$(ls -1 | egrep -i '\.(mp4|ts|mkv|mov|webm)' | head -n1 || true)
  if [ -z "$FILE" ]; then
    echo "No media file found"
    exit 3
  fi
  mv "$FILE" input_part.mp4 || true
else
  wget -q --show-progress -O input_part.mp4 "$INPUT_URL" || curl -L -o input_part.mp4 "$INPUT_URL" || (echo "download failed" && exit 4)
fi

# 2) ensure font available
FONT_DIR="/usr/local/share/fonts/sansitaswashed"
FONT_PATH="${FONT_DIR}/SansitaSwashed.ttf"
FALLBACK_FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
if [ ! -f "${FONT_PATH}" ]; then
  mkdir -p "$FONT_DIR"
  wget -q -O "${FONT_PATH}" "https://github.com/google/fonts/raw/main/ofl/sansitaswashed/SansitaSwashed[wght].ttf" || true
fi
if [ -f "${FONT_PATH}" ]; then
  FONT_FOR_FF="${FONT_PATH}"
else
  FONT_FOR_FF="${FALLBACK_FONT}"
fi

ESCAPED_TITLE=$(printf '%s' "$MOVIE_TITLE" | sed "s/'/\\\\'/g" | sed 's/:/\\:/g')
OUTNAME="${MOVIE_TITLE// /_}_part${PART_INDEX}_final.mp4"

FILTER_COMPLEX="[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=40:8[bg]; \
[0:v]scale=1080:-1:force_original_aspect_ratio=decrease[fg]; \
[bg][fg]overlay=(W-w)/2:(H-h)/2, \
drawtext=fontfile='${FONT_FOR_FF}':text='${ESCAPED_TITLE}':fontcolor=white:fontsize=120:x=(w-text_w)/2:y=320, \
drawtext=fontfile='${FONT_FOR_FF}':text='Part - ${PART_INDEX}':fontcolor=white:fontsize=75:x=(w-text_w)/2:y=h-200"

ffmpeg -y -i input_part.mp4 -filter_complex "${FILTER_COMPLEX}" \
  -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k -movflags +faststart -aspect 9:16 "${OUTNAME}"

# 3) upload final
rclone copy --progress "${OUTNAME}" "${OUTPUT_FOLDER}"

# 4) try to get link
LINK=$(rclone link "${OUTPUT_FOLDER%:}/${OUTNAME}" 2>/dev/null || echo "")
if [ -n "$LINK" ]; then
  FINAL_REMOTE="$LINK"
else
  FINAL_REMOTE="${OUTPUT_FOLDER%:}/${OUTNAME}"
fi

# 5) write result json and push to repo at jobs/edit_results/<jobid>.json
RESULT_PATH="jobs/edit_results/${JOB_ID}.json"
mkdir -p "$(dirname "$GITHUB_WORKSPACE/$RESULT_PATH")"
jq -n --arg movie "$MOVIE_TITLE" --arg out "$OUTNAME" --arg link "$FINAL_REMOTE" --arg part "$PART_INDEX" '{ movie_title: $movie, output_name: $out, final_link: $link, part_index:(($part|tonumber)) }' > "$GITHUB_WORKSPACE/$RESULT_PATH"

cd "$GITHUB_WORKSPACE"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add "$RESULT_PATH"
git commit -m "Add edit result for ${JOB_ID}" || echo "No change to commit"
git push origin HEAD || echo "Push failed"

echo "Edit job done: $RESULT_PATH"
