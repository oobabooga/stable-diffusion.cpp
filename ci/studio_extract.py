"""Extract a bundle exactly the way Studio's installer does, then report what Studio would run."""
import sys
import zipfile
from pathlib import Path

studio, zpath, dest = sys.argv[1], sys.argv[2], Path(sys.argv[3])
sys.path.insert(0, studio)
import install_sd_cpp_prebuilt as m  # noqa: E402

dest.mkdir(parents = True, exist_ok = True)
with zipfile.ZipFile(zpath) as zf:
    m._safe_extractall(zf, dest)
cli = m._locate_sd_cli(dest)
srv = m._locate_sd_server(dest)
assert cli, "studio found no sd-cli"
m._make_executable(cli)
if srv:
    m._make_executable(srv)
print(cli)
