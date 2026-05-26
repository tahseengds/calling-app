"""Tiny WAV generator for the bundled notification sounds.

Run once after cloning the repo, or any time you tweak the catalog in
lib/features/settings/domain/models/notification_preferences.dart:

    python flutter_app/assets/sounds/notifications/_generate.py

Each clip is ≤ 60 KB, mono, 22 050 Hz, 16-bit PCM — small enough to
ship in the APK without bloating it.
"""
from __future__ import annotations

import math
import os
import struct
import wave

SAMPLE_RATE = 22050
HERE = os.path.dirname(os.path.abspath(__file__))


def _envelope(t: float, attack: float, decay: float) -> float:
    if t < attack:
        return t / attack
    return max(0.0, 1.0 - (t - attack) / decay)


def _write(name: str, samples: list[float]) -> None:
    path = os.path.join(HERE, f"{name}.wav")
    # Normalise to peak 0.9 to avoid clipping.
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.9 / peak
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
        for s in samples
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(frames)
    print(f"  {name}.wav  ({len(frames) // 1024:>3} KB, {len(samples) / SAMPLE_RATE:.2f}s)")


def _tone(
    freq: float,
    duration: float,
    *,
    start: float = 0.0,
    attack: float = 0.005,
    decay: float | None = None,
    harmonics: tuple[tuple[float, float], ...] = ((2.0, 0.3), (3.0, 0.1)),
) -> list[tuple[float, float]]:
    """Returns list of (t, sample) pairs that can be summed into a track."""
    decay = decay if decay is not None else duration
    n = int(duration * SAMPLE_RATE)
    out: list[tuple[float, float]] = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, attack, decay)
        v = math.sin(2 * math.pi * freq * t)
        for mult, amp in harmonics:
            v += amp * math.sin(2 * math.pi * freq * mult * t)
        out.append((start + t, v * env))
    return out


def _mix(layers: list[list[tuple[float, float]]], total: float) -> list[float]:
    buf = [0.0] * int(total * SAMPLE_RATE)
    for layer in layers:
        for t, v in layer:
            idx = int(t * SAMPLE_RATE)
            if 0 <= idx < len(buf):
                buf[idx] += v
    return buf


# ── Catalog ───────────────────────────────────────────────────────────────

def make_chime() -> None:
    # Two ascending bell-like notes.
    _write(
        "chime",
        _mix(
            [
                _tone(659.25, 0.45),  # E5
                _tone(987.77, 0.55, start=0.18),  # B5
            ],
            total=0.75,
        ),
    )


def make_pop() -> None:
    # Short high-frequency click.
    _write(
        "pop",
        _mix(
            [_tone(1500, 0.12, attack=0.001, decay=0.10, harmonics=((2.0, 0.2),))],
            total=0.15,
        ),
    )


def make_ding() -> None:
    # Single bell note with slow decay.
    _write(
        "ding",
        _mix(
            [_tone(880.0, 0.7, attack=0.003, harmonics=((2.0, 0.45), (3.0, 0.2), (4.0, 0.1)))],
            total=0.75,
        ),
    )


def make_note() -> None:
    # Piano-ish G4 with a softer harmonic stack.
    _write(
        "note",
        _mix(
            [_tone(392.0, 0.6, attack=0.008, harmonics=((2.0, 0.5), (3.0, 0.25), (5.0, 0.05)))],
            total=0.65,
        ),
    )


def make_bubble() -> None:
    # Low pop that rises slightly (frequency sweep simulated by overlap).
    _write(
        "bubble",
        _mix(
            [
                _tone(220.0, 0.15, attack=0.005, decay=0.13),
                _tone(330.0, 0.12, start=0.05, attack=0.005, decay=0.10),
            ],
            total=0.22,
        ),
    )


def make_pulse() -> None:
    # Three quick beeps (alarm-style).
    layers = []
    for k in range(3):
        layers.append(_tone(1046.5, 0.08, start=k * 0.12, attack=0.002, decay=0.06))
    _write("pulse", _mix(layers, total=0.45))


def main() -> None:
    print(f"Writing bundled notification sounds to {HERE}")
    make_chime()
    make_pop()
    make_ding()
    make_note()
    make_bubble()
    make_pulse()
    print("Done. Don't forget to bump the catalog if you renamed any files.")


if __name__ == "__main__":
    main()
