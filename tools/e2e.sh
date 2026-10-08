#!/bin/bash
# e2e.sh <vulkan|hip>: build base (#18 head) and PR (#19 head) sd-cli, render MiniMax-H3 with each, compare.
set -euxo pipefail
BACKEND=$1
TOOLS="$(cd "$(dirname "$0")" && pwd)"
W="$RUNNER_TEMP/w"; mkdir -p "$W"/{tmp,models,hf,cache/pip}
export TMPDIR="$W/tmp" PIP_CACHE_DIR="$W/cache/pip" HF_HOME="$W/hf" HF_HUB_ENABLE_HF_TRANSFER=1
python3 -m venv "$W/venv"; . "$W/venv/bin/activate"
pip install -q cmake ninja huggingface_hub hf_transfer numpy
. "$TOOLS/toolchain.sh" "$BACKEND"
python3 - "$W/models" > "$W/dl.log" 2>&1 <<'PY' &
import sys
from huggingface_hub import hf_hub_download
for f in ["vae/minimax_h3_audio_vae_fp32.safetensors", "vae/minimax_h3_video_vae_fp16.safetensors",
          "minimax_h3_fl2va_pruned-UD-Q2_K_XL.gguf", "qwen3vl_32b_minimax_h3-Q2_K_M.gguf"]:
    print(hf_hub_download("unsloth/MiniMax-H3-GGUF", f, local_dir=sys.argv[1]), flush=True)
PY
DL=$!
cd "$W"
git clone -q https://github.com/unslothai/stable-diffusion.cpp src
git -C src fetch -q origin perf/h3-gguf-speed-v2 perf/h3-gguf-speed-v3
for arm in base pr; do
  sha=$([ $arm = base ] && echo 5f222b8 || echo 338079e)
  git -C src worktree add -q "../$arm" "$sha"
  (cd "$arm" && git submodule update --init --depth 1 ggml && for p in scripts/unsloth/ggml-patches/*.patch; do git -C ggml apply "../$p"; echo "applied $p"; done)
  python3 "$TOOLS/bench_hook.py" "$arm/examples/cli/main.cpp"
  cmake -S "$arm" -B "$arm/build" -G Ninja -DCMAKE_BUILD_TYPE=Release $SD_CMAKE_FLAGS
  cmake --build "$arm/build" -j 32 --target sd-cli
done
wait $DL; cat "$W/dl.log" | tail -4
M="$W/models"
run() {  # run <arm> <tag> [VAR=val ...]
  local arm=$1 tag=$2; shift 2
  mkdir -p "$W/out/$tag"
  env SD_BENCH_REPEAT=2 SD_BENCH_DUMP="$W/out/$tag/d" "$@" "$W/$arm/build/bin/sd-cli" -M vid_gen \
    --diffusion-model "$M/minimax_h3_fl2va_pruned-UD-Q2_K_XL.gguf" --vae "$M/vae/minimax_h3_video_vae_fp16.safetensors" \
    --audio-vae "$M/vae/minimax_h3_audio_vae_fp32.safetensors" --llm "$M/qwen3vl_32b_minimax_h3-Q2_K_M.gguf" \
    -p "A cute silver tabby kitten surfs on a tropical ocean wave. Upbeat surf-rock music." \
    --cfg-scale 1.0 --steps 4 -W 512 -H 288 --video-frames 56 --fps 24 --seed 42 --rng cpu --diffusion-fa -v \
    -o "$W/out/$tag/unused.png" > "$W/out/$tag/log.txt" 2>&1 || { echo "$tag FAILED"; tail -40 "$W/out/$tag/log.txt"; return 0; }
  grep -E "BENCH render|sampling completed|audio VAE decode completed|decode_first_stage completed|generate_video completed|ERROR|WARN.*(fall|unsupported)" "$W/out/$tag/log.txt" | grep -v "save result" || true
}
run base base
run pr pr
run pr pr_alloff SD_H3_FAST_SAGE_QKV=0 SD_TILE_ASYNC_MERGE=0 SD_H3_VAE_ASYNC_ASSEMBLY=0 SD_H3_VAE_REUSE_MEMQUERY=0 SD_H3_VAE_FUSED_QKV=0 SD_H3_VAE_FUSED_QK_NORM=0 SD_H3_AUDIO_DIRECT_DW=0
run pr pr_dwoff SD_H3_AUDIO_DIRECT_DW=0
for t in pr pr_alloff pr_dwoff; do python3 "$TOOLS/compare.py" "$W/out/base/d_r1" "$W/out/$t/d_r1" "base_vs_$t"; done
python3 "$TOOLS/compare.py" "$W/out/base/d_r0" "$W/out/base/d_r1" "base_r0_vs_r1"
python3 "$TOOLS/compare.py" "$W/out/pr/d_r0" "$W/out/pr/d_r1" "pr_r0_vs_r1"
