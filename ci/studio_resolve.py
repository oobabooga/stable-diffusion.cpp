"""What Studio's pure resolver picks for a Linux x86_64 ROCm host from a given asset list."""
import json
import sys

sys.path.insert(0, sys.argv[1])
import install_sd_cpp_prebuilt as m  # noqa: E402

names = json.loads(sys.argv[2])
for accel in ("rocm", "vulkan", "auto"):
    print(accel, "->", m.resolve_release_asset(names, system = "Linux", machine = "x86_64", accelerator = accel))
