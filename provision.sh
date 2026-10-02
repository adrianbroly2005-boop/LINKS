#!/usr/bin/env bash
set -uo pipefail

# ───────────── Configuración ─────────────
# El token se pasa como variable de entorno (-e CIVITAI_TOKEN=...) en Vast.ai
TOKEN="5ab2a62dc5bb5a278547ae7ba5504196"
BASE="/workspace/ComfyUI/models"
DOMAIN="civitai.com"

# Formato: "carpeta|url"
QUEUE=(
  "loras|https://${DOMAIN}/api/download/models/2126463?fileId=2020686"
  "loras|https://${DOMAIN}/api/download/models/3200596?fileId=3081829"
  "loras|https://${DOMAIN}/api/download/models/1804885?fileId=1705538"
  "loras|https://${DOMAIN}/api/download/models/1715751?fileId=1616313"
  "loras|https://${DOMAIN}/api/download/models/2026095?fileId=1923012"
  "loras|https://${DOMAIN}/api/download/models/3057488?fileId=2936182"
  "loras|https://${DOMAIN}/api/download/models/1479321?fileId=1380852"

  "upscale_models|https://${DOMAIN}/api/download/models/164821?fileId=2037845"

  "checkpoints|https://${DOMAIN}/api/download/models/2883731?fileId=2763986"
  "checkpoints|https://${DOMAIN}/api/download/models/2584885?fileId=2472352"
  "checkpoints|https://${DOMAIN}/api/download/models/2579194?fileId=2466379"

  "vae|https://${DOMAIN}/api/download/models/669051?fileId=584020"
  "vae|https://${DOMAIN}/api/download/models/3315526?fileId=3200992"
)

# ───────────── Estado ─────────────
OK_LIST=()
FAIL_LIST=()
TOTAL=${#QUEUE[@]}

line() { printf '%*s\n' 60 '' | tr ' ' '─'; }

download_one() {
  local idx="$1" subdir="$2" url="$3"
  local dir="$BASE/$subdir" outpath

  mkdir -p "$dir"
  echo "[$idx/$TOTAL] ⬇️  $subdir  ←  ${url##*/}"

  if outpath=$(curl -fL --retry 3 --retry-delay 5 --progress-bar \
        -H "Authorization: Bearer ${TOKEN}" \
        -J -O --output-dir "$dir" \
        -w '%{filename_effective}' "$url"); then
    local name size
    name=$(basename "$outpath")
    size=$(du -h "$outpath" | cut -f1)
    echo "      ✅ $name ($size)"
    OK_LIST+=("$subdir/$name  [$size]")
  else
    echo "      ❌ FALLÓ"
    FAIL_LIST+=("$subdir  ←  $url")
  fi
  echo
}

# ───────────── Parte 1: Civitai ─────────────
line
echo " Iniciando descarga de $TOTAL archivos (Civitai)"
line
echo

i=0
for item in "${QUEUE[@]}"; do
  i=$((i + 1))
  download_one "$i" "${item%%|*}" "${item#*|}"
done

# ───────────── Parte 2: Hugging Face ─────────────
download_all() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  cd "$dir" || return
  for url in "$@"; do
    wget -q --show-progress --content-disposition "${url}" &
  done
  wait
  cd - > /dev/null
}

line
echo " Descargando modelos de Hugging Face"
line

# Ultralytics face detector (bbox) - para FaceDetailer
download_all "/workspace/ComfyUI/models/ultralytics/bbox" \
  "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt"

# SAM model (opcional, mejor calidad que sam_vit_b)
download_all "/workspace/ComfyUI/models/sams" \
  "https://huggingface.co/segments-arnaud/sam_vit_l/resolve/main/sam_vit_l_0b3195.pth"

# ───────────── Resumen ─────────────
echo
line
echo " RESUMEN FINAL"
line
echo "✅ Descargados (Civitai): ${#OK_LIST[@]}/$TOTAL"
for f in "${OK_LIST[@]:-}"; do [[ -n "$f" ]] && echo "   ✔ $f"; done

if (( ${#FAIL_LIST[@]} > 0 )); then
  echo
  echo "❌ Fallidos: ${#FAIL_LIST[@]}/$TOTAL"
  for f in "${FAIL_LIST[@]}"; do echo "   ✘ $f"; done
  line
  exit 1
fi

line
echo "🎉 Todas las descargas se completaron correctamente"
