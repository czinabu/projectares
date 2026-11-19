"""Makes every weapon sound in this folder, from nothing but code.

Original and ours (no samples, nothing to credit): each gun is built from
layers the way a recorded gunshot is cut together in a game.

Ballistic guns:
  transient  the first 2-5 ms: a sharp click and crack of bright noise
  mech       the action: short metal resonances (bolt, slide, hammer)
  body       the punch: a sine that drops in pitch fast, plus low noise
  tail       the place answering: an outdoor echo off far ground, or a
             tight indoor slap, baked into separate takes
  cycle      what the gun does after (slide back, a pump, a revolver click)

Energy weapons swap the crack for a charged snap, the body for a falling
FM zap or a plasma hiss, and add a ring or crackle in place of the action.

Every gun gets three near takes outdoors ("_out_N"), three indoors
("_in_N") and two far takes ("_far_N": no transient or action, low passed,
a long roll). Run with plain Python 3 and numpy; it writes .ogg through
ffmpeg (libvorbis) beside itself.

    python3 assets/sounds/weapons/make_weapon_sounds.py [--wav DIR] [names]
"""

import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

def secs(n):
    return np.arange(n) / SR


def samples(duration):
    return int(duration * SR)


def biquad(x, kind, freq, q=0.707, gain_db=0.0):
    """RBJ cookbook biquad, run sample by sample (causal, so no pre-ring)."""
    freq = min(freq, SR * 0.45)
    w0 = 2 * np.pi * freq / SR
    alpha = np.sin(w0) / (2 * q)
    cw = np.cos(w0)
    a = 10 ** (gain_db / 40)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        aa = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        aa = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0, -alpha]
        aa = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * a, -2 * cw, 1 - alpha * a]
        aa = [1 + alpha / a, -2 * cw, 1 - alpha / a]
    else:
        raise ValueError(kind)
    b = [v / aa[0] for v in b]
    a1, a2 = aa[1] / aa[0], aa[2] / aa[0]
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    for i, xi in enumerate(x):
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, xi
        y2, y1 = y1, yi
        y[i] = yi
    return y


def onepole_lp(x, freq):
    a = np.exp(-2 * np.pi * freq / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, xi in enumerate(x):
        acc = (1 - a) * xi + a * acc
        y[i] = acc
    return y


def env(n, attack, tau, hold=0.0):
    """Fast linear attack, an optional hold, then an exponential fall."""
    t = secs(n)
    e = np.exp(-np.maximum(t - attack - hold, 0) / tau)
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    return e


def place(out, sig, at):
    s = int(at * SR)
    if s >= len(out):
        return
    e = min(len(out), s + len(sig))
    out[s:e] += sig[: e - s]


def norm(x, peak=1.0):
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x / m * peak


def sat(x, drive):
    """Soft clip: the glue that makes layers hit as one."""
    return np.tanh(x * drive) / np.tanh(drive)


def drop_sine(n, f0, f1, k, rng, phase_noise=0.0):
    """A sine falling from f0 to f1 with time constant k: the punch."""
    t = secs(n)
    f = f1 + (f0 - f1) * np.exp(-t / k)
    if phase_noise:
        f = f * (1 + phase_noise * onepole_lp(rng.standard_normal(n), 60) * 4)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def metal(n, freqs, tau, rng, spread=0.012):
    """Ringing metal: a few detuned partials, each its own decay."""
    t = secs(n)
    out = np.zeros(n)
    for i, f in enumerate(freqs):
        f = f * (1 + rng.uniform(-spread, spread))
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / (tau / (1 + 0.4 * i))) / (1 + 0.3 * i)
    return out


def clack(rng, bright=3200, ring=(2300, 3700, 5200), tau=0.012, gain=1.0, dur=0.06):
    """A metal part hitting home: a click of noise and a short ring."""
    n = samples(dur)
    click = biquad(rng.standard_normal(n), "bp", bright, 1.2) * env(n, 0.0002, 0.003)
    # Mostly click: a ring that lasts reads as a bell, so it dies in a few ms.
    return (click * 1.6 + metal(n, list(ring), min(tau, 0.004), rng) * 0.2) * gain


# --------------------------------------------------------------------------
# Rooms: a shot's tail is the place answering it
# --------------------------------------------------------------------------

def ir_outdoor(rng, length=1.4, size=1.0):
    """Open ground: almost no early sound, then a few discrete echoes off
    far slopes and ruins, each duller than the last, over a soft roll."""
    n = samples(length)
    ir = np.zeros(n)
    t = secs(n)
    roll = onepole_lp(rng.standard_normal(n), 900) * np.exp(-t / (0.18 * size))
    roll *= np.clip((t - 0.03) / 0.08, 0, 1)
    ir += roll * 0.5
    for d, g in [(0.09, 0.3), (0.21, 0.14), (0.38, 0.07)]:
        d *= size * rng.uniform(0.9, 1.1)
        m = samples(0.09)
        burst = onepole_lp(rng.standard_normal(m), 1400 / (1 + d * 3)) * env(m, 0.004, 0.02)
        place(ir, burst * g * 3, d)
    return ir


def ir_indoor(rng, length=0.6, size=1.0):
    """Concrete and steel close round you: dense early slaps and a short,
    bright decay with a boxy mid."""
    n = samples(length)
    t = secs(n)
    ir = np.zeros(n)
    for _ in range(14):
        d = rng.uniform(0.003, 0.035) * size
        place(ir, np.array([rng.uniform(0.3, 0.8) * rng.choice([-1, 1])]), d)
    diffuse = rng.standard_normal(n) * np.exp(-t / (0.06 * size))
    diffuse *= np.clip((t - 0.004) / 0.01, 0, 1)
    diffuse = biquad(diffuse, "peak", 420, 0.9, 6.0)
    diffuse = biquad(diffuse, "lp", 6500)
    ir += diffuse * 0.16
    return ir


def convolve(x, ir):
    m = len(x) + len(ir) - 1
    size = 1 << (m - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:m]


# --------------------------------------------------------------------------
# Gun recipes
# --------------------------------------------------------------------------

class Gun:
    """The numbers that make one gun's voice."""

    def __init__(self, **kw):
        self.crack_hz = 4500       # where the crack's brightness sits
        self.crack = 1.0           # how loud the crack is
        self.crack_tau = 0.004
        self.body_f0 = 180.0       # punch: starting pitch
        self.body_f1 = 55.0        # and where it falls to
        self.body_k = 0.025        # how fast it falls
        self.body_tau = 0.06       # how long the punch lasts
        self.body = 1.0
        self.rumble_hz = 260.0     # the low noise under the punch
        self.rumble = 0.6
        self.rumble_tau = 0.07
        self.mid_hz = 1100.0       # a gun's own colour: a resonant mid
        self.mid = 0.4
        self.mid_q = 1.6
        self.mech = None           # list of (time, clack kwargs)
        self.cycle = None          # list of (time, clack kwargs) after the shot
        self.drive = 1.2
        self.length = 0.6
        self.room = 1.0            # how big the place sounds for it
        self.tail_out = 0.55
        self.tail_in = 0.45
        self.far_hz = 900.0
        self.far_len = 1.8
        self.extra = None          # a function(rng, n) -> layer for odd guns
        self.pow = 0.0             # the 'pow': a fat mid-low blast (Caleb's ask)
        self.pow_hz = 300.0        # where the pow sits
        self.__dict__.update(kw)


def ballistic_dry(g, rng):
    """The gun alone, before any room: transient, action, body, colour."""
    n = samples(g.length)
    t = secs(n)
    out = np.zeros(n)
    jitter = lambda v, s=0.06: v * (1 + rng.uniform(-s, s))

    # Transient: one sample spike into bright, very short noise. This is
    # what makes it feel instant.
    tr = rng.standard_normal(n) * env(n, 0.0001, jitter(g.crack_tau))
    tr = biquad(tr, "hp", jitter(g.crack_hz) * 0.5)
    tr = biquad(tr, "peak", jitter(g.crack_hz), 0.8, 8.0)
    tr[0:3] += np.array([1.0, -0.7, 0.3]) * 2.5
    out += tr * g.crack * 1.8

    # Body: the punch in the chest.
    body = drop_sine(n, jitter(g.body_f0), jitter(g.body_f1), jitter(g.body_k), rng)
    out += body * env(n, 0.0008, jitter(g.body_tau) * 0.6) * g.body * 0.4

    # Rumble: low noise that fills the punch out.
    rum = onepole_lp(rng.standard_normal(n), jitter(g.rumble_hz))
    rum = onepole_lp(rum, jitter(g.rumble_hz) * 1.5)
    out += norm(rum) * env(n, 0.001, jitter(g.rumble_tau)) * g.rumble * 0.85

    # Pow: the blast itself, a fat mid-low pop that lands at once and is gone
    # in a few tens of ms. A falling tone so it reads as one hit, with
    # low-passed noise so it is a blast and never a note.
    if g.pow > 0.0:
        hz = jitter(g.pow_hz)
        pop = drop_sine(n, hz * 2.4, hz, 0.006, rng) * env(n, 0.0004, 0.022)
        air = onepole_lp(onepole_lp(rng.standard_normal(n), hz * 5), hz * 6)
        out += (pop * 0.7 + norm(air) * env(n, 0.0003, 0.018) * 0.9) * g.pow

    # Colour: a resonant band of noise that makes each gun its own.
    mid = biquad(rng.standard_normal(n), "bp", jitter(g.mid_hz, 0.04), g.mid_q)
    out += norm(mid) * env(n, 0.0005, 0.03) * g.mid

    for at, kw in (g.mech or []):
        place(out, clack(rng, **kw), at + rng.uniform(0, 0.002))
    if g.extra:
        out += g.extra(rng, n)
    out = sat(out, g.drive)
    return fade_end(out)


def take(g, rng, where):
    dry = norm(ballistic_dry(g, rng) if not callable(g.dry) else fade_end(g.dry(g, rng), 0.25))
    # The room never drowns the gun: the tail's peak is set against the
    # shot's, so the first few milliseconds are always the loudest part.
    if where == "out":
        # Low end out of the echo, or it booms on as a wobble.
        wet = norm(biquad(convolve(dry, ir_outdoor(rng, 0.9, g.room)), "hp", 140), g.tail_out * 0.22)
    else:
        wet = norm(biquad(convolve(dry, ir_indoor(rng, 0.4, g.room)), "hp", 110), g.tail_in * 0.35)
    length = len(dry) + samples(0.6 if where == "out" else 0.3) * g.room
    shot = np.zeros(int(length))
    place(shot, dry, 0)
    place(shot, wet[: len(shot)], 0)
    # The action cycling: after the shot and outside the room's punch.
    for at, kw in (g.cycle or []):
        # Heard, but well under the shot: about 15 dB down.
        c = norm(clack(rng, **kw), 0.2 * kw.get("gain", 0.5) / 0.5)
        place(shot, c, at + rng.uniform(-0.01, 0.01))
        room = fade_end(convolve(c, ir_indoor(rng, 0.3) if where == "in" else ir_outdoor(rng, 0.8))[: len(c) * 6], 0.1)
        place(shot, norm(room, np.max(np.abs(c)) * 0.3), at)
    return finish(shot)


def far_take(g, rng):
    """Heard from far off: the crack is gone, the punch is a dull thud and
    the ground rolls it back for a long while."""
    n = samples(0.4)
    t = secs(n)
    thud = drop_sine(n, g.body_f0 * 0.7, g.body_f1, g.body_k * 2, rng) * env(n, 0.004, g.body_tau * 1.1) * 0.35
    rum = onepole_lp(rng.standard_normal(n), g.far_hz)
    thud = thud * g.body + norm(rum) * env(n, 0.002, 0.05) * 0.8
    thud = fade_end(onepole_lp(onepole_lp(thud, g.far_hz * 1.4), g.far_hz * 2), 0.15)
    shot = np.zeros(samples(g.far_len * 0.75))
    place(shot, norm(thud), 0)
    roll = biquad(onepole_lp(convolve(thud, ir_outdoor(rng, g.far_len * 0.75, g.room * 1.3)), 1500), "hp", 90)
    place(shot, norm(roll[: len(shot)], 0.3), 0)
    return finish(shot, peak=0.85)


def fade_end(x, seconds=0.06):
    f = min(len(x), samples(seconds))
    x = x.copy()
    x[-f:] *= np.linspace(1, 0, f) ** 2
    return x


def finish(x, peak=0.97):
    x = x - np.mean(x[:64]) * 0
    x = norm(x, 1.0)
    # Fade the very end so nothing clicks off.
    f = min(len(x), samples(0.08))
    x[-f:] *= np.linspace(1, 0, f)
    # A last gentle limit keeps the crack loud against the tail.
    return sat(x, 1.1) * peak


# --------------------------------------------------------------------------
# Energy layers
# --------------------------------------------------------------------------

def zap(n, f0, f1, k, rng, fm_ratio=1.5, fm_depth=2.0):
    """A falling FM tone: the sci-fi 'pew', kept short and fat."""
    t = secs(n)
    f = f1 + (f0 - f1) * np.exp(-t / k)
    phase = 2 * np.pi * np.cumsum(f) / SR
    mod = np.sin(phase * fm_ratio) * fm_depth * np.exp(-t / (k * 3))
    return np.sin(phase + mod)


def crackle(n, rate, rng, hz=5000, tau=0.0015):
    """Electric arcing: random sharp clicks through a bright band."""
    out = np.zeros(n)
    t = 0.0
    while True:
        t += rng.exponential(1 / rate)
        if t * SR >= n:
            break
        m = samples(0.01)
        c = rng.standard_normal(m) * env(m, 0.0, tau) * rng.uniform(0.3, 1.0)
        place(out, c, t)
    return biquad(out, "bp", hz, 0.9)


def energy_dry(kind):
    def build(g, rng):
        n = samples(g.length)
        t = secs(n)
        j = lambda v, s=0.05: v * (1 + rng.uniform(-s, s))
        out = np.zeros(n)
        if kind == "rail":
            # The slug leaving the rails: a hard electric snap and crack,
            # a deep 'thoom' of the air, a metal ring as the rails settle and
            # a sizzle that dies away.
            snap = rng.standard_normal(n) * env(n, 0.0, 0.002)
            snap = biquad(snap, "hp", 2500)
            snap[0:3] += np.array([1.0, -0.8, 0.4]) * 3
            out += snap * 1.4
            out += zap(n, j(2400), j(90), 0.012, rng, 0.5, 3.0) * env(n, 0.0005, 0.05) * 0.8
            out += drop_sine(n, j(150), 48, 0.04, rng) * env(n, 0.002, 0.12) * 0.7
            out += metal(n, [j(1830), j(2770), j(4120), j(6230)], 0.05, rng, 0.03) * env(n, 0.001, 0.06) * 0.08
            out += crackle(n, 260, rng, 6500) * env(n, 0.0, 0.14) * 0.5
            out += biquad(rng.standard_normal(n), "bp", 9000, 0.7) * env(n, 0.0, 0.2) * 0.035
            return sat(out, 1.2)
        if kind == "plasma":
            # A launcher: the tube coughs a plasma ball out with a low whump,
            # a roaring hiss and a warble as it leaves.
            out += drop_sine(n, j(110), 50, 0.04, rng) * env(n, 0.003, 0.1) * 0.8
            hiss = biquad(rng.standard_normal(n), "bp", j(1800), 0.6)
            out += norm(hiss) * env(n, 0.008, 0.16) * 0.7
            warble = zap(n, j(700), j(180), 0.12, rng, 0.25, 5.0) * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t))
            out += warble * env(n, 0.004, 0.2) * 0.5
            out += crackle(n, 120, rng, 3500) * env(n, 0.0, 0.2) * 0.5
            pop = biquad(rng.standard_normal(n), "lp", 900) * env(n, 0.0003, 0.012)
            out += norm(pop) * 1.2
            return sat(out, 1.3)
        if kind == "arc":
            # A mortar: a hollow tube 'thoonk', the charge leaving with a
            # zip and a spray of arcs round the muzzle.
            out += drop_sine(n, j(240), 95, 0.03, rng) * env(n, 0.001, 0.06) * 0.8
            tube = biquad(rng.standard_normal(n), "bp", j(520), 4.0)
            out += norm(tube) * env(n, 0.001, 0.07) * 0.8
            out += zap(n, j(900), j(3400), 0.06, rng, 2.0, 1.5) * env(n, 0.01, 0.06) * 0.35
            out += crackle(n, 700, rng, 4200) * env(n, 0.003, 0.12) * 1.2
            return sat(out, 1.2)
        if kind == "pulse":
            # A rotary pulse cannon: each round a short, fat zap with a
            # low thump under it, so a stream of them purrs.
            out += zap(n, j(1600), j(220), 0.008, rng, 1.0, 2.5) * env(n, 0.0005, 0.035) * 0.9
            out += drop_sine(n, j(170), 60, 0.012, rng) * env(n, 0.0008, 0.03) * 0.7
            snap = biquad(rng.standard_normal(n), "hp", 3000) * env(n, 0.0, 0.0025)
            out += snap * 1.0
            out += crackle(n, 300, rng, 7000) * env(n, 0.0, 0.03) * 0.5
            return sat(out, 1.3)
        raise ValueError(kind)
    return build


# --------------------------------------------------------------------------
# The guns
# --------------------------------------------------------------------------

SLIDE = dict(bright=3800, ring=(2600, 4100, 6100), tau=0.01, gain=0.55)
BOLT = dict(bright=2600, ring=(1700, 2900, 4300), tau=0.016, gain=0.6)
RATTLE = dict(bright=2100, ring=(1200, 1900, 3300), tau=0.03, gain=0.5)

GUNS = {
    # Scrap Rifle: the starter, a worn automatic. Lower and rougher than the
    # carbine, with a loose part rattling after each shot.
    "shot_scrap": Gun(pow=0.90, pow_hz=270, crack_hz=3600, crack=0.64, body_f0=165, body_f1=52, body_tau=0.07,
            rumble_hz=230, rumble=0.75, mid_hz=850, mid=0.55, mid_q=1.2,
            mech=[(0.004, BOLT), (0.018, RATTLE)], drive=1.3, length=0.35,
            tail_out=0.5, tail_in=0.42),
    # Ashfront Carbine: the all-rounder. Tight, crisp and clean, a firm punch.
    "shot_carbine": Gun(pow=0.95, pow_hz=300, crack_hz=5200, crack=0.88, body_f0=200, body_f1=58, body_tau=0.055,
            rumble_hz=280, rumble=0.6, mid_hz=1400, mid=0.35, mech=[(0.003, BOLT)],
            drive=1.2, length=0.32, tail_out=0.55, tail_in=0.45),
    # Stinger SMG: very fast, so every round is short and snappy, light in
    # the low end and bright, so a burst is a crisp rip, not mush.
    "shot_smg": Gun(pow=0.50, pow_hz=380, crack_hz=6200, crack=0.90, crack_tau=0.003, body_f0=240, body_f1=90,
            body_k=0.012, body_tau=0.03, body=0.8, rumble_hz=380, rumble=0.4, rumble_tau=0.035,
            mid_hz=2100, mid=0.35, mech=[(0.002, dict(SLIDE, gain=0.4))], drive=1.0,
            length=0.2, room=0.8, tail_out=0.38, tail_in=0.35),
    # Longshot DMR: the big one. A hard crack, a heavy punch, its coils
    # giving the shot a short electric edge, a long roll, and the bolt.
    "shot_dmr": Gun(pow=1.00, pow_hz=240, crack_hz=4200, crack=1.10, crack_tau=0.006, body_f0=150, body_f1=50,
            body_k=0.035, body_tau=0.11, body=1.3, rumble_hz=200, rumble=0.9, rumble_tau=0.12,
            mid_hz=950, mid=0.4, mech=[(0.003, BOLT)], drive=1.4, length=0.6, room=1.3,
            tail_out=0.7, tail_in=0.55, far_len=2.4,
            extra=lambda rng, n: zap(n, 5200, 1400, 0.015, rng, 0.5, 1.0) * env(n, 0.0, 0.03) * 0.18,
            cycle=[(0.2, dict(BOLT, gain=0.45)), (0.3, dict(BOLT, bright=3000, gain=0.5))]),
    # Breacher Shotgun: a wide, deep boom, more push than crack, then the
    # pump racked back and forward.
    "shot_shotgun": Gun(pow=1.00, pow_hz=200, crack_hz=3000, crack=0.77, crack_tau=0.008, body_f0=120, body_f1=50,
            body_k=0.04, body_tau=0.1, body=1.5, rumble_hz=170, rumble=1.2, rumble_tau=0.09,
            mid_hz=650, mid=0.5, mid_q=0.9, drive=1.5, length=0.6, room=1.2,
            tail_out=0.65, tail_in=0.55, far_len=2.2,
            cycle=[(0.3, dict(bright=1800, ring=(900, 1500, 2600), tau=0.025, gain=0.7)),
                   (0.42, dict(bright=2600, ring=(1400, 2300, 3600), tau=0.02, gain=0.8))]),
    # Service Pistol: a sharp, bright crack and a short punch, the slide
    # snapping home.
    "shot_pistol": Gun(pow=1.05, pow_hz=330, crack_hz=5600, crack=0.92, crack_tau=0.0035, body_f0=230, body_f1=70,
            body_k=0.015, body_tau=0.04, body=0.9, rumble_hz=320, rumble=0.45, rumble_tau=0.045,
            mid_hz=1700, mid=0.35, mech=[(0.002, SLIDE), (0.035, dict(SLIDE, gain=0.35))],
            drive=1.1, length=0.25, room=0.9, tail_out=0.45, tail_in=0.42),
    # Hornet Machine Pistol: thin and buzzy, a high, light pop.
    "shot_mpistol": Gun(pow=0.45, pow_hz=430, crack_hz=6800, crack=0.81, crack_tau=0.0025, body_f0=280, body_f1=110,
            body_k=0.01, body_tau=0.025, body=0.7, rumble_hz=420, rumble=0.35, rumble_tau=0.03,
            mid_hz=2600, mid=0.45, mid_q=2.2, mech=[(0.002, dict(SLIDE, gain=0.35))], drive=0.9,
            length=0.17, room=0.75, tail_out=0.33, tail_in=0.32),
    # Warden Hand Cannon: a slow, heavy revolver. A deep boom with a
    # ringing frame, and the cylinder clicking round after.
    "shot_cannon": Gun(pow=1.20, pow_hz=220, crack_hz=3800, crack=0.96, crack_tau=0.006, body_f0=135, body_f1=50,
            body_k=0.03, body_tau=0.12, body=1.5, rumble_hz=190, rumble=1.0, rumble_tau=0.12,
            mid_hz=780, mid=0.45, mech=[(0.002, dict(bright=3300, ring=(2100, 3150, 4700), tau=0.004, gain=0.5))],
            drive=1.5, length=0.6, room=1.2, tail_out=0.68, tail_in=0.55, far_len=2.2,
            cycle=[(0.32, dict(bright=4200, ring=(3100, 4700), tau=0.008, gain=0.45))]),
    # Power weapons.
    "rail": Gun(dry=energy_dry("rail"), length=1.2, room=1.5, tail_out=0.55, tail_in=0.45,
            body_f0=140, body_f1=50, body_k=0.06, body_tau=0.25, body=1.3, far_hz=700, far_len=2.6),
    "plasma_shot": Gun(dry=energy_dry("plasma"), length=0.6, room=1.2, tail_out=0.5, tail_in=0.45,
            body_f0=110, body_f1=50, body_k=0.05, body_tau=0.18, body=1.2, far_hz=600, far_len=2.0),
    "arc_shot": Gun(dry=energy_dry("arc"), length=0.4, room=1.0, tail_out=0.45, tail_in=0.42,
            body_f0=240, body_f1=95, body_k=0.03, body_tau=0.09, body=1.0, far_hz=800, far_len=1.6),
    "pulse": Gun(dry=energy_dry("pulse"), length=0.14, room=0.8, tail_out=0.34, tail_in=0.32,
            body_f0=170, body_f1=60, body_k=0.012, body_tau=0.04, body=1.0, far_hz=1000, far_len=1.3),
}
for _g in GUNS.values():
    if not hasattr(_g, "dry"):
        _g.dry = None


# --------------------------------------------------------------------------
# Everything else a weapon says
# --------------------------------------------------------------------------

def one_shots(rng):
    """Hit and kill confirms, draws, charge and spin loops."""
    out = {}

    # Hit marker: a tight, dry 'tk' with a little weight, never shrill.
    n = samples(0.07)
    hit = biquad(rng.standard_normal(n), "bp", 2800, 1.5) * env(n, 0.0, 0.006) * 1.2
    hit += drop_sine(n, 900, 380, 0.01, rng) * env(n, 0.0005, 0.018) * 0.6
    out["hit"] = finish(sat(hit, 2.0), 0.7)

    # Headshot: a bright metal 'tink' that rings a moment.
    n = samples(0.32)
    hs = metal(n, [3150, 4720, 6900], 0.02, rng, 0.03) * 0.6
    hs += biquad(rng.standard_normal(n), "hp", 5000) * env(n, 0.0, 0.003) * 1.2
    hs += drop_sine(n, 1200, 600, 0.01, rng) * env(n, 0.0005, 0.02) * 0.4
    out["headshot"] = finish(hs, 0.75)

    # Armor soaking it: a dull plate 'tunk'.
    n = samples(0.1)
    ah = metal(n, [820, 1340, 2050], 0.012, rng, 0.03) + biquad(rng.standard_normal(n), "bp", 1500, 1.2) * env(n, 0.0, 0.006)
    out["armor_hit"] = finish(ah, 0.6)

    # Armor breaking: a glassy shatter falling apart.
    n = samples(0.5)
    ab = crackle(n, 900, rng, 6000, 0.002) * env(n, 0.0, 0.12) * 1.4
    ab += metal(n, [2900, 3720, 4610, 5900], 0.03, rng, 0.03) * 0.3
    ab += drop_sine(n, 500, 140, 0.03, rng) * env(n, 0.001, 0.06) * 0.6
    out["armor_break"] = finish(ab, 0.8)

    # Kill: a heavy, final thump with a rising two-note chime over it.
    n = samples(0.55)
    t = secs(n)
    k = drop_sine(n, 180, 55, 0.03, rng) * env(n, 0.001, 0.05) * 1.1
    k += biquad(rng.standard_normal(n), "bp", 2200, 1.0) * env(n, 0.0, 0.005) * 0.9
    chime = np.zeros(n)
    for at, f in [(0.03, 1320), (0.09, 1980)]:
        m = n - samples(at)
        chime[samples(at):] += metal(m, [f, f * 2.01], 0.05, rng, 0.0) * 0.25
    out["kill"] = finish(sat(k, 1.6) + chime * 0.8, 0.85)

    # Drawing a gun: cloth, then the weapon seating in the hands.
    n = samples(0.28)
    cloth = onepole_lp(rng.standard_normal(n), 2500) * np.sin(np.pi * np.clip(t[:n] / 0.16, 0, 1)) ** 2
    draw = cloth * 0.5
    place(draw, clack(rng, bright=2400, ring=(1600, 2500, 3900), tau=0.02, gain=0.9), 0.15)
    out["draw_gun"] = finish(draw, 0.55)
    # A blade drawn: a short, bright metallic slide.
    n = samples(0.32)
    t = secs(n)
    slide = biquad(rng.standard_normal(n), "bp", 5200, 2.0) * np.sin(np.pi * np.clip(t / 0.25, 0, 1)) ** 2
    slide += metal(n, [3400, 5100], 0.02, rng) * env(n, 0.22, 0.05) * 0.3
    out["draw_blade"] = finish(slide, 0.5)

    # The Rail Lance charging: a rising whine with a hum under it. Played
    # from the start of a charge and held at its top while still held.
    n = samples(1.0)
    t = secs(n)
    f = 180 + 2600 * (t / 1.0) ** 1.6
    whine = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.4 + np.sin(2 * np.pi * np.cumsum(f * 2.01) / SR) * 0.15
    hum = np.sin(2 * np.pi * 60 * t) * 0.25 + crackle(n, 400, rng, 6000) * 0.5 * t * t
    out["rail_charge"] = finish((whine + hum) * np.clip(t / 0.05, 0, 1), 0.6)

    # The Storm Cannon's barrels spinning: a whirr that loops seamlessly
    # (whole cycles in one second, the noise crossfaded round). The game
    # raises its pitch and volume with the spin.
    n = samples(1.0)
    t = secs(n)
    ph = 2 * np.pi * 180 * t
    band = biquad(rng.standard_normal(n + samples(0.2)), "bp", 1200, 1.5)
    fade = samples(0.2)
    band[:fade] = band[:fade] * np.linspace(0, 1, fade) + band[n:n + fade] * np.linspace(1, 0, fade)
    band = norm(band[:n])
    whirr = np.sin(ph * 3) * 0.3 + np.sin(ph * 7) * 0.15 + band * 0.25 * (0.5 + 0.5 * np.sin(ph))
    out["storm_spin"] = norm(whirr, 0.5)
    return out


# --------------------------------------------------------------------------

def write_ogg(path, x):
    pcm = (np.clip(x, -1, 1) * 32000).astype("<i2").tobytes()
    tmp = path + ".tmp.wav"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis",
            "-q:a", "7", path], check=True)
    os.remove(tmp)


def write_wav(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32000).astype("<i2").tobytes())


def main():
    args = sys.argv[1:]
    wav_dir = None
    if "--wav" in args:
        i = args.index("--wav")
        wav_dir = args[i + 1]
        del args[i:i + 2]
    names = set(args)
    made = {}
    for seed, (name, g) in enumerate(GUNS.items()):
        if names and name not in names:
            continue
        rng = np.random.default_rng(1000 + seed * 17)
        for i in range(3):
            made["%s_out_%d" % (name, i + 1)] = take(g, rng, "out")
            made["%s_in_%d" % (name, i + 1)] = take(g, rng, "in")
        for i in range(2):
            made["%s_far_%d" % (name, i + 1)] = far_take(g, rng)
    if not names or "misc" in names:
        made.update(one_shots(np.random.default_rng(7)))
    for name, x in made.items():
        if wav_dir:
            write_wav(os.path.join(wav_dir, name + ".wav"), x)
        else:
            write_ogg(os.path.join(HERE, name + ".ogg"), x)
        print(name, "%.2f s" % (len(x) / SR))


if __name__ == "__main__":
    main()
