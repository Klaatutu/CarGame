# -*- coding: utf-8 -*-
"""
build_landmarks.py — LES REPÈRES DES VILLES, pour Route de nuit.

Un bourg qu'on ne reconnaît pas est un décor ; un bourg qu'on reconnaît est un
lieu. map.gd le dit déjà de la carte — « une carte se lit, se mémorise,
s'apprend ; un graphe procédural n'a pas de pays ». Ces modèles sont la même
idée posée dans le monde : chaque ville porte UNE silhouette qui n'est qu'à
elle, assez haute pour dépasser les maisons (town_plan.gd, BLD_H = 4,6 à
9,4 m) et assez claire pour se lire dans les phares avant qu'on ait lu le
panneau. « Assez haute » a été le point faible de quatre des huit, et ce
qu'il a fallu mesurer pour s'en apercevoir est raconté plus bas, repère par
repère.

LES HUIT, un par ville de map.gd, et pourquoi chacun est celui-là :

  ville         commodités (map.gd)          repère            ce qui luit
  ------------  ---------------------------  ----------------  --------------
  Corbeny       hôtel, distributeur          le clocher        le cadran
  Saint-Elme    station-service, café nuit   le totem          le panneau
  La Fresnaie   garage                       le château d'eau  la couronne
  Malassis      café nuit, distr., station   le silo           la cage vitrée
  Vieux-Bourg   hôtel, garage                la porte          la lanterne
  Les Essarts   distributeur                 la cheminée       le feu du haut
  Peyrelade     station-service, hôtel       la halle          la cage du beffroi
  Brumaire      café de nuit                 le pont           le fanal

Le raisonnement est écrit en tête de chaque fonction. En deux mots : le repère
dit le MÉTIER du bourg, pas son décor. Une ville qui n'a qu'un garage n'a pas
de monument — elle a le château d'eau qui lui donne son eau. Une ville qui a
trois commodités ouvertes la nuit est une ville où les camions viennent : elle
a un silo. Une ville qui n'a qu'un distributeur a été abandonnée par ce qui la
faisait vivre : il lui reste la cheminée de l'usine morte.

CE QUI DÉCIDE DE LA FORME : ces maillages ne deviendront pas des nœuds. Ils
sont COUSUS dans le maillage fusionné de la ville (town.gd, une MeshInstance3D,
six surfaces) — sinon chaque repère coûterait son propre appel de dessin, quatre
fois par image avec les rétroviseurs. Trois conséquences, et elles se voient
dans le code ci-dessous :

  1. LE NOM DIT LA SURFACE. Un objet dont le nom finit par `_Lit` part dans la
     surface 6 (ÉMISSIVE) de la ville ; tout le reste va dans la surface 5
     (bâtiments). C'est le seul contrat entre ce fichier et Godot — pas de
     matériau importé, pas de variante de shader à compiler au milieu d'un
     bourg (le dépôt a relevé 23 ips sur la première image à cache froid contre
     115 à chaud : c'est le pire moment possible pour compiler quoi que ce soit).
  2. LA COULEUR DE CE QUI LUIT N'EST PAS À NOUS. La surface 6 est UNE surface,
     donc UN matériau, donc UNE couleur d'émission : le sodium fatigué de
     `_mat_glow`, 0,55 / 0,38 / 0,16, posé une seule fois dans `_ready` de
     town.gd. Les fenêtres, les têtes de lampadaire, les porches et ce qui
     luit des repères passent TOUS par lui — `_build_glow` les verse dans les
     mêmes tampons et appelle `_commit(_mat_glow)` une fois. Un feu de
     balisage rouge sortirait ORANGE dans le jeu.

     (Cette phrase donnait ici DEUX couleurs pour un seul matériau : 0,55 /
     0,38 / 0,16 pour les fenêtres et 0,75 / 0,45 / 0,12 pour les têtes de
     lampadaire, avec deux numéros de ligne. La seconde était la couleur de
     l'ANCIENNE town.gd ; la neuve n'en a plus qu'une, et les deux numéros de
     ligne étaient morts par-dessus le marché. On cite une FONCTION, pas une
     ligne — c'est la règle que le dépôt s'est donnée, et ce fichier ne
     l'appliquait pas à lui-même.)

     Les huit lumières se distinguent donc par leur FORME et leur HAUTEUR,
     jamais par leur teinte : un disque à 8,90 m, un rectangle debout à 20,70,
     un anneau à 14,00, une barre verticale de 6,6 m à 15,10, un point sous
     une voûte à 6,90, un point seul à 24,10, une cage sur un beffroi à 20,65,
     un fanal sous une poutre à 16,00. C'est aussi pour ça que le rendu de
     contrôle donne la MÊME couleur aux huit : il ne montre pas ce qui serait
     joli, il montre ce que le joueur aura.

     ET C'EST VÉRIFIÉ, pas espéré. `_rendu_brume` rend les huit à 200 m, lune
     et phares ÉTEINTS — ce que le brouillard de town.gd fait de toute façon à
     cette distance : à 0,030 de densité il ne repasse plus que 0,25 % de ce
     que la pierre renvoie. Il ne reste à l'image que la surface 6. Les huit
     taches sont bien huit taches différentes (renders/planche_brume_200m.png,
     les huit côte à côte). MAIS trois d'entre elles — la porte, la cheminée,
     le pont — ne sont qu'un POINT à cette distance, et ne se distinguent que
     par la découpe qui les porte : une arche, une aiguille, une poutre en
     travers. Le résultat tient donc à la silhouette autant qu'à la lumière, et
     un quatrième repère à point isolé serait un de trop.
  3. LES SOMMETS SE COMPTENT — et pas ceux qu'on croit. Voir plus bas.

Repère : Z vertical, base du modèle en z = 0, centré en (0, 0). glTF Y-up →
Godot (x, z, -y). La face « avant » — celle qui porte l'horloge, celle que
town.gd tourne vers la rue que le repère ferme (`_lm_seat` rend un cap,
`_landmark_pose` l'applique) — regarde -Y.

Exécution :
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python assets/blender/build_landmarks.py
  ou, Blender ouvert : sys.path.insert(0, ".../assets/blender"); import build_landmarks; build_landmarks.main()

Sorties : assets/models/landmark_<nom>.glb, assets/blender/landmarks.blend,
          assets/blender/renders/landmark_<nom>{,_route,_pres,_brume}.png,
          et les deux planches planche_route_34m.png et planche_brume_200m.png
"""
import bpy, json, math, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
from civic_lib import (get_col, clear_collection, box, cyl, lathe, loft, mat,
                       node_of, empty, place, shade, camera, render_views,
                       export_glb, save_blend, link_obj)

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")
RENDERS = os.path.join(HERE, "renders")


# ---------------------------------------------------------------------------
# LE COMPTE DE SOMMETS, ET LE TROISIÈME PIÈGE — celui qui ne se voit PAS au
# rendu, contrairement aux deux autres. C'est celui qui coûte le plus cher,
# parce qu'il ment dans le sens rassurant.
#
# Ce fichier comptait `len(ob.data.vertices)`. C'est la CAGE, pas le maillage :
# le modificateur Bevel n'y est pas. Relevé sur le clocher, trois nombres pour
# le même objet :
#
#     cage (ob.data.vertices)        196 sommets,  312 triangles
#     évalué (biseaux appliqués)     420 sommets,  760 triangles
#     .glb exporté                   504 sommets,  760 triangles
#
# Le contrat dit « 400 par repère, BISEAUX COMPRIS » : la cage ne répond donc
# pas à la question, et 196 aurait laissé croire à deux fois plus de marge
# qu'il n'y en avait. Le seul nombre que la ville paye vraiment est le
# TROISIÈME — Godot lit le .glb, pas la scène Blender —, et il monte encore
# parce que le glTF DÉDOUBLE les sommets aux arêtes vives et aux changements de
# matériau. C'est pour ça que `_compte_glb` rouvre le fichier écrit et le
# relit : un budget se mesure sur le fichier livré.
#
# (PLAN_VILLES.md, la fiche de coût du repère de Corbeny, annonçait déjà 504
# pour le clocher contre les 420 que ce fichier imprimait. Les deux avaient
# raison, ils ne comptaient pas la même chose. Maintenant les trois sortent
# côte à côte.)
#
# ET CE QUE LE TROISIÈME NOMBRE APPREND, qui renverse une décision.
#
# Le premier jet des sept a laissé des dizaines de boîtes SANS biseau, pour
# « économiser » : 8 sommets de cage au lieu de 24. Relevé sur le .glb, sur
# deux modèles indépendants et à l'unité près (nombres du jour, à comparer à
# ce que le tableau final de ce fichier imprime à chaque lancement) :
#
#     totem : 15 boîtes (6 biseautées, 9 nues) -> 15 x 24 = 360 sommets  (360)
#             triangles : 6 x 44 + 9 x 12      =            372          (372)
#     pont  : 21 boîtes (2 biseautées)         -> 21 x 24 = 504 sommets  (504)
#             triangles : 2 x 44 + 19 x 12     =            316          (316)
#
# CE TABLEAU A MENTI, ET C'EST LA MÊME FAUTE QU'IL DÉNONCE. Il donnait la
# ligne du pont « à l'unité près » : 24 boîtes, 576 sommets, 352 triangles. Le
# .glb livré en faisait 20, 480 et 304 — le relevé datait d'une version à
# QUATRE diagonales par ferme, et la ligne qui a retiré deux barres, huit
# lignes plus bas dans ce même fichier, n'a pas recompté celle-ci. Le totem,
# lui, tombait juste. Un relevé recopié n'est plus un relevé : il vieillit,
# et il vieillit sans prévenir. Les deux lignes ci-dessus sont refaites sur
# les .glb d'aujourd'hui, et le seul chiffre qui ne puisse pas vieillir reste
# celui que `_compte_glb` imprime en bas de ce fichier à chaque lancement.
#
# UNE BOÎTE COÛTE 24 SOMMETS DANS LE .glb, BISEAUTÉE OU NON. Ses six faces sont
# vives, le glTF les dédouble toutes, et le biseau — qui triple pourtant la
# cage — ne coûte pas un sommet de plus. Il coûte des TRIANGLES, et eux seuls :
# 12 nue, 44 biseautée, soit 3,7 fois.
#
# L'économie n'existait donc pas. Pire : elle se payait en lecture, parce que
# l'arête biseautée est exactement ce qui accroche un phare rasant — c'est déjà
# l'argument du chaînage d'angle du clocher. Les piliers de la halle et les
# claveaux de la porte ont été rebiseautés après ce relevé, à sommets
# CONSTANTS. Le seul endroit où le biseau se refuse encore, c'est là où l'objet
# est vraiment vif : la tôle d'un caisson d'enseigne, une cornière rivée de
# pont, un vitrage. Pas la pierre.
#
# La contrainte qui reste, et elle est réelle : le budget de TRIANGLES. Le
# clocher en fait 760 et c'est le plafond du lot ; chaque boîte rebiseautée en
# ajoute 32.
# ---------------------------------------------------------------------------

def _compte(colname):
    """Cage et maillage évalué (modificateurs appliqués) d'une collection."""
    dg = bpy.context.evaluated_depsgraph_get()
    cage_v = cage_t = ev_v = ev_t = 0
    for ob in bpy.data.collections[colname].objects:
        if ob.type != "MESH":
            continue
        ob.data.calc_loop_triangles()
        cage_v += len(ob.data.vertices)
        cage_t += len(ob.data.loop_triangles)
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        ev_v += len(me.vertices)
        ev_t += len(me.loop_triangles)
        ev.to_mesh_clear()
    return cage_v, cage_t, ev_v, ev_t


def _emprise(colname):
    """L'EMPRISE MONDE, et le contrôle du contrat : « base à z = 0, centré en
    (0, 0) ».

    Cette clause-là n'était vérifiée par rien, et elle était ROMPUE sans que
    personne le voie : la cheminée était décentrée de 1,10 m et le silo de
    0,28, parce que les ruines de l'une et la trémie de l'autre débordaient
    toutes du même côté. Aucun compte de sommets ne dit ça, aucun rendu non
    plus — les deux modèles étaient parfaitement beaux, simplement pas là où le
    bourg croira les poser. C'est la cousine exacte du piège des sommets : un
    contrat qu'on ne mesure pas est un contrat qu'on ne tient pas.

    Et l'emprise se lit sur le maillage ÉVALUÉ, pas sur la cage — le biseau du
    sommet d'un modèle en fait partie, et la hauteur imprimée sortait fausse de
    quelques millimètres pour cette seule raison.
    """
    dg = bpy.context.evaluated_depsgraph_get()
    mn = [1.0e9] * 3
    mx = [-1.0e9] * 3
    for ob in bpy.data.collections[colname].objects:
        if ob.type != "MESH":
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ob.matrix_world
        for v in me.vertices:
            p = mw @ v.co
            for k in range(3):
                mn[k] = min(mn[k], p[k])
                mx[k] = max(mx[k], p[k])
        ev.to_mesh_clear()
    return {"base": mn[2], "haut": mx[2],
            "dx": (mn[0] + mx[0]) * 0.5, "dy": (mn[1] + mx[1]) * 0.5}


def _compte_glb(path):
    """Sommets et triangles du .glb ÉCRIT — le seul compte que Godot paye."""
    d = open(path, "rb").read()
    n = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + n])
    v = t = 0
    for me in j["meshes"]:
        for pr in me["primitives"]:
            v += j["accessors"][pr["attributes"]["POSITION"]]["count"]
            t += j["accessors"][pr["indices"]]["count"] // 3
    return v, t


# ---------------------------------------------------------------------------
# Matériaux
#
# Ils ne servent QU'AUX RENDUS de contrôle : dans le jeu, la géométrie est
# cousue dans les surfaces de la ville et prend le matériau retro déjà compilé.
# Les couleurs sont donc celles de town.gd, pour que le rendu Blender ressemble
# à ce qu'on verra — et pas pour qu'il soit joli. Tout est très sombre : la
# maison (`_mat_house`, posé dans `_ready`) est à 0,030, et un repère qui la
# dépasserait de beaucoup brillerait comme un projecteur au bout de la rue.
# ---------------------------------------------------------------------------

def _materiaux():
    return {
        # La pierre des bourgs, à peine plus claire que les maisons.
        "pierre": mat("LM_Pierre", (0.052, 0.050, 0.046), rough=0.92),
        # L'ardoise du toit, plus sombre et plus lisse : elle prend la lune.
        "ardoise": mat("LM_Ardoise", (0.026, 0.028, 0.033), rough=0.55),
        # Le zinc des ferrures et de la croix.
        "zinc": mat("LM_Zinc", (0.070, 0.072, 0.076), rough=0.40, metallic=0.6),
        # Le béton du château d'eau et du silo : c'est le plus clair du lot, et
        # c'est voulu — un ouvrage d'art d'après-guerre est gris pâle, il
        # ressort de la pierre du bourg même sans lumière dessus.
        "beton": mat("LM_Beton", (0.064, 0.064, 0.062), rough=0.88),
        # La brique de la cheminée : chaude et sale.
        "brique": mat("LM_Brique", (0.048, 0.034, 0.028), rough=0.90),
        # La charpente de la halle. Presque noire : de nuit une charpente est un
        # dessin de traits noirs sous une toiture, pas du bois.
        "bois": mat("LM_Bois", (0.030, 0.024, 0.018), rough=0.85),
        # La tuile de la halle, un ton au-dessus du bois.
        "tuile": mat("LM_Tuile", (0.040, 0.026, 0.021), rough=0.80),
        # L'acier peint : le treillis du pont, le mât du totem. Mat, pas
        # chromé — une poutre riveted repeinte huit fois ne reflète rien.
        "acier": mat("LM_Acier", (0.038, 0.040, 0.044), rough=0.55, metallic=0.5),
        # CE QUI LUIT, et il n'y en a qu'un pour les huit repères : la surface 6
        # de la ville est UNE surface, donc UN matériau. Sodium fatigué, comme
        # les fenêtres et les têtes de lampadaire de town.gd — `_mat_glow`,
        # émission 0,55 / 0,38 / 0,16, et c'est la SEULE couleur d'émission du
        # bourg. Voir le point 2 de l'en-tête : la couleur n'est pas à nous,
        # seule la forme l'est.
        "lumiere": mat("LM_Lumiere", (0.62, 0.55, 0.38), rough=0.6,
                       emission=(1.0, 0.86, 0.55), emit=2.2),
    }


# ---------------------------------------------------------------------------
# LA SCÈNE DE NUIT — les conditions de jeu, et rien de plus.
#
# Elle est bâtie ICI et pas seulement rangée dans landmarks.blend, parce que la
# ligne de commande de l'en-tête part du fichier de démarrage de Blender : une
# scène qui ne vit que dans le .blend n'existe pas pour `blender -b --python`,
# et le premier repère bâti à froid se serait rendu sur fond gris, sans phares.
#
# Deux sources, les deux relevées sur ce que le jeu fait :
#   - la LUNE, un soleil rasant à 28° d'élévation, bleu (0,62 / 0,72 / 1,0),
#     énergie 0,55. C'est elle qui donne le pan éclairé et le pan noir : sans
#     elle un repère est une silhouette plate et on ne juge rien de son volume ;
#   - les PHARES, un spot de 60° à 34 m devant, à 1,05 m du sol — la hauteur des
#     optiques de la Civic. C'est la seule lumière qui dise la vérité sur les
#     biseaux : ce qui n'accroche pas les phares à 34 m n'existe pas de nuit.
#
# Trois caméras, et la deuxième est celle qui décide :
#   - CAM_silhouette : trois quarts surélevée à 34 m. Le contrôle de MODELAGE.
#   - CAM_route      : l'ŒIL DU CONDUCTEUR, 1,45 m, à 34 m dans l'axe. C'est la
#     seule vue que le joueur aura jamais. Un repère qui ne se lit que sur la
#     première n'est pas un repère.
#   - CAM_pres       : sur la chose qui luit, de près. Le contrôle de DÉTAIL.
# ---------------------------------------------------------------------------

def _menage_demarrage():
    """QUATRIÈME PIÈGE, et le seul qui vienne de Blender et non de nous.

    `blender -b --python ...` — la ligne de commande écrite dans l'en-tête de ce
    fichier — part du FICHIER DE DÉMARRAGE d'usine, et celui-ci n'est pas vide.
    Il contient trois objets, dans une collection nommée « Collection » :

        MESH   Cube    à (0, 0, 0), 2 m de côté
        LIGHT  Light   à (4,08 / 1,01 / 5,90), point, 1000 W
        CAMERA Camera  à (7,36 / -6,93 / 4,96)

    Les deux premiers ont saboté les vingt-quatre premiers rendus, et aucun des
    deux ne se voyait dans un chiffre :

      - le CUBE est un bloc gris posé au milieu du modèle. Il dépasse de 1 m
        sous le sol (il est centré sur l'origine, pas posé dessus), donc il
        sortait SOUS le socle de la cheminée et SOUS la plateforme de la halle,
        là où l'on ne cherche pas une erreur. Au milieu de la porte fortifiée
        il occupait le passage ;
      - la LUMIÈRE est à 1000 W quand la lune de la scène est à 0,55. Mille
        huit cents fois. Elle posait un reflet sur le tablier du pont et
        éclairait les faces que la lune laisse noires — c'est-à-dire qu'elle
        montrait des volumes que le jeu ne montrera jamais.

    Le .blend livré n'en portait pas trace : son auteur les avait supprimés à la
    main dans l'interface, et la suppression est morte avec la session. C'est
    exactement ce que ce fichier reproche aux numéros de ligne du plan — une
    correction qui n'est pas dans le code n'a pas eu lieu.

    La règle est donc écrite ici et pas cliquée : après le ménage de NOS
    collections, plus rien ne doit rester debout. Ce qui reste n'est pas à nous.
    """
    restes = []
    for ob in list(bpy.data.objects):
        maison = any(c.name.startswith(("Landmark_", "ENV_"))
                     for c in ob.users_collection)
        if not maison:
            restes.append("%s:%s" % (ob.type, ob.name))
            bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(bpy.data.collections):
        if not c.name.startswith(("Landmark_", "ENV_")) and not c.objects:
            bpy.data.collections.remove(c)
    return restes


def _scene():
    col = get_col("ENV_landmark")

    lune = bpy.data.lights.new("ENV_Lune", 'SUN')
    lune.energy = 0.55
    lune.color = (0.62, 0.72, 1.0)
    lune.angle = math.radians(3.0)
    lu = bpy.data.objects.new("ENV_Lune", lune)
    link_obj(lu, col)
    place(lu, (0.0, 0.0, 0.0), (62.0, 0.0, 28.0))

    phares = bpy.data.lights.new("ENV_Phares", 'SPOT')
    phares.energy = 2600.0
    phares.color = (1.0, 0.93, 0.8)
    phares.spot_size = math.radians(60.0)
    phares.spot_blend = 0.6
    phares.shadow_soft_size = 0.0
    phares.cutoff_distance = 40.0
    ph = bpy.data.objects.new("ENV_Phares", phares)
    link_obj(ph, col)
    place(ph, (7.0, -34.0, 1.05))
    cible = empty("ENV_PharesCible", (0.0, 0.0, 3.0), col)
    c = ph.constraints.new('TRACK_TO')
    c.target = cible
    c.track_axis = 'TRACK_NEGATIVE_Z'
    c.up_axis = 'UP_Y'

    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x = 640
    sc.render.resolution_y = 900
    sc.eevee.taa_render_samples = 64
    sc.view_settings.view_transform = 'AgX'
    # Le ciel : presque rien, et un peu bleu. Il ne doit pas éclairer le
    # repère — il doit seulement empêcher le noir absolu, comme le brouillard
    # de town.gd le fait dans le jeu.
    w = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    sc.world = w
    # `use_nodes` est déprécié en 5.2 (retrait annoncé pour 6.0) et le monde du
    # fichier de démarrage a déjà son arbre : on ne l'écrit que s'il manque.
    if w.node_tree is None:
        w.use_nodes = True
    node_of(w.node_tree, 'ShaderNodeBackground').inputs['Color'].default_value = \
        (0.010, 0.012, 0.020, 1.0)
    return col


# ---------------------------------------------------------------------------
# CORBENY — le clocher
#
# Une tour carrée de bourg, celle qu'on voit de la nationale bien avant le
# panneau : socle de pierre à chaînage d'angle, chambre des cloches ajourée,
# flèche d'ardoise, croix. Et UN CADRAN ALLUMÉ tourné vers la route.
#
# Le cadran est tout l'objet. À deux heures du matin, une église est noire ;
# son horloge, non. C'est la seule chose du bourg qui dise l'heure au chauffeur
# sans qu'il baisse les yeux sur son téléphone — et c'est le genre de détail qui
# fait qu'on reconnaît Corbeny à deux cents mètres. Corbeny a l'hôtel et le
# distributeur : c'est le bourg où l'on s'arrête pour dormir, et l'heure est
# exactement ce qu'on veut savoir en y arrivant.
# ---------------------------------------------------------------------------

H_SOCLE = 11.0          # hauteur du fût
L_SOCLE = 3.60          # côté du fût, en bas
L_HAUT = 3.36           # côté du fût, en haut (fruit léger : la tour se lit)
H_BEFFROI = 3.20        # la chambre des cloches
L_BEFFROI = 3.90        # elle déborde du fût : une corniche, une ombre portée
H_FLECHE = 6.20
H_CROIX = 1.30
R_CADRAN = 1.24

## Un `lathe` à quatre pas fait un prisme carré, et son profil donne le rayon
## CIRCONSCRIT — pas le demi-côté. Le premier jet a coûté une tour de 2,55 m
## au lieu de 3,60 : le chaînage d'angle flottait autour d'elle comme quatre
## pieds de table, et ça se voyait au premier rendu.
DIAG = 2.0 ** 0.5

## ET LES ROTATIONS SE DONNENT EN DEGRES. civic_lib.place() fait lui-meme le
## math.radians ; passer des radians les divise une seconde fois par 57 et rien
## ne tourne. Releve au rendu : le cadran etait couche a plat comme une etagere
## et le chainage d'angle tombait au milieu des faces au lieu des aretes.

## TROISIEME PIEGE DU MEME OUTIL, paye par le chateau d'eau et la cheminee :
## `lathe` ne FERME PAS le tube. Releve sur CLO_Fut, deux points de profil et
## quatre pas : 8 sommets et 8 triangles, soit quatre quads de flanc et zero
## capuchon. Un fut de tour posee au sol s'en moque (le sol bouche le bas, la
## corniche bouche le haut) ; une cheminee dont on voit le sommet, non — il
## faut un couronnement par-dessus, ou l'on regarde dans un tuyau vide.


def _demi_cote(z):
    """Le demi-côté du fût à la hauteur z : il a du fruit, le cadran doit
    savoir où est le mur."""
    k = min(max(z / H_SOCLE, 0.0), 1.0)
    return (L_SOCLE * (1.0 - k) + L_HAUT * k) * 0.5


def clocher(col, m):
    # Le fût. Un tronc de pyramide, pas un prisme : 24 cm de fruit sur 11 m,
    # c'est invisible de face et c'est ce qui empêche la tour de ressembler à
    # une boîte posée debout quand on passe à côté.
    lathe("CLO_Fut", [(L_SOCLE * 0.5 * DIAG, 0.0), (L_HAUT * 0.5 * DIAG, H_SOCLE)],
          m["pierre"], col, steps=4, rot=(0, 0, 45.0))

    # Le chaînage d'angle : quatre arêtes de pierre plus saillantes. Douze
    # sommets chacune, et c'est ce qui accroche la lumière rasante des phares
    # quand on longe la place.
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("CLO_Chainage_%d%d" % (sx, sy), (0.40, 0.40, H_SOCLE),
                (sx * (_demi_cote(H_SOCLE * 0.5) - 0.06),
                 sy * (_demi_cote(H_SOCLE * 0.5) - 0.06), H_SOCLE * 0.5),
                m["pierre"], col, bevel=0.02, segs=1)

    # La corniche, puis la chambre des cloches. Elle déborde : c'est la seule
    # rupture de la silhouette, celle qui dit "clocher" et pas "château d'eau".
    box("CLO_Corniche", (L_BEFFROI + 0.22, L_BEFFROI + 0.22, 0.26),
        (0.0, 0.0, H_SOCLE + 0.13), m["pierre"], col, bevel=0.04, segs=1)
    box("CLO_Beffroi", (L_BEFFROI, L_BEFFROI, H_BEFFROI),
        (0.0, 0.0, H_SOCLE + 0.26 + H_BEFFROI * 0.5), m["pierre"], col,
        bevel=0.03, segs=1)

    # Les abat-son : quatre baies sombres, une par face. Creusées, pas peintes
    # — de nuit c'est le trou noir qui se voit, pas le dessin.
    z_baie = H_SOCLE + 0.26 + H_BEFFROI * 0.55
    for i, (dx, dy, rz) in enumerate([(0, -1, 0.0), (0, 1, 180.0),
                                      (-1, 0, 90.0), (1, 0, -90.0)]):
        box("CLO_Abatson_%d" % i, (1.30, 0.16, 1.90),
            (dx * (L_BEFFROI * 0.5 - 0.06), dy * (L_BEFFROI * 0.5 - 0.06), z_baie),
            m["ardoise"], col, rot=(0, 0, rz), bevel=0.02, segs=1)

    # LE CADRAN, tourné vers -Y : la face que la ville présente à la route.
    # Un disque plat, à peine sorti du mur, et son cercle de zinc.
    z_cad = H_SOCLE - 2.10
    y_mur = -(_demi_cote(z_cad) + 0.02)
    cyl("CLO_Cadran_Lit", R_CADRAN, 0.10, (0.0, y_mur - 0.03, z_cad),
        m["lumiere"], col, rot=(90.0, 0, 0), segments=16)
    cyl("CLO_Cercle", R_CADRAN + 0.14, 0.14, (0.0, y_mur, z_cad),
        m["zinc"], col, rot=(90.0, 0, 0), segments=16)
    # Les deux aiguilles. Deux heures dix : l'heure du jeu, et l'angle qui se
    # lit le mieux de loin — deux traits qui ne se superposent pas.
    for nom, lg, ep, deg in [("Grande", 1.02, 0.10, -60.0),
                             ("Petite", 0.66, 0.13, 32.0)]:
        a = math.radians(deg)
        box("CLO_Aiguille_%s_Lit" % nom, (lg, 0.05, ep),
            (math.cos(a) * lg * 0.5, y_mur - 0.10, z_cad + math.sin(a) * lg * 0.5),
            m["zinc"], col, rot=(0, -deg, 0), bevel=0.01, segs=1)

    # La flèche d'ardoise. Quatre pans, pas de révolution : un clocher de bourg
    # est charpenté, pas tourné.
    z0 = H_SOCLE + 0.26 + H_BEFFROI
    lathe("CLO_Fleche", [((L_BEFFROI * 0.5 + 0.10) * DIAG, 0.0),
                         (L_BEFFROI * 0.30 * DIAG, H_FLECHE * 0.42),
                         (0.03, H_FLECHE)],
          m["ardoise"], col, loc=(0, 0, z0), steps=4, rot=(0, 0, 45.0))

    # La croix, et le coq. Trois boîtes : c'est tout ce qu'on en voit de nuit,
    # et c'est ce qui termine la silhouette au-dessus du brouillard.
    zc = z0 + H_FLECHE
    box("CLO_Croix_V", (0.07, 0.07, H_CROIX), (0, 0, zc + H_CROIX * 0.5),
        m["zinc"], col, bevel=0.01, segs=1)
    box("CLO_Croix_H", (0.62, 0.06, 0.07), (0, 0, zc + H_CROIX * 0.72),
        m["zinc"], col, bevel=0.01, segs=1)


# ---------------------------------------------------------------------------
# SAINT-ELME — le totem de la station
#
# Saint-Elme a une station-service et un café de nuit, et rien d'autre. C'est
# LE bourg où l'on s'arrête : le premier de la carte (map.gd, at 0,18/0,78),
# celui où l'on fait le plein avant d'y aller.
#
# Alors son repère n'est pas un monument, c'est une ENSEIGNE — et c'est le seul
# objet de tout le jeu dont la RAISON D'ÊTRE est d'être vu de loin. Un clocher
# est haut parce qu'il porte des cloches ; un totem de station est haut parce
# qu'un routier doit le voir par-dessus les toits assez tôt pour ralentir.
#
# ET LE PREMIER JET NE LE FAISAIT PAS. Il s'arrêtait à 12,60 m sur cet
# argument-ci : « 3,2 m au-dessus de la plus haute maison possible (BLD_H.y =
# 9,4), c'est exactement le calcul que fait un pétrolier ». Le calcul était
# faux, et c'est town.gd qui l'a dit — `_lm_sky` mesure ce que les toits
# laissent voir depuis les treize points de vue de l'approche, et le totem ne
# dépassait que sur DEUX : 15 %, 0,3 m de marge moyenne. Le pire des huit.
#
# Pourquoi 3,2 m de plus que les maisons ne suffisent pas, et c'est le même
# raisonnement pour les quatre repères repris : l'œil du conducteur est à
# 1,45 m et le repère est à 26 ou 32 m de l'axe quand le rang de maisons est à
# 10. La ligne de vue qui rase un toit de 9,4 m remonte du RAPPORT des deux
# décalages, pas de la distance : au droit du repère elle est déjà à
# 1,45 + (9,4 − 1,45) × 30/10 ≈ 25 m. Un repère à 12,6 m ne passe pas
# au-dessus d'un toit de 9,4 m ; il se montre dans les TROUS du rang, et un
# trou n'est pas un repère.
#
# 22,55 m, donc, et c'est CE calcul-là que fait un pétrolier. Le mât passe de
# 9,00 à 18,50 m — un fût de dix-huit mètres à deux éclisses, jambé au pied,
# c'est un totem de relais routier ordinaire, pas une prouesse.
#
# RELEVÉ (villetest, `_audit_landmarks`) : 15 % de l'approche et 0,3 m au-dessus
# des toits sont devenus 92 % et 6,3 m. Ce n'est PAS 100 %, et c'est le seul du
# lot qui n'y arrive pas — il faut le dire et dire pourquoi. Le totem est le
# repère le plus MINCE des huit (1,6 x 4,1 m d'emprise) et town.gd l'assied à
# 30 m de l'axe, où seule la halle va plus loin. Une treizième ligne de vue
# reste bouchée, et la marche est haute : mesuré à trois hauteurs, 22,55 m
# donne 92 %, 24,05 en donne encore 92, et il faut 25,55 pour passer les
# treize (100 %, 9,1 m). Le toit qui ferme cette ligne-là vaut donc plus de
# 24 m vus du droit du repère — c'est une maison de 9,4 m posée assez près de
# l'œil pour que le rapport des décalages la triple.
#
# ET ON NE LES PREND PAS, parce qu'un chiffre en cache un autre : la cheminée
# des Essarts fait 24,45 m et TOUT ce qu'elle raconte tient dans « elle est
# plus haute que tout ce que la carte contient ». Une enseigne d'essence qui
# dépasserait la cheminée de la briqueterie gagnerait une ligne de banc et
# coûterait un bourg. Douze points de vue sur treize, donc, et le treizième
# assumé.
#
# CE QUI LUIT : le panneau. Un rectangle debout de 3,46 x 2,66 m à 20,7 m du
# sol, allumé des deux côtés — la seule surface éclairée du bourg à trois
# heures du matin, et la plus grande du lot des huit. C'est l'anti-clocher : là
# où Corbeny offre un petit disque chaud à 8,9 m, Saint-Elme jette un mur de
# lumière, et il le jette maintenant PAR-DESSUS le bourg au lieu d'entre deux
# pignons. Aucune confusion possible dans le brouillard, et c'est tout ce
# qu'on demande à un repère.
#
# Le cadre est fait de QUATRE barres et non d'une boîte pleine : un caisson
# lumineux est un cadre autour d'une plaque, et de nuit c'est la découpe noire
# du cadre sur la plaque allumée qui donne l'échelle. Une boîte pleine avec un
# panneau collé dessus aurait rendu le même nombre de pixels sans le dessin.
# ---------------------------------------------------------------------------

H_MAT = 18.50           # le fût, du haut du socle au bas du caisson
L_CAISSON = 3.90        # largeur hors-tout du caisson
H_CAISSON = 3.10
Z_PANNEAU = 0.65 + H_MAT + H_CAISSON * 0.5      # 20,70 m : le centre du panneau
H_TOTEM = Z_PANNEAU + H_CAISSON * 0.5 + 0.30    # 22,55 m : la casquette ferme


def totem(col, m):
    # Le massif de béton. Un totem de 22 m pèse, et ça se voit au pied : le
    # massif a grandi avec le mât, sinon l'objet a l'air planté dans du sable.
    box("TOT_Socle", (2.10, 1.60, 0.55), (0.0, 0.0, 0.275),
        m["beton"], col, bevel=0.04, segs=1)
    box("TOT_Platine", (1.15, 0.90, 0.10), (0.0, 0.0, 0.60),
        m["acier"], col, bevel=0.02, segs=1)

    # Le mât, et ses DEUX colliers d'éclisse : trois tronçons boulonnés, parce
    # qu'on ne transporte pas dix-huit mètres d'un seul morceau — un seul
    # collier laisserait des tronçons de neuf, ce qui ne passe pas davantage
    # sous un pont. Ils tombent aux tiers du fût (6,82 et 12,98 m), là où un
    # monteur les met.
    box("TOT_Mat", (0.74, 0.54, H_MAT), (0.0, 0.0, 0.65 + H_MAT * 0.5),
        m["acier"], col, bevel=0.03, segs=1)
    for k, z in enumerate((6.82, 12.98)):
        box("TOT_Collier_%d" % k, (0.88, 0.68, 0.26), (0.0, 0.0, z),
            m["acier"], col, bevel=0.02, segs=1)

    # Deux jambes de force au pied. Elles ne portent rien de neuf dans le
    # calcul, elles portent le VENT — et le vent sur dix-huit mètres de mât
    # n'est pas celui de neuf : les jambes montent à 3,97 m au lieu de 2,60,
    # et leur pied tombe pile au bord du massif. De près, dans les phares, ce
    # sont elles qui disent que l'objet est planté et pas posé.
    #
    # ET ELLES ÉTAIENT À L'ENVERS. `rot=(0, sx * 15, 0)` fait pencher le haut
    # de la barre VERS L'EXTÉRIEUR : les deux jambes s'écartaient du mât en
    # montant et se rejoignaient au sol — une jambe de force qui ne touche
    # rien. À 2,60 m ça ne se voyait pas ; à quatre mètres, le rendu de
    # l'œil du conducteur le montre du premier coup. Le signe est inversé.
    for sx in (-1, 1):
        box("TOT_Jambe_%d" % sx, (0.20, 0.20, 3.40),
            (sx * 0.72, 0.0, 2.31), m["acier"], col, rot=(0.0, -sx * 12.0, 0.0))

    # Le cadre du caisson : quatre barres autour du vide où vient la plaque.
    z_c = Z_PANNEAU
    ep = 0.22
    box("TOT_Cadre_Haut", (L_CAISSON, 0.60, ep),
        (0.0, 0.0, z_c + H_CAISSON * 0.5 - ep * 0.5), m["acier"], col)
    box("TOT_Cadre_Bas", (L_CAISSON, 0.60, ep),
        (0.0, 0.0, z_c - H_CAISSON * 0.5 + ep * 0.5), m["acier"], col)
    for sx in (-1, 1):
        box("TOT_Cadre_Cote_%d" % sx, (ep, 0.60, H_CAISSON - 2 * ep),
            (sx * (L_CAISSON * 0.5 - ep * 0.5), 0.0, z_c), m["acier"], col)

    # Les deux traverses qui accrochent le caisson au mât, vues par le côté.
    for sz in (-1, 1):
        box("TOT_Traverse_%d" % sz, (L_CAISSON - 0.5, 0.14, 0.14),
            (0.0, 0.24, z_c + sz * (H_CAISSON * 0.5 - 0.55)), m["acier"], col)

    # LE PANNEAU. Il traverse le cadre de part en part (0,74 m contre 0,60) :
    # il déborde de 7 cm de chaque côté, donc il s'allume aussi POUR CELUI QUI
    # REPART. Un totem qui ne s'allumerait que vers -Y serait un décor de
    # théâtre — et le joueur repasse par les mêmes bourgs toute la nuit.
    box("TOT_Panneau_Lit", (L_CAISSON - 2 * ep, 0.74, H_CAISSON - 2 * ep),
        (0.0, 0.0, z_c), m["lumiere"], col)

    # La casquette : elle coiffe le caisson et jette une ombre sur le haut de
    # la plaque. Sans elle, le rectangle lumineux flotte.
    box("TOT_Casquette", (L_CAISSON + 0.24, 0.86, 0.30),
        (0.0, 0.0, H_TOTEM - 0.15), m["acier"], col, bevel=0.03, segs=1)


# ---------------------------------------------------------------------------
# LA FRESNAIE — le château d'eau
#
# La Fresnaie n'a qu'un garage (map.gd). C'est le plus petit bourg de la carte
# et le seul à une seule commodité : deux cents habitants, une pompe à essence
# qu'on n'a jamais remplacée, un mécanicien.
#
# Un village pareil n'a pas de monument. Il a l'OUVRAGE PUBLIC qui lui a été
# construit une fois pour toutes et qui le dépasse de six fois : le château
# d'eau. C'est la seule chose que La Fresnaie possède en commun, et c'est ce
# qu'on voit d'elle avant de voir une maison. Le repère n'est pas ce que la
# ville a bâti pour être belle — c'est ce qu'on lui a bâti pour qu'elle vive.
#
# CE QUI LUIT : la couronne. Le bandeau vitré de la chambre des vannes, au bas
# de la cuve, à 14,0 m — allumé toute la nuit parce que personne n'éteint
# jamais un local technique. C'est un ANNEAU, et c'est la forme qui le sépare
# des sept autres : à deux cents mètres dans le brouillard, un cercle de
# lumière qui flotte à quatorze mètres au-dessus de rien ne peut être que La
# Fresnaie. La cuve noire au-dessus ne se devine qu'ensuite.
#
# Toute la tour est UN SEUL lathe à cinq points de profil : fût, évasement,
# cuve, coupole. Douze pas, 60 sommets pour 18 m d'ouvrage — c'est le meilleur
# rapport du lot, et c'est ce qui paye les quatre anneaux de la passerelle.
# ---------------------------------------------------------------------------

H_EAU = 18.62
Z_CUVE = 12.40          # le fût s'arrête là, l'évasement commence
R_CUVE = 3.05
Z_COURONNE = 14.00      # la chose qui luit


def chateau_eau(col, m):
    # La tour entière, d'un trait. Le fût a du fruit (1,55 -> 1,42) pour la
    # même raison que le clocher : une colonne parfaitement droite se lit comme
    # un tuyau, une colonne qui se resserre se lit comme un ouvrage.
    #
    # Le fût est MINCE : 1,18 m de rayon pour une cuve de 3,05, soit 0,39. Le
    # premier jet lui en donnait 1,55 (rapport 0,51) et le rendu a répondu tout
    # de suite — ça faisait un champignon, ou une lampe de chevet. Un château
    # d'eau tient sa lecture de l'ÉCART entre un pied grêle et une panse
    # énorme ; c'est ce déséquilibre qu'on reconnaît de loin, et il se perd
    # bien avant que le fût soit gros.
    lathe("EAU_Tour", [(1.18, 0.0),
                       (1.08, Z_CUVE),
                       (R_CUVE, 13.80),
                       (R_CUVE, 17.60),
                       (0.55, 18.35)],
          m["beton"], col, steps=12)
    # L'évent qui coiffe la coupole — et qui bouche le trou : `lathe` laisse le
    # tube OUVERT en haut (voir le troisième piège), et sans ce capuchon on
    # regarde à l'intérieur de la cuve depuis la route.
    cyl("EAU_Event", 0.42, 0.32, (0.0, 0.0, H_EAU - 0.16),
        m["beton"], col, segments=8)

    # LA COURONNE : le bandeau vitré, 28 cm de haut, saillant de 9 cm sur la
    # cuve pour que son ombre le détache. Un anneau complet et pas quatre
    # hublots — à 34 m un hublot fait trois pixels, un anneau fait une forme.
    lathe("EAU_Couronne_Lit", [(R_CUVE + 0.09, Z_COURONNE - 0.14),
                               (R_CUVE + 0.09, Z_COURONNE + 0.14)],
          m["lumiere"], col, steps=12)

    # La passerelle de service et son garde-corps, juste au-dessus. C'est ce
    # qui empêche la couronne de ressembler à une bague posée là : la lumière
    # sort SOUS un plancher, comme dans la réalité.
    lathe("EAU_Passerelle", [(R_CUVE, Z_COURONNE + 0.16),
                             (R_CUVE + 0.32, Z_COURONNE + 0.16)],
          m["beton"], col, steps=12)
    lathe("EAU_GardeCorps", [(R_CUVE + 0.30, Z_COURONNE + 0.20),
                             (R_CUVE + 0.30, Z_COURONNE + 1.05)],
          m["zinc"], col, steps=12)

    # L'échelle à crinoline, sur le flanc gauche pour ne pas barrer la face de
    # la route. Une seule boîte : de nuit, une échelle est une ligne verticale.
    box("EAU_Echelle", (0.10, 0.52, Z_CUVE - 1.2),
        (-1.10, 0.0, 0.6 + (Z_CUVE - 1.2) * 0.5), m["zinc"], col)

    # La porte du pied, tournée vers la route. Sombre et creuse : c'est le seul
    # élément à hauteur d'homme, et c'est lui qui donne l'échelle des 18 m.
    box("EAU_Porte", (0.90, 0.14, 2.00), (0.0, -1.14, 1.00),
        m["ardoise"], col, bevel=0.02, segs=1)


# ---------------------------------------------------------------------------
# MALASSIS — le silo à grain
#
# Malassis est le seul bourg à TROIS commodités : café de nuit, distributeur,
# station-service (map.gd). C'est le carrefour de la carte — trois routes y
# arrivent, et tout y est ouvert quand tout dort ailleurs.
#
# Une ville n'ouvre pas la nuit par gentillesse : elle ouvre parce que des
# CAMIONS y passent la nuit. Le silo de la coopérative est la cause, et les
# trois commodités sont la conséquence — le café est ouvert pour les chauffeurs
# qui attendent la bascule, la station pour leur gazole, le distributeur parce
# qu'ils sont payés en liquide. Le repère explique la ville au lieu de la
# décorer.
#
# CE QUI LUIT : la cage d'escalier vitrée de la tour du gerbeur. Une BARRE
# VERTICALE de 6,6 m, de 11,8 à 18,4 m — la plus grande hauteur allumée des
# huit, et la seule forme haute et étroite. On la voit avant de voir le silo,
# et de très loin elle ressemble à une fente de lumière debout dans le noir.
# C'est aussi la seule qui dise quelque chose de vrai sur l'intérieur : un
# escalier de silo est vitré et éclairé la nuit parce qu'on y monte la nuit.
# ---------------------------------------------------------------------------

H_SILO = 21.60
R_CELL = 1.70
Z_CELL = 16.00
X_TOUR = 4.90           # la tour du gerbeur, en bout de batterie


def silo(col, m):
    # Les trois cellules. Dix pas chacune : à 34 m, un décagone de 3,4 m de
    # diamètre est rond, et le onzième pas serait payé pour rien.
    for i, dx in enumerate((-5.35, -1.85, 1.65)):
        lathe("SIL_Cellule_%d" % i, [(R_CELL, 0.0), (R_CELL, Z_CELL)],
              m["beton"], col, loc=(dx, 0.0, 0.0), steps=10)
    # La dalle de couverture des cellules, qui les relie en un seul bloc — et
    # qui bouche les trois tubes ouverts que `lathe` vient de faire.
    box("SIL_Dalle", (10.90, 3.90, 0.55), (-1.85, 0.0, Z_CELL + 0.275),
        m["beton"], col, bevel=0.04, segs=1)

    # La tour du gerbeur : c'est elle qui donne la hauteur, et c'est autour
    # d'elle que tout tourne. Une gaine d'élévateur ne s'arrête pas au niveau
    # du grain, elle le dépasse pour pouvoir le laisser tomber.
    box("SIL_Tour", (2.60, 3.10, 19.20), (X_TOUR, 0.0, 9.60),
        m["beton"], col, bevel=0.05, segs=1)
    box("SIL_Tete", (3.20, 3.70, 2.20), (X_TOUR, 0.0, 20.30),
        m["beton"], col, bevel=0.05, segs=1)
    # La gaine de l'élévateur, plaquée contre le flanc de la tour. Elle y est
    # COLLÉE (rayon 0,55 contre un demi-côté de 1,30, donc 1,75 de centre) :
    # posée à 1,90 comme au premier jet, elle flottait à côté de la tour et le
    # rendu la donnait pour une verrue. Une gaine ne flotte pas, elle monte le
    # long du mur — et c'est ce trait vertical qui dit qu'il y a une machine
    # dedans.
    cyl("SIL_Gaine", 0.55, 6.00, (X_TOUR + 1.75, 0.0, 16.00),
        m["zinc"], col, segments=8)
    box("SIL_Paratonnerre", (0.06, 0.06, 1.20), (X_TOUR - 1.10, 0.0, H_SILO - 0.60),
        m["zinc"], col)

    # LA CAGE D'ESCALIER. 0,85 m de large, 6,6 m de haut, plaquée sur la face
    # de la route et débordant de 6 cm — de nuit c'est le débord qui fait
    # l'arête vive, et l'arête vive qui fait la barre.
    box("SIL_Cage_Lit", (0.85, 0.18, 6.60), (X_TOUR - 0.60, -1.60, 15.10),
        m["lumiere"], col)

    # La galerie du tapis : elle part de la tête et court au-dessus des
    # cellules. C'est le trait horizontal qui empêche le silo de n'être qu'une
    # tour de plus, et c'est ce que l'œil lit comme « ça travaille ».
    box("SIL_Galerie", (11.20, 1.30, 1.05), (-1.30, 0.0, 17.60),
        m["zinc"], col, bevel=0.03, segs=1)

    # La trémie de chargement, au pied de la tour : le camion se met dessous.
    # Elle est recentrée sur y = 0 (elle avançait de 30 cm) : c'est le seul
    # volume profond du modèle, donc c'est lui seul qui décentrait l'emprise —
    # de 0,28 m, sous la tolérance, mais dans le même sens que la faute de la
    # cheminée et pour la même raison.
    box("SIL_Tremie", (4.80, 4.40, 3.40), (X_TOUR, 0.0, 1.70),
        m["beton"], col, bevel=0.05, segs=1)


# ---------------------------------------------------------------------------
# VIEUX-BOURG — la porte fortifiée
#
# Vieux-Bourg a un hôtel et un garage (map.gd), et son nom dit le reste : c'est
# le bourg ANCIEN, celui qui existait avant la route. Une ville qui a un hôtel
# est une ville où l'on arrive tard.
#
# Son repère est donc la seule chose qu'un vieux bourg a de plus qu'un neuf :
# sa PORTE. Et c'est le seul des huit qu'on voit À TRAVERS : le passage fait
# 3,90 m entre les jambages et court selon Y, c'est-à-dire dans l'axe même de
# la rue qu'il ferme (town.gd tourne le repère face à la rue). Le conducteur
# arrive dessus et voit la nuit de l'autre côté par le trou. Aucun autre ne
# fait ça.
#
# (LA VERSION D'AVANT DISAIT « on passe DEDANS, la voiture s'y engouffre ». Ce
# n'est pas vrai et ça ne l'a jamais été : town.gd pose le repère à LM_CLEAR
# = 7 m AU-DELA du bout de la rue, sur un parvis — voir le commentaire de
# LM_CLEAR, « il reste 2,8 m de trottoir devant le socle ». La rue s'arrête
# avant la porte ; on la regarde, on ne la traverse pas. Le relevé du banc le
# dit à chaque lancement : « dégagement 2,70 m ». Les mêmes sept mètres valent
# pour les huit, et deux autres commentaires de ce fichier les ignoraient
# aussi — voir le pont et la halle.)
#
# CE QUI LUIT : la lanterne sous la voûte, à 6,90 m. C'est la seule des huit
# lumières qu'on voit À TRAVERS un trou — encadrée par l'arc, elle est
# reconnaissable même quand on ne distingue plus la pierre. Et elle raconte
# l'hôtel : on ne laisse pas une lampe allumée sous un porche pour soi-même, on
# la laisse pour celui qui n'est pas encore arrivé.
#
# L'arc est fait de SIX claveaux posés en polaire, pas d'un demi-tore. Six
# boîtes tournées de 30° en 30° donnent la lecture d'une voûte à 34 m pour
# 144 sommets dans le .glb ; un demi-tore à seize pas en coûterait plusieurs
# centaines (estimation, pas relevé — mais l'ordre de grandeur suffit à
# trancher, et l'intrados en claveaux se rabote, voir le corps).
#
# ET IL LUI MANQUAIT SA TOUR. À 14,795 m la porte ne dépassait les toits que
# sur SIX des treize points de vue de l'approche (46 %, 0,8 m de marge
# moyenne) : une porte de ville qu'on ne voit qu'une fois dans le bourg
# n'annonce pas le bourg. Le corps sur l'arc était un simple bloc crénelé, ce
# qui est une porte de rempart et rien de plus ; une porte de VILLE — celle
# qu'on garde après que les remparts sont tombés, parce qu'elle porte le
# guet — a sa tour au-dessus du passage. Elle monte à 22,60 m, ce qui est
# modeste pour l'objet (la Craffe à Nancy en fait 25). RELEVÉ : 46 % de
# l'approche et 0,8 m au-dessus des toits sont devenus 100 % et 6,6 m.
#
# EFFET DE BORD À CONNAÎTRE, et il ne vient pas de ce fichier : la porte a
# CHANGÉ DE CÔTÉ. Elle était à (s 40,0 ; u −30), elle est à (s 41,4 ; u +28).
# `_lm_seat` départage à trois mètres près (LM_TIE) les deux bouts de rue qui
# se disputent la première place, et il les départage AU CIEL — donc avec la
# hauteur du modèle. Grandir change le vainqueur. Ce n'est pas un défaut, mais
# il faut le savoir : toucher à la hauteur d'un repère peut le déplacer, et
# c'est le banc, pas le modeleur, qui dit où il finit.
#
# Les quatre merlons du milieu sont partis AVEC le changement, et pas malgré
# lui : ils tombaient à 1,05 m de l'axe, la tour en fait 1,80 de demi-largeur
# — ils étaient DANS la maçonnerie. C'était 96 sommets de pierre invisible, et
# ils payent la tour EN ENTIER : fût 24, corniche 24, baie 24, toit 16, soit
# 88 pour 96 rendus. Le repère passe de 480 à 472 sommets .glb — il a gagné
# 7,8 m et il pèse moins.
# ---------------------------------------------------------------------------

H_PORTE = 22.60
X_PIED = 3.05           # entraxe des deux jambages
L_PIED = 2.20
Z_NAISSANCE = 6.40      # naissance de l'arc
R_ARC = 2.43            # rayon moyen des claveaux
Z_LANTERNE = 6.90
Z_TOUR = 13.95          # le bandeau finit là, la tour de guet commence
H_TOUR = 6.70
L_TOUR = 3.60           # côté de la tour : elle tient sur le corps (8,30 m)


def porte(col, m):
    # Les deux jambages. Ils montent jusqu'au sommet de l'arc (9,31 m) et pas
    # jusqu'à la naissance : sinon il aurait fallu deux écoinçons de plus pour
    # boucher les vides de part et d'autre de l'arc, et c'est deux boîtes
    # payées pour de la pierre qu'on ne voit pas.
    for sx in (-1, 1):
        box("POR_Jambage_%d" % sx, (L_PIED, 4.40, 9.30),
            (sx * X_PIED, 0.0, 4.65), m["pierre"], col, bevel=0.05, segs=1)

    # L'arc : six claveaux à 15°, 45°, 75°, 105°, 135°, 165°. Le Z LOCAL de
    # chaque boîte doit pointer vers l'EXTÉRIEUR du cercle, donc la rotation
    # vaut 90 - theta et pas theta — et en DEGRÉS (voir le piège du haut).
    # Ils sont BISEAUTÉS, et c'est le seul endroit du modèle où ça compte : le
    # repère est à 7 m du bout de la rue (LM_CLEAR), donc les phares du bourg
    # frappent la voûte de biais et de tout près. Le biseau ne coûte pas un
    # sommet (voir le troisième piège), seulement 32 triangles pièce.
    #
    # SIX et non cinq, et 1,26 m de large et non 1,58 : l'intrados d'un arc en
    # claveaux droits est un POLYGONE, et les coins de chaque bloc mordent dans
    # le passage. Relevé : 15 cm de morsure à cinq claveaux, 10 à six. Le rendu
    # rapproché montrait une rangée de dents sous la voûte ; six blocs plus
    # étroits la rabotent, et les 24 sommets viennent de l'écusson qu'on a
    # retiré pour ça.
    for i, th in enumerate((15.0, 45.0, 75.0, 105.0, 135.0, 165.0)):
        a = math.radians(th)
        box("POR_Claveau_%d" % i, (1.26, 4.40, 0.96),
            (math.cos(a) * R_ARC, 0.0, Z_NAISSANCE + math.sin(a) * R_ARC),
            m["pierre"], col, rot=(0.0, 90.0 - th, 0.0), bevel=0.04, segs=1)

    # Le corps de la tour au-dessus de l'arc, puis la file de corbeaux qui
    # porte le chemin de ronde. Le débord de 30 cm fait une ombre horizontale :
    # c'est elle qui coupe la masse en deux et qui dit « fortifié ».
    box("POR_Corps", (8.30, 4.60, 4.20), (0.0, 0.0, 11.40),
        m["pierre"], col, bevel=0.05, segs=1)
    box("POR_Bandeau", (8.90, 5.20, 0.45), (0.0, 0.0, 13.72),
        m["pierre"], col, bevel=0.04, segs=1)

    # Les merlons. Un de chaque côté de la tour, sur les deux faces : le
    # chemin de ronde ne fait plus que 1,90 m de part et d'autre du guet, et
    # c'est tout ce qu'il y a la place de créneler.
    #
    # Ils étaient QUATRE par face, à 1,05 et 3,15 m de l'axe. Les deux du
    # milieu sont maintenant DANS la tour (demi-largeur 1,80 m) : 96 sommets
    # de pierre enfermée dans de la pierre, que personne n'aurait vus et que
    # rien n'aurait signalés. Ils sont partis, et ils payent la tour.
    #
    # Devant ET derrière : la porte est vue de face depuis la rue qu'elle
    # ferme, puis de trois quarts et de dos quand on l'a dépassée — le bourg
    # se traverse et le joueur y repasse toute la nuit. Une seule rangée de
    # créneaux serait un décor de théâtre dès le second passage.
    for j, sy in enumerate((-1, 1)):
        for i, dx in enumerate((-3.35, 3.35)):
            box("POR_Merlon_%d%d" % (j, i), (1.60, 0.60, 0.85),
                (dx, sy * 1.90, 14.37), m["pierre"], col)

    # LA TOUR DE GUET, et c'est elle qui fait de la porte un repère : sans
    # elle l'objet culminait à 14,795 m et ne dépassait les toits que sur six
    # des treize points de vue de l'approche. Un fût carré, une corniche, un
    # toit en pavillon d'ardoise — le vocabulaire d'un guet, pas d'un clocher :
    # pas de flèche élancée, pas de croix, une pyramide écrasée qui dit
    # « militaire » et qu'on ne confondra pas avec Corbeny à deux cents mètres.
    box("POR_Tour", (L_TOUR, 3.80, H_TOUR), (0.0, 0.0, Z_TOUR + H_TOUR * 0.5),
        m["pierre"], col, bevel=0.05, segs=1)
    box("POR_Tour_Corniche", (L_TOUR + 0.40, 4.20, 0.30),
        (0.0, 0.0, Z_TOUR + H_TOUR + 0.15), m["pierre"], col, bevel=0.04, segs=1)

    # La baie du guet, sur la face qui regarde la rue. Creusée et sombre,
    # comme les abat-son du clocher : de nuit c'est le TROU qui se voit, et
    # c'est lui qui donne l'échelle de la tour — sans elle, un bloc de 3,60 m
    # et un bloc de 7 m se ressemblent.
    box("POR_Tour_Baie", (0.90, 0.16, 1.70), (0.0, -1.84, Z_TOUR + 2.60),
        m["ardoise"], col, bevel=0.02, segs=1)

    # Le toit en pavillon. Un `lathe` à quatre pas et DEUX points de profil :
    # 8 sommets pour 1,65 m de couverture (voir le troisième piège) — et le
    # rayon du profil est CIRCONSCRIT, donc demi-côté x racine de deux, sinon
    # le toit rentre sous sa corniche.
    lathe("POR_Tour_Toit",
          [((L_TOUR + 0.40) * 0.5 * DIAG, 0.0), (0.04, 1.65)],
          m["ardoise"], col, loc=(0.0, 0.0, Z_TOUR + H_TOUR + 0.30),
          steps=4, rot=(0, 0, 45.0))

    # LA LANTERNE, et sa potence accrochée à la clé de voûte. Une petite boîte
    # de 42 cm : c'est la plus petite lumière des huit, et elle n'a pas besoin
    # d'être grande — elle est vue dans un cadre noir de 3,90 m de large.
    box("POR_Potence", (0.09, 0.09, 1.30), (0.0, 0.0, Z_LANTERNE + 0.90),
        m["zinc"], col)
    box("POR_Lanterne_Lit", (0.42, 0.42, 0.52), (0.0, 0.0, Z_LANTERNE),
        m["lumiere"], col)

    # (Il y avait ici un écusson au-dessus de la clé, censé « poser une
    # horizontale entre l'arc et le corps ». Le rendu rapproché l'a montré pour
    # ce qu'il était : une plaque de 16 cm d'épaisseur vue par en dessous, donc
    # deux traits en équerre au milieu d'un mur noir — une rayure, pas un
    # blason. La transition arc/corps se passe très bien de lui, et ses 24
    # sommets payent le sixième claveau, qui, lui, se voit.)


# ---------------------------------------------------------------------------
# LES ESSARTS — la cheminée de la briqueterie
#
# Les Essarts n'a qu'un distributeur (map.gd). Pas de café, pas d'hôtel, pas de
# garage, pas de pompe. C'est le bourg le plus démuni de la carte, au bout
# nord (at 0,30/0,16), et « essarts » veut dire une terre qu'on a défrichée —
# un endroit qui a été mis en valeur une fois, et plus jamais depuis.
#
# Son repère est donc ce qui reste quand tout est parti : la CHEMINÉE de la
# briqueterie qui l'a fait vivre. 24,45 m — le plus haut des huit, et il le
# reste APRÈS la reprise des quatre autres : c'est une contrainte qu'on a
# tenue, pas un hasard (voir le totem) —, et rien
# autour qu'un pan de mur. La ville n'a plus qu'un distributeur parce que
# l'usine a fermé ; la cheminée est debout parce qu'on ne démolit pas ça pour
# rien.
#
# CE QUI LUIT : le feu du haut, à 24,10 m. Un point, un seul, le plus haut du
# pays — et il est allumé pour les AVIONS, pas pour la ville. C'est la lumière
# la plus triste des huit et la mieux justifiée : elle est entretenue par
# règlement quand plus personne ne travaille en dessous. À l'œil du conducteur
# elle se lit sans erreur possible, parce qu'elle est seule et parce qu'elle
# est plus haute que tout ce que la carte contient.
#
# (Elle sortira ORANGE dans le jeu et non rouge — voir le point 2 de
# l'en-tête. Ce n'est pas un défaut à corriger, c'est la contrainte : un point
# isolé à 24 m ne ressemble à rien d'autre, quelle que soit sa teinte.)
# ---------------------------------------------------------------------------

H_CHEMINEE = 24.45
Z_SOUCHE = 22.00        # la souche s'arrête, le couronnement commence
Z_FEU = 24.10


def cheminee(col, m):
    # Le socle carré. Une cheminée d'usine part toujours d'un dé de maçonnerie
    # plus large : c'est ce qui l'empêche d'avoir l'air plantée comme un
    # poteau.
    box("CHE_Socle", (3.40, 3.40, 2.20), (0.0, 0.0, 1.10),
        m["brique"], col, bevel=0.05, segs=1)

    # La souche, octogonale et fuyante : 1,42 m de rayon en bas, 0,74 en haut
    # sur vingt mètres. Huit pas seulement — à 34 m un octogone de 1,5 m de
    # rayon est rond, et c'est 24 sommets pour la moitié de la hauteur du
    # modèle. C'est le meilleur marché du lot, et c'est ce qui paye les trois
    # cercles de fer.
    lathe("CHE_Souche", [(1.42, 2.00), (1.18, 6.00), (0.74, Z_SOUCHE)],
          m["brique"], col, steps=8)

    # Le couronnement, évasé. Il ferme le tube ouvert du lathe (troisième
    # piège) ET il fait la seule saillie de vingt mètres de fût : sans lui la
    # cheminée finit en biseau et ressemble à un crayon.
    lathe("CHE_Couronnement", [(0.74, Z_SOUCHE), (0.98, Z_SOUCHE + 0.35),
                               (0.98, Z_SOUCHE + 1.15), (0.86, Z_SOUCHE + 1.45)],
          m["brique"], col, steps=8)

    # Les trois cercles de fer. Ils ne tiennent rien de neuf : ils sont là
    # parce que ce sont les SEULES arêtes vives de la souche, et qu'une arête
    # vive est la seule chose qu'un phare rasant à 34 m sait faire briller sur
    # vingt mètres de brique mate.
    for i, z in enumerate((9.00, 14.00, 18.50)):
        k = (z - 2.0) / (Z_SOUCHE - 2.0)
        r = (1.18 * (1.0 - k) + 0.74 * k) if z > 6.0 else 1.18
        lathe("CHE_Cercle_%d" % i, [(r + 0.07, z - 0.11), (r + 0.07, z + 0.11)],
              m["zinc"], col, steps=8)

    # LE FEU, sur son petit mât. Et le paratonnerre à côté, décalé de 55 cm
    # pour qu'on lise deux objets et pas un seul trait épais.
    box("CHE_Mat", (0.09, 0.09, 0.65), (0.0, 0.0, Z_SOUCHE + 1.45 + 0.325),
        m["zinc"], col)
    box("CHE_Feu_Lit", (0.30, 0.30, 0.34), (0.0, 0.0, Z_FEU),
        m["lumiere"], col)
    box("CHE_Paratonnerre", (0.05, 0.05, 1.10), (0.55, 0.0, Z_SOUCHE + 1.90),
        m["zinc"], col)

    # Ce qui reste de la halle : un long mur DERRIÈRE la cheminée (+Y), pour que
    # le socle reste visible depuis la route, et un pignon en équerre qui
    # ENJAMBE la cheminée d'avant en arrière.
    #
    # Le pignon traversait autrefois de y = -0,30 à +3,90, tout entier derrière.
    # C'était faux deux fois. Faux d'architecture, parce qu'une cheminée
    # d'usine se tenait DEDANS le bâtiment et non contre son dos. Et faux de
    # contrat : l'emprise partait de -1,80 à +3,90, donc un repère décentré de
    # 1,10 m que rien ne mesurait (voir `_emprise`). Le mur qui enjambe corrige
    # les deux d'un coup — la ruine entoure la souche, et l'emprise se referme
    # symétriquement sur elle.
    box("CHE_Mur_Long", (7.20, 0.55, 3.60), (0.0, 2.40, 1.80),
        m["brique"], col, bevel=0.04, segs=1)
    box("CHE_Mur_Pignon", (0.55, 5.60, 2.80), (3.30, 0.00, 1.40),
        m["brique"], col, bevel=0.04, segs=1)


# ---------------------------------------------------------------------------
# PEYRELADE — la halle couverte
#
# Peyrelade a une station-service et un hôtel (map.gd), et pas de café. C'est
# le couple qui définit un bourg de MARCHÉ : on y vient, on y dort, on repart
# — mais la ville ne veille pas.
#
# La halle est la cause de l'hôtel. Un village n'entretient pas dix-sept mètres
# de charpente pour rien : il le fait parce que des gens viennent de loin un
# matin par semaine, et un village où l'on vient de loin a une auberge. Le
# repère explique encore une fois la commodité.
#
# C'EST LE SEUL LARGE DES HUIT. Huit piliers et un couvercle : 17,2 m de
# plateforme contre 3,9 m pour le clocher. Dans le brouillard, une masse basse
# et étalée ne se confond avec aucune verticale — c'est une deuxième façon
# d'être reconnaissable, et il en fallait une.
#
# ET C'ÉTAIT AUSSI SON DÉFAUT. À 13,37 m la halle ne dépassait les toits que
# sur six des treize points de vue de l'approche (46 %, 1,1 m de marge
# moyenne) : la moitié du temps elle n'était pas une masse au bout de la rue,
# elle était un bâtiment de plus dans le rang. Or une halle BASSE est juste :
# on n'empile pas un marché. Ce n'est donc pas la halle qu'il fallait monter,
# c'est ce qu'une halle porte.
#
# ELLE A DONC SON BEFFROI, et il n'est pas ajouté pour la vue : une halle de
# marché a sa cloche, et la cloche a sa cage. C'est elle qui sonne l'ouverture
# et la fermeture du marché — le beffroi de halle est l'objet civil par
# excellence, celui que la ville se donne à elle-même quand elle n'est ni une
# église ni un château. Peyrelade a la station-service et l'hôtel : c'est un
# bourg de marché, et le beffroi dit l'heure du marché.
#
# 24,00 m au lieu de 13,37, et la silhouette y GAGNE au lieu d'y perdre : la
# halle reste la seule masse large des huit, et elle est maintenant la seule
# qui soit large ET verticale. Une masse étalée surmontée d'une aiguille ne
# ressemble ni au clocher (qui est une verticale nue) ni au silo (qui est un
# bloc). RELEVÉ : 46 % de l'approche et 1,1 m au-dessus des toits sont devenus
# 100 % et 9,4 m — la meilleure marge du lot après la cheminée.
#
# Le beffroi est passé par 20,65 m (92 %) avant de se poser à 24,00 : c'est la
# halle que town.gd assied LE PLUS LOIN de l'axe (u = 32 m, contre 26 pour le
# clocher), et le rapport des décalages la punit d'autant. Le chiffre n'a pas
# été choisi, il a été trouvé — deux relevés pour l'encadrer.
#
# CE QUI LUIT : la cage vitrée du beffroi, à 20,65 m — la chambre de la cloche,
# la seule des huit lumières perchée sur un toit plutôt que plaquée sur un
# mur. Elle était en bas, sur le faîtage, à 11,88 m, où elle valait un
# lampadaire ; elle est maintenant au-dessus de tout le bourg. Le lanterneau
# qu'elle remplace n'a pas été perdu : c'est le même volume, monté de 8,8 m et
# mis dans la cage à laquelle il aurait toujours dû appartenir.
#
# La toiture est UN `loft` à deux anneaux : quatre coins d'égout, quatre points
# de faîtage. 8 sommets pour 5,85 m de croupe — un toit à quatre pans dessiné
# à la main aurait coûté six boîtes tournées et ne se serait pas fermé.
# ---------------------------------------------------------------------------

Z_EGOUT = 5.35          # le haut des piliers, la naissance du toit
Z_FAITAGE = 11.20
Z_BEFFROI = 10.40       # le fût du beffroi part SOUS le faîtage : il est assis
H_FUT_BEFFROI = 9.00    # dedans, pas posé dessus
Z_CAGE = 20.65          # la cage vitrée, la chose qui luit
H_HALLE = 24.00


def halle(col, m):
    # La plateforme. Une halle est TOUJOURS sur un emmarchement : c'est ce qui
    # la sépare de la place et ce qui empêche l'eau d'entrer.
    box("HAL_Socle", (17.20, 10.00, 0.35), (0.0, 0.0, 0.175),
        m["pierre"], col, bevel=0.04, segs=1)

    # Huit piliers de pierre, deux rangs de quatre. ILS SONT BISEAUTÉS, et
    # c'est le relevé du .glb qui l'a décidé contre le premier jet : huit
    # piliers nus coûtaient déjà 192 sommets, et les biseauter n'en ajoute PAS
    # UN (voir le troisième piège). Or ce sont les seules arêtes de pierre du
    # lot à hauteur de phare — 5 m de haut, à quelques mètres de la route,
    # frappées de biais. Refuser le biseau ici, c'était payer le prix fort pour
    # huit poteaux plats.
    for i, dx in enumerate((-6.90, -2.30, 2.30, 6.90)):
        for j, dy in enumerate((-3.90, 3.90)):
            box("HAL_Pilier_%d%d" % (i, j), (0.75, 0.75, Z_EGOUT - 0.35),
                (dx, dy, 0.35 + (Z_EGOUT - 0.35) * 0.5), m["pierre"], col,
                bevel=0.035, segs=1)

    # Les deux sablières et les trois entraits : la charpente qu'on voit PAR
    # DESSOUS le toit quand les phares entrent entre les piliers. Le repère est
    # à 7 m du bout de la rue (LM_CLEAR) et les piliers font 5 m : le faisceau
    # passe sous l'égout et va frapper la charpente et le mur du fond. C'est le
    # seul endroit du jeu où l'on verra un dessous de toit.
    for j, dy in enumerate((-3.90, 3.90)):
        box("HAL_Sabliere_%d" % j, (16.40, 0.30, 0.40), (0.0, dy, Z_EGOUT + 0.20),
            m["bois"], col)
    for i, dx in enumerate((-5.60, 0.0, 5.60)):
        box("HAL_Entrait_%d" % i, (0.28, 8.40, 0.34), (dx, 0.0, Z_EGOUT + 0.55),
            m["bois"], col)

    # LA TOITURE, d'un seul tenant. Anneau bas : les quatre coins d'égout.
    # Anneau haut : le faîtage, une bande de 12 cm de large — et non deux
    # points confondus. Deux sommets à la même place feraient un quad dégénéré
    # que `remove_doubles` recollerait en triangle, ce qui marche, mais qui
    # laisse la normale du faîtage au hasard. 12 cm coûtent zéro sommet de plus
    # et rendent la crête franche.
    loft("HAL_Toiture",
         [[(-8.60, -4.90, Z_EGOUT), (8.60, -4.90, Z_EGOUT),
           (8.60, 4.90, Z_EGOUT), (-8.60, 4.90, Z_EGOUT)],
          [(-5.00, -0.06, Z_FAITAGE), (5.00, -0.06, Z_FAITAGE),
           (5.00, 0.06, Z_FAITAGE), (-5.00, 0.06, Z_FAITAGE)]],
         m["tuile"], col, closed=True, caps=True, subsurf=0, smooth=False)

    # LE BEFFROI, à cheval sur le faîtage et au milieu exact : décalé, il
    # aurait fait croire à un accident de charpente. Son fût part à 10,40 m,
    # c'est-à-dire 80 cm SOUS le faîtage — un beffroi de halle est assis dans
    # la charpente, il ne se pose pas dessus comme une cheminée de bateau.
    #
    # Il est en ARDOISE et pas en bois : le bois du dépôt est à 0,030 de
    # réflectance, il disparaît. L'ardoise est à 0,026 mais lisse (rugosité
    # 0,55) — elle prend la lune, et c'est exactement ce qu'on demande à la
    # seule verticale du bourg. La flèche du clocher de Corbeny est du même
    # matériau et pour la même raison.
    box("HAL_Beffroi", (2.90, 2.70, H_FUT_BEFFROI),
        (0.0, 0.0, Z_BEFFROI + H_FUT_BEFFROI * 0.5), m["ardoise"], col,
        bevel=0.04, segs=1)
    box("HAL_Beffroi_Corniche", (3.40, 3.20, 0.30),
        (0.0, 0.0, Z_BEFFROI + H_FUT_BEFFROI + 0.15), m["bois"], col,
        bevel=0.03, segs=1)

    # LA CAGE de la cloche : c'est le lanterneau d'avant, le même volume à
    # 8,8 m de plus. Un abat-son vitré s'allume par en dedans. À 11,88 m il
    # était à hauteur de pignon, au milieu des fenêtres allumées du bourg ; à
    # 20,65 il est seul dans le noir au-dessus d'elles, et c'est toute la
    # différence entre une fenêtre de plus et un repère.
    box("HAL_Cage_Lit", (1.80, 1.60, 1.90), (0.0, 0.0, Z_CAGE),
        m["lumiere"], col)

    # La flèche et l'épi. Deux points de profil, quatre pas : 8 sommets de
    # cage, 16 dans le .glb — le glTF dédouble les quatre pans, et c'est le
    # second nombre que la ville paye (voir le troisième piège). Elle est
    # courte et large — 1,80 m pour 2,60 m de base —, là où celle de Corbeny
    # fait 6,20 m sur 4,10 : de loin, une aiguille et un chapeau ne se
    # confondent pas.
    lathe("HAL_Fleche", [(1.30 * DIAG, 0.0), (0.04, 1.80)],
          m["ardoise"], col, loc=(0.0, 0.0, Z_CAGE + 0.95),
          steps=4, rot=(0, 0, 45.0))
    box("HAL_Epi", (0.10, 0.10, 0.60), (0.0, 0.0, H_HALLE - 0.30),
        m["zinc"], col)

    # Le mur-bahut du fond, entre les piliers arrière. Il ferme la halle d'un
    # côté — c'est ce qui la distingue d'un préau : les phares qui entrent
    # entre les piliers tombent sur un MUR, donc sur quelque chose, et pas
    # dans le vide. (La lumière, elle, est maintenant dans la cage du beffroi
    # et n'éclaire plus rien du dessous : c'est le faisceau qui fait ce
    # travail, et il le fait mieux — il bouge.)
    box("HAL_Bahut", (16.40, 0.42, 1.15), (0.0, 3.90, 0.35 + 0.575),
        m["pierre"], col, bevel=0.04, segs=1)


# ---------------------------------------------------------------------------
# BRUMAIRE — le pont du chemin de fer
#
# Brumaire n'a qu'un café de nuit (map.gd), et c'est le bout de la carte
# (at 0,88/0,42, deux routes seulement). Son nom est le mois du brouillard.
#
# Un bourg au bout d'une ligne qui ne sert plus, avec un café ouvert la nuit
# pour ceux qui font demi-tour : le repère est le PONT du chemin de fer
# désaffecté, celui qui barre le fond de la rue en entrant. La voie est
# déposée, le tablier est resté — on ne démonte pas dix-huit mètres de
# treillis rivé pour la ferraille.
#
# C'EST LE SEUL HORIZONTAL DES HUIT. Le treillis barre le ciel en travers de
# la rue : à l'œil du conducteur c'est une ligne noire en l'air, et rien
# d'autre sur cette carte n'est une ligne. Avec le clocher (une verticale) et
# la halle (une masse coiffée d'une aiguille), ça fait trois façons
# différentes d'occuper le brouillard.
#
# (LA VERSION D'AVANT DISAIT « le seul qu'on passe DESSOUS », et l'entretoise
# de clé était payée pour « la seconde où l'on lève les yeux ». On ne passe
# pas dessous : town.gd pose le repère à LM_CLEAR = 7 m au-delà du bout de la
# rue, sur un parvis. L'entretoise a donc été retirée : 24 sommets pour un
# événement qui n'arrive jamais. Ils rendent la moitié des 48 que coûte le
# sémaphore — le repère passe de 480 à 504 sommets .glb, soit exactement le
# plafond du lot, celui du clocher, et pas un de plus.)
#
# ET C'EST LE REPÈRE QUI A ÉTÉ LE PLUS DUR À CORRIGER. À 12,05 m il ne
# dépassait les toits que sur quatre des treize points de vue de l'approche
# (31 %, 0,4 m de marge moyenne) ; et un pont ne se rallonge pas vers le haut
# comme une tour — un treillis de 18 m qui monterait à 20 serait une
# caricature. Deux gestes, tous les deux vrais du chemin de fer et pas de la
# lisibilité :
#
#   1. LES CULÉES DEVIENNENT DES PILES. La ligne ne franchissait pas une route
#      de plain-pied, elle franchissait le VALLON au fond duquel le bourg est
#      posé — ce qui est la raison ordinaire d'un tablier en treillis, et la
#      raison pour laquelle la ligne est morte : on n'entretient pas ça pour
#      deux trains par jour. Le dessus des piles passe de 8,40 à 14,20 m. Ça
#      ne coûte PAS UN SOMMET : une boîte plus haute est la même boîte, et à
#      elle seule cette ligne-là a fait passer le repère de 31 % à 100 %.
#   2. LE SÉMAPHORE reste debout sur la pile, comme ils le restent tous sur
#      les lignes déposées : c'est en fonte, ça ne vaut rien à la ferraille et
#      ça demande une grue. 7,10 m de mât au-dessus de la pile, donc 21,30 m
#      au-dessus de la rue — un mât de signal ordinaire, porté haut par le
#      pont. Son bras est retombé à l'horizontale, position de FERMÉ : c'est
#      là que retombe un sémaphore qu'on ne tire plus, et c'est la seule
#      chose que Brumaire dise encore aux trains.
#
# IL N'EST PAS ALLUMÉ, ET C'EST VOULU. La tentation était d'y mettre un
# second feu — un signal, ça s'allume. Deux raisons de ne pas le faire, et la
# seconde est la vraie : un point isolé à vingt mètres dans le brouillard,
# c'est déjà LES ESSARTS (le feu d'avion de la cheminée, à 24,10 m), et deux
# bourgs qui se ressemblent à deux cents mètres, c'est un bourg de moins. La
# lanterne d'un sémaphore est sur son BRAS, et le bras d'un signal mort est
# mort avec lui.
#
# CE QUI LUIT : le fanal accroché à la membrure basse, à 16,00 m et décalé de
# 3,20 m à gauche de l'axe. C'est la seule lumière DÉCENTRÉE du lot — les sept
# autres sont sur l'axe du modèle —, et ce décalage est précisément ce qui la
# rend lisible : une lumière qui n'est pas au milieu de sa silhouette ne peut
# être que Brumaire. Elle était à 10,20 m et elle a monté avec le tablier :
# c'est le même fanal, à la même place sur la même membrure.
#
# Le treillis : trois diagonales par ferme, alternées. Le compte est choisi
# sur la LECTURE et sur le relevé du .glb, pas sur la statique — voir le corps
# de la fonction.
# ---------------------------------------------------------------------------

Z_TABLIER = 14.20       # le dessus des piles : la profondeur du vallon franchi
Z_MEMBRURE_B = 14.35
Z_MEMBRURE_H = 17.55
Y_FACE = 1.85           # demi-écartement des deux fermes
Z_FANAL = 16.00
X_SEMAPHORE = 7.40      # sur la pile opposée au fanal, dans l'emprise des 18 m
Z_SEMAPHORE = 21.30     # le haut du mât : c'est lui qui donne sa hauteur
H_PONT = Z_SEMAPHORE


def pont(col, m):
    # Les deux PILES de pierre. Elles portent tout et elles sont la seule masse
    # du modèle : sans elles le treillis flotte, et un pont qui flotte n'est
    # pas un pont, c'est une poutre.
    #
    # Elles faisaient 8,40 m et c'étaient des culées ; elles font 14,20 m et ce
    # sont des piles. Le geste ne coûte RIEN — une boîte plus haute est la même
    # boîte, 24 sommets —, et c'est lui qui a rendu le repère visible : voir
    # l'en-tête. 3,20 m d'épaisseur pour 14,20 de haut, c'est l'élancement
    # ordinaire d'une pile de viaduc en maçonnerie ; plus mince, elle aurait eu
    # l'air d'un pilotis.
    for sx in (-1, 1):
        box("PON_Pile_%d" % sx, (3.20, 6.00, Z_TABLIER),
            (sx * 7.40, 0.0, Z_TABLIER * 0.5), m["pierre"], col,
            bevel=0.06, segs=1)

    # Le tablier, posé d'une pile à l'autre.
    box("PON_Tablier", (12.60, 3.60, 0.30), (0.0, 0.0, Z_TABLIER + 0.15),
        m["acier"], col)

    # Les quatre membrures, deux par ferme.
    for j, sy in enumerate((-1, 1)):
        for k, z in enumerate((Z_MEMBRURE_B, Z_MEMBRURE_H)):
            box("PON_Membrure_%d%d" % (j, k), (11.60, 0.30, 0.34),
                (0.0, sy * Y_FACE, z), m["acier"], col)

    # Les diagonales : TROIS par ferme, sur trois travées de 3,867 m pour 3,20 m
    # de hauteur, donc 50,4° du vertical — et la rotation se donne en DEGRÉS
    # (le piège du haut se paye ici aussi, et il se verrait tout de suite : les
    # barres seraient restées verticales).
    #
    # Elles étaient quatre par ferme. Le relevé du .glb a tranché : à 24
    # sommets la barre quel que soit son biseau, huit diagonales pesaient 192
    # sommets — plus que les deux piles, le tablier et les quatre membrures
    # réunis. Et à 34 m, trois grandes diagonales se lisent MIEUX que quatre
    # petites : ce qui fait un treillis à l'œil, c'est le zigzag, pas le
    # nombre de mailles.
    dz = Z_MEMBRURE_H - Z_MEMBRURE_B
    pas = 11.60 / 3.0
    lg = math.hypot(pas, dz)
    ang = math.degrees(math.atan2(pas, dz))
    for j, sy in enumerate((-1, 1)):
        for i, dx in enumerate((-pas, 0.0, pas)):
            s = 1.0 if i % 2 == 0 else -1.0
            box("PON_Diagonale_%d%d" % (j, i), (0.22, 0.20, lg),
                (dx, sy * Y_FACE, (Z_MEMBRURE_B + Z_MEMBRURE_H) * 0.5),
                m["acier"], col, rot=(0.0, s * ang, 0.0))

    # Les montants d'extrémité, qui ferment le treillis à ses deux bouts.
    #
    # (Il y avait ici une entretoise de clé entre les deux fermes, justifiée
    # par « elle ne se voit que de dessous, à l'instant où l'on passe — c'est
    # une seconde de jeu ». Cette seconde n'existe pas : town.gd pose le repère
    # sur un parvis de 7 m au bout de la rue, et l'on ne passe jamais sous le
    # pont. Vingt-quatre sommets pour un événement qui n'arrive pas, c'est
    # exactement l'erreur que le troisième piège raconte dans l'autre sens.
    # Ils sont rendus, et ils payent le mât du sémaphore.)
    for j, sy in enumerate((-1, 1)):
        for i, dx in enumerate((-5.80, 5.80)):
            box("PON_Montant_%d%d" % (j, i), (0.26, 0.22, dz + 0.34),
                (dx, sy * Y_FACE, (Z_MEMBRURE_B + Z_MEMBRURE_H) * 0.5),
                m["acier"], col)

    # LE SÉMAPHORE. Le mât est planté sur la pile de droite, hors du treillis :
    # dessus, il se serait confondu avec les montants ; à côté, il fait la
    # SECONDE ligne du repère — une verticale au bout d'une horizontale, ce que
    # ni le clocher ni la halle ne dessinent.
    #
    # Le bras est à l'horizontale, tendu vers le tablier (donc vers -X depuis
    # le mât) : le côté de la voie qu'il protégeait. C'est la position de
    # FERMÉ, celle où un sémaphore retombe tout seul quand plus personne ne
    # tire le fil — le signal n'est pas figé par erreur, il est fermé pour
    # toujours.
    box("PON_Semaphore_Mat", (0.30, 0.30, Z_SEMAPHORE - Z_TABLIER),
        (X_SEMAPHORE, 0.0, (Z_SEMAPHORE + Z_TABLIER) * 0.5), m["acier"], col)
    box("PON_Semaphore_Bras", (2.10, 0.12, 0.46),
        (X_SEMAPHORE - 1.20, -0.21, Z_SEMAPHORE - 0.75), m["acier"], col)

    # LE FANAL et sa potence, sur la face de la rue. Le fanal est en avant de
    # la ferme (-Y) : accroché derrière, il aurait été mangé par la membrure
    # dès qu'on s'approche.
    box("PON_Potence", (0.09, 0.34, 0.09), (-3.20, -Y_FACE - 0.17, Z_FANAL + 0.32),
        m["zinc"], col)
    box("PON_Fanal_Lit", (0.34, 0.30, 0.42), (-3.20, -Y_FACE - 0.32, Z_FANAL),
        m["lumiere"], col)


# ---------------------------------------------------------------------------
# LE CATALOGUE
#
# `vise` : la hauteur que la caméra de trois quarts regarde. `route` : celle que
# regarde l'œil du conducteur — plus basse, parce qu'un conducteur ne lève pas
# la tête au volant. `pres` : (position, cible, focale) de la caméra de détail,
# posée sur la chose qui luit et sur elle seule.
# ---------------------------------------------------------------------------

REPERES = {
    "clocher": {
        "ville": "Corbeny", "bati": clocher, "prefixe": "CLO_", "h": 21.96,
        "vise": 11.50, "route": 9.60, "brume": 8.90,
        "pres": ((3.60, -14.00, 9.60), (0.0, 0.0, 9.20), 62.0),
    },
    "totem": {
        "ville": "Saint-Elme", "bati": totem, "prefixe": "TOT_", "h": H_TOTEM,
        "vise": 11.70, "route": 10.30, "brume": Z_PANNEAU,
        "pres": ((2.90, -10.00, 21.30), (0.0, 0.0, Z_PANNEAU), 55.0),
    },
    "chateau_eau": {
        "ville": "La Fresnaie", "bati": chateau_eau, "prefixe": "EAU_",
        "h": H_EAU, "vise": 10.60, "route": 9.20, "brume": 14.00,
        "pres": ((4.20, -12.00, 15.60), (0.0, 0.0, 14.00), 55.0),
    },
    "silo": {
        "ville": "Malassis", "bati": silo, "prefixe": "SIL_", "h": H_SILO,
        "vise": 11.60, "route": 10.00, "brume": 15.10,
        "pres": ((4.30, -11.00, 16.40), (4.30, 0.0, 15.10), 50.0),
    },
    "porte": {
        "ville": "Vieux-Bourg", "bati": porte, "prefixe": "POR_", "h": H_PORTE,
        "vise": 11.80, "route": 10.40, "brume": 6.90,
        # De face et bas : c'est la seule facon de voir la lanterne, et c'est
        # exactement la place du conducteur qui va passer dessous.
        "pres": ((0.30, -13.00, 1.60), (0.0, 0.0, 6.90), 45.0),
    },
    "cheminee": {
        "ville": "Les Essarts", "bati": cheminee, "prefixe": "CHE_",
        "h": H_CHEMINEE, "vise": 12.40, "route": 10.60, "brume": 24.10,
        "pres": ((3.20, -13.00, 22.60), (0.0, 0.0, 23.20), 55.0),
    },
    "halle": {
        "ville": "Peyrelade", "bati": halle, "prefixe": "HAL_", "h": H_HALLE,
        "vise": 12.40, "route": 11.00, "brume": Z_CAGE,
        "pres": ((3.40, -12.00, 21.25), (0.0, 0.0, Z_CAGE), 55.0),
    },
    "pont": {
        "ville": "Brumaire", "bati": pont, "prefixe": "PON_", "h": H_PONT,
        "vise": 11.20, "route": 9.80, "brume": Z_FANAL,
        "pres": ((-2.20, -11.00, 16.20), (-3.20, -1.85, Z_FANAL), 55.0),
    },
}


def _rendu_brume(nom, spec, col_env, pct, autres):
    """LA VUE QUI JUGE LA DOCTRINE — « lisible à deux cents mètres dans le
    brouillard, quand la pierre ne rend plus rien ».

    Toute la conception des huit repose sur une affirmation : chaque bourg se
    reconnaît à la FORME de sa lumière, puisque la couleur ne nous appartient
    pas (point 2 de l'en-tête). Cette vue-là est la seule qui puisse la
    démentir, et elle est bâtie pour ça — pas pour flatter.

    Le protocole : caméra à 200 m, LUNE ET PHARES ÉTEINTS. Éteindre les deux
    fait exactement ce que le brouillard de town.gd fait à cette distance —
    à 0,030 de densité il ne passe plus que 0,25 % de ce que la pierre
    renvoie, autant dire rien. Il ne reste donc à l'image que la surface 6, et
    la question devient nette : ces huit taches sont-elles huit taches
    DIFFÉRENTES ?

    Ce n'est pas un test photométrique — EEVEE ne fait pas diffuser une surface
    émissive dans un volume, donc pas de halo, donc l'image est PLUS SÉVÈRE que
    le jeu. Une forme qui se distingue ici se distinguera là-bas.
    """
    lune = bpy.data.objects["ENV_Lune"]
    ph = bpy.data.objects["ENV_Phares"]
    garde = (lune.data.energy, ph.data.energy)
    lune.data.energy = 0.0
    ph.data.energy = 0.0
    try:
        # La caméra vise la CHOSE QUI LUIT et non le milieu du modèle : à 200 m
        # c'est elle qu'on cherche, et le reste n'est qu'une découpe autour.
        camera("CAM_brume", (0.0, -200.0, 2.60), (0.0, 0.0, spec["brume"]),
               85.0, col_env)
        render_views([("CAM_brume", "landmark_%s_brume.png" % nom, autres)],
                     RENDERS, pct=pct)
    finally:
        lune.data.energy, ph.data.energy = garde


def _rendus(nom, spec, col_env, pct):
    """Trois vues du repère `nom`, tous les autres masqués."""
    camera("CAM_silhouette", (16.0, -30.0, 12.0), (0.0, 0.0, spec["vise"]),
           40.0, col_env)
    camera("CAM_route", (1.30, -34.00, 1.45), (0.0, 0.0, spec["route"]),
           40.0, col_env)
    loc, cible, foc = spec["pres"]
    camera("CAM_pres", loc, cible, foc, col_env)
    autres = [s["prefixe"] for n, s in REPERES.items() if n != nom]
    render_views([("CAM_silhouette", "landmark_%s.png" % nom, autres),
                  ("CAM_route", "landmark_%s_route.png" % nom, autres),
                  ("CAM_pres", "landmark_%s_pres.png" % nom, autres)],
                 RENDERS, pct=pct)
    _rendu_brume(nom, spec, col_env, pct, autres)


def planche(noms, suffixe="_brume", sortie="planche_brume_200m.png",
            cw=300, ch=300, cols=4, reduire=0):
    """Les huit CÔTE À CÔTE, découpés au centre de leur rendu.

    Elle est faite ici et pas à la main, pour la raison qui a coûté les
    vingt-quatre premiers rendus (voir `_menage_demarrage`) : une vérification
    qui n'est pas dans le code n'a pas eu lieu, et c'est celle-ci qui juge la
    doctrine des huit lumières. On ne compare pas huit images ouvertes l'une
    après l'autre — on les met sur la même planche, ou on ne compare rien.

    Les deux images sont mises en `Non-Color` : sans ça, Blender décode le PNG
    en linéaire à la lecture et le ré-encode à l'écriture, et la planche sort
    plus claire que les rendus qu'elle est censée montrer.

    ET LES DEUX PLANCHES RÉDUISENT, aucune ne découpe. La planche de brume
    découpait encore au centre : ça marchait tant que le plus grand des huit
    faisait 24,45 m, ça s'est mis à décapiter la halle et le pont dès qu'ils
    ont grandi — exactement la faute racontée ci-dessous, un cran plus tard.
    Une fenêtre fixe est une hypothèse sur la taille des sujets, et une
    hypothèse sur les sujets finit toujours par être fausse.
    """
    import numpy as np
    rows = (len(noms) + cols - 1) // cols
    if reduire:
        # Vue ENTIÈRE réduite d'un facteur entier, et non découpée au centre.
        # Le premier jet découpait : sur un lot qui allait alors de 12,05 m à
        # 24,45, une fenêtre fixe décapitait la cheminée, le silo et le
        # clocher, et coupait le pont en deux. Une planche qui ampute trois
        # sujets sur huit ne compare rien — elle ment sur ce qu'elle montre.
        # (Le lot va aujourd'hui de 18,62 à 24,45 : l'écart s'est resserré,
        # l'argument non. Une fenêtre fixe redeviendrait fausse au premier
        # repère qui bouge, et c'est ce qui vient d'arriver.)
        cw, ch = 640 // reduire, 900 // reduire
    out = np.zeros((rows * ch, cols * cw, 4), dtype=np.float32)
    out[..., 3] = 1.0
    for i, nom in enumerate(noms):
        img = bpy.data.images.load(
            os.path.join(RENDERS, "landmark_%s%s.png" % (nom, suffixe)))
        img.colorspace_settings.name = 'Non-Color'
        w, h = img.size
        buf = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        buf = buf.reshape(h, w, 4)
        if reduire:
            crop = buf[::reduire, ::reduire][:ch, :cw]
        else:
            crop = buf[h // 2 - ch // 2:h // 2 + ch // 2,
                       w // 2 - cw // 2:w // 2 + cw // 2]
        r, c = divmod(i, cols)
        # Blender range ses pixels du BAS vers le haut : la première ligne de
        # repères doit donc aller dans la dernière bande du tableau.
        out[(rows - 1 - r) * ch:(rows - r) * ch, c * cw:(c + 1) * cw] = crop
        bpy.data.images.remove(img)
    res = bpy.data.images.new("planche", cols * cw, rows * ch, alpha=True)
    res.colorspace_settings.name = 'Non-Color'
    res.pixels.foreach_set(out.ravel())
    res.filepath_raw = os.path.join(RENDERS, sortie)
    res.file_format = 'PNG'
    res.save()
    bpy.data.images.remove(res)
    return os.path.join(RENDERS, sortie)


def main(seuls=None, rendre=True, pct=100):
    noms = [n for n in REPERES if not seuls or n in seuls]

    # Le ménage d'abord, TOUT le ménage. Les materiaux se refont APRES, pas
    # avant : clear_collection purge les datablocks orphelins, et des materiaux
    # crees d'avance n'ont encore aucun utilisateur — ils partaient a la
    # poubelle et le premier maillage recevait un pointeur mort. Paye au
    # premier lancement. Avec huit reperes le piege est huit fois plus proche :
    # un seul clear_collection tardif suffirait a vider la table.
    for nom in noms:
        clear_collection("Landmark_%s" % nom)
    clear_collection("ENV_landmark")
    restes = _menage_demarrage()
    if restes:
        print("  menage : %s" % ", ".join(restes))

    m = _materiaux()
    col_env = _scene()

    faits = {}
    for nom in noms:
        spec = REPERES[nom]
        colname = "Landmark_%s" % nom
        col = get_col(colname)
        spec["bati"](col, m)
        for ob in col.objects:
            shade(ob, 40)
        bpy.context.view_layer.update()

        chemin = os.path.join(MODELS, "landmark_%s.glb" % nom)
        export_glb(colname, chemin)
        cage_v, cage_t, ev_v, ev_t = _compte(colname)
        glb_v, glb_t = _compte_glb(chemin)
        # L'emprise est MESURÉE sur la géométrie, pas recopiée des constantes du
        # haut : c'est la constante qui doit suivre le modèle.
        em = _emprise(colname)
        lits = sorted(ob.name for ob in col.objects if ob.name.endswith("_Lit"))
        # Le contrat, vérifié et pas supposé. Un demi-mètre de tolérance sur le
        # centrage : au-delà, le bourg posera le repère à côté de l'endroit où
        # il croit le poser.
        ecarts = []
        if abs(em["base"]) > 0.005:
            ecarts.append("base a z=%.3f et non 0" % em["base"])
        if max(abs(em["dx"]), abs(em["dy"])) > 0.50:
            ecarts.append("decentre de (%.2f, %.2f)" % (em["dx"], em["dy"]))
        if not lits:
            ecarts.append("aucun objet _Lit : rien n'y luit")
        faits[nom] = {
            "ville": spec["ville"], "objets": len(col.objects),
            "cage": (cage_v, cage_t), "evalue": (ev_v, ev_t),
            "glb": (glb_v, glb_t), "haut": round(em["haut"], 2),
            "centre": (round(em["dx"], 2), round(em["dy"], 2)),
            "lits": lits, "ecarts": ecarts,
        }

    if rendre:
        for nom in noms:
            _rendus(nom, REPERES[nom], col_env, pct)
        # Deux planches, et elles ne posent pas la même question. Celle de
        # 200 m demande « ces huit lumières sont-elles huit lumières ? » ;
        # celle de 34 m demande « ces huit bourgs sont-ils huit bourgs ? ».
        planche(noms, reduire=2)
        planche(noms, suffixe="_route", sortie="planche_route_34m.png",
                reduire=2)

    save_blend(os.path.join(HERE, "landmarks.blend"))
    return faits


if __name__ == "__main__":
    res = main()
    print("")
    print("  %-12s %-12s %7s %-13s  %-13s %-13s %-13s  %s"
          % ("repere", "ville", "haut", "centre", "cage", "evalue", ".glb",
             "ce qui luit"))
    tv = tt = 0
    ecarts = []
    for nom, d in res.items():
        tv += d["glb"][0]
        tt += d["glb"][1]
        print("  %-12s %-12s %5.2f m (%+.2f,%+.2f)  %5d v %5d t  %5d v %5d t  %5d v %5d t  %s"
              % (nom, d["ville"], d["haut"], d["centre"][0], d["centre"][1],
                 d["cage"][0], d["cage"][1], d["evalue"][0], d["evalue"][1],
                 d["glb"][0], d["glb"][1], ", ".join(d["lits"])))
        ecarts += ["%s : %s" % (nom, e) for e in d["ecarts"]]
    print("  %-33s TOTAL .glb des huit : %5d v %5d t" % ("", tv, tt))
    # Le contrat parle en dernier, et il parle fort : un repere hors contrat est
    # un repere que le bourg posera de travers, et rien d'autre ne le dira.
    print("")
    if ecarts:
        print("  CONTRAT ROMPU :")
        for e in ecarts:
            print("    - %s" % e)
    else:
        print("  contrat tenu : les huit ont leur base a z = 0, sont centres a")
        print("  moins de 50 cm pres, et chacun a sa chose qui luit.")
