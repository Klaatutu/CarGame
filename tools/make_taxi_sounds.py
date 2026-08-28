#!/usr/bin/env python3
"""
Sons du quotidien du chauffeur pour "Route de nuit".

    python tools/make_taxi_sounds.py        # ecrit assets/audio/taxi/

Sept sons, courts, tous synthetises avec les briques du geant (modes amortis,
bouffees de bruit filtre, dosage a la sonie — voir make_giant_sounds.py).
C'est le versant DOUX de la banque de sons : rien ici ne veut faire peur,
tout veut faire vrai — le jeu de taxi vit de ces gestes-la.

  gulp.wav    boire a la canette. Trois deglutitions : un plop grave qui
              glisse (la gorge), une goutte de bruit liquide, et un fond de
              petillement qui s'eteint — c'est une boisson gazeuse.
  crush.wav   la canette ecrasee d'une main. Une tole MINCE : partiels
              inharmoniques hauts et brefs, deux plis qui claquent, pas de
              grave — une canette n'est pas une portiere.
  ring.wav    la sonnerie du telephone, EN BOUCLE (periode 2 s exacte) :
              deux breves bitonales puis le silence — une sonnerie d'appareil
              bon marche, pas une melodie.
  tap.wav     le doigt sur l'ecran. Presque rien : un tic mat.
  tpe.wav     le terminal de paiement : deux bips, puis le bip long
              d'acceptation, un demi-ton au-dessus — la petite musique
              administrative de la carte qui passe.
  cash.wav    des billets comptes : du papier froisse par petites rafales,
              et la claque du billet plie en fin de compte.
  door.wav    une portiere fermee de l'exterieur, sans violence : le coup
              sourd de la caisse et le clic de la serrure — le passager est
              monte, ou descendu.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_engine_sounds import (SR, apply_filter, ensure_import, highpass,  # noqa: E402
                                lowpass, soft_clip, write_wav)
from make_giant_sounds import burst, mix, modes, report  # noqa: E402

OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..",
                                        "assets", "audio", "taxi"))


def finish(y, level=0.82):
    y = y / (np.max(np.abs(y)) + 1e-12) * level
    return soft_clip(y)


# --------------------------------------------------------------------------
# Boire
# --------------------------------------------------------------------------

def make_gulp(rng):
    n = int(1.5 * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)

    # Trois deglutitions, un peu irregulieres : une gorge, pas un metronome.
    for i, at in enumerate([0.22, 0.66, 1.08]):
        m = int(0.30 * SR)
        seg = np.zeros(n)
        # Le plop : un mode grave qui GLISSE vers le bas — la gorgee qui descend.
        plop = modes(m, [(150.0 - 12.0 * i, 0.16, 1.0, 0.45)], rng)
        # La goutte : un souffle liquide tres bref, medium.
        drip = burst(m, lambda f: lowpass(f, 2400.0) * highpass(f, 500.0),
                     0.004, 0.05, rng)
        s = mix([("plop", plop, 1.0), ("drip", drip, 0.4)])
        seg[int(at * SR):int(at * SR) + m] += s[:min(m, n - int(at * SR))] \
            * np.exp(-np.arange(min(m, n - int(at * SR))) / (0.22 * SR))
        y += seg

    # Le petillement : de tout petits clics haut places, denses au debut.
    fizz = burst(n, lambda f: highpass(f, 3000.0) * lowpass(f, 6500.0),
                 0.02, 0.9, rng) * (0.10 * np.exp(-t / 0.7))
    y += fizz
    return finish(apply_filter(y, lowpass(np.fft.rfftfreq(n, 1.0 / SR), 7000.0)))


# --------------------------------------------------------------------------
# La canette ecrasee
# --------------------------------------------------------------------------

def make_crush(rng):
    n = int(0.4 * SR)
    # La tole mince : partiels hauts, brefs, qui se detendent (drop negatif :
    # le metal plie MONTE en se raidissant).
    body = modes(n, [
        (430.0, 0.10, 0.8, -0.12),
        (660.0, 0.08, 1.0, -0.18),
        (990.0, 0.06, 0.7, -0.10),
        (1460.0, 0.05, 0.55, -0.22),
        (2100.0, 0.04, 0.35, -0.15),
    ], rng)
    # Deux plis qui claquent, le second plus tot qu'on ne l'attend.
    y = np.zeros(n)
    for at, w in [(0.0, 1.0), (0.085, 0.75)]:
        m = int(0.16 * SR)
        c = burst(m, lambda f: highpass(f, 900.0) * lowpass(f, 5200.0),
                  0.001, 0.030, rng) * w
        y[int(at * SR):int(at * SR) + m] += c[:n - int(at * SR)]
    return finish(mix([("plis", y, 1.0), ("tole", body, 0.8)]), 0.85)


# --------------------------------------------------------------------------
# Le telephone
# --------------------------------------------------------------------------

def make_ring(rng):
    # Periode 2 s EXACTE : la boucle n'a pas de couture. Deux breves
    # bitonales (880 + 1180 Hz, battement leger) puis le silence.
    n = 2 * SR
    t = np.arange(n) / SR
    y = np.zeros(n)
    for at in [0.0, 0.55]:
        m = int(0.38 * SR)
        tt = np.arange(m) / SR
        tone = np.sin(2 * np.pi * 880.0 * tt) + 0.7 * np.sin(2 * np.pi * 1180.0 * tt)
        tone *= 0.5 + 0.5 * np.sin(2 * np.pi * 21.0 * tt)      # le tremolo du timbre
        env = np.clip(tt / 0.008, 0, 1) * np.clip((0.38 - tt) / 0.03, 0, 1)
        y[int(at * SR):int(at * SR) + m] += tone * np.clip(env, 0, 1)
    _ = t
    return finish(y, 0.62)


def make_tap(rng):
    n = int(0.07 * SR)
    tick = burst(n, lambda f: highpass(f, 700.0) * lowpass(f, 3600.0),
                 0.0008, 0.012, rng)
    knock = modes(n, [(1250.0, 0.02, 0.6, 0.0)], rng)
    return finish(mix([("tic", tick, 1.0), ("mat", knock, 0.5)]), 0.5)


def make_tpe(rng):
    n = int(0.62 * SR)
    y = np.zeros(n)
    for at, dur, f0 in [(0.0, 0.085, 1568.0), (0.15, 0.085, 1568.0),
                        (0.32, 0.26, 1661.0)]:
        m = int(dur * SR)
        tt = np.arange(m) / SR
        env = np.clip(tt / 0.004, 0, 1) * np.clip((dur - tt) / 0.02, 0, 1)
        y[int(at * SR):int(at * SR) + m] += np.sin(2 * np.pi * f0 * tt) * np.clip(env, 0, 1)
    return finish(y, 0.55)


# --------------------------------------------------------------------------
# L'argent, la portiere
# --------------------------------------------------------------------------

def make_cash(rng):
    n = int(0.75 * SR)
    y = np.zeros(n)
    # Le papier : des rafales minuscules, serrees puis espacees.
    at = 0.02
    k = 0
    while at < 0.52:
        m = int(0.05 * SR)
        c = burst(m, lambda f: highpass(f, 1400.0) * lowpass(f, 7500.0),
                  0.001, 0.014, rng) * rng.uniform(0.4, 1.0)
        y[int(at * SR):int(at * SR) + m] += c
        at += rng.uniform(0.030, 0.075) * (1.0 + 0.6 * (k / 8.0))
        k += 1
    # La claque du billet plie.
    m = int(0.12 * SR)
    snap = burst(m, lambda f: highpass(f, 900.0) * lowpass(f, 5000.0),
                 0.001, 0.030, rng)
    y[int(0.58 * SR):int(0.58 * SR) + m] += snap * 1.2
    return finish(y, 0.6)


def make_door(rng):
    n = int(0.5 * SR)
    # Le coup sourd de la caisse — grave, court — et la serrure qui claque.
    thunk = modes(n, [(72.0, 0.16, 1.0, 0.30), (118.0, 0.10, 0.7, 0.20),
                      (210.0, 0.07, 0.4, 0.10)], rng)
    latch = np.zeros(n)
    m = int(0.09 * SR)
    c = burst(m, lambda f: highpass(f, 1500.0) * lowpass(f, 6000.0),
              0.0008, 0.018, rng)
    latch[int(0.045 * SR):int(0.045 * SR) + m] += c
    return finish(mix([("caisse", thunk, 1.0), ("serrure", latch, 0.5)]), 0.8)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rng = np.random.default_rng(1990)
    sounds = {
        "gulp": (make_gulp, False),
        "crush": (make_crush, False),
        "ring": (make_ring, True),
        "tap": (make_tap, False),
        "tpe": (make_tpe, False),
        "cash": (make_cash, False),
        "door": (make_door, False),
    }
    for name, (fn, loop) in sounds.items():
        y = fn(rng)
        report(name, y)
        path = os.path.join(OUT_DIR, name + ".wav")
        write_wav(path, y, loop=loop)
        ensure_import(path)
    print("ecrit dans", OUT_DIR)


if __name__ == "__main__":
    main()
