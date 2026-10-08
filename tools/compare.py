import sys, numpy as np
# compare.py <ref_prefix> <test_prefix> <label>
a, b, label = sys.argv[1:4]
ra = np.fromfile(a + ".rgb", np.uint8); rb = np.fromfile(b + ".rgb", np.uint8)
if ra.size != rb.size:
    print(f"{label}: video size differs {ra.size} vs {rb.size}")
else:
    diff = np.abs(ra.astype(np.int16) - rb.astype(np.int16))
    mse = float((diff.astype(np.float64) ** 2).mean())
    psnr = float("inf") if mse == 0 else 10 * np.log10(255 ** 2 / mse)
    print(f"{label}: video bit-identical={bool((diff == 0).all())} differing_bytes={int((diff != 0).sum())}/{ra.size} max_abs={int(diff.max())} psnr={psnr:.2f}dB")
try:
    fa = np.fromfile(a + ".f32", np.float32); fb = np.fromfile(b + ".f32", np.float32)
    if fa.size != fb.size:
        print(f"{label}: audio size differs {fa.size} vs {fb.size}")
    else:
        err = fa.astype(np.float64) - fb.astype(np.float64)
        snr = float("inf") if not err.any() else 10 * np.log10((fa.astype(np.float64) ** 2).sum() / (err ** 2).sum())
        print(f"{label}: audio bit-identical={not err.any()} snr={snr:.2f}dB max_abs={float(np.abs(err).max()):.3e} nan={int(np.isnan(fb).sum())}")
except FileNotFoundError as e:
    print(f"{label}: audio missing {e}")
