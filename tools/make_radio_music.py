#!/usr/bin/env python3
"""
La station de radio de "Route de nuit".

    python tools/make_radio_music.py        # ecrit assets/audio/radio/

Une seule boucle, 40 s EXACTES : 16 mesures a 96 BPM, 64 temps — un nombre
entier de tout, pour que la couture n'existe pas. Tout est synthetise, comme
le reste de la banque de sons : pas un echantillon ne vient d'ailleurs.

La musique elle-meme est celle qu'une petite station passe a la nuit :
  - une nappe d'accords en sinus additifs desaccordes (deux oscillateurs par
    note, 3 et 5 cents d'ecart : le chorus des synthes bon marche), huit
    accords de deux mesures — Am F C G, Am F Dm E — la boucle harmonique la
    plus usee de la FM, et c'est expres ;
  - une basse a la noire, pincee (attaque courte, decroissance longue), a
    l'octave sous la fondamentale ;
  - une boite a rythmes modeste : grosse caisse en sinus amorti qui plonge,
    caisse claire en bouffee de bruit, charley en bruit haut place, huit
    par mesure, deux accents.

Le tout passe par la "diffusion" : coupe a 3,8 kHz (au-dela ca gresille dans
le tramage — la regle de toute la banque), une pointe vers 2 kHz (le
haut-parleur de planche de bord), un souffle de fond a -44 dB, et un
tremblement d'accord lent (0,3 %, 0,23 Hz) : une porteuse qui derive un peu.
Le detunage du cauchemar, lui, est fait EN JEU (pitch_scale sur le lecteur).
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_engine_sounds import (SR, apply_filter, ensure_import, highpass,  # noqa: E402
                                lowpass, peak, soft_clip, write_wav)

OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..",
                                        "assets", "audio", "radio"))

BPM = 96.0
BEATS = 64                 # 16 mesures de 4 temps
BEAT = 60.0 / BPM          # 0,625 s
LOOP = BEATS * BEAT        # 40 s exactes
N = int(round(LOOP * SR))

# La gamme : A mineur naturel, La2 = 110 Hz.
NOTE = {"A2": 110.0, "C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61,
        "G3": 196.0, "A3": 220.0, "B3": 246.94, "C4": 261.63, "D4": 293.66,
        "E4": 329.63, "F4": 349.23, "G4": 392.0}

# Huit accords de deux mesures : (notes de la nappe, note de basse).
CHORDS = [
    (["A3", "C4", "E4"], "A2"),
    (["F3", "A3", "C4"], "F3"),
    (["C4", "E4", "G4"], "C3"),
    (["G3", "B3", "D4"], "G3"),
    (["A3", "C4", "E4"], "A2"),
    (["F3", "A3", "C4"], "F3"),
    (["D4", "F3", "A3"], "D3"),
    (["E3", "B3", "E4"], "E3"),
]


def wrap_add(buf, at, seg):
    """Additionne seg dans buf a partir de l'echantillon at, EN BOUCLANT :
    ce qui depasse la fin retombe au debut. C'est ca, une boucle sans couture
    — la fin du dernier accord nourrit le debut du premier."""
    n = len(buf)
    at = int(at) % n
    m = len(seg)
    first = min(m, n - at)
    buf[at:at + first] += seg[:first]
    if m > first:
        buf[:m - first] += seg[first:]


def osc_pair(freq, dur, cents=4.0):
    """Deux sinus desaccordes de `cents` centiemes de ton, plus une trace
    d'harmonique 2 : le son de nappe le plus simple qui ne soit pas un
    diapason."""
    t = np.arange(int(dur * SR)) / SR
    d = 2.0 ** (cents / 1200.0)
    y = (np.sin(2 * np.pi * freq * t) + np.sin(2 * np.pi * freq * d * t)
         + 0.22 * np.sin(2 * np.pi * freq * 2.0 * t))
    return y


def make_station(rng):
    pad = np.zeros(N)
    bass = np.zeros(N)
    drums = np.zeros(N)

    # La nappe. Chaque accord dure 2 mesures ; son enveloppe deborde d'un
    # demi-temps de chaque cote et s'ecrit en boucle : pas de trou, pas de
    # clic, y compris entre la fin et le debut.
    slot = 8 * BEAT
    for i, (notes, _) in enumerate(CHORDS):
        dur = slot + BEAT
        m = int(dur * SR)
        env = np.minimum(np.arange(m) / (0.5 * BEAT * SR), 1.0)
        env = np.minimum(env, np.clip((dur - np.arange(m) / SR) / (0.5 * BEAT), 0.0, 1.0))
        seg = np.zeros(m)
        for k, name in enumerate(notes):
            seg += osc_pair(NOTE[name], dur, 3.0 + 1.2 * k) / 3.0
        wrap_add(pad, (i * slot - 0.5 * BEAT) * SR, seg * env * 0.30)

    # La basse : une noire pincee sur chaque temps, l'octave dessous.
    for b in range(BEATS):
        root = NOTE[CHORDS[(b // 8) % 8][1]] * 0.5
        m = int(0.55 * SR)
        t = np.arange(m) / SR
        seg = np.sin(2 * np.pi * root * t + 2.2 * np.exp(-t / 0.012)) \
            * np.exp(-t / 0.22) * np.minimum(t / 0.004, 1.0)
        wrap_add(bass, b * BEAT * SR, seg * 0.5)

    # La boite a rythmes.
    for b in range(BEATS):
        # Grosse caisse sur 1 et 3 : un sinus qui plonge de 95 a 45 Hz.
        if b % 4 in (0, 2):
            m = int(0.22 * SR)
            t = np.arange(m) / SR
            f = 45.0 + 50.0 * np.exp(-t / 0.03)
            seg = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09)
            wrap_add(drums, b * BEAT * SR, seg * 0.9)
        # Caisse claire sur 2 et 4.
        if b % 4 in (1, 3):
            m = int(0.16 * SR)
            t = np.arange(m) / SR
            x = rng.standard_normal(m)
            f = np.fft.rfftfreq(m, 1.0 / SR)
            x = apply_filter(x, highpass(f, 900.0) * lowpass(f, 3600.0))
            seg = x * np.exp(-t / 0.045) + 0.4 * np.sin(2 * np.pi * 190.0 * t) * np.exp(-t / 0.05)
            wrap_add(drums, b * BEAT * SR, seg * 0.5)
        # Charley a la croche, plus court sur les contretemps.
        for half in (0.0, 0.5):
            m = int(0.05 * SR)
            t = np.arange(m) / SR
            x = rng.standard_normal(m)
            f = np.fft.rfftfreq(m, 1.0 / SR)
            x = apply_filter(x, highpass(f, 2800.0) * lowpass(f, 3900.0))
            seg = x * np.exp(-t / (0.020 if half else 0.032))
            wrap_add(drums, (b + half) * BEAT * SR, seg * 0.16)

    y = pad + bass + drums

    # La diffusion : le haut-parleur de planche de bord et la porteuse.
    t = np.arange(N) / SR
    y *= 1.0 + 0.003 * np.sin(2 * np.pi * 0.225 * t)   # 9 cycles sur 40 s : ca boucle
    f = np.fft.rfftfreq(N, 1.0 / SR)
    y = apply_filter(y, lowpass(f, 3800.0) * highpass(f, 70.0) * peak(f, 2000.0, 0.9, 2.5))
    hiss = rng.standard_normal(N)
    hiss = apply_filter(hiss, lowpass(f, 3600.0) * highpass(f, 300.0))
    y += hiss / np.max(np.abs(hiss)) * 10.0 ** (-44.0 / 20.0)

    y = y / np.max(np.abs(y)) * 0.80
    return soft_clip(y)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rng = np.random.default_rng(1996)
    y = make_station(rng)
    path = os.path.join(OUT_DIR, "station_loop.wav")
    write_wav(path, y, loop=True)
    ensure_import(path)
    print("station : %.1f s, %d temps a %.0f BPM, crete %.2f" % (
        LOOP, BEATS, BPM, float(np.max(np.abs(y)))))
    print("ecrit dans", OUT_DIR)


if __name__ == "__main__":
    main()
