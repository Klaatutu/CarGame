#!/usr/bin/env python3
"""
Sons du demarreur et du calage pour "Route de nuit".

    python tools/make_starter_sounds.py             # ecrit assets/audio/starter/
    python tools/make_starter_sounds.py --demo x.wav  # + la sequence complete

Meme atelier que le moteur, l'habitacle et l'arme, dont on reprend les briques
(voir make_engine_sounds.py et make_cabin_sounds.py) : rien d'echantillonne.

DEUX SONS, ET UN SEUL EST UNE BOUCLE
------------------------------------
  starter  le demarreur tourne, moteur pas encore parti. BOUCLE : le joueur
           tient la touche aussi longtemps qu'il veut.
  stall    le moteur cale. Non bouclee : elle a une fin, c'est tout son sujet.

CE QU'ON ENTEND QUAND ON LANCE UN MOTEUR
----------------------------------------
Deux machines a la fois, et c'est leur SUPERPOSITION qui fait reconnaitre le
bruit :

  - le demarreur, un moteur electrique qui tourne treize fois plus vite que le
    vilebrequin (pignon de 9 dents sur une couronne de 120). A 250 tr/min de
    vilebrequin il fait 3300 tr/min, et ses 9 dents engrenent a ~500 Hz. C'est
    le SIFFLEMENT, la partie aigue, celle qui ne varie pas ;
  - le moteur thermique entraine a 250 tr/min, qui n'explose pas mais
    COMPRIME. Un 4 cylindres 4 temps comprime deux fois par tour, soit 8,3 Hz
    a ce regime : c'est le "wouh-wouh-wouh" grave, et c'est lui qu'on compte
    quand on dit qu'une voiture "a du mal a demarrer".

Le sifflement seul fait perceuse ; les compressions seules font moteur au
ralenti. Il faut les deux.

POURQUOI LE CALAGE N'EST PAS UN FONDU
--------------------------------------
Un moteur qui cale ne baisse pas le volume : il RALENTIT, et ses compressions
s'espacent jusqu'a s'arreter sur l'une d'elles. La derniere est la plus forte
et la plus grave — le vilebrequin s'arrete contre une compression qu'il n'a
plus l'energie de passer, et toute la voiture le sent. Le fichier suit donc un
regime qui tombe de 850 a 0, et place ses coups la ou la PHASE du vilebrequin
franchit un demi-tour. Un fondu de volume, lui, s'entendrait comme quelqu'un
qui baisse la radio.
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_engine_sounds import (SR, apply_filter, ensure_import, highpass,  # noqa: E402
                                lowpass, peak, soft_clip, tilt, write_wav)
from make_cabin_sounds import burst, finish, modes, place, rms  # noqa: E402

OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "starter"))

## Regime auquel le demarreur entraine le moteur. C'est la valeur de car.gd
## (STARTER_RPM) : le "wouh-wouh" du fichier doit avoir la cadence que le jeu
## affiche au compte-tours, sinon l'oreille et l'aiguille se contredisent.
STARTER_RPM = 250.0
## Demultiplication pignon -> couronne, et nombre de dents du pignon. C'est ce
## couple qui donne la frequence du sifflement, et rien d'autre.
GEAR_RATIO = 120.0 / 9.0
PINION_TEETH = 9

## Duree de la boucle du demarreur. Choisie pour tomber sur un nombre ENTIER de
## compressions (6), sinon le raccord se fait au milieu d'un coup et s'entend a
## chaque tour de boucle.
FIRES_PER_LOOP = 6

## Regime de depart du calage : le ralenti de car.gd.
STALL_FROM_RPM = 850.0
## En combien de temps le vilebrequin s'immobilise. Court : un moteur qui cale
## en charge s'arrete net, il ne roue pas libre.
STALL_TIME = 0.75


def fire_hz(rpm):
    """Compressions par seconde. Un 4 temps en fait deux par tour."""
    return rpm / 30.0


def place_wrap(out, at_s, sig):
    """Comme place(), mais ce qui depasse revient en tete.

    Indispensable pour une boucle : la queue de la derniere compression doit
    se retrouver au debut du fichier, sinon elle est coupee net au raccord.
    """
    i = int(round(at_s * SR)) % out.size
    for k in range(0, sig.size, out.size):
        chunk = sig[k:k + out.size]
        j = i + chunk.size
        if j <= out.size:
            out[i:j] += chunk
        else:
            cut = out.size - i
            out[i:] += chunk[:cut]
            out[:chunk.size - cut] += chunk[cut:]
        i = 0 if k else (i + chunk.size) % out.size


def compression(t, rng, amp=1.0, deep=1.0):
    """Une compression : le piston monte, l'air resiste, la soupape lache.

    Ce n'est PAS une explosion — pas d'attaque raide. La pression s'etablit sur
    une dizaine de millisecondes puis retombe, d'ou l'enveloppe en cloche
    plutot qu'en percussion. Le tout est grave : au-dessus de 400 Hz un moteur
    entraine ne dit plus rien, c'est le demarreur qu'on entend.
    """
    env = np.exp(-((t - 0.012) / 0.016) ** 2)
    body = modes(t, [
        (52.0 * deep, 0.055, 1.00),
        (88.0 * deep, 0.040, 0.55),
        (141.0 * deep, 0.028, 0.30),
        (218.0 * deep, 0.018, 0.14),
    ])
    air = burst(t, 0.030, 60.0, 520.0, 0.45, rng)
    y = body * env + air * env
    return amp * y / (np.abs(y).max() + 1e-9)


def whine(n, rpm, rng, amp=1.0):
    """Le moteur electrique et son engrenement, sur n echantillons BOUCLABLES.

    Toutes les partielles sont des multiples entiers de 1/T : c'est la seule
    facon qu'une sinusoide se raccorde a elle-meme au bout de la boucle. On
    arrondit donc chaque frequence au multiple le plus proche au lieu de la
    poser telle quelle — un dixieme de hertz d'erreur, et le raccord claque.
    """
    T = n / SR
    t = np.arange(n) / SR
    base = rpm * GEAR_RATIO / 60.0                        # tours/s du demarreur
    mesh = base * PINION_TEETH

    y = np.zeros(n)
    for k, level in [(1, 1.00), (2, 0.42), (3, 0.20), (4, 0.10), (6, 0.05)]:
        f = round(mesh * k / (1.0 / T)) * (1.0 / T)       # cale sur la boucle
        y += level * np.sin(2.0 * np.pi * f * t + k * 0.7)
    # Le collecteur du moteur electrique : un frottement large bande, module
    # par la rotation. Sans lui le sifflement est une onde de synthetiseur.
    brush = rng.standard_normal(n)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    brush = apply_filter(brush, highpass(f, 1200.0, 2) * lowpass(f, 7000.0, 2))
    brush *= 1.0 + 0.6 * np.sin(2.0 * np.pi * round(base / (1.0 / T)) * (1.0 / T) * t)
    y = y / (np.abs(y).max() + 1e-9) + 0.22 * brush / (np.abs(brush).max() + 1e-9)
    return amp * y / (np.abs(y).max() + 1e-9)


def make_starter(rng):
    """Le demarreur qui tourne, bouclable."""
    period = 1.0 / fire_hz(STARTER_RPM)
    n = int(round(FIRES_PER_LOOP * period * SR))
    out = np.zeros(n)

    # Les compressions, regulieres. Elles ne sont PAS toutes identiques : les
    # quatre cylindres n'ont ni la meme compression ni le meme calage, et c'est
    # cette irregularite qui fait entendre un moteur plutot qu'un metronome.
    tail = np.arange(int(0.22 * SR)) / SR
    for k in range(FIRES_PER_LOOP):
        cyl = k % 4
        amp = [1.00, 0.88, 0.96, 0.83][cyl]
        deep = [1.00, 1.03, 0.98, 1.01][cyl]
        jitter = [0.0, 0.004, -0.003, 0.002][cyl]
        place_wrap(out, k * period + jitter, compression(tail, rng, amp, deep))

    out = out / (np.abs(out).max() + 1e-9)
    out = 0.62 * out + 0.30 * whine(n, STARTER_RPM, rng)

    # La caisse : tout ca arrive par le tablier, pas par l'air libre.
    f = np.fft.rfftfreq(n, 1.0 / SR)
    out = apply_filter(out, peak(f, 62.0, 1.1, 4.0) * peak(f, 500.0, 2.2, 2.5)
                       * lowpass(f, 3400.0, 3) * tilt(f, 900.0, -3.0))
    out = soft_clip(out, 0.80, 0.95)
    return out / (np.abs(out).max() + 1e-9) * 0.72


def make_stall(rng):
    """Le moteur cale : les compressions s'espacent, la derniere l'arrete."""
    n = int((STALL_TIME + 0.55) * SR)
    out = np.zeros(n)

    # Le regime tombe. L'exposant 0,6 freine d'abord vite puis s'attarde : le
    # volant moteur garde de l'energie jusqu'a la compression qui le bloque.
    def rpm_at(x):
        u = min(max(x / STALL_TIME, 0.0), 1.0)
        return STALL_FROM_RPM * (1.0 - u) ** 0.6

    # On avance par PHASE, pas par temps : une compression a chaque demi-tour.
    # Espacer les coups "de plus en plus" a la main donnerait un ralenti
    # plausible mais faux — ici la cadence tombe exactement comme le regime.
    tail = np.arange(int(0.30 * SR)) / SR
    t = 0.0
    phase = 0.0
    k = 0
    fires = []
    while t < STALL_TIME:
        r = rpm_at(t)
        if r <= 1.0:
            break
        phase += fire_hz(r) * (1.0 / SR)
        if phase >= 1.0:
            phase -= 1.0
            fires.append((t, r))
            k += 1
        t += 1.0 / SR

    for i, (at, r) in enumerate(fires):
        # Plus le moteur ralentit, plus le coup est grave et large : c'est la
        # meme masse d'air comprimee plus lentement.
        u = r / STALL_FROM_RPM
        amp = 0.55 + 0.45 * (1.0 - u)
        deep = 0.72 + 0.28 * u
        place(out, at, compression(tail, rng, amp, deep))

    # La derniere : le vilebrequin s'arrete CONTRE une compression qu'il ne
    # passe plus. C'est le coup le plus fort de la sequence, et il est suivi du
    # rebond de la transmission, pas du silence.
    last = fires[-1][0] if fires else 0.0
    place(out, last + 0.02, 1.35 * compression(np.arange(int(0.45 * SR)) / SR,
                                               rng, 1.0, 0.62))
    place(out, last + 0.09, 0.30 * modes(np.arange(int(0.30 * SR)) / SR, [
        (74.0, 0.075, 1.0), (127.0, 0.045, 0.5), (196.0, 0.030, 0.25)]))
    # Le cliquetis de la transmission qui se detend, sec et bref.
    place(out, last + 0.13, 0.16 * burst(np.arange(int(0.10 * SR)) / SR,
                                         0.020, 900.0, 5200.0, 1.0, rng))

    f = np.fft.rfftfreq(n, 1.0 / SR)
    out = apply_filter(out, peak(f, 62.0, 1.1, 5.0) * lowpass(f, 3000.0, 3)
                       * tilt(f, 700.0, -4.0))
    out = soft_clip(out, 0.82, 0.96)
    return finish(out, 0.78)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--demo", metavar="WAV",
                    help="ecrit aussi la sequence demarrage -> calage")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    rng = np.random.default_rng(20260825)

    jobs = [("starter", make_starter(rng), True),
            ("stall", make_stall(rng), False)]
    for name, y, loop in jobs:
        path = os.path.join(OUT_DIR, name + ".wav")
        write_wav(path, y, loop=loop)
        ensure_import(path)
        print("%-8s %5.2f s   crete %.2f   rms %.3f%s" % (
            name, len(y) / SR, float(np.abs(y).max()), rms(y),
            "   (boucle)" if loop else ""))

    if args.demo:
        # Trois tours de demarreur, le moteur prend, puis il cale.
        starter = dict(jobs_by_name(jobs))["starter"]
        stall = dict(jobs_by_name(jobs))["stall"]
        gap = np.zeros(int(0.45 * SR))
        seq = np.concatenate([np.tile(starter, 3), gap, stall])
        write_wav(args.demo, finish(seq, 0.85), loop=False)
        print("demo     %5.2f s -> %s" % (len(seq) / SR, args.demo))


def jobs_by_name(jobs):
    return [(name, y) for name, y, _ in jobs]


if __name__ == "__main__":
    main()
