#!/bin/bash
# build.sh — Generate slides using Docker containers
# 1. Mermaid diagrams (.mmd -> .svg) via minlag/mermaid-cli
# 2. Marp slides (.md -> .html/.pdf/.pptx) via marpteam/marp-cli
# Configuration is read from .marprc.yml (theme, html, template, etc.)
#
# Usage:
#   ./build.sh           Build diagrams + HTML, then watch for changes
#   ./build.sh html      Build diagrams + HTML once
#   ./build.sh pdf       Build diagrams + PDF with speaker notes
#   ./build.sh pptx      Build diagrams + PowerPoint
#   ./build.sh serve     Build diagrams, then start live-reload server
#   ./build.sh diagrams  Only rebuild Mermaid diagrams

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MARP_IMAGE="marpteam/marp-cli:latest"
MMDC_IMAGE="mmdc-heisenbug:latest"
CONTAINER_WORKDIR="/home/marp/app"
MMDC_WORKDIR="/data"

DOCKER_MARP="docker run --rm \
  -v ${SCRIPT_DIR}:${CONTAINER_WORKDIR} \
  -e LANG=C.UTF-8"

DOCKER_MMDC="docker run --rm \
  -v ${SCRIPT_DIR}/diagrams:${MMDC_WORKDIR}/diagrams:ro \
  -v ${SCRIPT_DIR}/img:${MMDC_WORKDIR}/img \
  -e LANG=C.UTF-8"

# --- Build custom mermaid-cli image if missing ---
ensure_mmdc_image() {
  if ! docker image inspect "$MMDC_IMAGE" >/dev/null 2>&1; then
    echo "Building custom mermaid-cli image (Mermaid 11.14.0 with venn-beta support)..."
    docker build -t "$MMDC_IMAGE" -f "${SCRIPT_DIR}/Dockerfile.mmdc" "${SCRIPT_DIR}"
  fi
}

# --- Step 1: Convert Mermaid diagrams to SVG ---
build_diagrams() {
  local src_dir="diagrams"
  local out_dir="img"
  local count=0

  if [ ! -d "${SCRIPT_DIR}/${src_dir}" ]; then
    echo "No diagrams/ directory — skipping."
    return
  fi

  local mmd_files=$(find "${SCRIPT_DIR}/${src_dir}" -name '*.mmd' 2>/dev/null)
  if [ -z "$mmd_files" ]; then
    echo "No .mmd files found — skipping diagrams."
    return
  fi

  ensure_mmdc_image
  echo "Building Mermaid diagrams..."
  for mmd in ${mmd_files}; do
    local basename=$(basename "$mmd" .mmd)
    local svg="${SCRIPT_DIR}/${out_dir}/${basename}.svg"

    # Rebuild only if .mmd is newer than .svg (or .svg missing)
    if [ ! -f "$svg" ] || [ "$mmd" -nt "$svg" ]; then
      echo "  ${src_dir}/${basename}.mmd -> ${out_dir}/${basename}.svg"
      $DOCKER_MMDC "$MMDC_IMAGE" \
        -i "${MMDC_WORKDIR}/${src_dir}/${basename}.mmd" \
        -o "${MMDC_WORKDIR}/${out_dir}/${basename}.svg" \
        -b transparent \
        -t dark
      count=$((count + 1))
    fi
  done

  if [ $count -eq 0 ]; then
    echo "  All diagrams up to date."
  else
    echo "  Built ${count} diagram(s)."
    # Post-process: fix Mermaid auto-generated colors to match Heisenbug palette
    echo "  Patching SVG colors..."
    for svg in "${SCRIPT_DIR}/${out_dir}"/*.svg; do
      [ -f "$svg" ] || continue
      sed -i '' \
        -e 's/#9966FF/#cc7e19/g' \
        "$svg"
    done
  fi
}

# --- Step 2: Build slides ---
MODE="${1:-watch}"

case "$MODE" in

  diagrams)
    build_diagrams
    ;;

  watch)
    build_diagrams
    echo ""
    echo "Building HTML and watching for changes..."
    echo "Open ${SCRIPT_DIR}/index.html in your browser."
    echo "Edit index.md — HTML will rebuild automatically."
    echo "NOTE: If you change .mmd files, re-run ./build.sh diagrams"
    echo "Press Ctrl+C to stop."
    $DOCKER_MARP "$MARP_IMAGE" index.md -o index.html -w
    ;;

  html)
    build_diagrams
    echo ""
    echo "Generating HTML index..."
    $DOCKER_MARP "$MARP_IMAGE" index.md -o index.html
    echo "Done: ${SCRIPT_DIR}/index.html"
    ;;

  pdf)
    build_diagrams
    echo ""
    echo "Generating PDF with speaker notes..."
    $DOCKER_MARP "$MARP_IMAGE" index.md --pdf --pdf-notes -o index.pdf
    echo "Done: ${SCRIPT_DIR}/index.pdf"
    ;;

  pptx)
    build_diagrams
    echo ""
    echo "Generating PowerPoint..."
    $DOCKER_MARP "$MARP_IMAGE" index.md --pptx -o index.pptx
    echo "Done: ${SCRIPT_DIR}/index.pptx"
    ;;

  serve)
    build_diagrams
    echo ""
    echo "Starting live-reload server on http://localhost:8080 ..."
    echo "Press Ctrl+C to stop."
    $DOCKER_MARP \
      -p 8080:8080 \
      -p 37717:37717 \
      "$MARP_IMAGE" -s .
    ;;

  *)
    echo "Usage: $0 {watch|html|pdf|pptx|serve|diagrams}"
    echo ""
    echo "  (default)  watch     — build diagrams + HTML, watch for .md changes"
    echo "  html                 — build diagrams + HTML once"
    echo "  pdf                  — build diagrams + PDF with speaker notes"
    echo "  pptx                 — build diagrams + PowerPoint"
    echo "  serve                — build diagrams + live-reload server on :8080"
    echo "  diagrams             — only rebuild Mermaid .mmd -> .svg"
    exit 1
    ;;
esac
