"""Makes the world's sounds in this folder: footsteps, engines, wind, music.

Two kinds of file come out of it, both CC0 (see assets/LICENSES.md):

* Cut from Kenney's CC0 packs (Impact Sounds, Sci-Fi Sounds, kenney.nl):
  the footsteps ("step_<ground>_N") and the engine loops ("engine_<kind>").
  Pass the folder the packs' .ogg files were put in with --kenney; without
  it those files are left as they are.
* Made here from nothing but code (no samples, nothing to credit): the
  cold wind ("wind_cold") and the plaza's music ("music_plaza").

Run with plain Python 3 and numpy; it writes .ogg through ffmpeg
(libvorbis) beside itself.

    python3 assets/sounds/world/make_world_sounds.py [--kenney DIR] [names]

names: steps, engines, wind, music (all four when none is given).
"""

import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))


# --------------------------------------------------------------------------
# Files in and out
# --------------------------------------------------------------------------

def read(path, sr):
    """Any file ffmpeg reads, as mono float samples at `sr`."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1",
            "-ar", str(sr), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def write_ogg(name, x, sr, quality=4):
    """`x` mono (n) or stereo (n, 2), written as <name>.ogg beside this script."""
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32000).astype(np.int16)
    channels = 1 if pcm.ndim == 1 else pcm.shape[1]
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "out.wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(channels)
            w.setsampwidth(2)
            w.setframerate(sr)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav_path, "-c:a", "libvorbis",
                "-q:a", str(quality), os.path.join(HERE, name + ".ogg")], check=True)
    print("wrote", name + ".ogg")


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x / m * peak


def fft_filter(x, sr, low=0.0, high=None, slope=2.0):
    """A gentle band (no ringing): each side falls off as (f/edge)^slope."""
    spec = np.fft.rfft(x, axis=0)
    f = np.fft.rfftfreq(x.shape[0], 1.0 / sr)
    gain = np.ones_like(f)
    if low > 0.0:
        gain *= 1.0 / (1.0 + (low / np.maximum(f, 1e-3)) ** (2 * slope))
    if high is not None:
        gain *= 1.0 / (1.0 + (f / high) ** (2 * slope))
    if spec.ndim == 2:
        gain = gain[:, None]
    return np.fft.irfft(spec * gain, n=x.shape[0], axis=0)


def trim(x, sr, floor=0.01, tail=0.03):
    """Cuts the silence off both ends, leaving `tail` s of fade after."""
    loud = np.nonzero(np.abs(x) > floor * np.max(np.abs(x)))[0]
    if loud.size == 0:
        return x
    start = max(loud[0] - int(0.002 * sr), 0)
    end = min(loud[-1] + int(tail * sr), len(x))
    y = x[start:end].copy()
    fade = min(int(tail * sr), len(y))
    y[-fade:] *= np.linspace(1.0, 0.0, fade)
    return y


def seam_loop(x, sr, fade=0.4):
    """A clip that loops with no click: its tail crossfaded into its head."""
    n = int(fade * sr)
    head = x[:n]
    tail = x[-n:]
    k = np.linspace(0.0, 1.0, n)
    out = x[:-n].copy()
    out[:n] = head * np.sqrt(k) + tail * np.sqrt(1.0 - k)
    return out


# --------------------------------------------------------------------------
# Footsteps and engines, cut from Kenney's CC0 packs
# --------------------------------------------------------------------------

STEP_SR = 22050

## Each ground's footsteps: (Kenney files it is cut from, how it is shaped).
STEPS = {
    # Concrete, metal decks, rock, packed salt, ice: a short hard tap.
    "hard": ("footstep_concrete_00%d", "tap"),
    # Ash, dirt and gravel: the tap dulled, with a little grit under it.
    "dirt": ("footstep_concrete_00%d", "dirt"),
    "snow": ("footstep_snow_00%d", "plain"),
    # Grass, moss and mud: a soft rustle.
    "soft": ("footstep_grass_00%d", "soft"),
    "wood": ("footstep_wood_00%d", "plain"),
}


def make_steps(kenney):
    for ground, (pattern, shape) in STEPS.items():
        for i in range(5):
            x = read(os.path.join(kenney, pattern % i + ".ogg"), STEP_SR)
            if shape == "dirt":
                grit = read(os.path.join(kenney, "footstep_grass_00%d.ogg" % i), STEP_SR)
                grit = fft_filter(grit[: int(0.22 * STEP_SR)], STEP_SR, high=2500.0)
                grit *= np.linspace(1.0, 0.0, len(grit)) ** 2
                tap = fft_filter(x, STEP_SR, high=1800.0)
                y = np.zeros(max(len(tap), len(grit)))
                y[: len(tap)] += norm(tap, 1.0)
                y[: len(grit)] += norm(grit, 0.45)
                x = y
            elif shape == "soft":
                # A grass step runs most of a second: keep its first part.
                x = x[: int(0.32 * STEP_SR)] * np.linspace(1.0, 0.0, int(0.32 * STEP_SR)) ** 1.5
            x = trim(x, STEP_SR)
            write_ogg("step_%s_%d" % (ground, i + 1), norm(x, 0.9), STEP_SR, 3)


ENGINE_SR = 22050

## Each kind of machine's engine: the Kenney loop it is cut from. Played on
## and on, pitched by speed (`EngineSound`).
ENGINES = {
    # Bikes, buggies and walkers: a low motor rumble.
    "ground": "spaceEngineLow_004",
    # Hoverbikes: a smaller, higher whine.
    "hover": "spaceEngineSmall_002",
    # Anything that flies: a big turbine roar.
    "air": "spaceEngineLarge_002",
}


def make_engines(kenney):
    for kind, source in ENGINES.items():
        x = read(os.path.join(kenney, source + ".ogg"), ENGINE_SR)
        write_ogg("engine_" + kind, norm(seam_loop(x, ENGINE_SR), 0.8), ENGINE_SR, 3)


# --------------------------------------------------------------------------
# The cold wind, from code
# --------------------------------------------------------------------------

WIND_SR = 22050
WIND_LENGTH = 40.0


def periodic(t, length, harmonics, rng):
    """A slow wander that comes back to where it started after `length` s,
    so the loop it shapes has no seam: a few sines whole cycles long."""
    out = np.zeros_like(t)
    for k in harmonics:
        out += np.sin(2 * np.pi * k * t / length + rng.uniform(0, 2 * np.pi)) / k
    return out


def band_noise(n, sr, rng, centre, width):
    """Noise only in a band, made in the frequency domain so it loops."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / sr)
    spec *= np.exp(-0.5 * ((f - centre) / width) ** 2)
    return norm(np.fft.irfft(spec, n=n), 1.0)


def make_wind():
    """A cold wind over open snow: a low roar that gusts, and two thin
    whistles that come and go with the gusts. Every part is built whole
    cycles of the loop long, so it plays on and on with no seam."""
    rng = np.random.default_rng(7)
    n = int(WIND_LENGTH * WIND_SR)
    t = np.arange(n) / WIND_SR
    # The roar: noise falling off toward the top like far-off air moving.
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / WIND_SR)
    spec *= 1.0 / (1.0 + (f / 180.0) ** 2) * (1.0 / (1.0 + (25.0 / np.maximum(f, 1e-3)) ** 4))
    roar = norm(np.fft.irfft(spec, n=n), 1.0)
    # Gusts: a slow swell of the whole, and the brighter air riding it.
    gust = 0.5 + 0.5 * np.tanh(1.6 * periodic(t, WIND_LENGTH, [2, 3, 5, 7], rng))
    hiss = band_noise(n, WIND_SR, rng, 1400.0, 700.0)
    low_whistle = band_noise(n, WIND_SR, rng, 620.0, 18.0)
    high_whistle = band_noise(n, WIND_SR, rng, 910.0, 14.0)
    sway = 0.5 + 0.5 * periodic(t, WIND_LENGTH, [3, 4], rng) / 1.3
    whistle = (low_whistle * sway + high_whistle * (1.0 - sway)) * gust ** 3
    x = roar * (0.55 + 0.45 * gust) + hiss * 0.12 * gust ** 2 + whistle * 0.16
    write_ogg("wind_cold", norm(x, 0.8), WIND_SR, 3)


# --------------------------------------------------------------------------
# The plaza's music, from code
# --------------------------------------------------------------------------

MUSIC_SR = 44100
BPM = 72.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
## Two bars a chord, eight chords a pass: D minor, falling and climbing back
## up through its brighter chords, the last one (A major) leading home.
CHORDS = [
    ("D", [50, 53, 57, 62]),   # Dm
    ("Bb", [46, 53, 58, 62]),  # Bb
    ("F", [41, 53, 57, 60]),   # F
    ("C", [48, 52, 55, 60]),   # C
    ("D", [50, 53, 57, 62]),   # Dm
    ("G", [43, 55, 58, 62]),   # Gm
    ("Bb", [46, 53, 58, 62]),  # Bb
    ("A", [45, 52, 57, 61]),   # A
]
BARS_PER_CHORD = 2
## What plays in each pass of the eight chords; the track is the passes in
## order and loops back to the first, which the last leads into.
PASSES = [
    {"pad": 0.55, "bass": False, "arp": False, "drums": False},  # the city at rest
    {"pad": 0.75, "bass": True, "arp": True, "drums": False},    # it wakes
    {"pad": 0.9, "bass": True, "arp": True, "drums": True},      # all of it
    {"pad": 1.0, "bass": False, "arp": True, "drums": False},    # the lift, easing off
]


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def pad_note(n, f, bright, rng):
    """A warm pad voice: three detuned saws, built from their harmonics
    with the top rolled off by `bright` (0 dark, 1 open)."""
    t = np.arange(n) / MUSIC_SR
    out = np.zeros(n)
    for cents in (-7.0, 0.0, 6.0):
        fd = f * 2.0 ** (cents / 1200.0)
        phase = rng.uniform(0, 2 * np.pi)
        for h in range(1, 13):
            if fd * h > 9000.0:
                break
            roll = np.exp(-(h - 1) / (1.5 + 4.0 * bright))
            out += np.sin(2 * np.pi * fd * h * t + phase * h) * roll / h
    # A slow breath in the level, so it never sits dead still.
    out *= 0.85 + 0.15 * np.sin(2 * np.pi * t / (BAR * 1.5) + rng.uniform(0, 6.28))
    return out / 3.0


def pluck(n, f):
    """A soft glassy pluck for the arpeggio."""
    t = np.arange(n) / MUSIC_SR
    tone = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t) + 0.12 * np.sin(2 * np.pi * 3 * f * t)
    return tone * np.exp(-t / 0.32) * np.clip(t / 0.004, 0, 1)


def kick(n):
    t = np.arange(n) / MUSIC_SR
    f = 42.0 + 50.0 * np.exp(-t / 0.035)
    return np.sin(2 * np.pi * np.cumsum(f) / MUSIC_SR) * np.exp(-t / 0.22)


def place(out, sig, at, gain=(1.0, 1.0)):
    """Adds `sig` (mono) into stereo `out` at sample `at`, wrapping round
    the end: the track loops, so what rings past its end rings into its start."""
    n = len(sig)
    idx = (np.arange(n) + at) % out.shape[0]
    out[idx, 0] += sig * gain[0]
    out[idx, 1] += sig * gain[1]


def make_music():
    """The plaza's track: slow, wide pads under a city that never sleeps,
    a pulse of bass and a glassy arpeggio coming in and going, and a soft
    beat in the third pass. About three and a half minutes, looping with
    no seam (everything that rings past the end rings into the start)."""
    rng = np.random.default_rng(1)
    chord_len = BAR * BARS_PER_CHORD
    pass_len = chord_len * len(CHORDS)
    total = int(round(pass_len * len(PASSES) * MUSIC_SR))
    dry = np.zeros((total, 2))
    arp_bus = np.zeros((total, 2))
    chord_n = int(chord_len * MUSIC_SR)
    fade = int(1.6 * MUSIC_SR)
    for p, part in enumerate(PASSES):
        bright = 0.25 + 0.6 * (part["pad"] - 0.55) / 0.45
        for c, (_, notes) in enumerate(CHORDS):
            start = int(round((p * pass_len + c * chord_len) * MUSIC_SR))
            # The pad: each chord swells in over the last one's fade.
            n = chord_n + fade
            env = np.ones(n)
            env[:fade] = np.sin(np.linspace(0, np.pi / 2, fade)) ** 2
            env[-fade:] = np.cos(np.linspace(0, np.pi / 2, fade)) ** 2
            for k, note in enumerate(notes[1:]):
                voice = pad_note(n, hz(note), bright, rng) * env * 0.11 * part["pad"]
                pan = 0.5 + (k - 1) * 0.28
                place(dry, voice, start - fade // 2, (np.sqrt(1 - pan), np.sqrt(pan)))
            root = hz(notes[0])
            # A low drone on the root under every pass.
            drone = np.sin(2 * np.pi * root / 2 * np.arange(n) / MUSIC_SR) * env * 0.09
            place(dry, drone, start - fade // 2, (0.7, 0.7))
            if part["bass"]:
                # The bass: eighth notes on the root, each swelling in late
                # like a pump, so it moves without a hard edge.
                step = int(BEAT / 2 * MUSIC_SR)
                for e in range(int(chord_len / (BEAT / 2))):
                    t = np.arange(step) / MUSIC_SR
                    shape = np.sin(np.pi * np.clip(t / (BEAT / 2), 0, 1)) ** 1.5
                    tone = np.sin(2 * np.pi * root * t) + 0.25 * np.sin(4 * np.pi * root * t)
                    place(dry, tone * shape * 0.16, start + e * step, (0.7, 0.7))
            if part["arp"]:
                # The arpeggio, an octave up: root, fifth, tenth, fifth and on.
                tones = [notes[1] + 12, notes[2] + 12, notes[3] + 12, notes[2] + 12,
                        notes[1] + 24, notes[3] + 12, notes[2] + 12, notes[3] + 12]
                step = int(BEAT / 2 * MUSIC_SR)
                for e in range(int(chord_len / (BEAT / 2))):
                    note = tones[e % len(tones)]
                    level = 0.07 * (0.75 + 0.25 * (e % 2 == 0))
                    pan = 0.3 if e % 2 == 0 else 0.7
                    place(arp_bus, pluck(int(1.2 * MUSIC_SR), hz(note)) * level, start + e * step,
                            (np.sqrt(1 - pan), np.sqrt(pan)))
            if part["drums"]:
                beat_n = int(BEAT * MUSIC_SR)
                for b in range(int(chord_len / BEAT)):
                    at = start + b * beat_n
                    if b % 2 == 0:
                        place(dry, kick(int(0.5 * MUSIC_SR)) * 0.22, at, (0.7, 0.7))
                    # A soft tick on the off-beat.
                    tick = rng.standard_normal(int(0.05 * MUSIC_SR))
                    tick = np.diff(tick, prepend=0.0) * np.exp(-np.arange(len(tick)) / (0.012 * MUSIC_SR))
                    place(dry, tick * 0.025, at + beat_n // 2, (0.55, 0.85) if b % 2 else (0.85, 0.55))
    # The arpeggio's echo: a dotted eighth, crossing sides, wrapping round.
    delay = int(BEAT * 0.75 * MUSIC_SR)
    echo = arp_bus.copy()
    tap = arp_bus.copy()
    for k in range(1, 5):
        tap = np.roll(tap[:, ::-1], delay, axis=0) * 0.42
        echo += fft_filter(tap, MUSIC_SR, high=3500.0)
    mix = dry + echo
    # A big dark hall round it all: a long decaying noise, convolved round
    # the loop (circular, so the tail of the end lands on the start).
    ir_n = int(3.2 * MUSIC_SR)
    decay = np.exp(-np.arange(ir_n) / (0.9 * MUSIC_SR))
    wet = np.zeros_like(mix)
    for ch in range(2):
        ir = np.zeros(total)
        ir[:ir_n] = rng.standard_normal(ir_n) * decay
        ir = fft_filter(ir, MUSIC_SR, low=120.0, high=4000.0)
        ir /= np.sqrt(np.sum(ir ** 2))
        wet[:, ch] = np.fft.irfft(np.fft.rfft(mix[:, ch]) * np.fft.rfft(ir), n=total)
    out = mix * 0.7 + wet * 0.55
    out = fft_filter(out, MUSIC_SR, low=28.0)
    out = np.tanh(out * 1.4) / 1.4
    rms = np.sqrt(np.mean(out ** 2))
    out *= 0.13 / rms
    out = np.clip(out, -0.97, 0.97)
    write_ogg("music_plaza", out, MUSIC_SR, 4)


def main(argv):
    kenney = None
    names = []
    i = 0
    while i < len(argv):
        if argv[i] == "--kenney":
            kenney = argv[i + 1]
            i += 2
            continue
        names.append(argv[i])
        i += 1
    names = names or ["steps", "engines", "wind", "music"]
    for name in names:
        if name in ("steps", "engines") and kenney is None:
            print("skipping %s: pass --kenney DIR with the Kenney packs' .ogg files" % name)
            continue
        {"steps": lambda: make_steps(kenney), "engines": lambda: make_engines(kenney),
                "wind": make_wind, "music": make_music}[name]()


if __name__ == "__main__":
    main(sys.argv[1:])
