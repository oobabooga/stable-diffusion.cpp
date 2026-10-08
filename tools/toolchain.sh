# sourced: toolchain.sh <vulkan|hip>; sets SD_CMAKE_FLAGS and GGML_CMAKE_FLAGS
case "$1" in
vulkan)
  if ! command -v glslc >/dev/null; then
    if sudo -n true 2>/dev/null; then
      sudo apt-get update -qq && sudo apt-get install -y -qq libvulkan-dev glslc mesa-vulkan-drivers vulkan-tools spirv-headers >/dev/null
    else
      curl -sSL -o "$TMPDIR/vk.tar.xz" https://sdk.lunarg.com/sdk/download/latest/linux/vulkan_sdk.tar.xz
      mkdir -p "$TMPDIR/vk" && tar -xf "$TMPDIR/vk.tar.xz" -C "$TMPDIR/vk"
      set +u; . "$(ls -d "$TMPDIR"/vk/*/ | head -1)setup-env.sh"; set -u
    fi
  fi
  glslc --version | head -1
  ls /usr/share/vulkan/icd.d /etc/vulkan/icd.d 2>/dev/null || true
  vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverName|apiVersion" | head -6 || true
  SD_CMAKE_FLAGS="-DSD_VULKAN=ON"; GGML_CMAKE_FLAGS="-DGGML_VULKAN=ON"; DEV=Vulkan0 ;;
hip)
  if [ -x /opt/rocm/bin/hipcc ]; then ROCM=/opt/rocm; else
    pip install -q --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ "rocm[libraries,devel]"
    ROCM="$(rocm-sdk path --root)"; fi
  export PATH="$ROCM/bin:$ROCM/llvm/bin:$PATH" LD_LIBRARY_PATH="$ROCM/lib:${LD_LIBRARY_PATH:-}"
  HIPF="-DGPU_TARGETS=gfx1151 -DAMDGPU_TARGETS=gfx1151 -DCMAKE_HIP_COMPILER=$ROCM/llvm/bin/clang++ -DCMAKE_PREFIX_PATH=$ROCM -DROCM_PATH=$ROCM -DHIP_PLATFORM=amd"
  SD_CMAKE_FLAGS="-DSD_HIPBLAS=ON $HIPF"; GGML_CMAKE_FLAGS="-DGGML_HIP=ON $HIPF"; DEV=ROCm0 ;;
esac
