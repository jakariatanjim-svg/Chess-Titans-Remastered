#!/usr/bin/env python3
"""Generate the game's short original, synthesized interface sounds."""
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
RATE = 22050
random.seed(19)

SOUNDS = {
    "select": (0.11, [(1120, 0.040), (1760, 0.024)], 0.11, 0.010),
    "move": (0.19, [(430, 0.075), (710, 0.038), (1030, 0.018)], 0.18, 0.020),
    "capture": (0.29, [(118, 0.14), (244, 0.085), (520, 0.028)], 0.30, 0.050),
    "check": (0.38, [(523, 0.17), (784, 0.13), (1047, 0.09)], 0.055, 0.006),
    "menu": (0.15, [(640, 0.055), (960, 0.027)], 0.08, 0.008),
}


def generate(name: str, duration: float, tones: list[tuple[float, float]], noise_level: float, click: float) -> None:
    total = int(RATE * duration)
    frames = bytearray()
    for index in range(total):
        t = index / RATE
        sample = 0.0
        for frequency, decay in tones:
            envelope = math.exp(-t / decay)
            sample += math.sin(2.0 * math.pi * frequency * t) * envelope
            sample += 0.19 * math.sin(2.0 * math.pi * frequency * 2.01 * t) * envelope
        attack = min(1.0, t / 0.003)
        release = min(1.0, (duration - t) / 0.018)
        envelope = max(0.0, attack) * max(0.0, release)
        sample *= envelope
        sample += (random.random() * 2.0 - 1.0) * noise_level * math.exp(-t / 0.035) * envelope
        if click > 0:
            sample += (random.random() * 2.0 - 1.0) * click * math.exp(-t / 0.004)
        sample = math.tanh(sample * 0.55)
        frames.extend(struct.pack("<h", int(max(-1.0, min(1.0, sample)) * 32767)))
    with wave.open(str(OUT / f"{name}.wav"), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(frames)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for sound_name, params in SOUNDS.items():
        generate(sound_name, *params)
    print(f"Generated {len(SOUNDS)} original SFX in {OUT}")
