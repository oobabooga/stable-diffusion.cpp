import sys, os, hashlib, wave
import numpy as np
from PIL import Image
root = sys.argv[1]
def frames(d):
    return sorted(f for f in os.listdir(d) if f.endswith('.png'))
def wavs(d):
    return sorted(f for f in os.listdir(d) if f.endswith('.wav'))
def read_wav(p):
    with wave.open(p) as w:
        b = w.readframes(w.getnframes()); sw = w.getsampwidth()
    return np.frombuffer(b, dtype={2: np.int16, 4: np.int32}.get(sw, np.int16)).astype(np.float64)
def stats(a):
    d = os.path.join(root, a)
    if not os.path.isdir(d): return f"{a}: MISSING"
    fs = frames(d)
    if not fs: return f"{a}: no frames"
    x = np.stack([np.asarray(Image.open(os.path.join(d, f)), dtype=np.float64) for f in fs[::max(1, len(fs)//4)]])
    return f"{a}: {len(fs)} frames, {len(wavs(d))} wav, mean {x.mean():.1f} std {x.std():.1f}"
def cmp(a, b):
    da, db = os.path.join(root, a), os.path.join(root, b)
    if not (os.path.isdir(da) and os.path.isdir(db)): return f"{a} vs {b}: missing"
    fa, fb = frames(da), frames(db)
    if not fa or fa != fb: return f"{a} vs {b}: frame lists differ ({len(fa)} vs {len(fb)})"
    same = 0; mses = []; maxd = 0
    for f in fa:
        x = np.asarray(Image.open(os.path.join(da, f)), dtype=np.float64)
        y = np.asarray(Image.open(os.path.join(db, f)), dtype=np.float64)
        same += int(np.array_equal(x, y)); mses.append(((x - y) ** 2).mean()); maxd = max(maxd, np.abs(x - y).max())
    m = float(np.mean(mses)); psnr = float('inf') if m == 0 else 10 * np.log10(255 ** 2 / m)
    s = f"{a} vs {b}: video {'BIT-IDENTICAL' if same == len(fa) else 'DIFFERS'} {same}/{len(fa)} frames, PSNR {psnr:.2f} dB, max|d| {maxd:.0f}"
    wa, wb = wavs(da), wavs(db)
    if wa and wa == wb:
        x = read_wav(os.path.join(da, wa[0])); y = read_wav(os.path.join(db, wb[0]))
        if x.shape == y.shape:
            e = ((x - y) ** 2).sum(); snr = float('inf') if e == 0 else 10 * np.log10((x ** 2).sum() / e)
            s += f"; audio {'BIT-IDENTICAL' if e == 0 else 'DIFFERS'} SNR {snr:.1f} dB"
        else:
            s += f"; audio length differs {x.shape} {y.shape}"
    else:
        s += f"; audio files {wa} vs {wb}"
    return s
args = sys.argv[2:]
for a in sorted(set(x for p in args for x in p.split(':'))): print(stats(a))
for p in args:
    a, b = p.split(':'); print(cmp(a, b))
