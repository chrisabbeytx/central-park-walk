#!/usr/bin/env python3
"""Generate procedural ambient sound loops for Central Park Walk.

Uses numpy + scipy to synthesize realistic ambient audio:
- Bird songs (FM synthesis warble, multiple species)
- Wind through trees (filtered brown noise with gusting)
- Distant city traffic (low-frequency rumble)
- Lake water (gentle filtered noise with lapping rhythm)
- Fountain splash (broadband noise with periodic bursts)
- Footstep on grass (soft thump + rustling)
- Footstep on stone (hard click + short reverb)

All files are WAV format, 44100 Hz mono, loopable.
"""

import numpy as np
from scipy import signal
from scipy.io import wavfile
import os

RATE = 44100
SOUNDS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sounds")


def normalize(audio, peak=0.85):
    """Normalize audio to peak amplitude."""
    mx = np.max(np.abs(audio))
    if mx > 0:
        audio = audio * (peak / mx)
    return audio


def brown_noise(n):
    """Generate brown noise (random walk, low-frequency emphasis)."""
    white = np.random.randn(n)
    brown = np.cumsum(white)
    # Remove DC drift
    brown -= np.linspace(brown[0], brown[-1], n)
    return brown / np.max(np.abs(brown))


def bandpass(audio, low, high, order=4):
    """Apply bandpass filter."""
    nyq = RATE / 2
    low_n = max(low / nyq, 0.001)
    high_n = min(high / nyq, 0.999)
    if low_n >= high_n:
        return audio
    b, a = signal.butter(order, [low_n, high_n], btype='band')
    return signal.filtfilt(b, a, audio)


def lowpass(audio, freq, order=4):
    """Apply lowpass filter."""
    nyq = RATE / 2
    freq_n = min(freq / nyq, 0.999)
    b, a = signal.butter(order, freq_n, btype='low')
    return signal.filtfilt(b, a, audio)


def highpass(audio, freq, order=4):
    """Apply highpass filter."""
    nyq = RATE / 2
    freq_n = max(freq / nyq, 0.001)
    b, a = signal.butter(order, freq_n, btype='high')
    return signal.filtfilt(b, a, audio)


def crossfade_loop(audio, fade_samples=4410):
    """Make audio seamlessly loopable with crossfade."""
    n = len(audio)
    if n < fade_samples * 2:
        return audio
    fade_in = np.linspace(0, 1, fade_samples)
    fade_out = np.linspace(1, 0, fade_samples)
    # Crossfade end into beginning
    audio[:fade_samples] = audio[:fade_samples] * fade_in + audio[-fade_samples:] * fade_out
    audio = audio[:n - fade_samples]
    return audio


def save_wav(filename, audio):
    """Save as 16-bit WAV."""
    path = os.path.join(SOUNDS_DIR, filename)
    audio = normalize(audio)
    audio_16 = np.clip(audio * 32767, -32768, 32767).astype(np.int16)
    wavfile.write(path, RATE, audio_16)
    print(f"  OK  {filename} ({len(audio)/RATE:.1f}s, {os.path.getsize(path)/1024:.0f} KB)")


# ---- Bird songs ----

def bird_chirp(t, freq=3200, mod_freq=18, mod_depth=800, amp=1.0):
    """Single FM-synthesized bird chirp."""
    modulator = np.sin(2 * np.pi * mod_freq * t) * mod_depth
    return amp * np.sin(2 * np.pi * (freq + modulator) * t)


def generate_birds(duration=30.0):
    """Layered bird chorus: multiple species, varied timing."""
    n = int(duration * RATE)
    out = np.zeros(n)
    rng = np.random.RandomState(42)

    # Species: (base_freq, mod_freq, mod_depth, chirp_dur, gap_range)
    species = [
        (3200, 18, 800, 0.12, (0.3, 1.5)),   # robin-like trill
        (4500, 25, 600, 0.08, (0.5, 2.0)),   # sparrow-like chip
        (2800, 12, 1200, 0.20, (1.0, 3.0)),  # cardinal-like whistle
        (5500, 35, 400, 0.05, (0.2, 0.8)),   # chickadee-like
        (2200, 8, 1500, 0.30, (2.0, 5.0)),   # wood thrush-like (slower)
    ]

    for sp_i, (base_f, mod_f, mod_d, chirp_d, gap_r) in enumerate(species):
        pos = rng.uniform(0, 2.0)  # stagger start
        amp = rng.uniform(0.15, 0.35)
        while pos < duration - chirp_d:
            # Sometimes do a phrase of 2-5 chirps
            phrase_len = rng.randint(1, 6)
            for _ in range(phrase_len):
                if pos >= duration - chirp_d:
                    break
                chirp_n = int(chirp_d * RATE)
                start = int(pos * RATE)
                if start + chirp_n > n:
                    break
                t = np.arange(chirp_n) / RATE
                # Frequency variation per chirp
                f_var = base_f * rng.uniform(0.9, 1.1)
                chirp = bird_chirp(t, f_var, mod_f, mod_d, amp)
                # Envelope: quick attack, longer decay
                env = np.exp(-t / (chirp_d * 0.4))
                env[:int(chirp_n * 0.05)] *= np.linspace(0, 1, int(chirp_n * 0.05))
                chirp *= env
                out[start:start + chirp_n] += chirp
                pos += chirp_d + rng.uniform(0.05, 0.15)  # within-phrase gap
            pos += rng.uniform(*gap_r)  # between-phrase gap

    # Add subtle high-frequency ambient (insect hum)
    t_full = np.arange(n) / RATE
    insects = np.sin(2 * np.pi * 6800 * t_full) * 0.02
    insects *= (1 + 0.5 * np.sin(2 * np.pi * 0.3 * t_full))  # slow modulation
    out += insects

    out = bandpass(out, 1500, 8000)
    return crossfade_loop(out)


# ---- Wind ----

def generate_wind(duration=20.0):
    """Wind through tree canopy: filtered noise with gusting."""
    n = int(duration * RATE)
    # Base: brown noise (low-frequency emphasis)
    base = brown_noise(n)

    # Gust envelope: slow random modulation
    t = np.arange(n) / RATE
    gust1 = 0.5 + 0.5 * np.sin(2 * np.pi * 0.08 * t + 1.3)
    gust2 = 0.5 + 0.5 * np.sin(2 * np.pi * 0.13 * t + 0.7)
    gust3 = 0.5 + 0.5 * np.sin(2 * np.pi * 0.03 * t)
    envelope = 0.3 + 0.7 * gust1 * gust2 * gust3

    # Leaf rustle: higher frequency filtered noise
    rustle = np.random.randn(n) * 0.3
    rustle = bandpass(rustle, 2000, 6000)
    rustle *= envelope * 0.5

    # Main wind body
    wind = bandpass(base, 80, 800) * envelope
    wind += bandpass(base, 400, 2000) * envelope * 0.3

    out = wind + rustle
    return crossfade_loop(out)


# ---- City ----

def generate_city(duration=25.0):
    """Distant city ambience: low rumble, occasional horn/siren hints."""
    n = int(duration * RATE)

    # Base urban rumble: very low frequency noise
    rumble = brown_noise(n)
    rumble = lowpass(rumble, 300)

    # Traffic hum: mid-low drone
    t = np.arange(n) / RATE
    drone = np.sin(2 * np.pi * 85 * t) * 0.1
    drone += np.sin(2 * np.pi * 120 * t) * 0.05
    drone += np.sin(2 * np.pi * 170 * t) * 0.03
    # Modulate with slow variation
    drone *= 0.7 + 0.3 * np.sin(2 * np.pi * 0.05 * t)

    # Occasional distant horn-like bleat
    rng = np.random.RandomState(99)
    horns = np.zeros(n)
    pos = 3.0
    while pos < duration - 1.0:
        horn_dur = rng.uniform(0.3, 0.8)
        horn_n = int(horn_dur * RATE)
        start = int(pos * RATE)
        if start + horn_n > n:
            break
        ht = np.arange(horn_n) / RATE
        freq = rng.uniform(280, 450)
        horn = np.sin(2 * np.pi * freq * ht) * 0.04
        horn *= np.exp(-ht / (horn_dur * 0.6))
        horn[:int(horn_n * 0.1)] *= np.linspace(0, 1, int(horn_n * 0.1))
        horns[start:start + horn_n] += horn
        pos += rng.uniform(4.0, 12.0)

    horns = lowpass(horns, 500)  # muffle — it's distant

    out = rumble * 0.4 + drone + horns
    out = lowpass(out, 600)  # everything is muffled by distance
    return crossfade_loop(out)


# ---- Water ----

def generate_lake(duration=20.0):
    """Gentle lake water: slow lapping rhythm with filtered noise."""
    n = int(duration * RATE)
    t = np.arange(n) / RATE

    # Base: filtered noise
    noise = np.random.randn(n)
    water = bandpass(noise, 200, 3000) * 0.3

    # Lapping rhythm: gentle periodic swells
    lap1 = 0.5 + 0.5 * np.sin(2 * np.pi * 0.25 * t)
    lap2 = 0.5 + 0.5 * np.sin(2 * np.pi * 0.18 * t + 1.0)
    lap3 = 0.5 + 0.5 * np.sin(2 * np.pi * 0.4 * t + 2.3)
    envelope = lap1 * lap2 * 0.6 + lap3 * 0.4

    water *= envelope

    # Subtle deeper resonance
    deep = bandpass(noise, 80, 250) * 0.15 * (0.5 + 0.5 * lap1)
    out = water + deep
    return crossfade_loop(out)


def generate_fountain(duration=15.0):
    """Fountain: splashing broadband noise with periodic spray bursts."""
    n = int(duration * RATE)
    t = np.arange(n) / RATE

    # Continuous splash base
    noise = np.random.randn(n)
    splash = bandpass(noise, 500, 6000) * 0.4

    # Periodic spray pulses (multiple jets)
    pulse1 = 0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t)
    pulse2 = 0.7 + 0.3 * np.sin(2 * np.pi * 0.7 * t + 0.8)
    splash *= pulse1 * pulse2

    # Water impact: lower frequency component
    impact = bandpass(noise, 100, 800) * 0.25 * pulse1

    out = splash + impact
    return crossfade_loop(out)


# ---- Footsteps ----

def generate_footstep_grass():
    """Single grass footstep: soft thump + leaf/grass rustling."""
    dur = 0.4
    n = int(dur * RATE)
    t = np.arange(n) / RATE

    # Soft thump (low freq)
    thump = np.sin(2 * np.pi * 60 * t) * np.exp(-t / 0.04)

    # Grass rustle (filtered noise burst)
    rustle = np.random.randn(n) * np.exp(-t / 0.08)
    rustle = bandpass(rustle, 1500, 5000)

    out = thump * 0.5 + rustle * 0.7
    # Quick attack
    out[:int(0.005 * RATE)] *= np.linspace(0, 1, int(0.005 * RATE))
    return out


def generate_footstep_stone():
    """Single stone footstep: hard click + short decay."""
    dur = 0.35
    n = int(dur * RATE)
    t = np.arange(n) / RATE

    # Hard click (broadband impulse with resonance)
    click = np.random.randn(n) * np.exp(-t / 0.015)
    click = bandpass(click, 300, 4000)

    # Stone resonance
    res = np.sin(2 * np.pi * 280 * t) * np.exp(-t / 0.03) * 0.3
    res += np.sin(2 * np.pi * 450 * t) * np.exp(-t / 0.02) * 0.2

    out = click * 0.6 + res
    out[:int(0.002 * RATE)] *= np.linspace(0, 1, int(0.002 * RATE))
    return out


def main():
    os.makedirs(SOUNDS_DIR, exist_ok=True)

    # Remove old stub files
    for f in os.listdir(SOUNDS_DIR):
        if f.endswith('.ogg'):
            path = os.path.join(SOUNDS_DIR, f)
            if os.path.getsize(path) < 100:  # stub files are ~58 bytes
                os.remove(path)
                print(f"  DEL {f} (stub)")

    print("Generating ambient sounds...")
    save_wav("birds_daytime.wav", generate_birds(30.0))
    save_wav("wind_trees.wav", generate_wind(20.0))
    save_wav("city_distant.wav", generate_city(25.0))
    save_wav("water_lake.wav", generate_lake(20.0))
    save_wav("water_fountain.wav", generate_fountain(15.0))
    save_wav("footstep_grass.wav", generate_footstep_grass())
    save_wav("footstep_stone.wav", generate_footstep_stone())

    print(f"\nDone. WAV files in {SOUNDS_DIR}/")
    print("Godot AudioStreamPlayer supports WAV natively.")


if __name__ == "__main__":
    main()
