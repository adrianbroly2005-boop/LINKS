#!/usr/bin/env bash
set -uo pipefail

# ════════════════════════════════════════════════════════════════
#  SOLO ESTOS 2 MODELOS  →  formato:  "modelo_ollama|nombre_final"
#  Cada uno se descarga y se crea con TU comando (system prompt) incluido.
#  Este script REEMPLAZA al provisioning por defecto de la plantilla,
#  así que no se descarga ningún otro modelo.
# ════════════════════════════════════════════════════════════════
MODELS=(
  "vickiovikthompson/uncensored-qwen|prompter-qwen-unc"      # modelo que pediste (Ollama, base Qwen 2.5)
  "huihui_ai/qwen3-abliterated:14b|prompter-qwen3"           # ~9 GB · reemplaza al ZIP de GitHub (ver nota)
)

# Tu comando (system prompt). Por defecto se lee de tu repo de GitHub.
SYSTEM_URL="${SYSTEM_PROMPT_URL:-https://raw.githubusercontent.com/adrianbroly2005-boop/LINKS/main/system_prompt.txt}"
TEMPERATURE="${LLM_TEMPERATURE:-0.7}"
NUM_CTX="${LLM_NUM_CTX:-4096}"
FILE_HELP="${LLM_FILE_HELP:-1}"      # 1 = el modelo sabe crear archivos con el Code Interpreter

WORKDIR="/workspace/llm"
TMP_PORT=11500
mkdir -p "$WORKDIR"

OK_LIST=()
FAIL_LIST=()

# ───────────── 1. Asegurar que Ollama existe ─────────────
if ! command -v ollama >/dev/null 2>&1; then
  echo "⬇️  Instalando Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

# ───────────── 2. Servidor temporal (el de la plantilla está pausado durante el provisioning) ─────────────
export OLLAMA_HOST="127.0.0.1:${TMP_PORT}"
export OLLAMA_MODELS="${OLLAMA_MODELS:-/workspace/ollama/models}"   # misma carpeta que usa la plantilla
ollama serve > "$WORKDIR/ollama_provision.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 60); do
  ollama list >/dev/null 2>&1 && break
  sleep 1
done

# ───────────── 3. Tu comando (system prompt) ─────────────
BASE_FILE="$WORKDIR/system_prompt.txt"
SYSTEM_FILE="$WORKDIR/system_full.txt"
if curl -fsSL "$SYSTEM_URL" -o "$BASE_FILE" && [ -s "$BASE_FILE" ]; then
  echo "✅ System prompt descargado"
else
  cat > "$BASE_FILE" <<'EOF'
Eres un generador de prompts SFW para imágenes. Responde únicamente con el prompt final, sin explicaciones.
EOF
  echo "⚠️  Usando system prompt por defecto (no se encontró $SYSTEM_URL)"
fi

cp "$BASE_FILE" "$SYSTEM_FILE"
if [ "$FILE_HELP" = "1" ]; then
  cat >> "$SYSTEM_FILE" <<'EOF'

Cuando el usuario pida un archivo (bloc de notas .txt, .md, .csv, .json, .html, etc.), créalo con el Code Interpreter: escribe el contenido en un archivo con Python, guárdalo en el sistema de archivos para que el usuario pueda descargarlo, y confirma el nombre del archivo.
EOF
fi

# ───────────── 4. Descargar y crear cada modelo ─────────────
TOTAL=${#MODELS[@]}
i=0
for item in "${MODELS[@]}"; do
  i=$((i + 1))
  model="${item%%|*}"
  name="${item#*|}"
  echo
  echo "[$i/$TOTAL] ⬇️  $model  →  $name"

  ok=0
  for try in 1 2 3; do
    if ollama pull "$model"; then ok=1; break; fi
    echo "⚠️  Intento $try falló, reintentando..."
    sleep 5
  done
  if [ "$ok" -ne 1 ]; then
    echo "      ❌ No se pudo descargar $model"
    FAIL_LIST+=("$model")
    continue
  fi

  cat > "$WORKDIR/Modelfile.$name" <<EOF
FROM $model
PARAMETER temperature $TEMPERATURE
PARAMETER num_ctx $NUM_CTX
SYSTEM """$(cat "$SYSTEM_FILE")"""
EOF

  if ollama create "$name" -f "$WORKDIR/Modelfile.$name"; then
    echo "      ✅ $name listo"
    OK_LIST+=("$name  ($model)")
  else
    echo "      ❌ Falló la creación de $name"
    FAIL_LIST+=("$name")
  fi
done

# ───────────── 5. Apagar el servidor temporal y resumen ─────────────
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null

echo
echo "────────────────────────────────────────"
echo " RESUMEN"
echo "────────────────────────────────────────"
echo "✅ Listos: ${#OK_LIST[@]}/$TOTAL"
for f in "${OK_LIST[@]:-}"; do [[ -n "$f" ]] && echo "   ✔ $f"; done
if (( ${#FAIL_LIST[@]} > 0 )); then
  echo "❌ Fallidos: ${#FAIL_LIST[@]}/$TOTAL"
  for f in "${FAIL_LIST[@]}"; do echo "   ✘ $f"; done
fi
echo "🎉 Provisioning del LLM terminado"
exit 0
