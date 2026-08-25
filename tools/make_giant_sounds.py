#!/usr/bin/env python3
"""
Sons du geant pour "Route de nuit" : le pas, et le cri quand il se leve.

    python tools/make_giant_sounds.py            # ecrit assets/audio/giant/

Tout est synthetise, comme le reste (voir make_engine_sounds.py, dont on
reprend les briques : filtres en frequence a phase minimale, soft clip, WAV).

CE QUE L'ECHELLE DIT, ET OU ON ARRETE DE L'ECOUTER
--------------------------------------------------
Le geant fait 26 m pour 1,75 m d'homme, soit une echelle de 14,9. Au nombre de
Froude, les frequences vont comme l'inverse de la racine de l'echelle : ce qui
sonne a 100 Hz chez un homme sonne a 26 Hz chez lui. C'est la loi qui donne au
pas son grave, et on la suit — le coup est cale entre 24 et 70 Hz.

On cesse de la suivre pour le CRI. Un conduit vocal quinze fois plus long
mettrait ses formants a 35, 100 et 220 Hz : personne ne l'entendrait sur des
enceintes de PC, et dans une voiture le passe-bas de l'habitacle (1300 Hz)
n'aurait plus rien a couper. Les formants sont donc remontes a 190, 560 et
1250 Hz — ceux d'un tres gros animal, pas ceux d'un geant. Le grave, lui, reste
juste : fondamentale a 34 Hz qui descend a 24. C'est le compromis habituel du
cinema, et il vaut mieux le noter que le decouvrir plus tard.

LE PAS (step.wav, 1,6 s)
------------------------
Quatre couches, toutes declenchees ensemble :

  - le coup      : quatre sinus amortis a 24, 33, 47 et 68 Hz, avec une legere
                   chute de hauteur — le sol se tasse sous la charge, donc il
                   se ramollit, donc il descend. Sans cette chute on entend un
                   tambour ; avec, on entend de la terre.
  - la claque    : bruit filtre 80-450 Hz, l'air chasse et la semelle qui plaque.
  - le gravier   : bruit 400 Hz - 4 kHz, 40 ms, plus une queue de petits chocs
                   epars (cailloux qui retombent) jusqu'a 0,6 s.
  - le souffle   : 14-22 Hz, presque inaudible, surtout senti. C'est lui qui
                   fait que le pas "pousse" au lieu de claquer.

Le jeu le rejoue tel quel pour le pietinement, une tierce plus bas et six
decibels plus fort (giant.gd, _boom) : la meme masse tombee de plus haut.

LE CRI (roar.wav, 2,9 s)
------------------------
Un train de pulsations glottales a f0 descendante, avec :

  - du JITTER (la periode varie de 3 % au hasard, lentement) et du SHIMMER
    (l'amplitude aussi). Une voix parfaitement periodique sonne synthetique ;
    ce sont ces defauts-la qui la rendent vivante.
  - une SUBHARMONIQUE a f0/2 qui monte au milieu du cri. C'est le "growl" des
    gros felins — deux regimes vibratoires en meme temps, ce que les cordes
    vocales font quand elles sont poussees. C'est la couche qui fait peur.
  - trois formants, plus le souffle : du bruit filtre large qui monte avec
    l'intensite, parce qu'un cri force fuit de l'air.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_engine_sounds import (SR, apply_filter, ensure_import, highpass,  # noqa: E402
                                lowpass, peak, soft_clip, tilt, write_wav)

OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "giant"))


# --------------------------------------------------------------------------
# Dosage a la SONIE, pas a l'amplitude
# --------------------------------------------------------------------------
#
# C'est le piege de tout son de geant, et la premiere version y est tombee : on
# empile des graves, on regarde la forme d'onde, on trouve ca enorme — et a
# l'ecoute il ne reste qu'un frottement de gravier. A 30 Hz l'oreille perd
# 40 dB par rapport a 1 kHz. Une couche a 24 Hz qui occupe 86 % de l'energie du
# fichier peut donc etre parfaitement inaudible, pendant qu'une pincee de bruit
# a 2 kHz, invisible sur la courbe, porte tout le son.
#
# Chaque couche est donc ramenee a une sonie unite (RMS pondere A) avant d'etre
# dosee. Les poids ci-dessous se lisent alors comme ce qu'on entend, pas comme
# ce qu'on trace. Les couches d'infra gardent au passage une amplitude BRUTE
# enorme, ce qui est correct : elles sont ressenties, pas entendues.

def a_weight(f):
    """Gain de la ponderation A, rapporte a 1 kHz."""
    f = np.maximum(np.asarray(f, dtype=float), 1e-6)

    def r(x):
        return (12194.0 ** 2 * x ** 4
                / ((x ** 2 + 20.6 ** 2)
                   * np.sqrt((x ** 2 + 107.7 ** 2) * (x ** 2 + 737.9 ** 2))
                   * (x ** 2 + 12194.0 ** 2)))
    return r(f) / r(np.array(1000.0))


def a_rms(x):
    """Sonie approchee : RMS du signal pondere A."""
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    return float(np.sqrt(np.mean(np.fft.irfft(np.fft.rfft(x) * a_weight(f), len(x)) ** 2))) + 1e-12


def mix(layers):
    """layers : liste de (nom, signal, poids de sonie). Renvoie le melange."""
    out = None
    for _, x, w in layers:
        y = x / a_rms(x) * w
        out = y if out is None else out + y
    return out


def modes(n, table, rng):
    """Somme de sinus amortis. Chaque entree : (frequence, duree a -60 dB,
    amplitude, chute de hauteur en fraction sur la duree)."""
    t = np.arange(n) / SR
    y = np.zeros(n)
    for f0, decay, amp, drop in table:
        # Hauteur qui glisse : on integre la frequence, sinon on fabrique un
        # saut de phase au lieu d'un glissando.
        f = f0 * (1.0 - drop * (1.0 - np.exp(-t / (decay * 0.5))))
        phase = 2.0 * np.pi * np.cumsum(f) / SR
        y += amp * np.exp(-6.91 * t / decay) * np.sin(phase + rng.uniform(0, 2 * np.pi))
    return y


def burst(n, shape, attack, decay, rng, power=1.0):
    """Bouffee de bruit filtre, attaque courte et decroissance exponentielle."""
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    x = apply_filter(x, shape(np.fft.rfftfreq(n, 1.0 / SR)))
    env = (1.0 - np.exp(-t / max(attack, 1e-4))) * np.exp(-t / decay)
    return x * env ** power


# --------------------------------------------------------------------------
# Le pas
# --------------------------------------------------------------------------

def make_step(rng):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1.0 / SR)

    # L'infra : la note du sol. On ne l'ENTEND pas, on la recoit — d'ou un poids
    # de sonie faible et, malgre tout, la plus grosse amplitude du fichier.
    sub = modes(n, [
        (24.0, 1.05, 1.00, 0.07),
        (33.0, 0.80, 0.72, 0.06),
        (16.0, 0.55, 0.55, 0.10),
    ], rng)
    sub *= 1.0 - np.exp(-t / 0.008)               # le sol s'enfonce avant de repousser

    # Le corps : 55 a 165 Hz. C'est CETTE bande qu'on entend comme "enorme" —
    # la premiere version n'en avait presque rien et sonnait creux.
    body = modes(n, [
        (57.0, 0.42, 1.00, 0.06),
        (88.0, 0.30, 0.80, 0.05),
        (124.0, 0.21, 0.55, 0.05),
        (165.0, 0.14, 0.34, 0.04),
    ], rng)
    body *= 1.0 - np.exp(-t / 0.004)

    # La claque : l'air chasse sous une semelle de 4 m sur 1,7, et la terre qui
    # se tasse d'un coup.
    slap = burst(n, lambda ff: lowpass(ff, 700.0, 3) * highpass(ff, 110.0, 2)
                 * peak(ff, 245.0, 1.2, 7.0), 0.004, 0.17, rng)

    # Le gravier. Deux temps : la projection, puis les cailloux qui retombent —
    # une pluie de petits chocs dont la densite s'effondre.
    grit = burst(n, lambda ff: lowpass(ff, 3200.0, 2) * highpass(ff, 380.0, 2),
                 0.001, 0.048, rng)
    rain = rng.standard_normal(n) * np.exp(-t / 0.22)
    # Un caillou sur quatre-vingts : sinon c'est du bruit blanc, pas des chutes.
    rain = apply_filter(rain * (rng.random(n) < 0.0125).astype(float),
                        lowpass(f, 2800.0, 2) * highpass(f, 650.0, 2))

    # Les poids se lisent comme ce qu'on entend. Le corps mene, la claque le
    # suit de pres, le gravier n'est qu'un vernis — sans lui le coup n'aurait
    # aucun bord, avec trop il redevient un sac de graviers.
    y = mix([
        ("infra", sub, 0.16),
        ("corps", body, 1.00),
        ("claque", slap, 0.80),
        ("gravier", grit, 0.34),
        ("cailloux", rain, 0.16),
    ])
    y = soft_clip(y / np.max(np.abs(y)) * 0.95)
    # Dernieres millisecondes a zero : un one-shot coupe net claque a l'arret.
    y *= np.minimum(1.0, (n - np.arange(n)) / (0.02 * SR))
    return y


# --------------------------------------------------------------------------
# Le cri
# --------------------------------------------------------------------------

def glottis(n, f0, jitter, shimmer, sub, rng):
    """Train de pulsations glottales. f0, jitter, shimmer et sub sont des
    tableaux de la longueur du signal (ils evoluent pendant le cri)."""
    # Bruit lent, pour que le jitter derive au lieu de grelotter.
    slow = apply_filter(rng.standard_normal(n),
                        lowpass(np.fft.rfftfreq(n, 1.0 / SR), 11.0, 2))
    slow /= np.std(slow) + 1e-9
    slow2 = apply_filter(rng.standard_normal(n),
                         lowpass(np.fft.rfftfreq(n, 1.0 / SR), 7.0, 2))
    slow2 /= np.std(slow2) + 1e-9

    phase = 2.0 * np.pi * np.cumsum(f0 * (1.0 + jitter * slow)) / SR

    # Modele de Rosenberg : ouverture lente (T1), fermeture brusque (T2), puis
    # glotte fermee le reste de la periode.
    #
    # C'est la FERMETURE qui fait tout. Une bosse lisse — un cosinus redresse au
    # cube, ce qu'on avait ici — n'a que quatre ou cinq harmoniques utiles : son
    # spectre s'effondre de 36 dB entre 150 et 400 Hz, et il ne reste alors plus
    # rien a mettre dans les formants. Un vrai cycle glottique casse la derivee
    # a l'instant ou les cordes se referment, et cette rupture porte le spectre
    # jusqu'en haut avec une pente douce de -12 dB par octave. On l'entend tout
    # de suite : avec la bosse c'est un tambour, avec la rupture c'est une gorge.
    u = np.mod(phase / (2.0 * np.pi), 1.0)
    t1, t2 = 0.44, 0.16
    flow = np.where(
        u < t1,
        0.5 * (1.0 - np.cos(np.pi * np.clip(u, 0.0, t1) / t1)),
        np.where(u < t1 + t2,
                 np.cos(np.pi * np.clip(u - t1, 0.0, t2) / (2.0 * t2)),
                 0.0))
    flow -= flow.mean()

    # La subharmonique : une pulsation sur deux plus forte. C'est litteralement
    # ca, un growl — le larynx qui bat a deux regimes a la fois.
    flow *= 1.0 + sub * 0.55 * np.cos(phase * 0.5)
    return flow * (1.0 + shimmer * slow2)


def make_roar(rng):
    n = int(2.9 * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1.0 / SR)

    # L'enveloppe : une inspiration courte, un corps tenu, une chute longue.
    env = np.clip(t / 0.22, 0.0, 1.0) * np.clip((2.85 - t) / 1.05, 0.0, 1.0)
    env *= 0.82 + 0.18 * np.sin(2.0 * np.pi * 1.4 * t)      # il pousse par a-coups

    # La hauteur descend : il commence en criant, il finit en grondant.
    f0 = 34.0 * (1.0 - 0.30 * np.clip((t - 0.3) / 2.2, 0.0, 1.0))
    jit = 0.020 + 0.018 * np.clip((t - 0.8) / 1.4, 0.0, 1.0)
    shim = 0.10 + 0.14 * np.clip((t - 0.6) / 1.6, 0.0, 1.0)
    # Le growl s'installe au milieu et ne repart plus.
    sub = np.clip((t - 0.55) / 0.8, 0.0, 1.0)

    voice = glottis(n, f0, jit, shim, sub, rng)
    # Le conduit vocal. Quatre formants (voir l'en-tete pour le choix des
    # hauteurs) et une coupure a 2,8 kHz : au-dela ca gresille au tramage, et
    # surtout ca fait siffler le souffle au lieu de gronder.
    #
    # Le `tilt` en tete est le rayonnement aux levres : ce qui sort d'une bouche
    # est la DERIVEE du debit, soit +6 dB par octave. On n'en met que 2 : la
    # gueule d'une bete de 26 m est une caisse, pas un pavillon, et a +6 le cri
    # part dans les aigus et se met a couiner (releve : 39 % de la sonie
    # au-dessus de 500 Hz a +6, contre 16 % ici).
    voice = apply_filter(voice,
                         tilt(f, 55.0, 2.0)
                         * peak(f, 190.0, 1.1, 12.0)
                         * peak(f, 380.0, 1.6, 9.0)
                         * peak(f, 720.0, 1.8, 7.0)
                         * peak(f, 1400.0, 2.2, 5.0)
                         * lowpass(f, 2600.0, 3) * highpass(f, 30.0, 2))

    # Le souffle : un cri force fuit de l'air, et cette fuite monte avec
    # l'intensite. Sans elle on entend un instrument, pas une gorge. Il reste
    # bas : dose a l'oreille, un souffle a 2 kHz prend toute la place.
    breath = apply_filter(rng.standard_normal(n),
                          peak(f, 700.0, 0.7, 4.0) * lowpass(f, 2400.0, 3)
                          * highpass(f, 210.0, 2))

    y = env * mix([("voix", voice, 1.00), ("souffle", breath * (0.35 + 0.65 * env), 0.16)])
    y = soft_clip(y / np.max(np.abs(y)) * 0.94)
    y *= np.minimum(1.0, (n - np.arange(n)) / (0.03 * SR))
    return y


# --------------------------------------------------------------------------

BANDS = [(0, 40), (40, 80), (80, 200), (200, 500), (500, 1500), (1500, 4000), (4000, 22050)]


def report(name, y):
    """Les DEUX repartitions, et c'est tout l'interet de les mettre cote a cote.

    A gauche l'energie brute : celle qu'on voit sur la forme d'onde, celle qui
    remplit le fichier, celle que le corps recoit. A droite la sonie ponderee A :
    ce qui sortira reellement des enceintes. Sur un son de geant les deux
    colonnes ne se ressemblent pas du tout, et confondre l'une avec l'autre
    donne soit un fichier vide de graves, soit un fichier qu'on n'entend pas.
    """
    f = np.fft.rfftfreq(len(y), 1.0 / SR)
    spec = np.abs(np.fft.rfft(y)) ** 2
    aud = spec * a_weight(f) ** 2
    print("%-5s %5.2f s   crete %.3f   sonie %.4f        brut   entendu" % (
        name, len(y) / SR, float(np.max(np.abs(y))), a_rms(y)))
    for a, b in BANDS:
        sel = (f >= a) & (f < b)
        r = float(spec[sel].sum() / (spec.sum() + 1e-30))
        w = float(aud[sel].sum() / (aud.sum() + 1e-30))
        print("   %5d-%5d Hz  %22s %5.1f %%  %5.1f %%  %s" % (
            a, b, "", 100.0 * r, 100.0 * w, "#" * int(round(40 * w))))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rng = np.random.default_rng(20260825)
    for name, y in [("step", make_step(rng)), ("roar", make_roar(rng))]:
        path = os.path.join(OUT_DIR, name + ".wav")
        write_wav(path, y, loop=False)
        ensure_import(path)
        report(name, y)


if __name__ == "__main__":
    main()
