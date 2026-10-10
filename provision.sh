#!/usr/bin/env bash
set -uo pipefail

# ───────────── Configuración ─────────────
# Exporta el token antes de correr:  export CIVITAI_TOKEN="tu_token"
TOKEN="5ab2a62dc5bb5a278547ae7ba5504196"
COMFY="/workspace/ComfyUI"
BASE="$COMFY/models"
DOMAIN="civitai.com"
RED="civitai.red"

# 0 = guarda con el nombre original del archivo (como antes)
# 1 = guarda como "Título del modelo - Versión.ext" (el que ves en la página)
RENAME_TO_TITLE=0

if [[ -z "$TOKEN" ]]; then
  echo "❌ Falta el token. Ejecuta primero: export CIVITAI_TOKEN=\"tu_token\""
  exit 1
fi

# Formato: "carpeta|url"  (el título se consulta solo a la API de Civitai)
QUEUE=(
  "loras|https://${DOMAIN}/api/download/models/2362210?fileId=2252956|Mixplin_Style"
  "loras|https://${DOMAIN}/api/download/models/2233984?fileId=2126880|Shexyo"
  "loras|https://${DOMAIN}/api/download/models/1804885?fileId=1705538|T-Rex Studio V2 NEW!!- Hentai +18" 
  "loras|https://${DOMAIN}/api/download/models/1680391?fileId=1581449|rizdraws_style"
  "loras|https://${DOMAIN}/api/download/models/1672146?fileId=1572944|dzenrei_style"
  "loras|https://${DOMAIN}/api/download/models/994457?fileId=900288|Saigalisk_Artist"
  "loras|https://${DOMAIN}/api/download/models/2026095?fileId=1923012|CreamyAI_Style"
  "loras|https://${DOMAIN}/api/download/models/1903200?fileId=1802650|11_22_Style"
  "loras|https://${DOMAIN}/api/download/models/3252969?fileId=3135998|YabaAIstyle"
  "loras|https://${DOMAIN}/api/download/models/3200596?fileId=3081829|Milfication"
  "loras|https://${DOMAIN}/api/download/models/2056337?fileId=1953157|Raikageart"
  "loras|https://${DOMAIN}/api/download/models/3200596?fileId=3081829|Milfication"
  "loras|https://${DOMAIN}/api/download/models/3200596?fileId=3081829|DreamcoreArt"

  "upscale_models|https://${DOMAIN}/api/download/models/164821?fileId=2037845"

  "checkpoints|https://${RED}/api/download/models/2584885?fileId=2472352"
  "checkpoints|https://${RED}/api/download/models/1166878?fileId=1072193"
  "checkpoints|https://${RED}/api/download/models/1828803?fileId=1729137"

  "vae|https://${DOMAIN}/api/download/models/669051?fileId=584020"
  "vae|https://${DOMAIN}/api/download/models/3315526?fileId=3200992"
)

# ───────────── Estado ─────────────
OK_LIST=()
FAIL_LIST=()
HF_FAIL=()
TOTAL=${#QUEUE[@]}
SEP=$'\x1f'

line() { printf '%*s\n' 60 '' | tr ' ' '─'; }

# Consulta la API de Civitai y devuelve: "Modelo - Versión" SEP archivo_original SEP nombre_seguro
civitai_info() {
  local url="$1" host vid fid json
  host=$(sed -E 's#https?://([^/]+)/.*#\1#' <<<"$url")
  vid=$(sed -E 's#.*/models/([0-9]+).*#\1#' <<<"$url")
  fid=$(sed -nE 's#.*fileId=([0-9]+).*#\1#p' <<<"$url")
  json=$(curl -fsL --max-time 20 -H "Authorization: Bearer ${TOKEN}" \
         "https://${host}/api/v1/model-versions/${vid}") || return 1
  FID="$fid" python3 -c '
import sys, json, os, re
d = json.load(sys.stdin)
model = (d.get("model") or {}).get("name", "")
ver = d.get("name", "")
title = f"{model} - {ver}".strip(" -") or "sin título"
fid = os.environ.get("FID", "")
files = d.get("files") or []
f = next((x for x in files if str(x.get("id")) == fid), files[0] if files else {})
fname = f.get("name", "")
ext = os.path.splitext(fname)[1] or ".safetensors"
safe = re.sub(r"[^\w\-. ()\[\]]", "_", title).strip() + ext
print(title, fname, safe, sep="\x1f")
' <<<"$json" 2>/dev/null
}

# Modo "titulos": solo muestra el título de cada link, sin descargar
if [[ "${1:-}" == "titulos" ]]; then
  for item in "${QUEUE[@]}"; do
    url="${item#*|}"
    if info=$(civitai_info "$url"); then
      IFS="$SEP" read -r t _ _ <<<"$info"
      echo "${item%%|*}  |  $t"
    else
      echo "${item%%|*}  |  (no se pudo consultar) $url"
    fi
  done
  exit 0
fi

download_one() {
  local idx="$1" subdir="$2" url="$3"
  local dir="$BASE/$subdir" outpath="" title="(sin título)" fname="" safe="" info ok=0

  mkdir -p "$dir"

  if info=$(civitai_info "$url"); then
    IFS="$SEP" read -r title fname safe <<<"$info"
  fi
  echo "[$idx/$TOTAL] ⬇️  $subdir  ←  $title"

  local args=(-fL --retry 3 --retry-delay 5 --progress-bar -H "Authorization: Bearer ${TOKEN}")
  if (( RENAME_TO_TITLE == 1 )) && [[ -n "$safe" ]]; then
    outpath="$dir/$safe"
    curl "${args[@]}" -o "$outpath" "$url" && ok=1
  else
    outpath=$(curl "${args[@]}" -J -O --output-dir "$dir" -w '%{filename_effective}' "$url") && ok=1
  fi

  if (( ok == 1 )); then
    local name size bytes
    name=$(basename "$outpath")
    size=$(du -h "$outpath" | cut -f1)
    bytes=$(stat -c %s "$outpath")
    # Si pesa menos de 100 KB probablemente es una página de error, no un modelo
    if (( bytes < 102400 )); then
      echo "      ⚠️  $name pesa solo $size (¿página de error/login?)"
      FAIL_LIST+=("$subdir  ←  $title  (archivo sospechoso: $name, $size)")
    else
      echo "      ✅ $name ($size)"
      OK_LIST+=("$subdir/$name  [$size]  — $title")
    fi
  else
    echo "      ❌ FALLÓ"
    FAIL_LIST+=("$subdir  ←  $title  ($url)")
  fi
  echo
}

# Descarga varias URLs en paralelo dentro de un directorio y registra fallos
download_all() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  pushd "$dir" > /dev/null || return
  local pids=() urls=() url i
  for url in "$@"; do
    wget -c -q --show-progress --content-disposition "$url" &
    pids+=($!)
    urls+=("$url")
  done
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" || HF_FAIL+=("${urls[$i]}")
  done
  popd > /dev/null
}

# Descarga un archivo con nombre fijo y registra fallos
fetch_named() {
  local out="$1" url="$2"
  wget -c -O "$out" "$url" || HF_FAIL+=("$url")
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

# SAM model
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

fetch_named "$BASE/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors" \
  "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"

fetch_named "$BASE/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors" \
  "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors"

# CLIP Vision (obligatorio, con el nombre correcto)
fetch_named "$BASE/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors" \
  "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors"

# Nodo IPAdapter
mkdir -p "$COMFY/custom_nodes"
if [[ -d "$COMFY/custom_nodes/ComfyUI_IPAdapter_plus" ]]; then
  echo "Nodo IPAdapter ya existe, omitiendo clone."
else
  git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus "$COMFY/custom_nodes/ComfyUI_IPAdapter_plus" \
    || HF_FAIL+=("git clone ComfyUI_IPAdapter_plus")
fi

# ───────────── Resumen ─────────────
echo
line
echo " RESUMEN FINAL"
line
echo "✅ Descargados (Civitai): ${#OK_LIST[@]}/$TOTAL"
for f in "${OK_LIST[@]:-}"; do [[ -n "$f" ]] && echo "   ✔ $f"; done

EXIT=0
if (( ${#FAIL_LIST[@]} > 0 )); then
  echo
  echo "❌ Fallidos (Civitai): ${#FAIL_LIST[@]}/$TOTAL"
  for f in "${FAIL_LIST[@]}"; do echo "   ✘ $f"; done
  EXIT=1
fi

if (( ${#HF_FAIL[@]} > 0 )); then
  echo
  echo "❌ Fallidos (Hugging Face / git): ${#HF_FAIL[@]}"
  for f in "${HF_FAIL[@]}"; do echo "   ✘ $f"; done
  EXIT=1
fi

line
if (( EXIT == 0 )); then
  echo "🎉 Todas las descargas se completaron correctamente"
  echo "Listo. Reinicia ComfyUI."
fi
exit $EXIT
