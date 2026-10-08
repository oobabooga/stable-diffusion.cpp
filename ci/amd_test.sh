#!/usr/bin/env bash
# A/B of the PR #14 ROCm bundle against what Studio installs today on an AMD Linux host.
set -uo pipefail
CI="$(cd "$(dirname "$0")" && pwd)"
W="$RUNNER_TEMP/unsloth-work"
mkdir -p "$W"/{bundles,zips,models,out,tmp,cache/huggingface}
export TMPDIR="$W/tmp" HF_HOME="$W/cache/huggingface"
OUT="$W/out"
sec() { echo; echo "=================== $* ==================="; }

sec host
uname -a; grep PRETTY /etc/os-release; ldd --version | head -1; nproc; free -g | head -2
lspci -nn | grep -iE 'vga|display' || true
ls -l /dev/kfd /dev/dri 2>&1; id
ls -d /opt/rocm* 2>&1; cat /opt/rocm/.info/version 2>/dev/null || true
echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<unset>}"
command -v rocminfo && rocminfo 2>/dev/null | grep -m4 -E 'gfx|Marketing' || true
ldconfig -p | grep -E 'libamdhip64|librocblas|libhipblas' || echo "ldconfig: no ROCm libs"
python3 - <<'EOF'
import ctypes
for s in ("libamdhip64.so.7", "libhipblas.so.3", "librocblas.so.5"):
    try:
        ctypes.CDLL(s); print("loader resolves", s)
    except OSError as e:
        print("loader MISSING", s, e)
EOF
command -v vulkaninfo >/dev/null && vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|driverName' || echo "no vulkaninfo"
docker info --format 'docker {{.ServerVersion}}' 2>&1 | head -1

sec downloads
PRZIP="$(ls "$W"/dl/*.zip 2>/dev/null | head -1 || true)"
[ -n "$PRZIP" ] && cp "$PRZIP" "$W/zips/pr_rocm.zip" || echo "NO PR ROCm ARTIFACT"
get() { curl -fsSL --retry 3 -o "$W/zips/$1.zip" "$2" && echo "got $1 $(du -h "$W/zips/$1.zip" | cut -f1)" || echo "FAILED $1"; }
get up_rocm https://github.com/leejet/stable-diffusion.cpp/releases/download/master-813-bfbef5b/sd-master-bfbef5b-bin-Linux-Ubuntu-24.04-x86_64-rocm-7.14.0.zip
get up_vulkan https://github.com/leejet/stable-diffusion.cpp/releases/download/master-813-bfbef5b/sd-master-bfbef5b-bin-Linux-Ubuntu-24.04-x86_64-vulkan.zip
get mirror_vulkan https://github.com/unslothai/stable-diffusion.cpp/releases/download/master-813-bfbef5b-u6321a69/sd-master-813-bfbef5b-u6321a69-bin-Linux-Ubuntu-22.04-x86_64-vulkan.zip
ls -la "$W/zips"
[ -f "$W/zips/pr_rocm.zip" ] && { unzip -l "$W/zips/pr_rocm.zip" | awk 'NR>3{print $4}' | sed 's#^[^/]*/##' | awk -F/ '{print ($2==""?"(top)":$1)}' | sort | uniq -c; unzip -l "$W/zips/pr_rocm.zip" | tail -1; }

sec "studio checkout"
git clone -q --depth 1 --filter=blob:none --sparse https://github.com/unslothai/unsloth "$W/unsloth"
git -C "$W/unsloth" sparse-checkout set studio/backend/utils
git -C "$W/unsloth" log -1 --format='unsloth main %h %s'
STUDIO="$W/unsloth/studio"
NAMES="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' ${PRZIP:+"$(basename "$PRZIP")"} sd-master-bfbef5b-bin-Linux-Ubuntu-24.04-x86_64-rocm-7.14.0.zip sd-master-bfbef5b-bin-Linux-Ubuntu-24.04-x86_64-vulkan.zip sd-master-813-bfbef5b-u6321a69-bin-Linux-Ubuntu-22.04-x86_64-vulkan.zip sd-master-813-bfbef5b-u6321a69-bin-Linux-Ubuntu-22.04-x86_64.zip)"
echo "asset names: $NAMES"
python3 "$CI/studio_resolve.py" "$STUDIO" "$NAMES"

declare -A CLI
for b in pr_rocm up_rocm up_vulkan mirror_vulkan; do
  [ -f "$W/zips/$b.zip" ] || continue
  sec "extract $b with Studio's _safe_extractall"
  if c="$(python3 "$CI/studio_extract.py" "$STUDIO" "$W/zips/$b.zip" "$W/bundles/$b" 2>&1 | tail -1)" && [ -x "$c" ]; then
    CLI[$b]="$c"; echo "sd-cli: $c"; du -sh "$W/bundles/$b"
  else
    echo "EXTRACT FAILED: $c"
  fi
done
[ -n "${CLI[pr_rocm]:-}" ] && { D="$(dirname "${CLI[pr_rocm]}")"; ls -la "$D"; ls "$D/lib" | head -60; ls "$D/lib" | wc -l; ls "$D/.kpack" 2>/dev/null | wc -l; du -sh "$D/lib" "$D/.kpack" 2>/dev/null; readelf -d "${CLI[pr_rocm]}" | grep -E 'RPATH|RUNPATH|NEEDED'; }

for b in "${!CLI[@]}"; do
  c="${CLI[$b]}"; d="$(dirname "$c")"
  sec "static checks $b"
  echo "max GLIBC needed: $(objdump -T "$c" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)"
  echo "-- ldd, host env (LD_LIBRARY_PATH as Studio's runtime_env sets it):"
  LD_LIBRARY_PATH="$d" ldd "$c" | grep -E 'not found|amdhip|rocblas|hipblas|hsa|vulkan|gomp|omp' || true
  sec "--list-devices $b (host)"
  LD_LIBRARY_PATH="$d" timeout 300 "$c" --list-devices; echo "exit=$?"
done

# Hosts without a ROCm userspace (what the bundling is for): a bare container with only the GPU
# device nodes. Also a 22.04 container for the glibc floor.
KFD_GID="$(stat -c %g /dev/kfd)"; REN_GID="$(stat -c %g "$(ls /dev/dri/renderD* | head -1)")"
dock() { local img="$1" dir="$2"; shift 2
  docker run --rm --device /dev/kfd --device /dev/dri --group-add "$KFD_GID" --group-add "$REN_GID" \
    --security-opt seccomp=unconfined -e LD_LIBRARY_PATH=/b -v "$dir":/b -v "$W/models":/m:ro -v "$OUT":/o \
    "$img" "$@"; }
for b in pr_rocm up_rocm; do
  [ -n "${CLI[$b]:-}" ] || continue
  d="$(dirname "${CLI[$b]}")"
  for img in ubuntu:24.04 ubuntu:22.04; do
    sec "$b in bare $img (no ROCm userspace)"
    dock "$img" "$d" sh -c 'ls /opt/rocm 2>&1 | head -1; ldd /b/sd-cli | grep -E "not found|amdhip|rocblas" ; /b/sd-cli --list-devices; echo exit=$?'
  done
done

sec models
dl() { [ -s "$W/models/$1" ] || curl -fsSL --retry 3 -o "$W/models/$1" "$2"; ls -la "$W/models/$1"; }
dl sd15.gguf https://huggingface.co/second-state/stable-diffusion-v1-5-GGUF/resolve/main/stable-diffusion-v1-5-pruned-emaonly-Q8_0.gguf
dl zimg.gguf https://huggingface.co/leejet/Z-Image-Turbo-GGUF/resolve/main/z_image_turbo-Q4_K.gguf
dl qwen3-4b.gguf https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf
dl ae.safetensors https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors

SD15=(-m /m/sd15.gguf -p "a photograph of a red fox in the snow, highly detailed" -W 512 -H 512 --steps 20 --seed 42)
ZIMG=(--diffusion-model /m/zimg.gguf --vae /m/ae.safetensors --llm /m/qwen3-4b.gguf
      -p "a lighthouse on a rocky coast at sunset, photorealistic" --cfg-scale 1.0 --diffusion-fa
      -W 1024 -H 1024 --steps 8 --seed 42)
# run <name> <mode host|bare|shadow> <bundle> <model args...>
run() { local name="$1" mode="$2" b="$3"; shift 3
  local c="${CLI[$b]:-}"; [ -n "$c" ] || { echo "skip $name (no $b)"; return; }
  local d; d="$(dirname "$c")"
  sec "gen $name [$mode]"
  local t0=$SECONDS rc
  case "$mode" in
    host)   ( cd /; LD_LIBRARY_PATH="$d" timeout 1200 "$c" "${@//\/m\//$W/models/}" -o "$OUT/$name.png" ) > "$OUT/$name.log" 2>&1; rc=$? ;;
    shadow) ( cd /; LD_LIBRARY_PATH="$d:/opt/rocm/lib" timeout 1200 "$c" "${@//\/m\//$W/models/}" -o "$OUT/$name.png" ) > "$OUT/$name.log" 2>&1; rc=$? ;;
    bare)   dock ubuntu:24.04 "$d" timeout 1200 /b/sd-cli "$@" -o "/o/$name.png" > "$OUT/$name.log" 2>&1; rc=$? ;;
  esac
  echo "rc=$rc wall=$((SECONDS - t0))s"
  grep -iE 'rocm devices|found [0-9]+ |vulkan0|using .*backend|gfx|error|fail|abort|sampling completed|decode_first_stage completed|generate_image completed|completed, taking|total' "$OUT/$name.log" | grep -v '^\s*$' | tail -14
}
for M in SD15 ZIMG; do
  declare -n ARGS="$M"
  run "${M}_pr_rocm_host" host pr_rocm "${ARGS[@]}"
  run "${M}_pr_rocm_bare" bare pr_rocm "${ARGS[@]}"
  run "${M}_up_rocm_host" host up_rocm "${ARGS[@]}"
  run "${M}_up_rocm_bare" bare up_rocm "${ARGS[@]}"
  run "${M}_mirror_vulkan_host" host mirror_vulkan "${ARGS[@]}"
  run "${M}_up_vulkan_host" host up_vulkan "${ARGS[@]}"
  run "${M}_pr_rocm_warm" host pr_rocm "${ARGS[@]}"
  run "${M}_mirror_vulkan_warm" host mirror_vulkan "${ARGS[@]}"
  unset -n ARGS
done

sec "LD_LIBRARY_PATH shadowing (host /opt/rocm/lib after the bundle dir, as a ROCm user env would add)"
if [ -n "${CLI[pr_rocm]:-}" ] && [ -d /opt/rocm/lib ]; then
  d="$(dirname "${CLI[pr_rocm]}")"
  LD_LIBRARY_PATH="$d:/opt/rocm/lib" ldd "${CLI[pr_rocm]}" | grep -E 'amdhip|rocblas|hipblas|hsa-runtime|comgr'
  run SD15_pr_rocm_shadow shadow pr_rocm "${SD15[@]}"
fi

sec "image comparison"
python3 -m venv "$W/venv" && "$W/venv/bin/pip" -q install pillow numpy
for M in SD15 ZIMG; do
  ref="$OUT/${M}_pr_rocm_host.png"; [ -f "$ref" ] || ref="$(ls "$OUT"/${M}_*.png 2>/dev/null | head -1)"
  [ -n "$ref" ] && [ -f "$ref" ] && { echo "ref $ref"; "$W/venv/bin/python" "$CI/imgdiff.py" "$ref" "$OUT"/${M}_*.png; }
done
ls -la "$OUT"
