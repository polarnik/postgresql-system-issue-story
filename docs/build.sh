#!/bin/bash
# build.sh — Generate slides using marpteam/marp-cli Docker container
# Configuration is read from .marprc.yml (theme, html, template, etc.)
#
# Usage:
#   ./build.sh           Build HTML once and start watching for changes
#   ./build.sh html      Generate HTML once (no watch)
#   ./build.sh pdf       Generate PDF with speaker notes
#   ./build.sh pptx      Generate PowerPoint
#   ./build.sh serve     Start live-reload server on http://localhost:8080

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="marpteam/marp-cli:latest"
CONTAINER_WORKDIR="/home/marp/app"

# Marp CLI reads .marprc.yml automatically from the working directory.
# All common options (theme, html, template, lang, author, etc.)
# are defined there — no need to duplicate on the command line.
DOCKER_RUN="docker run --rm \
  -v ${SCRIPT_DIR}:${CONTAINER_WORKDIR} \
  -e LANG=C.UTF-8"

MODE="${1:-watch}"

case "$MODE" in

  watch)
    echo "Building HTML and watching for changes..."
    echo "Open ${SCRIPT_DIR}/slides.html in your browser."
    echo "Edit slides.md — HTML will rebuild automatically."
    echo "Press Ctrl+C to stop."
    $DOCKER_RUN "$IMAGE" slides.md -o slides.html -w
    ;;

  html)
    echo "Generating HTML slides (one-shot)..."
    $DOCKER_RUN "$IMAGE" slides.md -o slides.html
    echo "Done: ${SCRIPT_DIR}/slides.html"
    ;;

  pdf)
    echo "Generating PDF with speaker notes..."
    $DOCKER_RUN "$IMAGE" slides.md --pdf --pdf-notes -o slides.pdf
    echo "Done: ${SCRIPT_DIR}/slides.pdf"
    ;;

  pptx)
    echo "Generating PowerPoint..."
    $DOCKER_RUN "$IMAGE" slides.md --pptx -o slides.pptx
    echo "Done: ${SCRIPT_DIR}/slides.pptx"
    ;;

  serve)
    echo "Starting live-reload server on http://localhost:8080 ..."
    echo "Press Ctrl+C to stop."
    $DOCKER_RUN \
      -p 8080:8080 \
      -p 37717:37717 \
      "$IMAGE" -s .
    ;;

  *)
    echo "Usage: $0 {watch|html|pdf|pptx|serve}"
    echo ""
    echo "  (default)  watch  — build HTML + watch for changes"
    echo "  html              — build HTML once"
    echo "  pdf               — build PDF with speaker notes"
    echo "  pptx              — build PowerPoint"
    echo "  serve             — live-reload server on :8080"
    exit 1
    ;;
esac
