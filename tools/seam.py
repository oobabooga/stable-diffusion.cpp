import sys
import numpy as np
from PIL import Image
# seam score: largest mean absolute difference along any single row or column, vs reference
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.float64)
b = np.asarray(Image.open(sys.argv[2]).convert("RGB")).astype(np.float64)
d = np.abs(a - b).mean(axis=2)
cols = d.mean(axis=0); rows = d.mean(axis=1)
print(f"mean_abs={d.mean():.3f} worst_col={cols.max():.2f}@{cols.argmax()} worst_row={rows.max():.2f}@{rows.argmax()} seam={max(cols.max(), rows.max()):.2f} identical={np.array_equal(a,b)}")
