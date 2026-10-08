import sys
import numpy as np
from PIL import Image

ref = np.asarray(Image.open(sys.argv[1]).convert("RGB"), dtype = np.float64)
for p in sys.argv[2:]:
    try:
        x = np.asarray(Image.open(p).convert("RGB"), dtype = np.float64)
    except Exception as e:  # noqa: BLE001
        print(f"{p}: unreadable ({e})")
        continue
    if x.shape != ref.shape:
        print(f"{p}: shape {x.shape} vs {ref.shape}")
        continue
    mse = ((x - ref) ** 2).mean()
    psnr = float("inf") if mse == 0 else 10 * np.log10(255 ** 2 / mse)
    print(f"{p}: mean|d|={np.abs(x - ref).mean():.3f} psnr={psnr:.2f}dB std={x.std():.1f}")
