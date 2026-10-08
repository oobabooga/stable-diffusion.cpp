#!/usr/bin/env bash
# Helpers for the throwaway H3 stack review CI. Sourced by the workflow steps.
set -euo pipefail
REPO_URL=${REPO_URL:-https://github.com/oobabooga/stable-diffusion.cpp}
MODEL_URL=${MODEL_URL:-https://huggingface.co/Green-Sky/SD-Turbo-GGUF/resolve/main/sd_turbo-f16-q8_0.gguf}

command -v timeout >/dev/null 2>&1 || timeout() { shift; "$@"; }

sha16() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -c1-16; }

njobs() { if [ "$(uname -s)" = Darwin ]; then sysctl -n hw.logicalcpu; else nproc; fi; }

# fetch_src SHA DIR PATCHED(0|1): shallow clone at SHA, ggml submodule, optional carried patches.
fetch_src() {
  local sha=$1 dir=$2 patched=$3 n=0
  rm -rf "$dir"; git init -q "$dir"; git -C "$dir" remote add origin "$REPO_URL"
  git -C "$dir" fetch -q --depth 1 origin "$sha"
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
  git -C "$dir" submodule update --init --depth 1 ggml
  if [ "$patched" = 1 ]; then
    for p in "$dir"/scripts/unsloth/ggml-patches/*.patch; do
      [ -e "$p" ] || continue
      git -C "$dir/ggml" apply --verbose "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
      n=$((n + 1))
    done
  fi
  echo "fetched $sha into $dir patched=$patched patches_applied=$n"
}

# build_sd DIR TARGETS CMAKE_ARGS...
build_sd() {
  local dir=$1 targets=$2; shift 2
  cmake -S "$dir" -B "$dir/build" -DCMAKE_BUILD_TYPE=Release -DSD_BUILD_EXAMPLES=ON \
    -DSD_SERVER_BUILD_FRONTEND=OFF -DSD_WEBP=OFF -DSD_WEBM=OFF -DGGML_NATIVE=OFF "$@" 2>&1 | tee "$dir/configure.log"
  grep -E 'fused DiT ops|SD_GGML_H3' "$dir/configure.log" || true
  # shellcheck disable=SC2086
  cmake --build "$dir/build" --config Release -j "$(njobs)" --target $targets
}

get_model() {
  MODEL="${RUNNER_TEMP:-/tmp}/sd_turbo.gguf"
  [ -s "$MODEL" ] || curl -fsSL --retry 5 -o "$MODEL" "$MODEL_URL"
  export MODEL
}

# smoke BIN OUTDIR RES: three fixed-seed SD-Turbo renders.
smoke() {
  local bin=$1 out=$2 res=$3 t=${SMOKE_THREADS:-4}
  mkdir -p "$out"
  local common=(-m "$MODEL" -p "a red fox sitting in a snowy pine forest, detailed fur" --steps 2 --cfg-scale 1
                -W "$res" -H "$res" -s 42 --rng cpu -t "$t")
  "$bin" "${common[@]}" -o "$out/plain.png" > "$out/plain.log" 2>&1 || { tail -40 "$out/plain.log"; return 1; }
  "$bin" "${common[@]}" --diffusion-fa --vae-tiling --vae-tile-size 24x16 -o "$out/fa_tiled.png" > "$out/fa_tiled.log" 2>&1 || { tail -40 "$out/fa_tiled.log"; return 1; }
  SD_TILE_ASYNC_MERGE=0 "$bin" "${common[@]}" --diffusion-fa --vae-tiling --vae-tile-size 24x16 -o "$out/fa_tiled_sync.png" > "$out/fa_tiled_sync.log" 2>&1 || { tail -40 "$out/fa_tiled_sync.log"; return 1; }
  grep -hiE 'backend|using .* backend|tile' "$out/fa_tiled.log" | head -8 || true
}

# compare_dirs A B: per-case byte comparison of two smoke output dirs.
compare_dirs() {
  local a=$1 b=$2 rc=0 h1 h2
  for c in plain fa_tiled fa_tiled_sync; do
    h1=$(sha16 "$a/$c.png"); h2=$(sha16 "$b/$c.png")
    if [ "$h1" = "$h2" ]; then echo "SMOKE $c MATCH $h1"; else echo "SMOKE $c DIFF $h1 vs $h2"; rc=1; fi
  done
  h1=$(sha16 "$b/fa_tiled.png"); h2=$(sha16 "$b/fa_tiled_sync.png")
  [ "$h1" = "$h2" ] && echo "SMOKE async-vs-sync-merge MATCH" || { echo "SMOKE async-vs-sync-merge DIFF"; rc=1; }
  return $rc
}

# tbo BIN OPS...: run test-backend-ops per op on every non-CPU backend, summarise.
tbo() {
  local bin=$1; shift
  for op in "$@"; do
    local log="tbo-$op.log"
    local rc=0
    timeout "${TBO_TIMEOUT:-1500}" "$bin" -o "$op" > "$log" 2>&1 || rc=$?
    local ok fail ns
    ok=$(grep -c ' OK$' "$log" || true); fail=$(grep -c 'FAIL' "$log" || true); ns=$(grep -c 'not supported' "$log" || true)
    echo "TBO $op rc=$rc ok=$ok fail=$fail not_supported=$ns"
    grep 'FAIL' "$log" | head -15 || true
  done
  grep -h -E 'Backend [0-9]+/|Testing|Device description' tbo-*.log | sort -u | head -6 || true
}
