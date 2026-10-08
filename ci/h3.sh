# Sourced helpers. Needs W (work root), M (model dir), OUT (render root).
ALL_OFF="SD_H3_GRAPH_FAST=0 SD_H3_FAST_SAGE_QKV=0 SD_H3_VAE_GRAPH_OPT=0 SD_H3_VAE_FUSED_QKV=0 SD_H3_VAE_FUSED_QK_NORM=0 SD_TILE_ASYNC_MERGE=0 SD_H3_VAE_ASYNC_ASSEMBLY=0 SD_H3_VAE_REUSE_MEMQUERY=0 SD_H3_VAE_KEEP_RESIDENT=0 SD_H3_AUDIO_DIRECT_DW=0 GGML_CUDA_CPY_ROWS=0 GGML_CUDA_FA_LONGSEQ=0 GGML_CUDA_NORM_SMALL_ROWS=0 GGML_CUDA_CUBLAS_EPILOGUE_FUSION=0 GGML_CUDA_CUDNN_ATTN=0"

fetch_src() { # dir sha patched(0|1)
  local d=$1 sha=$2 patched=$3
  git init -q "$d"
  git -C "$d" remote add origin https://github.com/unslothai/stable-diffusion.cpp
  git -C "$d" fetch -q --depth 1 origin "$sha"
  git -C "$d" checkout -q FETCH_HEAD
  git -C "$d" submodule update --init --depth 1 ggml
  local n=0
  if [ "$patched" = 1 ]; then
    for p in "$d"/scripts/unsloth/ggml-patches/*.patch; do
      [ -e "$p" ] || continue
      git -C "$d/ggml" apply "$p"; n=$((n+1))
    done
  fi
  echo "$d: $(git -C "$d" log --oneline -1 | cut -c1-60) patches=$n"
}

# render NAME BIN [extra sd-cli args...] ; env vars passed via ENVS="A=1 B=2"
H3_W=${H3_W:-480}; H3_H=${H3_H:-272}; H3_F=${H3_F:-22}; H3_STEPS=${H3_STEPS:-2}
render() {
  local name=$1 bin=$2; shift 2
  mkdir -p "$OUT/$name"
  local t0=$(date +%s)
  env ${ENVS:-} "$bin" -M vid_gen \
    --diffusion-model "$M/minimax_h3_fl2va_pruned-UD-Q2_K_XL.gguf" \
    --vae "$M/vae/minimax_h3_video_vae_fp16.safetensors" \
    --audio-vae "$M/vae/minimax_h3_audio_vae_fp32.safetensors" \
    --llm "$M/qwen3vl_32b_minimax_h3-Q2_K_M.gguf" \
    -p "A red fox runs through fresh snow in a pine forest, soft morning light, wind and crunching snow sounds." \
    --cfg-scale 1.0 -W "$H3_W" -H "$H3_H" --video-frames "$H3_F" --steps "$H3_STEPS" --seed 42 --rng cpu --fps 24 \
    "$@" -o "$OUT/$name/f_%03d.png" > "$OUT/$name.log" 2>&1
  local rc=$?
  echo "RENDER $name rc=$rc files=$(ls "$OUT/$name" | wc -l) secs=$(( $(date +%s) - t0 )) env=[${ENVS:-}] args=[$*]"
  grep -iE "error|assert|abort|fallback|cudnn|not supported|Using flash|fused" "$OUT/$name.log" | sort | uniq -c | sort -rn | head -12
  return 0
}
