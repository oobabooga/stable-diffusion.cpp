#!/bin/bash
# vae_oom.sh <linux|windows>: build master and PR #21 sd-cli with Vulkan, force the untiled VAE pass to fail with
# --max-vram, and compare the retry output against an unbudgeted untiled render of the same seed.
set -uo pipefail
OS=$1
TOOLS="$(cd "$(dirname "$0")" && pwd)"
W="$RUNNER_TEMP/w"; mkdir -p "$W"/{tmp,models,hf,out}
export TMPDIR="$W/tmp" HF_HOME="$W/hf"
PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
if [ "$OS" = linux ]; then
  $PY -m venv "$W/venv"; . "$W/venv/bin/activate"; PY=python3
  pip install -q cmake huggingface_hub numpy pillow
  if ! command -v glslc >/dev/null; then
    curl -sSL -o "$TMPDIR/vk.tar.xz" https://sdk.lunarg.com/sdk/download/latest/linux/vulkan_sdk.tar.xz
    mkdir -p "$TMPDIR/vk" && tar -xf "$TMPDIR/vk.tar.xz" -C "$TMPDIR/vk"
    set +u; . "$(ls -d "$TMPDIR"/vk/*/ | head -1)setup-env.sh"; set -u
  fi
  vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverName" | head -4 || true
  GEN=(-G "Unix Makefiles"); EXE=build/bin/sd-cli
else
  $PY -m pip install -q huggingface_hub numpy pillow
  GEN=(-G "Visual Studio 17 2022" -A x64); EXE=build/bin/Release/sd-cli.exe
fi
$PY - "$W/models" > "$W/dl.log" 2>&1 <<'PY' &
import sys
from huggingface_hub import hf_hub_download
for repo, f in [("second-state/stable-diffusion-v1-5-GGUF", "stable-diffusion-v1-5-pruned-emaonly-Q8_0.gguf"),
                ("unsloth/Z-Image-Turbo-GGUF", "z-image-turbo-Q4_K_M.gguf"),
                ("unsloth/Z-Image-Turbo-ComfyUI", "split_files/vae/ae.safetensors"),
                ("unsloth/Z-Image-Turbo-ComfyUI", "split_files/text_encoders/qwen_3_4b.safetensors")]:
    print(hf_hub_download(repo, f, local_dir=sys.argv[1]), flush=True)
PY
DL=$!
cd "$W"
git clone -q https://github.com/unslothai/stable-diffusion.cpp src
git -C src fetch -q origin pull/21/head:pr21
for arm in master pr; do
  ref=$([ $arm = master ] && echo origin/master || echo pr21)
  git -C src worktree add -q "../$arm" "$ref"
  (cd "$arm" && git log --oneline -1 && git submodule update --init --recursive --depth 1 -q)
  cmake -S "$arm" -B "$arm/build" "${GEN[@]}" -DCMAKE_BUILD_TYPE=Release -DSD_VULKAN=ON > "$W/out/cmake-$arm.log" 2>&1 || { tail -30 "$W/out/cmake-$arm.log"; exit 1; }
  cmake --build "$arm/build" --config Release -j 32 --target sd-cli > "$W/out/build-$arm.log" 2>&1 || { grep -iE "error" "$W/out/build-$arm.log" | head -30; exit 1; }
  echo "built $arm"; grep -iE "warning" "$W/out/build-$arm.log" | grep -E "tiling|backend_fit|vae.hpp|diffusion_engine|image.cpp" | head -10 || true
done
wait $DL; tail -4 "$W/dl.log"
M="$W/models"
run() {  # run <arm> <tag> <model> <W> <H> [extra...]
  local arm=$1 tag=$2 model=$3 w=$4 h=$5; shift 5
  local args
  if [ $model = z ]; then
    args=(--diffusion-model "$M/z-image-turbo-Q4_K_M.gguf" --vae "$M/split_files/vae/ae.safetensors" --llm "$M/split_files/text_encoders/qwen_3_4b.safetensors" --cfg-scale 1 --steps 8 -p "a lighthouse on a rocky coast under a stormy sky, photorealistic")
  else
    args=(-m "$M/stable-diffusion-v1-5-pruned-emaonly-Q8_0.gguf" --cfg-scale 7 --steps 12 -p "a red fox sitting in a snowy pine forest, detailed fur")
  fi
  local t0=$(date +%s)
  "$W/$arm/$EXE" "${args[@]}" -W $w -H $h -s 7 -v -o "$W/out/$tag.png" "$@" > "$W/out/$tag.log" 2>&1
  local rc=$?
  echo "== $tag rc=$rc wall=$(( $(date +%s) - t0 ))s"
  grep -E "VAE (decode|encode) failed|VAE Tile size|num tiles|optimal overlap|retrying|vae (decode|encode) compute failed|decode_first_stage completed|cannot make enough|generate failed" "$W/out/$tag.log" | head -16
}
cmp() { [ -f "$W/out/$2.png" ] && echo -n "$2 vs $1: " && $PY "$TOOLS/seam.py" "$W/out/$1.png" "$W/out/$2.png"; }
# SD1.5 at 1024: 128-latent axes, master's 0.5 retry is two 64-latent tiles meeting edge to edge
run master s_ref s 1024 1024
run pr s_ref_pr s 1024 1024
for b in 3 2; do run master s_b${b}_master s 1024 1024 --max-vram $b; run pr s_b${b}_pr s 1024 1024 --max-vram $b; done
# Z-Image 1008x1008 (author's case), and img2img to reach the encode retry
run master z_ref z 1008 1008
for b in 6 4; do run master z_b${b}_master z 1008 1008 --max-vram $b; run pr z_b${b}_pr z 1008 1008 --max-vram $b; done
run master zi_ref z 1008 1008 -i "$W/out/z_ref.png" --strength 0.5
for b in 4; do run master zi_b${b}_master z 1008 1008 -i "$W/out/z_ref.png" --strength 0.5 --max-vram $b; run pr zi_b${b}_pr z 1008 1008 -i "$W/out/z_ref.png" --strength 0.5 --max-vram $b; done
echo "==== seam scores (largest mean |diff| along any row/column vs the unbudgeted untiled render)"
cmp s_ref s_ref_pr
for b in 3 2; do cmp s_ref s_b${b}_master; cmp s_ref s_b${b}_pr; done
for b in 6 4; do cmp z_ref z_b${b}_master; cmp z_ref z_b${b}_pr; done
cmp zi_ref zi_b4_master; cmp zi_ref zi_b4_pr
exit 0
