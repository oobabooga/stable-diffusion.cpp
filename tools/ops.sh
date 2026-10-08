#!/bin/bash
# ops.sh <vulkan|hip>: test-backend-ops for the PR's ggml (patches 0001-0005) plus H3-shaped CONV_2D_DW cases
set -euxo pipefail
TOOLS="$(cd "$(dirname "$0")" && pwd)"
W="$RUNNER_TEMP/ops"; mkdir -p "$W"/{tmp,cache/pip}
export TMPDIR="$W/tmp" PIP_CACHE_DIR="$W/cache/pip"
python3 -m venv "$W/venv"; . "$W/venv/bin/activate"; pip install -q cmake ninja
. "$TOOLS/toolchain.sh" "$1"
cd "$W"; git clone -q https://github.com/unslothai/stable-diffusion.cpp src; cd src
git fetch -q origin perf/h3-gguf-speed-v3; git checkout -q 338079e; git submodule update --init --depth 1 ggml
for p in scripts/unsloth/ggml-patches/*.patch; do git -C ggml apply "../$p"; done
python3 "$TOOLS/h3_dw_tests.py" ggml/tests/test-backend-ops.cpp
cmake -S ggml -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_BUILD_TESTS=ON -DGGML_NATIVE=OFF $GGML_CMAKE_FLAGS
cmake --build build -j 32 --target test-backend-ops
for op in CONV_2D_DW ROPE_PE_PERMUTE RMS_NORM; do ./build/bin/test-backend-ops -b $DEV -o $op 2>&1 | grep -vE "^\s*$" | grep -E "conv_dw_h3|CONV_2D_DW|ROPE_PE|not supported|FAIL|passed|Backend|OK" | tail -60 || true; done
