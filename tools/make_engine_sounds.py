#!/usr/bin/env python3
"""
Synthese des boucles de son moteur pour "Route de nuit".

    python tools/make_engine_sounds.py            # ecrit assets/audio/engine/*.wav
    python tools/make_engine_sounds.py --demo x.wav   # + un rendu de 25 s qui monte
                                                      #   et descend dans les tours

Il n'y a aucun enregistrement : tout est calcule, comme le reste du jeu.
Honda D15, 4 cylindres, 4 temps, ecoute depuis le siege conducteur.

COMMENT C'EST FAIT
------------------
Un moteur, c'est une suite d'explosions. A 4 cylindres et 4 temps, il y en a
deux par tour, donc la frequence de "tir" vaut regime / 30 : 28 Hz au ralenti,
227 Hz au rupteur. Chaque boucle est construite a un regime FIXE en trois
couches additionnees :

  1. Echappement : un train d'impulsions, une par explosion. L'attaque est
     raide (0,3 ms, c'est elle qui donne le mordant) et la decroissance dure
     120 degres de vilebrequin, donc raccourcit avec le regime. Les quatre
     cylindres n'ont pas tout a fait la meme force ni le meme calage, ce qui
     cree les "demi-ordres" qui font qu'on entend un 4 cylindres et pas une
     sirene. Le tout passe ensuite dans un filtre a resonances fixes : boom de
     caisse vers 60 Hz, ligne d'echappement, tole du tablier qui coupe les
     aigus. Fixes parce que c'est ce qui fait que le TIMBRE reste le meme
     quand le regime bouge, comme une vraie voiture.
  2. Admission : du bruit blanc hache au rythme des soupapes d'admission,
     filtre autour de 330 Hz. Presque muet pied leve.
  3. Mecanique : les culbuteurs (8 tocs par cycle, 2 a 7 kHz) et un sifflement
     large (courroies, alternateur) qui monte avec le regime.

Deux couches par regime : "on" (gaz) et "off" (frein moteur : explosions
faibles et irregulieres, admission muette, mecanique plus presente).
Le jeu fond l'une dans l'autre selon l'accelerateur.

Une troisieme, "out", c'est ce que la vitre retirait : l'echappement entendu
de dehors, le rapeux de 300 Hz a 7 kHz, sans le filtre de l'habitacle. Memes
explosions que "on" (meme graine aleatoire, donc en phase), seul le filtre
change. Le jeu l'ajoute par-dessus selon l'ouverture des vitres.

POURQUOI PLUSIEURS REGIMES
--------------------------
Une seule boucle pitchee de 850 a 6800 tr/min (x8, trois octaves) sonne comme
un jouet : les resonances montent avec elle. Avec une boucle tous les ~40 %, le
jeu n'a jamais a pitcher de plus de ~20 % et les resonances restent a leur
place. Voir scripts/engine_audio.gd pour la partie temps reel.

BOUCLES PARFAITES
-----------------
Chaque fichier contient un nombre ENTIER de cycles moteur (720 degres), donc
il boucle sans couture, sans fondu. Et comme toutes les boucles commencent sur
l'explosion du cylindre 1, le jeu peut les lire en phase : en les fondant
l'une dans l'autre, les impulsions s'additionnent au lieu de se battre.
Un chunk "smpl" dans le WAV porte la boucle, Godot la detecte a l'import.
"""

import argparse
import json
import math
import os
import re
import struct

import numpy as np

SR = 44100
LOOP_SECONDS = 3.0
CYLINDERS = 4
## Regimes des boucles. Le jeu a besoin d'une boucle SOUS le ralenti (850) et
## d'une AU-DESSUS du rupteur (6800), sinon il pitche en dehors de l'intervalle.
RPM_POINTS = [900, 1300, 1800, 2500, 3400, 4500, 5700, 7000]
OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "engine"))

## Calage et force de chaque cylindre, en fraction de cycle : c'est ce qui
## rend le moteur un peu bancal, comme un vrai. Commun a toutes les boucles
## pour qu'elles restent en phase entre elles.
CYL_OFFSET = [0.0, 0.004, -0.003, 0.002]


# --------------------------------------------------------------------------
# Filtres (en frequence, sur la boucle entiere : circulaire, donc parfait
# pour une boucle)
# --------------------------------------------------------------------------

def peak(f, fc, q, gain_db):
    """Bosse resonante : +gain_db a fc, largeur 1/q."""
    g = 10.0 ** (gain_db / 20.0)
    fs = np.maximum(f, 1e-3)
    return 1.0 + (g - 1.0) / np.sqrt(1.0 + (q * (fs / fc - fc / fs)) ** 2)


def lowpass(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def highpass(f, fc, order=2):
    fs = np.maximum(f, 1e-3)
    return 1.0 / np.sqrt(1.0 + (fc / fs) ** (2 * order))


def tilt(f, f0, db_per_oct):
    """Pente en dB/octave au-dessus de f0, plate en dessous."""
    return (np.maximum(f, f0) / f0) ** (db_per_oct / 6.02)


def min_phase(mag):
    """
    Transforme une reponse en amplitude en filtre a phase minimale (cepstre).
    Sans ca, le filtrage serait a phase nulle : chaque impulsion serait
    precedee de son echo, ce qui sonne "mou". Avec, la resonance SUIT le coup.
    """
    n = 2 * (len(mag) - 1)
    logm = np.log(np.maximum(mag, 1e-6))
    cep = np.fft.irfft(logm, n)
    w = np.zeros(n)
    w[0] = 1.0
    w[1:n // 2] = 2.0
    w[n // 2] = 1.0
    return np.exp(np.fft.rfft(cep * w))


def apply_filter(x, mag):
    return np.fft.irfft(np.fft.rfft(x) * min_phase(mag), len(x))


def exhaust_response(f):
    """Ligne d'echappement + caisse, entendues du siege."""
    # Coupure raide a 3 kHz : le tablier et les vitres ne laissent rien
    # passer au-dessus, et c'est la-haut que ca gresille.
    h = highpass(f, 32.0, 2) * lowpass(f, 3000.0, 3)
    h *= peak(f, 62.0, 2.2, 8.0)       # boom de caisse
    h *= peak(f, 128.0, 3.0, 5.0)      # ligne
    h *= peak(f, 215.0, 3.5, 4.5)
    h *= peak(f, 390.0, 4.0, 4.0)
    h *= peak(f, 640.0, 5.0, 3.0)
    h *= peak(f, 1150.0, 5.0, 2.5)     # rape
    h *= tilt(f, 300.0, -3.0)
    return h


def exhaust_outside_response(f):
    """Le pot entendu par la vitre ouverte : ce que le tablier et la glace
    retiraient. S'AJOUTE a exhaust_response, donc rien en dessous de 300 Hz."""
    h = highpass(f, 250.0, 2) * lowpass(f, 7000.0, 2)
    h *= peak(f, 700.0, 3.0, 4.0) * peak(f, 1500.0, 3.0, 5.0) * peak(f, 2600.0, 3.0, 4.0)
    h *= tilt(f, 1000.0, -2.0)
    return h


def intake_response(f):
    return highpass(f, 110.0, 2) * lowpass(f, 1800.0, 2) \
        * peak(f, 330.0, 2.5, 8.0) * peak(f, 720.0, 3.0, 3.0)


def tick_response(f):
    return highpass(f, 1500.0, 2) * lowpass(f, 4500.0, 3) * peak(f, 2800.0, 2.5, 3.0)


def whirr_response(f):
    return highpass(f, 500.0, 2) * lowpass(f, 2500.0, 3) * peak(f, 1400.0, 2.0, 3.0)


# --------------------------------------------------------------------------
# Briques
# --------------------------------------------------------------------------

def kernel(ta, td):
    """Impulsion : montee en ta, decroissance en td, crete a 1."""
    t = np.arange(int((7.0 * td + 5.0 * ta) * SR)) / SR
    k = (1.0 - np.exp(-t / ta)) * np.exp(-t / td)
    return k / k.max()


def impulses(n, k_cycles, events):
    """events : liste de (instant en cycles, amplitude) -> train d'impulsions."""
    imp = np.zeros(n)
    times = np.array([e[0] for e in events])
    amps = np.array([e[1] for e in events])
    idx = np.round(times * n / k_cycles).astype(np.int64) % n
    np.add.at(imp, idx, amps)
    return imp


def convolve_circ(x, ker):
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ker, len(x)), len(x))


def soft_clip(x, knee=0.75, ceiling=0.97):
    """Ecrase doucement les cretes : un peu de distorsion d'echappement, pas de clic."""
    a = np.abs(x)
    over = a > knee
    a = np.where(over, knee + (ceiling - knee) * np.tanh((a - knee) / (ceiling - knee)), a)
    return np.sign(x) * a


# --------------------------------------------------------------------------
# Une boucle
# --------------------------------------------------------------------------

## Met a zero les couches de bruit (admission, culbuteurs, courroies) : pour
## diagnostiquer a l'oreille d'ou vient un defaut.
NO_NOISE = False


def layer_params(rpm, layer):
    # "out" partage TOUT avec "on" sauf le filtre et l'attaque (plus seche,
    # rien ne l'amortit) : memes explosions, donc en phase avec "on".
    on = layer in ("on", "out")
    out = layer == "out"
    # Le "burble" (coups rates, irreguliers) n'existe qu'en frein moteur et
    # dans les tours. Un ralenti sain est REGULIER : des ratees aleatoires a
    # 30 Hz, ca crepite.
    burble = min(max((rpm - 1500.0) / 2000.0, 0.0), 1.0)
    # Poids relatifs (chaque couche est ramenee au meme niveau avant).
    # Le bruit doit rester tres loin derriere : du siege on entend la caisse
    # et la ligne, pas les culbuteurs ni les courroies. Et l'oreille est
    # 20 a 30 dB plus sensible a 3 kHz qu'a 30 Hz : un souffle a -25 dB sous
    # un bourdonnement grave est percu presque aussi fort que lui.
    mix = dict(exhaust=1.0, intake=0.30, ticks=0.0, whirr=0.04) if on \
        else dict(exhaust=1.0, intake=0.08, ticks=0.0, whirr=0.06)
    if NO_NOISE or out:
        mix = dict(exhaust=1.0, intake=0.0, ticks=0.0, whirr=0.0)
    return dict(
        attack=(0.0003 if out else 0.0006) if on else 0.0014,
        decay=20.0 / rpm * (1.0 if on else 1.25),        # 120 degres de vilebrequin
        cyl_amp=[1.0, 0.93, 1.05, 0.96] if on else [1.0, 0.82, 0.92, 0.76],
        amp_jitter=0.04 if on else 0.06 + 0.10 * burble,
        time_jitter=0.0015 if on else 0.002,
        dropout=0.0 if on else 0.18 * burble,
        mix=mix,
        # "out" est tres pointu (attaque seche, rien sous 250 Hz) : plus bas,
        # sinon l'ecreteur doux le rabote.
        rms_db=(-18.0 if out else -15.0) if on else -19.5,
    )


def synth_loop(rpm, layer):
    p = layer_params(rpm, layer)
    # Meme graine pour "on" et "out" : memes explosions, boucles en phase.
    rng = np.random.default_rng(int(rpm) * 7 + (1 if layer in ("on", "out") else 2))

    # Longueur : un nombre entier de cycles de 720 degres, proche de 3 s.
    f_cycle = rpm / 120.0
    k = max(1, int(round(LOOP_SECONDS * f_cycle)))
    n = int(round(k * SR / f_cycle))
    f = np.fft.rfftfreq(n, 1.0 / SR)

    # --- echappement -------------------------------------------------------
    events = []
    for c in range(k):
        for j in range(CYLINDERS):
            amp = p["cyl_amp"][j] * (1.0 + rng.normal(0.0, p["amp_jitter"]))
            if rng.random() < p["dropout"]:
                amp *= 0.3
            t = c + j / CYLINDERS + CYL_OFFSET[j] + rng.normal(0.0, p["time_jitter"])
            events.append((t, max(amp, 0.05)))
    fire = impulses(n, k, events)
    exhaust = convolve_circ(fire, kernel(p["attack"], p["decay"]))
    response = exhaust_outside_response if layer == "out" else exhaust_response
    exhaust = apply_filter(exhaust, response(f))

    # --- admission ---------------------------------------------------------
    # Chaque cylindre aspire un demi-cycle apres avoir explose.
    intake_events = [(c + j / CYLINDERS + 0.5 + CYL_OFFSET[j], 1.0)
                     for c in range(k) for j in range(CYLINDERS)]
    gate = convolve_circ(impulses(n, k, intake_events), kernel(0.002, 30.0 / rpm))
    gate /= gate.max()
    intake = rng.standard_normal(n) * (0.25 + gate)
    intake = apply_filter(intake, intake_response(f))

    # --- mecanique ---------------------------------------------------------
    tick_events = [(c + m / 8.0 + 0.011 * math.sin(m * 1.7), rng.uniform(0.6, 1.0))
                   for c in range(k) for m in range(8)]
    # Attaque de 0,3 ms et pas moins : un toc d'un seul echantillon gresille.
    tgate = convolve_circ(impulses(n, k, tick_events), kernel(0.0003, 0.0006))
    tgate /= tgate.max()
    ticks = rng.standard_normal(n) * tgate
    ticks = apply_filter(ticks, tick_response(f)) * (rpm / 3000.0) ** 0.3

    egate = convolve_circ(fire, kernel(0.001, 0.004))
    egate /= egate.max()
    whirr = rng.standard_normal(n) * (0.8 + 0.2 * egate)
    whirr = apply_filter(whirr, whirr_response(f)) * (rpm / 3000.0) ** 0.8

    # --- mix ---------------------------------------------------------------
    def rms(x):
        return math.sqrt(float(np.mean(x * x))) + 1e-12

    m = p["mix"]
    y = exhaust / rms(exhaust) * m["exhaust"]
    for sig, w in ((intake, m["intake"]), (ticks, m["ticks"]), (whirr, m["whirr"])):
        if w > 0.0:
            y = y + sig / rms(sig) * w
    y *= 10.0 ** (p["rms_db"] / 20.0) / rms(y)
    y = soft_clip(y)
    return y, k, n


# --------------------------------------------------------------------------
# WAV 16 bits mono avec chunk "smpl" (boucle avant, tout le fichier)
# --------------------------------------------------------------------------

def write_wav(path, y, loop=True):
    data = np.clip(np.round(y * 32767.0), -32768, 32767).astype("<i2").tobytes()
    n = len(y)
    chunks = []
    chunks.append(b"fmt " + struct.pack("<I", 16)
                  + struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16))
    if loop:
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<IIIIII", 0, 0, 0, n - 1, 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    chunks.append(b"data" + struct.pack("<I", len(data)) + data)
    body = b"WAVE" + b"".join(chunks)
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", len(body)) + body)


## Reglages d'import Godot. Sans ce fichier, Godot 4.8 importe en QOA
## (compresse, avec perte) ; on veut du PCM, 16 lectures en parallele ne
## coutent rien et le son reste celui qu'on a calcule. loop_mode=0 veut dire
## "detecter dans le WAV" : c'est notre chunk smpl. Godot complete le reste
## (uid, chemin du cache) au premier import.
IMPORT_TEMPLATE = """[remap]

importer="wav"
type="AudioStreamWAV"

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=0
edit/loop_begin=0
edit/loop_end=-1
compress/mode=0
"""


def ensure_import(wav_path):
    path = wav_path + ".import"
    if os.path.exists(path):
        with open(path) as fh:
            txt = fh.read()
        new = re.sub(r"compress/mode=\d+", "compress/mode=0", txt)
        if new != txt:
            with open(path, "w") as fh:
                fh.write(new)
    else:
        with open(path, "w") as fh:
            fh.write(IMPORT_TEMPLATE)


def read_wav(path):
    """Lecture minimale (pour la demo) : on saute les chunks inconnus."""
    with open(path, "rb") as fh:
        raw = fh.read()
    pos = 12
    while pos < len(raw):
        cid, size = raw[pos:pos + 4], struct.unpack("<I", raw[pos + 4:pos + 8])[0]
        if cid == b"data":
            return np.frombuffer(raw[pos + 8:pos + 8 + size], dtype="<i2") / 32768.0
        pos += 8 + size + (size & 1)
    raise ValueError(path)


# --------------------------------------------------------------------------
# Demo : le meme algorithme que engine_audio.gd, mais hors ligne
# --------------------------------------------------------------------------

## (duree, regime depart, regime arrivee, accelerateur)
DEMO_SCRIPT = [
    (2.0, 850, 850, 0.0),        # ralenti
    (1.6, 850, 6200, 1.0),       # coup de gaz, embrayage enfonce
    (0.4, 6200, 6200, 1.0),
    (2.2, 6200, 850, 0.0),       # ca redescend
    (1.0, 850, 850, 0.0),
    (3.2, 850, 6800, 1.0),       # depart en 1re
    (0.8, 6800, 6800, 1.0),      # rupteur
    (0.25, 6800, 4300, 0.0),     # passage
    (4.0, 4300, 6800, 1.0),      # 2e
    (0.25, 6800, 4800, 0.0),
    (2.5, 4800, 6000, 1.0),      # 3e
    (3.0, 6000, 3000, 0.0),      # pied leve
    (2.5, 3000, 850, 0.0),
    (1.5, 850, 850, 0.0),
]


def render_demo(points, path):
    # Trajectoire de regime et d'accelerateur, echantillon par echantillon.
    rpm, thr = [], []
    for dur, r0, r1, t in DEMO_SCRIPT:
        m = int(dur * SR)
        u = np.linspace(0.0, 1.0, m, endpoint=False)
        u = u * u * (3.0 - 2.0 * u)                   # smoothstep : pas de cassure
        rpm.append(r0 + (r1 - r0) * u)
        thr.append(np.full(m, t))
    rpm = np.concatenate(rpm)
    thr = np.concatenate(thr)
    n = len(rpm)
    t = np.arange(n) / SR

    # Charge : suit l'accelerateur avec une attaque vive et un relachement lent,
    # et le rupteur la hache.  Copie de engine_audio.gd.
    # Rupteur : dans le jeu c'est car.gd qui coupe l'allumage 60 ms des que le
    # regime touche la ligne rouge, ce qui rebondit a ~7,5 Hz. Ici on le
    # modelise par un carre a cette frequence.
    limiter = (rpm > 6800 - 50) & (thr > 0.0)
    target = np.where(limiter & ((t * 7.5) % 1.0 < 0.5), 0.0, thr)
    load = np.zeros(n)
    for i in range(1, n):
        rate = 40.0 if limiter[i] else (10.0 if target[i] > load[i - 1] else 5.0)
        load[i] = load[i - 1] + (target[i] - load[i - 1]) * min(rate / SR, 1.0)

    # Flottement de regime : marche aleatoire lente, forte au ralenti.
    rng = np.random.default_rng(3)
    steps = rng.uniform(-1.0, 1.0, int(n / SR * 6) + 2)
    wob = np.interp(t, np.arange(len(steps)) / 6.0, steps)
    norm = np.clip((rpm - 850.0) / (6800.0 - 850.0), 0.0, 1.0)
    r = rpm * (1.0 + 0.007 * wob * (1.0 - 0.75 * norm))

    master = (0.5 + 0.5 * norm) * (0.72 + 0.28 * load)
    grid = np.array([pt[0] for pt in points], dtype=float)
    out = np.zeros(n)
    for j, (rj, on, off) in enumerate(points):
        # Meme position de lecture pour toutes les boucles : elles restent en phase.
        pos = np.cumsum(r / rj)
        src_on = np.interp(pos % len(on), np.arange(len(on) + 1), np.append(on, on[0]))
        src_off = np.interp(pos % len(off), np.arange(len(off) + 1), np.append(off, off[0]))
        # Fondu lineaire entre voisines : un triangle centre sur rj, 1 au sommet.
        one_hot = np.zeros(len(points))
        one_hot[j] = 1.0
        g = np.interp(r, grid, one_hot)
        out += g * master * (src_on * load + src_off * (1.0 - load))
    # Normalise pour l'ecoute : dans le jeu c'est volume_db qui regle ca.
    out *= 0.9 / np.abs(out).max()
    write_wav(path, out, loop=False)
    return rpm, thr


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--demo", help="rendre aussi une montee/descente de regime dans ce fichier")
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--no-noise", action="store_true",
                    help="echappement seul, sans admission ni mecanique (diagnostic)")
    args = ap.parse_args()
    global NO_NOISE
    NO_NOISE = args.no_noise
    os.makedirs(args.out, exist_ok=True)

    points = []
    for rpm in RPM_POINTS:
        loops = {}
        for layer in ("on", "off", "out"):
            y, k, n = synth_loop(rpm, layer)
            name = "engine_%s_%04d.wav" % (layer, rpm)
            write_wav(os.path.join(args.out, name), y)
            ensure_import(os.path.join(args.out, name))
            loops[layer] = y
            print("%-20s %d cycles, %6d ech., %.3f s, crete %.2f" % (name, k, n, n / SR, np.abs(y).max()))
        points.append((rpm, loops["on"], loops["off"]))

    with open(os.path.join(args.out, "engine_set.json"), "w") as fh:
        json.dump(dict(sample_rate=SR, rpm=RPM_POINTS, layers=["on", "off", "out"],
                       firing_hz_per_rpm=1.0 / 30.0), fh, indent=2)

    if args.demo:
        render_demo(points, args.demo)
        print("demo :", args.demo)


if __name__ == "__main__":
    main()
