#!/usr/bin/env python3
"""
Rendu hors ligne d'une sequence de conduite avec TOUS les sons du jeu, aux
niveaux par defaut de engine_audio.gd et cabin_audio.gd : pour juger la
balance moteur / route / vent / commandes a l'oreille sans lancer le jeu.

    python tools/render_audio_demo.py out.wav

Lit les WAV de assets/audio/ tels qu'ils sont (donc ce que Godot joue) et
reproduit les memes lois de volume que les deux scripts GDScript. Si on change
un volume_db dans le jeu, le changer aussi dans LEVELS.

Sequence (23 s) : ralenti, depart en 1re jusqu'au rupteur, 2e, 3e (la vitre
conducteur s'ouvre a la manivelle de 10,5 a 12,5 s), pied leve, la vitre se
referme pendant le freinage, point mort, frein a main tire puis relache.
"""

import glob
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_engine_sounds import SR, read_wav, write_wav  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
ENGINE_DIR = os.path.join(ROOT, "assets", "audio", "engine")
CABIN_DIR = os.path.join(ROOT, "assets", "audio", "cabin")

## Copie des valeurs par defaut des deux scripts GDScript.
LEVELS = dict(engine=-4.0, road=-13.0, wind=-15.0, shift=-11.0, handbrake=-13.0,
              engine_out=-7.0, wind_open=-8.0, buffet=-14.0, road_open=-16.0, crank=-18.0)
WINDOW_BOOST = 0.25
IDLE, REDLINE = 850.0, 6800.0

## Vitre conducteur : (instant s, ouverture). Ouverte pendant la 3e et le pied
## leve, refermee pendant le freinage.
WINDOW = [(0.0, 0.0), (10.5, 0.0), (12.5, 1.0), (16.5, 1.0), (18.5, 0.0), (23.0, 0.0)]

## (instant s, regime, vitesse m/s, accelerateur, en prise). Regime et vitesse
## sont interpoles lineairement ; accelerateur et prise tiennent jusqu'a la
## cle suivante.
KEYS = [
    (0.0, 850, 0.0, 0.0, False),
    (1.5, 850, 0.0, 1.0, True),       # 1re
    (4.6, 6800, 14.0, 1.0, True),
    (5.0, 6800, 14.0, 1.0, True),     # 0,4 s sur le rupteur
    (5.05, 6800, 14.0, 0.0, False),   # debraye, le regime retombe a 3500 tr/min/s
    (5.35, 3700, 13.4, 0.0, False),
    (5.4, 4200, 13.4, 1.0, True),     # 2e
    (9.5, 6700, 23.6, 1.0, True),
    (9.55, 6700, 23.6, 0.0, False),
    (9.85, 3800, 23.4, 0.0, False),
    (9.9, 4900, 23.4, 1.0, True),     # 3e
    (14.0, 6200, 30.6, 1.0, True),
    (14.05, 6200, 30.6, 0.0, True),   # pied leve, en prise
    (17.0, 5550, 26.9, 0.0, True),
    (19.0, 2250, 8.0, 0.0, True),     # freinage
    (19.05, 2250, 8.0, 0.0, False),   # point mort
    (19.3, 1650, 7.5, 0.0, False),
    (20.5, 900, 0.0, 0.0, False),     # frein a main
    (23.0, 850, 0.0, 0.0, False),
]
SHIFTS = [5.0, 9.5, 19.0]
HANDBRAKE_PULL = 19.5
HANDBRAKE_RELEASE = 22.0


def db(x):
    return 10.0 ** (x / 20.0)


def periodic(loop, pitch):
    pos = np.cumsum(pitch)
    return np.interp(pos % loop.size, np.arange(loop.size + 1), np.append(loop, loop[0]))


def trajectory():
    t_end = KEYS[-1][0]
    n = int(t_end * SR)
    t = np.arange(n) / SR
    kt = np.array([k[0] for k in KEYS])
    rpm = np.interp(t, kt, [k[1] for k in KEYS])
    v = np.interp(t, kt, [k[2] for k in KEYS])
    idx = np.searchsorted(kt, t, side="right") - 1
    thr = np.array([k[3] for k in KEYS])[idx]
    eng = np.array([k[4] for k in KEYS])[idx]
    win = np.interp(t, [w[0] for w in WINDOW], [w[1] for w in WINDOW])
    return t, rpm, v, thr, eng, win


def render_engine(t, rpm, thr, eng, win):
    n = t.size
    points = []
    for p in sorted(glob.glob(os.path.join(ENGINE_DIR, "engine_on_*.wav"))):
        r = int(re.search(r"engine_on_(\d+)\.wav", p).group(1))
        out_path = p.replace("engine_on_", "engine_out_")
        points.append((r, read_wav(p), read_wav(p.replace("engine_on_", "engine_off_")),
                       read_wav(out_path) if os.path.exists(out_path) else None))
    grid = np.array([p[0] for p in points], dtype=float)
    open_fx = np.clip(win, 0.0, 1.0) ** 0.6

    # Charge, rupteur, flottement : copie d'engine_audio.gd.
    # Rupteur : car.gd coupe l'allumage 60 ms a la ligne rouge, rebond a ~7,5 Hz.
    limiter = (thr > 0.0) & (rpm > REDLINE - 50.0)
    target = np.where(eng, thr, thr * 0.6)
    target = np.where(limiter & ((t * 7.5) % 1.0 < 0.5), 0.0, target)
    load = np.zeros(n)
    for i in range(1, n):
        rate = 40.0 if limiter[i] else (10.0 if target[i] > load[i - 1] else 5.0)
        load[i] = load[i - 1] + (target[i] - load[i - 1]) * min(rate / SR, 1.0)
    rng = np.random.default_rng(3)
    steps = rng.uniform(-1.0, 1.0, int(n / SR * 6) + 2)
    wob = np.interp(t, np.arange(steps.size) / 6.0, steps)
    norm = np.clip((rpm - IDLE) / (REDLINE - IDLE), 0.0, 1.0)
    r = rpm * (1.0 + 0.007 * wob * (1.0 - 0.75 * norm))
    master = db(LEVELS["engine"]) * (0.5 + 0.5 * norm) * (0.72 + 0.28 * load) \
        * (1.0 + WINDOW_BOOST * open_fx)
    g_out = open_fx * master * (0.4 + 0.6 * load) * db(LEVELS["engine_out"])

    out = np.zeros(n)
    for j, (rj, on, off, outside) in enumerate(points):
        one_hot = np.zeros(len(points))
        one_hot[j] = 1.0
        g = np.interp(r, grid, one_hot)
        out += g * master * (periodic(on, r / rj) * load + periodic(off, r / rj) * (1.0 - load))
        if outside is not None:
            out += g * g_out * periodic(outside, r / rj)
    return out


def render_cabin(t, v, win):
    n = t.size
    fx = np.clip(win, 0.0, 1.0) ** 0.6
    wopen = read_wav(os.path.join(CABIN_DIR, "wind_open.wav"))
    buffet = read_wav(os.path.join(CABIN_DIR, "wind_buffet.wav"))
    ropen = read_wav(os.path.join(CABIN_DIR, "road_open.wav"))
    crank = read_wav(os.path.join(CABIN_DIR, "crank.wav"))
    road = read_wav(os.path.join(CABIN_DIR, "road_roll.wav"))
    wlo = read_wav(os.path.join(CABIN_DIR, "wind_low.wav"))
    whi = read_wav(os.path.join(CABIN_DIR, "wind_high.wav"))
    r = np.clip(v / 30.0, 0.0, 1.0) ** 0.8
    out = periodic(road, 0.85 + 0.35 * np.clip(v / 40.0, 0.0, 1.0)) * r * db(LEVELS["road"])
    w = np.clip((v - 4.0) / 36.0, 0.0, 1.0)
    wg = w ** 1.6 * db(LEVELS["wind"])
    out += (periodic(wlo, np.ones(n)) * np.sqrt(1.0 - 0.75 * w) + periodic(whi, np.ones(n)) * np.sqrt(w)) * wg

    # Vitre ouverte : memes lois que cabin_audio.gd.
    out += periodic(wopen, 0.9 + 0.2 * np.clip(v / 40.0, 0.0, 1.0)) \
        * fx * np.clip(v / 35.0, 0.0, 1.0) ** 1.3 * db(LEVELS["wind_open"])
    out += periodic(buffet, np.ones(n)) * fx * np.exp(-((v - 25.0) / 12.0) ** 2) * db(LEVELS["buffet"])
    out += periodic(ropen, np.ones(n)) * fx * np.clip(v / 30.0, 0.0, 1.0) * db(LEVELS["road_open"])
    moving = (np.abs(np.diff(win, prepend=win[0])) > 1e-9).astype(float)
    moving = np.convolve(moving, np.ones(int(0.04 * SR)) / int(0.04 * SR), mode="same")
    out += periodic(crank, np.ones(n)) * moving * db(LEVELS["crank"])

    rng = np.random.default_rng(9)
    shots = [(at, "gear_shift.wav", LEVELS["shift"]) for at in SHIFTS]
    shots += [(HANDBRAKE_PULL, "handbrake_pull.wav", LEVELS["handbrake"]),
              (HANDBRAKE_RELEASE, "handbrake_release.wav", LEVELS["handbrake"])]
    for at, name, level in shots:
        y = read_wav(os.path.join(CABIN_DIR, name))
        # Le jeu desaccorde chaque lecture de +-6 %.
        y = np.interp(np.arange(0, y.size, rng.uniform(0.94, 1.06)), np.arange(y.size), y)
        i = int(at * SR)
        j = min(i + y.size, n)
        out[i:j] += y[:j - i] * db(level)
    return out


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "demo_complete.wav"
    t, rpm, v, thr, eng, win = trajectory()
    engine = render_engine(t, rpm, thr, eng, win)
    cabin = render_cabin(t, v, win)
    mix = engine + cabin
    # Une seule constante pour tout : la balance est celle du jeu.
    k = 0.9 / np.abs(mix).max()
    write_wav(path, mix * k, loop=False)

    def rms_db(x):
        return 20.0 * np.log10(np.sqrt(np.mean(x * x)) + 1e-9)
    print("moteur  %.1f dBFS rms   habitacle %.1f dBFS rms   (avant normalisation x%.2f)" % (
        rms_db(engine), rms_db(cabin), k))
    for a, b, label in ((0.0, 1.5, "ralenti"), (2.0, 5.0, "1re"), (10.0, 10.5, "3e fermee"),
                        (12.5, 14.0, "3e ouverte"), (14.5, 16.5, "pied leve, ouverte"),
                        (19.6, 20.5, "frein a main")):
        s = slice(int(a * SR), int(b * SR))
        print("  %-12s moteur %6.1f   habitacle %6.1f dBFS" % (label, rms_db(engine[s]), rms_db(cabin[s])))
    print("demo :", path)


if __name__ == "__main__":
    main()
