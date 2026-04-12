#!/bin/zsh
set -euo pipefail

CACHE_DIR="/Users/Shared/FluxBar"
CACHE_FILE="$CACHE_DIR/thermal-cache.json"
TMP_FILE="$CACHE_FILE.tmp"
SOURCE="powermetrics thermal+smc sampler (root helper)"

mkdir -p "$CACHE_DIR"

OUTPUT="$(/usr/bin/powermetrics --samplers thermal,smc -n 1 2>/dev/null || true)"

extract_temp() {
  local pattern="$1"
  printf '%s\n' "$OUTPUT" | /usr/bin/perl -ne "
    if (/${pattern}[^\n]*?([0-9]+(?:\\.[0-9]+)?)(?:\\s*(?:°|deg)?\\s*[Cc]|\\s*℃|\\s*摄氏(?:度)?)?/i) {
      my \$v = \$1 + 0;
      if (\$v >= 15 && \$v <= 130) { print \$1; exit }
    }
  " || true
}

# Newer Apple Silicon machines may expose labels other than plain CPU/GPU.
CPU="$(extract_temp "(CPU|P-?Cluster|E-?Cluster|package|SoC|die|ANE)")"
GPU="$(extract_temp "(GPU|GFX)")"

# Last-resort fallback: use the first thermal temperature line if label matching failed.
if [[ -z "${CPU}" && -z "${GPU}" ]]; then
  CPU="$(printf '%s\n' "$OUTPUT" | /usr/bin/perl -ne '
    if (/(temp|thermal|die|soc|package|cluster|cpu|gpu)/i && /([0-9]+(?:\.[0-9]+)?)/) {
      my $v = $2 + 0;
      if ($v >= 15 && $v <= 130) { print $2; exit }
    }
  ' || true)"
fi
TIMESTAMP="$(/bin/date +%s)"

CPU_JSON="${CPU:-null}"
GPU_JSON="${GPU:-null}"

/bin/cat > "$TMP_FILE" <<EOF
{"timestamp":$TIMESTAMP,"cpuCelsius":$CPU_JSON,"gpuCelsius":$GPU_JSON,"source":"$SOURCE"}
EOF

/bin/chmod 644 "$TMP_FILE"
/bin/mv "$TMP_FILE" "$CACHE_FILE"
