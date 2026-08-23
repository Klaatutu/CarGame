#!/usr/bin/env python3
"""
Sons de l'habitacle pour "Route de nuit" : route, vent, levier, frein a main.

    python tools/make_cabin_sounds.py                 # ecrit assets/audio/cabin/
    python tools/make_cabin_sounds.py --demo x.wav    # + 14 s de demo

Tout est synthetise, comme le moteur (voir make_engine_sounds.py, dont on
reprend les briques). Rien au-dessus de 3-4 kHz : ca gresille.

ROUTE ET VENT
-------------
Deux boucles de bruit construites directement en frequence : amplitude =
forme voulue x tirage de Rayleigh, phase au hasard, puis FFT inverse. Le
resultat est PARFAITEMENT periodique sur la longueur de la boucle, sans
couture ni fondu. Les rafales sont une modulation lente a nombre entier de
cycles sur la boucle, pour la meme raison.

  - road_roll  : grondement des pneus a travers le plancher, 25-350 Hz, bosse
                 a 70 Hz (la caisse). Le jeu le pitche un peu avec la vitesse.
  - wind_low   : souffle aux joints de portes, sourd (< 600 Hz).
  - wind_high  : le meme ouvert jusqu'a 3 kHz, pour la haute vitesse.
                 Le jeu fond l'un dans l'autre selon la vitesse. Les deux
                 partagent les memes rafales, donc le fondu ne "pompe" pas.

VITRE OUVERTE (le jeu les dose par l'ouverture des vitres ET la vitesse) :
  - wind_open   : le grondement turbulent qui s'engouffre, 60 Hz - 4,5 kHz,
                  bosse vers 350 Hz, agite vite (3-14 Hz) et lentement.
  - wind_buffet : le battement sourd d'une vitre ouverte a 60-110 km/h, un
                  grondement 35-150 Hz module a 18 Hz (resonance de Helmholtz
                  de l'habitacle, le "wub-wub").
  - road_open   : le sifflement des pneus, 300 Hz - 4 kHz, qui passe par la
                  vitre ouverte.
  - crank       : le mecanisme de la manivelle, joue tant que la vitre bouge :
                  des dents a 24 Hz sous un frottement sourd.

LEVIER ET FREIN A MAIN
----------------------
Synthese modale : quelques sinus amortis (le "tonc" de la tringlerie vers
60-200 Hz, le "toc" du bois/plastique vers 500-1300 Hz, le "clic" metallique
du cliquet vers 2-3 kHz) plus une bouffee de bruit de quelques millisecondes.

  - gear_shift        : deux coups, le levier qui quitte sa grille puis qui
                        arrive dans l'autre, 45 ms plus tard.
  - handbrake_pull    : six clics de cliquet qui s'accelerent, un grincement
                        au depart et une butee a l'arrivee.
  - handbrake_release : le bouton, puis le levier qui retombe.
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_engine_sounds import (SR, apply_filter, ensure_import, highpass, lowpass,  # noqa: E402
                                peak, soft_clip, tilt, write_wav)

OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "cabin"))
LOOP_SECONDS = 4.0


def rms(x):
    return math.sqrt(float(np.mean(x * x))) + 1e-12


# --------------------------------------------------------------------------
# Boucles de bruit
# --------------------------------------------------------------------------

def noise_loop(seconds, shape, rng):
    n = int(round(seconds * SR))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    mag = shape(f) * rng.rayleigh(1.0, f.size)
    spec = mag * np.exp(1j * rng.uniform(0.0, 2.0 * np.pi, f.size))
    spec[0] = 0.0
    y = np.fft.irfft(spec, n)
    return y / rms(y)


def gusts(seconds, cycles, depth, rng):
    """Modulation lente, periodique sur la boucle : chaque composante fait un
    nombre ENTIER de cycles."""
    n = int(round(seconds * SR))
    t = np.arange(n) / SR
    m = np.zeros(n)
    for c in cycles:
        m += np.sin(2.0 * np.pi * c * t / seconds + rng.uniform(0.0, 2.0 * np.pi))
    m /= len(cycles)
    return 1.0 + depth * m


def road_shape(f):
    return highpass(f, 25.0, 2) * lowpass(f, 350.0, 3) * peak(f, 70.0, 1.5, 6.0) \
        * peak(f, 140.0, 2.0, 3.0) * tilt(f, 100.0, -4.0)


def wind_low_shape(f):
    return highpass(f, 80.0, 2) * lowpass(f, 600.0, 2) * peak(f, 250.0, 1.2, 4.0)


def wind_high_shape(f):
    return highpass(f, 150.0, 2) * lowpass(f, 3000.0, 2) * tilt(f, 500.0, -3.0) \
        * peak(f, 900.0, 1.0, 3.0)


def wind_open_shape(f):
    return highpass(f, 60.0, 2) * lowpass(f, 4500.0, 2) * peak(f, 350.0, 0.8, 5.0) \
        * tilt(f, 800.0, -3.0)


def wind_buffet_shape(f):
    return highpass(f, 35.0, 3) * lowpass(f, 150.0, 3) * peak(f, 70.0, 1.5, 4.0)


def road_open_shape(f):
    return highpass(f, 300.0, 2) * lowpass(f, 4000.0, 2) * peak(f, 1000.0, 1.0, 4.0) \
        * tilt(f, 1200.0, -3.0)


def make_crank(rng):
    """Mecanisme de manivelle : 24 dents par seconde sous un frottement."""
    seconds = 1.0
    n = int(seconds * SR)
    t = np.arange(n) / SR
    gate = np.zeros(n)
    tooth = np.arange(int(0.006 * SR)) / SR
    for k in range(24):
        i = int(k * n / 24)
        g = np.exp(-tooth / 0.0015)
        gate[i:i + g.size] += g[:n - i]
    thud = np.zeros(n)
    for k in range(24):
        i = int(k * n / 24)
        m = modes(tooth, [(300.0, 0.003, 1.0), (520.0, 0.002, 0.5)])
        thud[i:i + m.size] += m[:n - i]
    f = np.fft.rfftfreq(n, 1.0 / SR)
    noise = rng.standard_normal(n) * (0.35 + gate)
    noise = apply_filter(noise, highpass(f, 150.0, 2) * lowpass(f, 2000.0, 3))
    y = thud / (np.abs(thud).max() + 1e-9) + 0.8 * noise / (np.abs(noise).max() + 1e-9)
    return y


def make_loops():
    rng = np.random.default_rng(11)
    road = noise_loop(LOOP_SECONDS, road_shape, rng)
    road *= gusts(LOOP_SECONDS, [2, 3, 7, 11], 0.20, rng)      # texture du bitume

    wind_mod = gusts(LOOP_SECONDS, [1, 2, 3, 5], 0.35, rng)    # les memes rafales
    wind_lo = noise_loop(LOOP_SECONDS, wind_low_shape, rng) * wind_mod
    wind_hi = noise_loop(LOOP_SECONDS, wind_high_shape, rng) * wind_mod

    # Vitre ouverte : turbulence rapide ET rafales lentes.
    turb = gusts(LOOP_SECONDS, [12, 19, 27, 41, 55], 0.45, rng) * gusts(LOOP_SECONDS, [1, 2, 3], 0.30, rng)
    wind_open = noise_loop(LOOP_SECONDS, wind_open_shape, rng) * turb
    t = np.arange(int(LOOP_SECONDS * SR)) / SR
    buffet = noise_loop(LOOP_SECONDS, wind_buffet_shape, rng) \
        * (1.0 + 0.6 * np.sin(2.0 * np.pi * 18.0 * t)) * gusts(LOOP_SECONDS, [1, 3], 0.25, rng)
    road_open = noise_loop(LOOP_SECONDS, road_open_shape, rng) * gusts(LOOP_SECONDS, [2, 5, 9], 0.15, rng)
    crank = make_crank(rng)

    out = {}
    for name, y, level in (("road_roll", road, -18.0), ("wind_low", wind_lo, -18.0),
                           ("wind_high", wind_hi, -18.0), ("wind_open", wind_open, -18.0),
                           ("wind_buffet", buffet, -18.0), ("road_open", road_open, -18.0),
                           ("crank", crank, -20.0)):
        y = y * 10.0 ** (level / 20.0) / rms(y)
        out[name] = soft_clip(y)
    return out


# --------------------------------------------------------------------------
# One-shots
# --------------------------------------------------------------------------

def modes(t, specs):
    """specs : liste de (frequence Hz, temps d'amortissement s, amplitude)."""
    y = np.zeros_like(t)
    for freq, decay, amp in specs:
        y += amp * np.sin(2.0 * np.pi * freq * t) * np.exp(-t / decay)
    return y


def burst(t, decay, lo, hi, amp, rng):
    """Bouffee de bruit filtree. On rallonge de 0,2 s avant de filtrer : le
    filtre est circulaire et sa queue reviendrait sinon en tete."""
    env = (1.0 - np.exp(-t / 0.0004)) * np.exp(-t / decay)
    x = np.concatenate([rng.standard_normal(t.size) * env, np.zeros(int(0.2 * SR))])
    f = np.fft.rfftfreq(x.size, 1.0 / SR)
    x = apply_filter(x, highpass(f, lo, 2) * lowpass(f, hi, 3))[:t.size]
    return amp * x / (np.abs(x).max() + 1e-9)


def place(out, at_s, sig):
    i = int(round(at_s * SR))
    j = min(i + sig.size, out.size)
    out[i:j] += sig[:j - i]


def finish(y, peak_level=0.7):
    fade = np.ones(y.size)
    k = int(0.01 * SR)
    fade[-k:] = np.linspace(1.0, 0.0, k)
    y = y * fade
    return y * peak_level / (np.abs(y).max() + 1e-9)


def make_gear_shift(rng):
    out = np.zeros(int(0.30 * SR))
    t = np.arange(int(0.15 * SR)) / SR
    hit = modes(t, [(62.0, 0.09, 1.0), (118.0, 0.05, 0.5), (190.0, 0.035, 0.3),     # tonc
                    (480.0, 0.012, 0.35), (820.0, 0.008, 0.25), (1300.0, 0.005, 0.12)])  # toc
    hit += burst(t, 0.004, 1200.0, 3500.0, 0.12, rng)
    place(out, 0.0, hit)
    # Le levier arrive dans l'autre grille.
    hit2 = modes(t, [(70.0, 0.08, 0.6), (130.0, 0.04, 0.3),
                     (520.0, 0.010, 0.25), (900.0, 0.006, 0.15)])
    hit2 += burst(t, 0.003, 1000.0, 3000.0, 0.08, rng)
    place(out, 0.045, hit2)
    return finish(out)


def make_handbrake_pull(rng):
    out = np.zeros(int(0.45 * SR))
    t = np.arange(int(0.12 * SR)) / SR
    place(out, 0.0, modes(t, [(90.0, 0.06, 0.5), (180.0, 0.03, 0.2)]))         # grincement
    clicks = [0.0, 0.070, 0.130, 0.185, 0.235, 0.283]
    for k, at in enumerate(clicks):
        amp = 0.8 + 0.2 * k / (len(clicks) - 1)
        c = modes(t, [(2100.0, 0.004, 0.5), (3300.0, 0.0025, 0.22), (700.0, 0.006, 0.2)])
        c += burst(t, 0.003, 1500.0, 4000.0, 0.3, rng)
        place(out, at, amp * c)
    place(out, clicks[-1] + 0.010, modes(t, [(70.0, 0.08, 0.7), (140.0, 0.04, 0.3)]))  # butee
    return finish(out)


def make_handbrake_release(rng):
    out = np.zeros(int(0.30 * SR))
    t = np.arange(int(0.15 * SR)) / SR
    button = modes(t, [(2600.0, 0.003, 0.3)]) + burst(t, 0.002, 2000.0, 4000.0, 0.2, rng)
    place(out, 0.0, button)
    drop = modes(t, [(75.0, 0.08, 1.0), (150.0, 0.04, 0.4), (600.0, 0.010, 0.3)])
    drop += burst(t, 0.005, 300.0, 1500.0, 0.15, rng)
    place(out, 0.060, drop)
    return finish(out)


# --------------------------------------------------------------------------
# Demo : meme loi que cabin_audio.gd
# --------------------------------------------------------------------------

def render_demo(loops, shots, path):
    secs = 14.0
    n = int(secs * SR)
    t = np.arange(n) / SR
    # 0 -> 40 m/s en 9 s, puis freinage a 0 en 4 s.
    v = np.where(t < 9.0, 40.0 * (t / 9.0) ** 1.3, np.maximum(40.0 * (1.0 - (t - 9.0) / 4.0), 0.0))

    def periodic(loop, pitch):
        pos = np.cumsum(pitch)
        return np.interp(pos % loop.size, np.arange(loop.size + 1), np.append(loop, loop[0]))

    r = np.clip(v / 30.0, 0.0, 1.0) ** 0.8
    road = periodic(loops["road_roll"], 0.85 + 0.35 * np.clip(v / 40.0, 0.0, 1.0))
    w = np.clip((v - 4.0) / 36.0, 0.0, 1.0)
    wg = w ** 1.6
    out = road * r * 10.0 ** (-10.0 / 20.0) \
        + (periodic(loops["wind_low"], np.ones(n)) * np.sqrt(1.0 - 0.75 * w)
           + periodic(loops["wind_high"], np.ones(n)) * np.sqrt(w)) * wg * 10.0 ** (-12.0 / 20.0)

    for at, name, db in ((3.0, "gear_shift", -8.0), (6.0, "gear_shift", -8.0),
                         (10.0, "handbrake_pull", -10.0), (12.0, "handbrake_release", -10.0)):
        place(out, at, shots[name] * 10.0 ** (db / 20.0))
    out *= 0.9 / np.abs(out).max()
    write_wav(path, out, loop=False)


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--demo")
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    loops = make_loops()
    rng = np.random.default_rng(5)
    shots = dict(gear_shift=make_gear_shift(rng),
                 handbrake_pull=make_handbrake_pull(rng),
                 handbrake_release=make_handbrake_release(rng))

    for name, y in loops.items():
        p = os.path.join(args.out, name + ".wav")
        write_wav(p, y, loop=True)
        ensure_import(p)
        print("%-22s boucle %.1f s, rms %.1f dBFS, crete %.2f" % (name + ".wav", y.size / SR, 20 * math.log10(rms(y)), np.abs(y).max()))
    for name, y in shots.items():
        p = os.path.join(args.out, name + ".wav")
        write_wav(p, y, loop=False)
        ensure_import(p)
        print("%-22s %.2f s, crete %.2f" % (name + ".wav", y.size / SR, np.abs(y).max()))

    if args.demo:
        render_demo(loops, shots, args.demo)
        print("demo :", args.demo)


if __name__ == "__main__":
    main()
