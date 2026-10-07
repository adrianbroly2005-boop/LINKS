#!/usr/bin/env bash
set -uo pipefail

# ───────────── Configuración ─────────────
TOKEN="5ab2a62dc5bb5a278547ae7ba5504196"
COMFY="/workspace/ComfyUI"
BASE="$COMFY/models"
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
  "loras|https://civitai.red/api/download/models/1145426?fileId=1050629"

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

# Descarga varias URLs en paralelo dentro de un directorio
download_all() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  pushd "$dir" > /dev/null || return
  for url in "$@"; do
    wget -c -q --show-progress --content-disposition "${url}" &
  done
  wait
  popd > /dev/null
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
line
echo " Descargando modelos de Hugging Face"
line

# Ultralytics face detector (bbox) - para FaceDetailer
download_all "$BASE/ultralytics/bbox" \
  "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt"

# SAM model (opcional, mejor calidad que sam_vit_b)
download_all "$BASE/sams" \
  "https://huggingface.co/segments-arnaud/sam_vit_l/resolve/main/sam_vit_l_0b3195.pth"

# Upscalers (easygoing0114/AI_upscalers)
UPSCALE_BASE="https://huggingface.co/easygoing0114/AI_upscalers/resolve/main"
UPSCALERS=(
  RealESRGAN_x4plus_anime_6B.safetensors
  4x_IllustrationJaNai_V1_ESRGAN_135k.safetensors
  4x-AnimeSharp.safetensors
  4x_NMKD-YandereNeoXL_200k.safetensors
  4x-UltraSharp.safetensors
)
UPSCALE_URLS=()
for f in "${UPSCALERS[@]}"; do
  UPSCALE_URLS+=("$UPSCALE_BASE/$f")
done
download_all "$BASE/upscale_models" "${UPSCALE_URLS[@]}"

# ───────────── Parte 3: IPAdapter (SDXL) ─────────────
line
echo " Instalando IPAdapter + CLIP Vision"
line

mkdir -p "$BASE/ipadapter" "$BASE/clip_vision"

wget -c -O "$BASE/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors" \
  "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"

wget -c -O "$BASE/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors" \
  "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors"

# CLIP Vision (obligatorio, con el nombre correcto)
wget -c -O "$BASE/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors" \
  "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors"

# Nodo IPAdapter
mkdir -p "$COMFY/custom_nodes"
if [[ -d "$COMFY/custom_nodes/ComfyUI_IPAdapter_plus" ]]; then
  echo "Nodo IPAdapter ya existe, omitiendo clone."
else
  git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus "$COMFY/custom_nodes/ComfyUI_IPAdapter_plus"
fi

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
echo "Listo. Reinicia ComfyUI."
