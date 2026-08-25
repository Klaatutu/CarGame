#!/usr/bin/env python3
"""
Sons du Webley pour "Route de nuit" : le coup de feu et le rechargement.

    python tools/make_gun_sounds.py                 # ecrit assets/audio/gun/
    python tools/make_gun_sounds.py --demo x.wav    # + la sequence complete

Meme atelier que le moteur et l'habitacle, dont on reprend les briques (voir
make_engine_sounds.py et make_cabin_sounds.py) : synthese modale pour la
mecanique, bouffees de bruit filtrees pour les chocs, rien d'echantillonne.

UN COUP DE FEU DANS UNE VOITURE
-------------------------------
Ce qui fait le coup n'est pas la deflagration : c'est la CAISSE. Une .455
tiree a l'air libre est un claquement sec ; tiree a cinquante centimetres du
pare-brise, dans une boite d'acier de trois metres cubes, elle devient un coup
de masse suivi d'une trainee. On synthetise donc les deux separement :

  - la source : un crack large bande de quelques millisecondes, un corps
    grave (la colonne de gaz), un "boom" modal vers 55-140 Hz et une queue de
    poudre sourde ;
  - la caisse : une reponse impulsionnelle courte (`cabin_ir`) faite de six
    premieres reflexions datees — pare-brise, glace, toit, tablier — et d'une
    queue de 200 ms. Le tout est convolue.

S'y ajoute, APRES la caisse parce qu'il n'est pas dans la voiture mais dans
l'oreille, le sifflement qui reste quand on tire sans protection.

LE RECHARGEMENT SUIT LA MECANIQUE, PAS L'INVERSE
------------------------------------------------
revolver.gd deroule le rechargement sur une chronologie fixe. Les fichiers
sont TAILLES dessus : chacun couvre son temps entier et place son choc a
l'instant ou la piece arrive en butee. C'est pour ca que R_LATCH & co. sont
recopies ci-dessous — s'ils bougent dans revolver.gd, il faut relancer ce
script, sinon le clonc tombe a cote de l'image.

  cock    0,00 -> 0,13   detente, rochet, barillet qui indexe (avant le coup)
  shot    au lacher du chien
  dry     idem, chambre vide : il ne reste que le chien sur l'acier
  open    0,00 -> 0,52   verrou au pouce, canon qui bascule, butee
  eject   0,00 -> 0,35   etoile qui sort, six etuis qui tombent
  fill    0,00 -> 0,26   six neuves qui glissent dans les chambres
  shut    0,00 -> 0,21   canon qui remonte, claque, verrou qui se rabat
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

OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "gun"))

## Chronologie de revolver.gd. A garder synchronise (voir l'entete).
HAMMER_DROP = 0.13
R_LATCH = 0.16
R_OPEN = 0.52
R_EJECT = 0.72
R_FILL = 0.98
R_SHUT = 1.34
RELOAD_TIME = 1.55


def convolve(x, h):
    """Convolution par FFT. numpy n'a que la version directe, qui mettrait une
    minute sur une seconde de son."""
    n = x.size + h.size - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(h, m), m)[:n]


def seconds(x):
    return np.zeros(int(round(x * SR)))


def secs(x):
    return np.arange(int(round(x * SR))) / SR


# --------------------------------------------------------------------------
# La caisse
# --------------------------------------------------------------------------

## Premieres reflexions vues du siege conducteur, en (retard s, amplitude).
## Les retards sont des distances : 2,1 ms = 72 cm, la glace laterale ; 3,6 ms
## = 1,2 m, le pare-brise en biais ; etc. Les signes alternent parce qu'une
## reflexion sur une surface plus dense revient en opposition de phase une fois
## sur deux.
##
## Leurs ecarts sont VOLONTAIREMENT irreguliers. Des retards regulierement
## espaces font un peigne : le spectre se creuse a intervalles fixes, et
## l'oreille lit ces creux comme la resonance d'une plaque. La premiere version
## de ce fichier avait des retards presque en progression arithmetique, un pic
## de peigne a 700 Hz, et un coup de feu qui sonnait comme un coup de marteau.
EARLY = ((0.0021, 0.30), (0.0036, -0.24), (0.0062, 0.20), (0.0091, -0.16),
         (0.0134, 0.13), (0.0187, -0.10))

## Energie de tout ce qui n'est pas le direct (reflexions et queue), rapportee
## a celle du direct. Un habitacle garni est mat : au-dela de 1, on entend une
## piece carrelee, et le coup gonfle au lieu de claquer.
ROOM_ENERGY = 0.85


def cabin_ir(rng, length=0.28):
    """Reponse de l'habitacle a un coup sec. Courte : trois metres cubes
    garnis de tissu ne tiennent pas une reverberation."""
    n = int(length * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1.0 / SR)

    late = np.zeros(n)
    for at, amp in EARLY:
        late[int(at * SR)] += amp
    # La queue diffuse, eteinte en 45 ms. Rien avant 10 ms : une reverberation
    # ne peut pas preceder ses propres premieres reflexions. On lui donne
    # l'energie des reflexions datees, moitie-moitie.
    #
    # Elle est construite EN FREQUENCE — amplitude constante, phase au hasard —
    # et non par un tirage gaussien. C'est le point qui decide du timbre. Le
    # spectre fin d'un bruit gaussien fluctue de ±10 dB au hasard ; convolue
    # avec le coup, chacune de ces bosses SONNE pendant toute la queue, et une
    # poignee de frequences qui tiennent 50 ms, c'est ce que l'oreille appelle
    # une plaque de tole. A amplitude constante, la queue ne colore rien : elle
    # ne fait que diffuser. (Meme construction que les boucles de vent et de
    # route dans make_cabin_sounds.py, pour la meme raison.)
    spec = np.exp(1j * rng.uniform(0.0, 2.0 * np.pi, n // 2 + 1))
    spec[0] = 0.0
    tail = np.fft.irfft(spec, n) * np.exp(-t / 0.045)
    tail[:int(0.010 * SR)] = 0.0
    late += tail * math.sqrt(float((late * late).sum())
                             / (float((tail * tail).sum()) + 1e-12))

    # Chaque rebond perd ses aigus : un habitacle est garni de tissu, il n'est
    # pas carrele. Sans ce filtre, le peigne des premieres reflexions colore
    # tout le haut du spectre et donne au coup son timbre de tole.
    late = apply_filter(late, highpass(f, 70.0, 2) * lowpass(f, 1600.0, 2))

    # Le tout se dose EN ENERGIE, pas en amplitude. Une queue de 280 ms dont
    # chaque echantillon vaut 0,3 semble discrete et porte en realite trois fois
    # l'energie du direct : la convolution la fait alors gonfler pendant 30 ms,
    # et le coup perd son claquement.
    ir = np.zeros(n)
    ir[0] = 1.0
    ir += late * ROOM_ENERGY / math.sqrt(float((late * late).sum()) + 1e-12)
    return ir


def in_cabin(x, rng, wet=1.0):
    """Passe le signal dans la caisse. ir[0] = 1 : le direct est dedans."""
    ir = cabin_ir(rng).copy()
    ir[1:] *= wet
    return convolve(x, ir)[:x.size]


# --------------------------------------------------------------------------
# Briques
# --------------------------------------------------------------------------

def clink(t, base, decay, amp, rng):
    """Petit choc de laiton : trois partiels inharmoniques et un souffle. Les
    rapports 1,83 et 2,71 ne sont pas harmoniques — un etui n'est pas une
    corde, et des partiels entiers sonneraient comme une cloche accordee."""
    y = modes(t, [(base, decay, 1.0), (base * 1.83, decay * 0.7, 0.55),
                  (base * 2.71, decay * 0.5, 0.30)])
    y += burst(t, decay * 0.5, base * 0.8, 6000.0, 0.35, rng)
    return amp * y / (np.abs(y).max() + 1e-9)


def steel(t, low, high, decay, amp, rng):
    """Choc acier sur acier : une piece grave (la carcasse encaisse) et une
    piece aigue (les deux surfaces qui se rencontrent)."""
    y = modes(t, [(low, decay * 4.0, 0.8), (low * 2.1, decay * 2.0, 0.4),
                  (high, decay, 0.6), (high * 1.6, decay * 0.7, 0.3)])
    y += burst(t, decay * 0.6, high * 0.5, 5000.0, 0.4, rng)
    return amp * y / (np.abs(y).max() + 1e-9)


def rub(length, lo, hi, rng, shape=None):
    """Frottement : du bruit filtre sous une enveloppe. Sert a tout ce qui
    GLISSE — le verrou sous le pouce, la charniere du canon, l'etoile dans son
    logement. `shape` module l'intensite le long du geste (0..1 -> gain)."""
    n = int(length * SR)
    t = np.arange(n) / SR
    x = rng.standard_normal(n + int(0.1 * SR))
    f = np.fft.rfftfreq(x.size, 1.0 / SR)
    x = apply_filter(x, highpass(f, lo, 2) * lowpass(f, hi, 3))[:n]
    env = np.sin(np.pi * np.clip(t / length, 0.0, 1.0)) ** 0.7   # entre et sort en douceur
    if shape is not None:
        env = env * shape(t / length)
    return x * env / (np.abs(x * env).max() + 1e-9)


def case_drop(out, at, rng, amp):
    """Un etui qui tombe et rebondit sur le plancher. Chaque rebond est plus
    court, plus faible et un peu plus grave que le precedent."""
    t = secs(0.14)
    base = rng.uniform(1500.0, 2400.0)
    a = amp
    while a > amp * 0.12 and at < out.size / SR - 0.14:
        place(out, at, clink(t, base, rng.uniform(0.004, 0.011), a, rng))
        # Un peu de plancher avec : le tapis encaisse, il ne tinte pas.
        place(out, at, 0.5 * a * modes(t, [(230.0, 0.012, 1.0), (410.0, 0.007, 0.4)]))
        at += rng.uniform(0.028, 0.070)
        a *= rng.uniform(0.42, 0.62)
        base *= rng.uniform(0.94, 1.06)


# --------------------------------------------------------------------------
# Le coup de feu
# --------------------------------------------------------------------------

def blast(rng):
    """
    La deflagration seule, hors caisse.

    UNE EXPLOSION N'EST PAS UN CHOC. Frapper une piece la fait vibrer a SES
    frequences : c'est la synthese modale, quelques sinus amortis, et c'est
    exactement ce qu'il faut pour un verrou ou une charniere. Employee pour un
    coup de feu, elle donne un marteau sur une tole — l'oreille entend des
    frequences accordees et en deduit une plaque.

    Une charge de poudre, elle, ne vibre pas : elle POUSSE. Une bulle de gaz se
    detend d'un coup, envoie un front de pression, puis la depression revient.
    C'est une onde de Friedlander, p(t) = (1 - t/T) e^(-t/T) : un front raide,
    une detente, une phase negative, et pas une seule frequence propre. Son
    spectre est lisse — d'ou le "boum" au lieu du "clang".

    Par-dessus, trois couches de BRUIT (jamais de modes) : le jet de gaz qui
    sort du canon, le crack de detente, et la trainee de poudre.
    """
    n = int(0.40 * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1.0 / SR)

    def wave(T, amp):
        # La montee est adoucie sur 80 us. Un front vraiment vertical ne serait
        # qu'un clic d'un seul echantillon, et aucun micro n'en a jamais capte.
        return amp * (1.0 - t / T) * np.exp(-t / T) * (1.0 - np.exp(-t / 0.00008))

    def band(decay, shape, attack=0.00010):
        env = (1.0 - np.exp(-t / attack)) * np.exp(-t / decay)
        y = apply_filter(rng.standard_normal(n) * env, shape)
        return y / (np.abs(y).max() + 1e-9)

    # Le souffle. Deux fronts superposes : un court qui donne la claque (son
    # spectre culmine vers 120 Hz), un plus long qui donne la masse.
    punch = wave(0.0013, 1.0) + wave(0.0060, 0.68)
    punch /= np.abs(punch).max() + 1e-9
    # Le jet de gaz : le gros du corps du coup, large et court.
    roar = band(0.030, highpass(f, 120.0, 2) * lowpass(f, 1600.0, 2)
                * peak(f, 420.0, 0.6, 3.0))
    # Le crack. Plafonne a 5,5 kHz : au-dessus, sur des haut-parleurs
    # d'ordinateur, ce n'est plus une detonation, c'est du gresillement.
    crack = band(0.0035, highpass(f, 1500.0, 2) * lowpass(f, 5500.0, 3)
                 * tilt(f, 2500.0, -3.0))
    # La trainee de poudre, sourde, qui donne au coup sa duree.
    smoke = band(0.100, highpass(f, 60.0, 2) * lowpass(f, 700.0, 3), attack=0.0006)

    y = 1.0 * punch + 0.68 * roar + 0.32 * crack + 0.35 * smoke
    return y / (np.abs(y).max() + 1e-9)


def make_shot(rng):
    out = seconds(1.20)
    t = secs(0.10)

    # Le chien sur l'amorce, DERRIERE le coup et non devant. C'est un detail de
    # deux millisecondes que la deflagration recouvre entierement ; le laisser
    # sortir, c'est entendre un marteau avant d'entendre le coup.
    place(out, 0.0, 0.10 * steel(t, 380.0, 1900.0, 0.0018, 1.0, rng))
    place(out, 0.0012, blast(rng))

    y = in_cabin(out, rng)

    # Saturation. Un coup de feu depasse ce que l'oreille — et n'importe quel
    # micro — peut suivre lineairement : ecraser les cretes est ce qui reste de
    # cet exces, et c'est aussi ce qui donne son grain a la detonation.
    y = soft_clip(finish(y, 1.0), knee=0.55, ceiling=0.99)
    return finish(y, 0.98)


def make_dry(rng):
    """Chambre vide : le chien va au bout de sa course et frappe l'acier. Sec,
    net, et beaucoup plus fort qu'on ne croit dans un habitacle silencieux."""
    out = seconds(0.40)
    t = secs(0.25)
    place(out, 0.0, steel(t, 420.0, 2050.0, 0.0032, 1.0, rng))
    place(out, 0.0012, 0.22 * modes(t, [(210.0, 0.024, 1.0), (130.0, 0.038, 0.6)]))
    return finish(in_cabin(out, rng, wet=0.6), 0.62)


def make_cock(rng):
    """Double action : une seule pression fait tout. On entend le rochet
    pousser le barillet, puis le verrou tomber dans son cran juste avant que le
    chien se lache. Tout tient dans les 130 ms de HAMMER_DROP."""
    out = seconds(0.26)
    t = secs(0.12)

    # La detente part : ressort et frottement, rien de pointu.
    place(out, 0.0, 0.22 * rub(0.11, 200.0, 1400.0, rng))
    # Le rochet : trois dents qui defilent en s'accelerant, le barillet prend
    # de la vitesse.
    for k, at in enumerate((0.018, 0.052, 0.080)):
        place(out, at, steel(t, 620.0, 1500.0 + 120.0 * k, 0.0016,
                             0.30 + 0.10 * k, rng))
    # Le verrou du barillet tombe dans son cran : le clic franc, celui qu'on
    # reconnait. Il arrive juste avant HAMMER_DROP.
    place(out, HAMMER_DROP - 0.026, steel(t, 520.0, 2400.0, 0.0026, 0.85, rng))
    return finish(in_cabin(out, rng, wet=0.5), 0.42)


# --------------------------------------------------------------------------
# Le rechargement
# --------------------------------------------------------------------------

def make_open(rng):
    """Le pouce pousse le verrou, le canon se decroche et pique vers l'avant
    jusqu'a la butee. Le geste dure R_OPEN ; la butee tombe a R_OPEN - 0,02,
    parce que l'oeil voit le canon s'arreter un poil avant la fin de la
    courbe lissee."""
    out = seconds(R_OPEN + 0.38)
    t = secs(0.22)

    place(out, 0.0, steel(t, 480.0, 2600.0, 0.0022, 0.55, rng))          # le verrou mord
    place(out, 0.006, 0.16 * rub(R_LATCH - 0.01, 300.0, 2000.0, rng))    # sa course
    place(out, R_LATCH, steel(t, 250.0, 1150.0, 0.0035, 0.45, rng))      # le canon se decroche
    # La charniere : un frottement grave qui s'ouvre a mesure que le canon
    # prend de la vitesse, puis retombe en fin de course.
    swing = R_OPEN - 0.02 - R_LATCH
    place(out, R_LATCH, 0.20 * rub(swing, 120.0, 900.0, rng,
                                   shape=lambda u: 0.35 + 0.65 * np.sin(np.pi * u ** 0.7)))
    # La butee. C'est le choc du rechargement : toute la masse du bloc canon
    # arrive d'un coup sur la carcasse.
    place(out, R_OPEN - 0.02, steel(t, 118.0, 900.0, 0.0060, 1.0, rng))
    place(out, R_OPEN - 0.02, 0.30 * modes(t, [(64.0, 0.055, 1.0), (152.0, 0.030, 0.5)]))
    return finish(in_cabin(out, rng, wet=0.55), 0.70)


def make_eject(rng):
    """L'etoile d'extraction sort avec le canon ouvert, decolle les six etuis
    et les chasse. Ils tombent ensuite ou ils veulent — sur le siege, entre les
    pedales — pendant que l'etoile rentre."""
    out = seconds(0.62)
    t = secs(0.16)

    travel = R_EJECT - R_OPEN                       # 0,20 s de course
    place(out, 0.0, 0.24 * rub(travel, 400.0, 2600.0, rng,
                               shape=lambda u: 0.4 + 0.6 * u))           # l'etoile monte
    # Les etuis se decollent un par un, pas ensemble : ils ne collent pas tous
    # pareil.
    for k in range(6):
        at = 0.045 + k * 0.021 + rng.uniform(-0.006, 0.006)
        place(out, at, clink(t, rng.uniform(1700.0, 2600.0), 0.005,
                             rng.uniform(0.10, 0.18), rng))
    place(out, travel, steel(t, 300.0, 1700.0, 0.0030, 0.50, rng))       # l'etoile en butee
    for k in range(6):
        case_drop(out, travel + 0.02 + k * rng.uniform(0.012, 0.045), rng,
                  rng.uniform(0.22, 0.40))
    return finish(in_cabin(out, rng, wet=0.5), 0.66)


def make_fill(rng):
    """Six cartouches neuves. Elles ne tombent pas d'un bloc : la main les
    presente, elles glissent dans les chambres et butent sur la collerette."""
    out = seconds(0.55)
    t = secs(0.14)
    span = R_FILL - R_EJECT                          # 0,26 s pour les six
    for k in range(6):
        at = max(0.0, k * span / 6.0 + rng.uniform(-0.008, 0.008))
        place(out, at, 0.10 * rub(0.030, 600.0, 3000.0, rng))            # elle glisse
        place(out, at + 0.022, clink(t, rng.uniform(900.0, 1400.0),
                                     rng.uniform(0.004, 0.007),
                                     rng.uniform(0.35, 0.55), rng))      # elle bute
        place(out, at + 0.022, 0.20 * modes(t, [(320.0, 0.014, 1.0)]))
    # La paume qui pousse le paquet au fond.
    place(out, span, 0.35 * steel(t, 200.0, 800.0, 0.0060, 1.0, rng))
    return finish(in_cabin(out, rng, wet=0.45), 0.60)


def make_shut(rng):
    """Le canon remonte et CLAQUE : c'est le bruit qui dit que l'arme est de
    nouveau bonne. Le verrou se rabat une fraction de seconde apres."""
    out = seconds(0.55)
    t = secs(0.22)
    swing = RELOAD_TIME - R_SHUT                     # 0,21 s pour refermer
    place(out, 0.0, 0.18 * rub(swing - 0.02, 120.0, 900.0, rng,
                               shape=lambda u: 0.3 + 0.7 * u))
    place(out, swing - 0.02, steel(t, 135.0, 1350.0, 0.0055, 1.0, rng))  # le claquement
    place(out, swing - 0.02, 0.35 * modes(t, [(70.0, 0.045, 1.0), (168.0, 0.026, 0.5)]))
    place(out, swing + 0.006, steel(t, 560.0, 2700.0, 0.0020, 0.45, rng))  # le verrou
    return finish(in_cabin(out, rng, wet=0.55), 0.72)


# --------------------------------------------------------------------------
# Demo : la sequence complete, aux instants ou revolver.gd la joue
# --------------------------------------------------------------------------

def render_demo(shots, path):
    out = seconds(9.0)
    at = 0.4
    for _ in range(3):                       # trois coups
        place(out, at, shots["cock"] * 10.0 ** (-16.0 / 20.0))
        place(out, at + HAMMER_DROP, shots["shot"] * 10.0 ** (-3.0 / 20.0))
        at += 0.9
    place(out, at, shots["cock"] * 10.0 ** (-16.0 / 20.0))
    place(out, at + HAMMER_DROP, shots["dry"] * 10.0 ** (-10.0 / 20.0))
    at += 0.8
    for name, when, db in (("open", 0.0, -12.0), ("eject", R_OPEN, -12.0),
                           ("fill", R_EJECT, -13.0), ("shut", R_SHUT, -10.0)):
        place(out, at + when, shots[name] * 10.0 ** (db / 20.0))
    out *= 0.9 / np.abs(out).max()
    write_wav(path, out, loop=False)


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--demo")
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    rng = np.random.default_rng(19)
    shots = dict(cock=make_cock(rng), shot=make_shot(rng), dry=make_dry(rng),
                 open=make_open(rng), eject=make_eject(rng),
                 fill=make_fill(rng), shut=make_shut(rng))

    for name, y in shots.items():
        p = os.path.join(args.out, name + ".wav")
        write_wav(p, y, loop=False)
        ensure_import(p)
        print("%-12s %.2f s, crete %.2f, rms %.1f dBFS"
              % (name + ".wav", y.size / SR, np.abs(y).max(), 20 * math.log10(rms(y))))

    if args.demo:
        render_demo(shots, args.demo)
        print("demo :", args.demo)


if __name__ == "__main__":
    main()










