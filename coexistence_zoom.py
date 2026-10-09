import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy import signal

def load_complex16s(path, max_samples=None, offset_samples=0):
    itemsize = 4
    with open(path, "rb") as f:
        f.seek(offset_samples * itemsize)
        count = -1 if max_samples is None else max_samples * 2
        raw = np.fromfile(f, dtype=np.int16, count=count)
    i = raw[0::2].astype(np.float32)
    q = raw[1::2].astype(np.float32)
    del raw
    return (i + 1j * q) / 32768.0

path = sys.argv[1]
out_png = sys.argv[2]
fc_hz = 2.425e9
fs = 20e6
offset_s = float(sys.argv[3])
dur_s = float(sys.argv[4])

offset_samples = int(offset_s * fs)
n = int(dur_s * fs)
x = load_complex16s(path, max_samples=n, offset_samples=offset_samples)
print(f"Loaded {len(x)} samples starting at {offset_s}s, duration {dur_s}s")

nperseg = 512
noverlap = nperseg - 64
f, t, Sxx = signal.spectrogram(x, fs=fs, window="hann", nperseg=nperseg,
                                noverlap=noverlap, return_onesided=False,
                                scaling="density", mode="psd")
f = np.fft.fftshift(f)
Sxx = np.fft.fftshift(Sxx, axes=0)
Sxx_db = 10*np.log10(Sxx+1e-20)
freq_mhz = (fc_hz+f)/1e6

fig, ax = plt.subplots(figsize=(7.5,4.2))
vmax = np.percentile(Sxx_db, 99.7)
pcm = ax.pcolormesh(t*1000+offset_s*1000, freq_mhz, Sxx_db, shading="auto",
                     cmap="viridis", vmin=vmax-50, vmax=vmax)
ax.set_xlabel("Time (ms)")
ax.set_ylabel("Frequency (MHz)")
ax.set_title(f"Zoomed burst, t={offset_s*1000:.1f}-{(offset_s+dur_s)*1000:.1f} ms")
cbar = fig.colorbar(pcm, ax=ax); cbar.set_label("PSD (dB, arb.)")
fig.tight_layout()
fig.savefig(out_png, dpi=160)
print("Wrote", out_png)

# Estimate occupied bandwidth at the burst peak time
peak_col = np.argmax(Sxx_db.max(axis=0))
col = Sxx_db[:, peak_col]
thresh = col.max() - 10  # -10 dB from peak
above = freq_mhz[col > thresh]
if len(above) > 0:
    print(f"SUMMARY peak_time_ms={t[peak_col]*1000+offset_s*1000:.3f} "
          f"occupied_bw_MHz={above.max()-above.min():.3f} "
          f"center_MHz={ (above.max()+above.min())/2:.3f}")
