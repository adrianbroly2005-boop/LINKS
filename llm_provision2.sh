#!/usr/bin/env bash
set -uo pipefail

# ════════════════════════════════════════════════════════════════
#  MODELOS  →  formato:  "modelo_ollama|nombre_final"
#  Cada uno se descarga y se crea con TU comando (system prompt) incluido.
#  Puedes agregar más líneas. También sirven modelos de Hugging Face en
#  formato GGUF:  "hf.co/usuario/repo:Q4_K_M|mi_modelo"
#  Verifica los tags en ollama.com/library si alguno falla.
# ════════════════════════════════════════════════════════════════
MODELS=(
  "huihui_ai/qwen3-abliterated:14b|prompter-qwen"            # ~9 GB  · el más preciso
  "mannix/llama3.1-8b-abliterated:q5_K_M|prompter-llama"     # ~5.7 GB · el más rápido
  "dolphin3:8b|prompter-dolphin"                             # ~5 GB  · obedece bien el system prompt
)

# Tu comando (system prompt). Por defecto se lee de tu repo de GitHub.
SYSTEM_URL="${SYSTEM_PROMPT_URL:-https://raw.githubusercontent.com/adrianbroly2005-boop/LINKS/main/system_prompt.txt}"
TEMPERATURE="${LLM_TEMPERATURE:-0.7}"
NUM_CTX="${LLM_NUM_CTX:-4096}"

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
ollama serve > "$WORKDIR/ollama_provision.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 60); do
  ollama list >/dev/null 2>&1 && break
  sleep 1
done

# ───────────── 3. Tu comando (system prompt) ─────────────
SYSTEM_FILE="$WORKDIR/system_prompt.txt"
if curl -fsSL "$SYSTEM_URL" -o "$SYSTEM_FILE" && [ -s "$SYSTEM_FILE" ]; then
  echo "✅ System prompt descargado"
else
  cat > "$SYSTEM_FILE" <<'EOF'
Eres un generador de prompts SFW para imágenes. Responde únicamente con el prompt final, sin explicaciones.
EOF
  echo "⚠️  Usando system prompt por defecto (no se encontró $SYSTEM_URL)"
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
