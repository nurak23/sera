"""
coexistence_spectrogram.py

Reads a real HackRF complex16s (interleaved int16 I/Q) capture and
produces a spectrogram figure. Used for the paper's Thread/BLE
coexistence analysis (Section: RF coexistence at 2.425 GHz).

Capture parameters (from the HackRF acquisition GUI, COEXISTENCE.png):
  Device: HackRF
  Center frequency: 2.425 GHz
  Sample rate: 20.0 MSps
  Bandwidth: 20.0 MHz
  RF Gain: 14, IF Gain: 16, Baseband gain: 14
  Bias tee: off, DC correction: on
"""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy import signal

def load_complex16s(path, max_samples=None, offset_samples=0):
    # Read only the requested slice directly from disk (4 bytes/sample:
    # int16 I + int16 Q) to avoid loading multi-hundred-MB files whole.
    itemsize = 4  # bytes per complex sample on disk
    with open(path, "rb") as f:
        f.seek(offset_samples * itemsize)
        count = -1 if max_samples is None else max_samples * 2
        raw = np.fromfile(f, dtype=np.int16, count=count)
    i = raw[0::2].astype(np.float32)
    q = raw[1::2].astype(np.float32)
    del raw
    return (i + 1j * q) / 32768.0

def main():
    path = sys.argv[1]
    out_png = sys.argv[2]
    fc_hz = float(sys.argv[3]) if len(sys.argv) > 3 else 2.425e9
    fs = float(sys.argv[4]) if len(sys.argv) > 4 else 20e6
    title = sys.argv[5] if len(sys.argv) > 5 else "Spectrogram"
    max_dur_s = float(sys.argv[6]) if len(sys.argv) > 6 else 0.5

    max_samples = int(max_dur_s * fs)
    x = load_complex16s(path, max_samples=max_samples)
    n_total = len(x)
    duration_s = n_total / fs
    print(f"Loaded {n_total} complex samples, {duration_s:.3f} s at {fs/1e6:.1f} MSps (window of full capture)")

    nperseg = 2048
    noverlap = nperseg // 4
    f, t, Sxx = signal.spectrogram(
        x, fs=fs, window="hann", nperseg=nperseg, noverlap=noverlap,
        return_onesided=False, scaling="density", mode="psd",
    )
    del x
    f = np.fft.fftshift(f)
    Sxx = np.fft.fftshift(Sxx, axes=0)
    Sxx_db = 10 * np.log10(Sxx + 1e-20)

    freq_mhz = (fc_hz + f) / 1e6

    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    vmax = np.percentile(Sxx_db, 99.5)
    vmin = vmax - 60
    pcm = ax.pcolormesh(t, freq_mhz, Sxx_db, shading="auto", cmap="viridis",
                         vmin=vmin, vmax=vmax)
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Frequency (MHz)")
    ax.set_title(title)
    cbar = fig.colorbar(pcm, ax=ax)
    cbar.set_label("Power spectral density (dB, arb. ref.)")
    fig.tight_layout()
    fig.savefig(out_png, dpi=160)
    print(f"Wrote {out_png}")

    # Also emit summary stats used in the paper text
    total_bw_mhz = fs / 1e6
    print(f"SUMMARY duration_s={duration_s:.3f} total_bw_mhz={total_bw_mhz:.1f} "
          f"fc_mhz={fc_hz/1e6:.3f} n_samples={n_total}")

if __name__ == "__main__":
    main()
