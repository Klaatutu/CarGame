#!/usr/bin/env python3
"""
Sons de l'etrangleur pour "Route de nuit".

    python tools/make_strangler_sounds.py        # ecrit assets/audio/strangler/

Cinq sons, tous synthetises avec les briques du geant (glotte de Rosenberg,
filtres a phase minimale, dosage a la sonie — voir make_giant_sounds.py) :

  scream.wav  le cri. Le geant GRONDE (f0 34 Hz, une caisse) ; lui HURLE — c'est
              une gorge d'homme poussee au-dela de ce qu'une gorge fait. f0 qui
              monte de 300 a 620 Hz puis se casse, jitter enorme (un cri qui
              deraille), growl de sous-harmonique sur la fin. Les formants sont
              ceux d'une bouche grande ouverte (820 / 1350 / 2500 Hz), et tout
              est coupe a 3,2 kHz : au-dela ca ne fait pas plus peur, ca
              gresille dans le tramage (feedback-audio-no-crackle).
  hurt.wav    le meme appareil, une demi-seconde, f0 qui chute : il encaisse
              une balle. Assez different du cri pour que le joueur SACHE que
              son coup a porte, sans regarder.
  breath.wav  la respiration, EN BOUCLE (unit_size 3 m dans strangler.gd : on
              ne l'entend que quand il est a la vitre, et c'est le but). Deux
              cycles par boucle, bruit filtre module par un formant qui se
              deplace, plus un fond de friture vocale a 55 Hz. Toutes les
              enveloppes sont periodiques sur la duree du fichier : la boucle
              n'a pas de couture.
  thump.wav   une paume sur la tole. Pas un pas de geant : une membrane d'acier
              frappee — le coup sourd (60-180 Hz), la tole qui sonne (partiels
              inharmoniques 210/330/520/870 Hz), la claque de peau tres breve.
  rattle.wav  la poignee secouee : trois claquements metalliques secs sur un
              fond de va-et-vient, et le thunk du mecanisme qui bute.
  creak.wav   la charniere qui cede. Du stick-slip : la meme glotte que la
              voix — un grincement EST une voix de metal — f0 de 320 a 90 Hz,
              jitter au maximum, et le clonc de la porte en butee a la fin.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_engine_sounds import (SR, apply_filter, ensure_import, highpass,  # noqa: E402
                                lowpass, peak, soft_clip, tilt, write_wav)
from make_giant_sounds import (a_rms, burst, glottis, mix, modes, report)  # noqa: E402

OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..",
                                        "assets", "audio", "strangler"))


# --------------------------------------------------------------------------
# Le cri
# --------------------------------------------------------------------------

def make_scream(rng):
    n = int(1.45 * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1.0 / SR)

    # Attaque quasi instantanee, tenue, puis la voix lache d'un coup.
    env = np.clip(t / 0.045, 0.0, 1.0) * np.clip((1.40 - t) / 0.38, 0.0, 1.0)
    env = np.minimum(env, 1.0)

    # La hauteur : elle MONTE d'abord (la panique), se tient en se cassant,
    # retombe en grondement. C'est le trajet inverse du geant, qui ne fait que
    # descendre — lui n'a rien d'une masse, c'est un nerf.
    f0 = np.interp(t, [0.0, 0.22, 0.75, 1.45], [300.0, 620.0, 540.0, 240.0])
    jit = 0.030 + 0.045 * np.clip((t - 0.45) / 0.6, 0.0, 1.0)
    shim = 0.12 + 0.16 * np.clip((t - 0.5) / 0.7, 0.0, 1.0)
    sub = np.clip((t - 0.7) / 0.45, 0.0, 1.0)

    voice = glottis(n, f0, jit, shim, sub, rng)
    # Bouche grande ouverte : premier formant tres haut (820 Hz), et une
    # coupure ferme a 3,2 kHz — le cri doit porter, pas siffler.
    voice = apply_filter(voice,
                         tilt(f, 120.0, 2.5)
                         * peak(f, 820.0, 1.2, 10.0)
                         * peak(f, 1350.0, 1.8, 7.0)
                         * peak(f, 2500.0, 2.5, 4.0)
                         * lowpass(f, 3200.0, 3) * highpass(f, 90.0, 2))

    breath = apply_filter(rng.standard_normal(n),
                          peak(f, 1100.0, 0.8, 4.0) * lowpass(f, 2800.0, 3)
                          * highpass(f, 350.0, 2))

    y = env * mix([("voix", voice, 1.00),
                   ("souffle", breath * (0.3 + 0.7 * env), 0.10)])
    y = soft_clip(y / np.max(np.abs(y)) * 0.94)
    y *= np.minimum(1.0, (n - np.arange(n)) / (0.03 * SR))
    return y


def make_hurt(rng):
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1.0 / SR)

    env = np.clip(t / 0.02, 0.0, 1.0) * np.exp(-t / 0.16)
    f0 = np.interp(t, [0.0, 0.08, 0.55], [420.0, 330.0, 150.0])
    voice = glottis(n, f0, 0.05 + 0.0 * t, 0.18 + 0.0 * t,
                    np.clip((t - 0.1) / 0.2, 0.0, 1.0), rng)
    voice = apply_filter(voice,
                         tilt(f, 120.0, 2.5)
                         * peak(f, 700.0, 1.2, 9.0)
                         * peak(f, 1250.0, 1.8, 6.0)
                         * lowpass(f, 3000.0, 3) * highpass(f, 90.0, 2))
    y = env * voice / (a_rms(env * voice) + 1e-12)
    y = soft_clip(y / np.max(np.abs(y)) * 0.92)
    y *= np.minimum(1.0, (n - np.arange(n)) / (0.02 * SR))
    return y


# --------------------------------------------------------------------------
# La respiration (boucle)
# --------------------------------------------------------------------------

def make_breath(rng):
    dur = 2.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1.0 / SR)

    # Deux cycles exactement par boucle : toutes les enveloppes sont des
    # fonctions de phase entiere sur n, la couture tombe sur zero.
    cyc = 2.0 * np.pi * 2.0 * t / dur
    inhale = np.clip(np.sin(cyc), 0.0, 1.0) ** 1.4
    exhale = np.clip(np.sin(cyc + np.pi), 0.0, 1.0) ** 1.1

    noise = rng.standard_normal(n)
    # L'inspiration serre la gorge (formant haut), l'expiration l'ouvre. On
    # fabrique les deux et on fond de l'une a l'autre.
    hi = apply_filter(noise, peak(f, 900.0, 1.1, 12.0) * lowpass(f, 1900.0, 3)
                      * highpass(f, 220.0, 2))
    lo = apply_filter(noise, peak(f, 430.0, 1.0, 12.0) * lowpass(f, 1300.0, 3)
                      * highpass(f, 130.0, 2))
    air = hi * inhale + lo * exhale * 0.9

    # La friture : un fond de voix a 55 Hz, jitter fort, presque du rale. Sa
    # sous-harmonique suit l'expiration — il GRONDE en soufflant.
    fry = glottis(n, 55.0 + 0.0 * t, 0.06 + 0.0 * t, 0.25 + 0.0 * t,
                  exhale, rng)
    fry = apply_filter(fry, peak(f, 210.0, 1.0, 8.0)
                       * lowpass(f, 900.0, 3) * highpass(f, 40.0, 2))

    y = mix([("air", air, 1.00), ("friture", fry * (0.3 + 0.7 * exhale), 0.55)])
    y = soft_clip(y / np.max(np.abs(y)) * 0.85)
    return y


# --------------------------------------------------------------------------
# La tole, la poignee, la charniere
# --------------------------------------------------------------------------

def make_thump(rng):
    n = int(0.7 * SR)
    t = np.arange(n) / SR

    # Le coup : la caisse repond en dessous de 200 Hz, comme sous un pas de
    # geant, mais SANS l'infra — une paume n'ebranle pas le sol.
    body = modes(n, [
        (62.0, 0.38, 1.00, 0.05),
        (118.0, 0.26, 0.70, 0.04),
        (172.0, 0.18, 0.45, 0.04),
    ], rng)
    body *= 1.0 - np.exp(-t / 0.003)

    # La tole qui sonne : des partiels INHARMONIQUES (une plaque n'est pas une
    # corde), amortis vite — c'est une portiere, pas une cloche.
    ring = modes(n, [
        (213.0, 0.30, 1.00, 0.02),
        (334.0, 0.22, 0.66, 0.02),
        (521.0, 0.16, 0.44, 0.015),
        (872.0, 0.10, 0.26, 0.01),
    ], rng)
    ring *= 1.0 - np.exp(-t / 0.002)

    # La claque de peau : tres breve, mate.
    slap = burst(n, lambda ff: lowpass(ff, 1600.0, 2) * highpass(ff, 180.0, 2),
                 0.002, 0.030, rng)

    y = mix([("coup", body, 1.00), ("tole", ring, 0.62), ("claque", slap, 0.30)])
    y = soft_clip(y / np.max(np.abs(y)) * 0.93)
    y *= np.minimum(1.0, (n - np.arange(n)) / (0.02 * SR))
    return y


def make_rattle(rng):
    n = int(0.6 * SR)
    t = np.arange(n) / SR

    # Trois claquements du mecanisme, serres au debut du geste, chacun un
    # transitoire metallique un peu different (la piece rebondit autrement a
    # chaque aller-retour).
    y = np.zeros(n)
    for i, at in enumerate((0.0, 0.085, 0.19)):
        k = int(at * SR)
        m = int(0.14 * SR)
        click = modes(m, [
            (760.0 + 90.0 * i, 0.045, 0.8, 0.0),
            (1420.0 - 60.0 * i, 0.030, 1.0, 0.0),
            (2350.0 + 120.0 * i, 0.018, 0.5, 0.0),
        ], rng)
        click *= 1.0 - np.exp(-np.arange(m) / SR / 0.0006)
        y[k:k + m] += click * (1.0 - 0.2 * i)

    # Le thunk : la poignee en butee, le caisson de porte qui repond.
    kn = int(0.22 * SR)
    thunk = modes(n - kn, [
        (96.0, 0.20, 1.0, 0.06),
        (158.0, 0.14, 0.6, 0.04),
    ], rng)
    y[kn:] += thunk / (a_rms(thunk) + 1e-12) * a_rms(y[:kn] + 1e-9) * 1.6

    # Un voile de frottement sous l'ensemble : la main qui tient la poignee.
    scrape = burst(n, lambda ff: lowpass(ff, 2400.0, 2) * highpass(ff, 300.0, 2),
                   0.01, 0.16, rng)
    y = mix([("mecanisme", y, 1.00), ("frottement", scrape, 0.14)])
    y = soft_clip(y / np.max(np.abs(y)) * 0.9)
    y *= np.minimum(1.0, (n - np.arange(n)) / (0.02 * SR))
    return y


def make_creak(rng):
    n = int(0.95 * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1.0 / SR)

    # Le grincement est du stick-slip : des lachers periodiques, c'est-a-dire
    # une glotte. f0 degringole (la porte accelere), jitter au maximum (une
    # charniere n'a pas d'oreille interne pour tenir sa note).
    env = np.clip(t / 0.05, 0.0, 1.0) * np.clip((0.72 - t) / 0.18, 0.0, 1.0)
    env = np.clip(env, 0.0, 1.0)
    f0 = np.interp(t, [0.0, 0.5, 0.72], [320.0, 150.0, 90.0])
    voice = glottis(n, f0, 0.09 + 0.0 * t, 0.3 + 0.0 * t, 0.4 + 0.0 * t, rng)
    voice = apply_filter(voice,
                         peak(f, 620.0, 1.4, 11.0)
                         * peak(f, 1150.0, 2.0, 7.0)
                         * lowpass(f, 2600.0, 3) * highpass(f, 70.0, 2))

    # La butee : la porte arrive au bout, toute la caisse le dit.
    kn = int(0.70 * SR)
    stop = np.zeros(n)
    hit = modes(n - kn, [
        (88.0, 0.24, 1.0, 0.06),
        (142.0, 0.16, 0.62, 0.05),
        (240.0, 0.10, 0.35, 0.04),
    ], rng)
    stop[kn:] = hit * (1.0 - np.exp(-np.arange(n - kn) / SR / 0.002))

    y = mix([("grincement", voice * env, 1.00), ("butee", stop, 0.85)])
    y = soft_clip(y / np.max(np.abs(y)) * 0.93)
    y *= np.minimum(1.0, (n - np.arange(n)) / (0.03 * SR))
    return y


# --------------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rng = np.random.default_rng(20260826)
    for name, y, loop in [
        ("scream", make_scream(rng), False),
        ("hurt", make_hurt(rng), False),
        ("breath", make_breath(rng), True),
        ("thump", make_thump(rng), False),
        ("rattle", make_rattle(rng), False),
        ("creak", make_creak(rng), False),
    ]:
        path = os.path.join(OUT_DIR, name + ".wav")
        write_wav(path, y, loop=loop)
        ensure_import(path)
        report(name, y)


if __name__ == "__main__":
    main()
