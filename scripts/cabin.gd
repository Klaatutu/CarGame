extends Node3D
##
## La voiture : interieur ET exterieur viennent des modeles Blender
## (assets/blender/build_civic_*.py -> assets/models/civic_*.glb).
##
## Honda Civic EF (1990), 3 portes. Cotes reelles : 3965 x 1675 x 1340 mm,
## empattement 2500 mm.
##
## Le .glb couvre plancher, planche de bord, compteurs, console, sieges,
## pedales, portieres, montants, ciel de toit, retroviseur, ceintures. Il a ete
## construit sur les memes constantes que ce script et driver.gd : volant a
## (-0.33, 0.78, -0.38) incline de 68 degres, pedales a -0.24 / -0.39 / -0.52.
## Rien a recaler.
##
## Ce script fournit en plus les PIVOTS que le jeu anime : volant, levier de
## vitesses et frein a main pour driver.gd, aiguilles des compteurs pour
## car.gd (set_gauges). Les pieces du .glb sont reparentees dessous, ce qui
## evite d'avoir a doubler le modele avec des primitives.
##

const Retro := preload("res://scripts/retro.gd")
## La geometrie de collision, relevee sur le .glb par tools/bake_cabin.gd.
## Chargee et non prechargee : si elle manque, on veut le dire et continuer,
## pas refuser de compiler.
const SHAPE_PATH := "res://assets/cabin_shape.res"
const INTERIOR := preload("res://assets/models/civic_interior.glb")
const EXTERIOR := preload("res://assets/models/civic_exterior.glb")
const CigPack := preload("res://scripts/cig_pack.gd")
const MirrorScript := preload("res://scripts/mirror.gd")
const VisorScript := preload("res://scripts/visor.gd")
const WindowScript := preload("res://scripts/window.gd")
const IgnitionScript := preload("res://scripts/ignition.gd")
const DomeLight := preload("res://scripts/dome_light.gd")
const GlareScript := preload("res://scripts/windshield_glare.gd")
const CentipedeScript := preload("res://scripts/centipede.gd")

## Couche des solides de l'habitacle. La caisse elle-meme est sur la couche 1
## avec une boite qui englobe tout l'interieur : sans couche dediee, un objet
## pose dedans en serait ejecte.
const LAYER_INTERIOR := 4
## Ou le paquet demarre, en espace voiture. Il est cree par car.gd et vit dans
## le MONDE : un RigidBody3D enfant d'un noeud qui bouge se bat avec la physique.
const PACK_SPAWN := Vector3(0.30, 0.495, 0.10)
## Canettes (can.gd) : [boisson, ecrasee, position de depart, lacet en degres],
## en espace voiture. Les intactes a portee de main — console entre le levier
## (z -0.30) et la pointe du frein a main (z -0.05), assise passager, planche
## cote passager — et les ecrasees qui trainent au plancher passager, sur la
## banquette et dans le plancher arriere. Elles demarrent quelques centimetres
## au-dessus de leur surface et s'y posent d'elles-memes.
const CAN_SPAWNS := [
	["nosleep", false, Vector3(0.0, 0.67, -0.19), 0.0],
	["kombo", false, Vector3(0.46, 0.56, 0.30), -20.0],
	["cariboon", false, Vector3(0.45, 1.02, -0.60), 10.0],
	["nosleep", true, Vector3(0.42, 0.42, -0.35), 40.0],
	["kombo", true, Vector3(-0.30, 0.56, 1.00), -30.0],
	["cariboon", true, Vector3(0.32, 0.42, 0.72), 70.0],
]

## Le revolver (revolver.gd), sur l'assise passager, dans le creux laisse entre
## le paquet (z 0.10) et la canette (z 0.30). Couche en travers, bouche vers la
## portiere passager : ni vers le conducteur, ni vers le pare-brise.
const REVOLVER_SPAWN := Vector3(0.40, 0.62, 0.20)
const REVOLVER_YAW := -95.0

const SEAT_X := -0.33
## Facteur applique aux albedos du .glb pour les ramener dans la palette de nuit.
const INTERIOR_DIM := 0.62
const EXTERIOR_DIM := 0.85
## Nom du materiau de vitrage dans les DEUX .glb (assets/blender/civic_materials.py).
## Les glaces de retroviseur sont en chrome, le verre de compteur et celui des
## phares ont chacun le leur : aucun ne porte ce nom, aucun n'est touche.
const GLASS_MATERIAL := "CIV_Window_Glass"
## Ce que la glace RETIENT de la lumiere qui la traverse. Chaque baie est vitree
## deux fois — la glace de l'habitacle double celle de la carrosserie — donc le
## paysage est attenue deux fois : 0,04 par glace, soit 8 % en tout. C'est le
## seul nombre a bouger pour rendre le vitrage plus ou moins present.
const GLASS_ALPHA := 0.04
## Teinte PROPRE de la glace, celle qu'elle ajoute par-dessus le paysage.
##
## Le .glb la sort presque BLANCHE (0,88 0,92 0,95). Eclairee par le plafonnier
## et le retour des phares, une surface blanche se comporte en depoli laiteux :
## mesure faite, elle ajoutait a elle seule +16 niveaux de luminance sur ce qu'on
## voit au travers (36 au lieu de 20) et rabotait le contraste de 17 a 14,6 —
## d'ou la route grise et les arbres delaves. Une vitre n'a pas de couleur a
## elle : au quasi-noir elle ne delave plus rien, et c'est le reflet qui la rend
## visible. Ne pas remonter ces trois valeurs sans re-tirer `-- shot`.
const GLASS_TINT := Color(0.02, 0.025, 0.035)
## Braquage maxi des roues avant, en degres.
const WHEEL_STEER_MAX := 30.0
## Roues du modele exterieur : nom -> [cote (-1 gauche / +1 droite), directrice].
## Chaque roue est un Node3D dont l'axe local +Y est l'essieu (tourne vers l'exterieur).
const WHEEL_NAMES := {
	"EXT_Wheel_FL": [-1.0, true], "EXT_Wheel_FR": [1.0, true],
	"EXT_Wheel_RL": [-1.0, false], "EXT_Wheel_RR": [1.0, false],
}

const HALF_W := 0.8375            # 1675 mm
const NOSE := -1.98
const TAIL := 1.98
const AXLE_F := -1.18
const AXLE_R := 1.32
const WHEEL_R := 0.29

const ROOF_Y := 1.30
const ROOF_BACK := 1.06
const BELT_Y := 0.97
const SILL_Y := 0.47
const HEADER_Y := 1.28
const HEADER_Z := -0.34
const COWL_Y := 0.93
const COWL_Z := -0.92

## De combien la colonne de direction est ramenee vers le conducteur.
const COLUMN_PULL := 0.02

## Les trois glaces a remplacer par de vrais miroirs (mirror.gd). Interieur,
## puis les deux retroviseurs de portiere.
const MIRROR_GLASS := ["BODY_MirrorGlass", "EXT_MirrorGlass_L", "EXT_MirrorGlass_R"]
## Ce que chaque glace doit montrer, en espace voiture. Voir _swivel().
## Seule l'interieure est a regler ; legerement plongeante pour cadrer la lunette
## arriere plutot que le ciel.
const MIRROR_AIM := {"BODY_MirrorGlass": Vector3(0.0, -0.05, 1.0)}
## Pieces qui pivotent avec la glace quand on la regle : la tete entiere, pas la
## tige, qui est fixee au pavillon.
const MIRROR_HEAD := {"BODY_MirrorGlass": ["BODY_Mirror", "BODY_MirrorGlass"]}
## Position de l'oeil au poste de conduite, pour le reglage des glaces.
## C'est HEAD_POS de car.gd : les deux doivent rester d'accord.
const EYE_REF := Vector3(SEAT_X, 1.15, 0.28)

## Vitres de portiere et leur manivelle. `panes` en liste DEUX : le modele
## d'habitacle et celui de carrosserie ont chacun leur glace.
const WINDOWS := [
	{"side": "L", "hub": "DOOR_L_CrankHub", "knob": "DOOR_L_CrankKnob",
		"moving": ["DOOR_L_CrankArm", "DOOR_L_CrankKnob"],
		"panes": ["DOOR_L_Glass", "EXT_DoorGlass_L"]},
	{"side": "R", "hub": "DOOR_R_CrankHub", "knob": "DOOR_R_CrankKnob",
		"moving": ["DOOR_R_CrankArm", "DOOR_R_CrankKnob"],
		"panes": ["DOOR_R_Glass", "EXT_DoorGlass_R"]},
]

## BOUCHES D'AERATION : par ou le mille-pattes entre (centipede.gd).
##
## Chaque nom est une piece du .glb, et tout le reste — position, taille,
## direction — en est RELEVE (voir _build_vents et tools/probe_vents.gd). Une
## bouche saisie a la main ici finirait par ne plus tomber sur la grille qu'elle
## pretend designer, exactement comme les surfaces de depose avant qu'on les
## mesure.
##
## Le haut-parleur de portiere en fait partie : c'est une grille, elle donne sur
## un caisson, et un caisson donne sur le vide de la portiere. Il n'y a aucune
## raison de la traiter autrement qu'un aerateur — sauf qu'elle est a hauteur de
## coude, ce qui est pire.
const VENT_MOUTHS := {
	"DASH_Defrost": "grille de degivrage",
	"DASH_CenterDefrost": "degivrage central",
	"DASH_SideVentInner_L": "aerateur lateral gauche",
	"DASH_SideVentInner_R": "aerateur lateral droit",
	"STK_Vent_L": "aerateur central gauche",
	"STK_Vent_R": "aerateur central droit",
	"DOOR_L_SpeakerGrille2": "haut-parleur gauche",
	"DOOR_R_SpeakerGrille2": "haut-parleur droit",
}

## Pare-soleil : panneau -> tige, qui donne l'axe de basculement.
const VISORS := {
	"BODY_Visor_L": "BODY_VisorRod_L",
	"BODY_Visor_R": "BODY_VisorRod_R",
}

## Pieces du volant qui tournent avec la jante. Le reste (colonne, fourreau,
## contacteur, commodos) doit rester fixe.
const WHEEL_SPINNING := ["STR_Rim", "STR_Pad", "STR_BadgePlate", "STR_H_Bar",
	"STR_H_Left", "STR_H_Right", "STR_Horn_L", "STR_Horn_R",
	"STR_Spoke_LL", "STR_Spoke_LR", "STR_Spoke_UL", "STR_Spoke_UR"]
const SHIFT_MOVING := ["CON_ShiftLever", "CON_ShiftKnob", "CON_ShiftBadge", "CON_ShiftBoot"]
const BRAKE_MOVING := ["CON_BrakeLever", "CON_BrakeGrip", "CON_BrakeButton"]

## Cadrans du bloc compteurs. Chacun balaie 270 degres, de 7 h 30 a 4 h 30, et
## le modele en gradue deux : 0-200 km/h (onze traits) et 0-8000 tr/min (neuf).
## Ces echelles sont celles de build_civic_interior.py ; si on y change les
## graduations, il faut les reporter ici.
const GAUGE_SWEEP_DEG := 270.0
const SPEEDO_MAX_KMH := 200.0
const TACHO_MAX_RPM := 8000.0

## LA FORME DE L'HABITACLE, RELEVEE SUR LE MODELE (cabin_shape.gd).
##
## Elle remplace les trois listes de boites que ce fichier declarait a la main —
## `surfaces` (ou l'on pose), `solids` (ce qui arrete) et `crawl_solids` (ou
## l'on rampe). Elles disaient chacune une partie du meme habitacle, aucune ne
## disait le vrai, et les trois defauts que voyait le joueur etaient le meme :
##
##   - un objet lance s'arretait DANS la portiere, parce que la boite etait a
##     x 0,79 (la tole) quand la garniture visible est a 0,70 — mesure :
##     28 % des lancers pour le paquet, 59 % pour une canette ;
##   - on ne pouvait pas poser sur tout le tableau de bord, parce que le fond de
##     planche n'avait de boite que cote passager, alors que la tole court d'un
##     montant a l'autre a 93-95 cm ;
##   - le mille-pattes ne marchait que sur les faces auxquelles on avait pense.
##
## Une seule geometrie, relevee et non saisie, les fait disparaitre ensemble.
## Voir cabin_shape.gd pour ce qu'elle contient et pourquoi elle est cuite.
var shape: Resource

## LE VITRAGE, qui lui n'est PAS dans le releve.
##
## Le releve ignore les glaces a dessein : on les regarde AU TRAVERS, et une
## vitre pleine dans la grille rendrait l'habitacle aveugle. Il reste donc a
## fermer le haut de caisse a la main — mais c'est de la geometrie qu'on
## connait, pas des cotes de garniture qu'il faudrait deviner : le pare-brise
## est un plan, defini par ses deux lignes de baie, et les autres glaces sont
## des plaques.
##
## Ces boites-la peuvent se chevaucher sans dommage : cabin_shape.gd resout
## contre l'UNION, pas boite par boite.
var shell: Array = []
## Bouches d'aeration relevees sur le modele : [{label, pos, dir, half}].
var vents: Array = []
## Le mille-pattes (centipede.gd). Il vit dans l'habitacle, pas dans la voiture.
var centipede: Node3D

## COQUE DE L'HABITACLE : le volume dont un objet ne sort JAMAIS.
##
## Les `solids` ci-dessus sont du MOBILIER — sieges, planche, console, portieres.
## Ils donnent les bons rebonds, mais ils ne ferment rien : c'est une dizaine de
## boites posees cote a cote, et entre elles il reste des fentes (sous la
## portiere, devant le tablier, au bord du plancher). Tant que les objets se
## contentaient de tomber et de glisser, aucun n'allait les chercher.
##
## Un objet LANCE, si. Sur un balayage de toutes les directions de lancer, deux
## sur trois trouvaient une fente, sortaient de la caisse, et le filet de
## securite de prop.gd les ramenait a leur point de depart : "l'objet disparait
## et reapparait au meme endroit".
##
## D'ou cette coque, testee EN DERNIER et pas comme les autres : les solides
## repoussent l'objet DEHORS, la coque le retient DEDANS. Une contrainte qui
## borne, pas un recouvrement a detecter — elle ne peut donc pas fuir, quels que
## soient la vitesse, le pas de temps ou l'angle. Ajouter du mobilier ne la
## rouvre pas.
##
## Ses faces sont celles du mobilier qui les borde, au millimetre : dessus du
## plancher (0,35), dessous du pavillon (1,30), faces internes des portieres
## (0,76), du tablier (-0,92) et du fond de coffre (1,43). Un objet arrete par
## la coque s'arrete donc exactement la ou la geometrie visible l'arreterait,
## et le joueur ne voit pas la difference : il voit le plancher.
##
## Le pare-brise est INCLINE : il reste fait de marches dans `solids`, qui
## renvoient l'objet selon la bonne pente. La coque n'est la que derriere elles,
## au plan du tablier, pour le cas ou un lancer rapide passerait entre deux.
## LE PLANCHER DE LA COQUE EST PASSE DE 0,35 A 0,33, ni plus ni moins, et les
## deux bornes ont ete essayees.
##
## Le plancher MODELISE est a 0,33. A 0,35, la coque passait 2 cm AU-DESSUS de
## lui : c'est elle qui arretait les objets, et ils flottaient — le releve
## n'avait plus voix au chapitre puisque, de deux planchers en desaccord, c'est
## le plus haut qui gagne.
##
## A 0,30, en revanche, elle passe DESSOUS, et c'est pire. Le maillage ne couvre
## pas tout : dans les coins arriere il n'y a pas de sol du tout, et la coque y
## est le seul plancher. Les objets y descendaient alors 3 cm sous le plan du
## plancher, c'est-a-dire DANS la tole qui le borde. Mesure : 92 % des lancers
## finissaient dans BODY_Floor, contre 28 % avant qu'on y touche.
##
## A 0,33 les deux sont d'accord au millimetre : la ou il y a du sol, le releve
## pose l'objet dessus et la coque ne dit rien ; la ou il n'y en a pas, la coque
## le pose au niveau du sol voisin. Un filet ne doit ni depasser ni manquer.
##
## SES FLANCS SE SONT RESSERRES DE 0,76 A 0,72, POUR LA MEME RAISON.
##
## Au droit du bas de caisse, le plancher modelise s'arrete a x 0,71 et le bas de
## caisse forme une levre a y 0,43 : entre les deux il y a un VIDE, que le modele
## ne remplit pas. Une coque a 0,76 y laissait entrer les objets — poussee par
## l'inertie d'un virage, une canette glissait sous la levre et s'y arretait, le
## coin superieur dans la tole. Mesure : 124 canettes sur 900 dans DOOR_R_Sill,
## a x 0,727, qui est exactement l'ancienne borne moins la demi-largeur.
##
## La regle est la meme que pour le plancher : la coque ne doit jamais etre plus
## LARGE que la garniture dont elle tient lieu, sinon elle ouvre un logement dans
## ce qui a l'air plein. Au niveau du bas de caisse, la garniture la plus etroite
## est a 0,71 ; a 0,72 la coque passe juste derriere elle, et au-dessus c'est de
## toute facon la contre-porte relevee (0,70) qui arrete, pas la coque.
const HULL_MIN := Vector3(-0.72, 0.33, -0.92)
const HULL_MAX := Vector3(0.72, 1.30, 1.43)

## Pivots exposes a driver.gd.
var wheel_tilt: Node3D            # STR_Root, deja incline de 68 degres
var wheel_spin: Node3D            # cree ici, tourne avec le braquage
var shift_pivot: Node3D
var brake_pivot: Node3D
## Pivots des aiguilles, au moyeu de chaque cadran ; voir set_gauges().
var speedo_needle: Node3D
var tacho_needle: Node3D
## Plafonnier (dome_light.gd), expose a interaction.gd comme objet utilisable.
var dome_light: Node3D
## Le berceau du telephone (voir _build_phone_dock et phone_dock_pose).
var phone_dock: Node3D
## Son reflet dans le pare-brise (windshield_glare.gd) : la contrepartie de
## l'avoir allume. Null si le .glb n'a pas de plafonnier.
var glare: Node3D
## Retroviseurs (mirror.gd) : voir aim_mirrors().
var mirrors: Array = []
## Ceux qu'on peut regler a la souris, exposes a interaction.gd.
var adjustables: Array[Node3D] = []
## Pare-soleil (visor.gd), exposes a interaction.gd comme objets utilisables.
var visors: Array[Node3D] = []
## Vitres de portiere (window.gd), manoeuvrees a la manivelle.
var windows: Array[Node3D] = []
## Charnieres de portiere : "L"/"R" -> pivot. Voir _build_doors().
var _doors := {}
## Cle de contact (ignition.gd). Null si le .glb ne la porte pas.
var ignition: Node3D
## Reperes de prehension, en local de leur pivot, releves sur le modele.
var knob_local := Vector3.ZERO
var grip_local := Vector3.ZERO
## Roues de l'exterieur : [{node, side, steer}], voir set_wheels().
var _wheels: Array = []

var _plastic: ShaderMaterial
var _paint: ShaderMaterial
var _chrome: ShaderMaterial
var _rubber: ShaderMaterial
var _lamp: ShaderMaterial
var _lamp_red: ShaderMaterial


func _ready() -> void:
	_build_materials()
	_build_interior()
	_load_shape()         # la geometrie de collision, relevee sur le .glb
	_build_exterior()
	_build_windows()      # apres l'exterieur : la glace exterieure en fait partie
	_build_doors()        # apres les vitres : la charniere emporte leurs pivots
	_build_shell()        # apres les vitres : les glaces en donnent les cotes
	_build_mirrors()
	_build_ignition()
	_build_phone_dock()   # le berceau du telephone, sur la console
	_build_vents()        # apres l'interieur : les grilles y sont relevees
	_spawn_centipede()    # en dernier : il lui faut la forme ET les bouches


## Articule les deux vitres de portiere et leur manivelle.
##
## Une Civic de 1990 n'a pas de leve-vitres electriques : c'est la manivelle
## qu'on manipule, et la vitre suit. Deux pivots par portiere :
##
##   - LA MANIVELLE — au moyeu (DOOR_*_CrankHub), axe X. On n'y accroche que le
##     bras et le bouton : le moyeu est la rosace, elle est vissee a la
##     contre-porte et ne tourne pas.
##   - LES VITRES — un pivot sans rotation qu'on descend simplement en Y. Il en
##     porte DEUX : le modele d'habitacle et celui de carrosserie ont chacun leur
##     glace, a 12 mm l'une de l'autre. N'en bouger qu'une laisserait l'autre en
##     l'air, bien visible de l'exterieur.
##
## Le pivot evite d'avoir a se soucier du repere d'origine des pieces : les
## portieres du .glb pendent sous un DOOR_*_Root tourne de 90/90 degres, ou "vers
## le bas" n'est pas Y du tout. Reparentees sous un pivot sans rotation, elles
## retrouvent les axes de la voiture.
func _build_windows() -> void:
	for spec in WINDOWS:
		var hub := find_child(spec["hub"], true, false) as MeshInstance3D
		var knob := find_child(spec["knob"], true, false) as MeshInstance3D
		if hub == null or knob == null:
			push_warning("%s introuvable : vitre fixe" % spec["hub"])
			continue
		var hub_c: Vector3 = (_relative_to(hub, self) * hub.mesh.get_aabb()).get_center()
		var knob_c: Vector3 = (_relative_to(knob, self) * knob.mesh.get_aabb()).get_center()

		var crank := _make_pivot(self, Transform3D(Basis(), hub_c), spec["moving"], self)
		crank.name = "Crank%s" % spec["side"]
		var panes := _make_pivot(self, Transform3D(), spec["panes"], self)
		panes.name = "Panes%s" % spec["side"]

		var win: Node3D = WindowScript.new()
		win.name = "Window%s" % spec["side"]
		crank.add_child(win)
		win.setup(crank, panes, knob_c, signf(hub_c.x), knob)
		# Cotes de la glace VITRE REMONTEE, en espace voiture : c'est le seul
		# instant ou elles se lisent sans avoir a defaire la course en cours.
		# centipede.gd s'en sert pour savoir ou s'ouvre le jour au-dessus d'elle
		# — la hauteur du bord superieur en est deduite, pas ecrite quelque part.
		var pane := find_child(spec["panes"][0], true, false) as MeshInstance3D
		if pane != null and pane.mesh != null:
			win.glass_box = _relative_to(pane, self) * pane.mesh.get_aabb()
		windows.append(win)


## Les PORTIERES peuvent s'ouvrir. Personne dans le jeu ne les ouvre — sauf
## l'etrangleur (strangler.gd), et c'est pour lui qu'elles existent.
##
## Une charniere par porte : un pivot vertical au bord AVANT du panneau
## (z -0,66, la cote DOOR_Y_FRONT de civic_dims.py), sous lequel passent
## toutes les pieces montees sur la porte — garniture, poignees, manivelle,
## haut-parleur, ET les deux pivots que _build_windows vient de creer
## (Crank* et Panes*, qui portent bras de manivelle et glaces). Les vitres
## continuent donc de se manoeuvrer porte ouverte : leur pivot descend en Y
## local, la charniere tourne au-dessus, les deux mouvements se composent.
##
## Ce qui NE tourne PAS : le panneau exterieur de la porte, qui est fondu dans
## le flanc de la caisse (un seul maillage, EXT_Side*), et le retroviseur.
## De nuit, vu du siege, la porte EST sa garniture et sa vitre : c'est elles
## qu'on voit s'ecarter, et le flanc reste dans le noir. Le jour ou la
## carrosserie decoupera ses portes, il suffira d'ajouter leurs noms ici.
##
## Le KickPanel n'y est pas non plus : malgre son nom DOOR_*, c'est l'habillage
## du passage de roue, visse a la caisse devant la porte.
const DOOR_PARTS := {
	"L": ["DOOR_L_Card", "DOOR_L_Cloth", "DOOR_L_HandleRecess", "DOOR_L_Handle",
		"DOOR_L_CrankHub", "DOOR_L_PullRecess", "DOOR_L_Speaker",
		"DOOR_L_SpeakerRing", "DOOR_L_SpeakerGrille0", "DOOR_L_SpeakerGrille1",
		"DOOR_L_SpeakerGrille2", "DOOR_L_LockKnob", "DOOR_L_BeltTrim",
		"DOOR_L_Sill", "DOOR_L_Skin", "CrankL", "PanesL",
		"EXT_DoorHandle_L", "EXT_DoorLock_L", "EXT_DoorWinSeal_L"],
	"R": ["DOOR_R_Card", "DOOR_R_Cloth", "DOOR_R_HandleRecess", "DOOR_R_Handle",
		"DOOR_R_CrankHub", "DOOR_R_PullRecess", "DOOR_R_Speaker",
		"DOOR_R_SpeakerRing", "DOOR_R_SpeakerGrille0", "DOOR_R_SpeakerGrille1",
		"DOOR_R_SpeakerGrille2", "DOOR_R_LockKnob", "DOOR_R_BeltTrim",
		"DOOR_R_Sill", "DOOR_R_Skin", "CrankR", "PanesR",
		"EXT_DoorHandle_R", "EXT_DoorLock_R", "EXT_DoorWinSeal_R"],
}


func _build_doors() -> void:
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var hinge := Vector3(sx * 0.80, 0.72, -0.66)
		var pivot := _make_pivot(self, Transform3D(Basis(), hinge),
			DOOR_PARTS[side], self)
		pivot.name = "Door%s" % side
		_doors[side] = pivot


## Ouvre une portiere. `angle` en radians, 0 fermee ; le SIGNE de la rotation
## est deduit du cote — les deux portes s'ouvrent vers l'exterieur, et la
## charniere est a l'avant, donc le bord arriere s'ecarte de la caisse.
func set_door(side: String, angle: float) -> void:
	if not _doors.has(side):
		return
	var sx := -1.0 if side == "L" else 1.0
	(_doors[side] as Node3D).rotation.y = sx * angle


## Ouverture courante, en radians. Sert au son de l'habitacle et aux bancs.
func door_amount(side: String) -> float:
	if not _doors.has(side):
		return 0.0
	return absf((_doors[side] as Node3D).rotation.y)


## Articule la cle de contact autour de l'axe de son barillet.
##
## Le .glb porte deja les trois pieces : STR_Ignition (le barillet, chrome, visse
## a la colonne — il ne tourne pas), STR_Key (le panneton) et STR_KeyHead (la
## tete de plastique, celle qu'on vise et qu'on attrape). Seules les deux
## dernieres passent sous le pivot.
##
## L'AXE N'EST PAS DEVINE, il est relevé : c'est la droite qui joint le centre du
## barillet a celui de la tete, c'est-a-dire la cle elle-meme. Lire l'axe long de
## l'AABB du barillet ne marcherait pas — il fait 20 mm de long pour 24 de
## diametre, sa boite est donc plus large que profonde et designerait le mauvais
## axe.
##
## Son SENS compte, et il est choisi pour pointer vers le conducteur : c'est ce
## qui donne un sens a "horaire" dans ignition.gd, quelle que soit l'orientation
## du modele.
func _build_ignition() -> void:
	var barrel := find_child("STR_Ignition", true, false) as MeshInstance3D
	var head := find_child("STR_KeyHead", true, false) as MeshInstance3D
	if barrel == null or head == null:
		push_warning("STR_Ignition ou STR_KeyHead introuvable : pas de cle de contact")
		return

	var barrel_c: Vector3 = (_relative_to(barrel, self) * barrel.mesh.get_aabb()).get_center()
	var head_c: Vector3 = (_relative_to(head, self) * head.mesh.get_aabb()).get_center()
	var axis := head_c - barrel_c
	if axis.length() < 0.001:
		push_warning("cle et barillet confondus : pas de cle de contact")
		return
	axis = axis.normalized()
	# Vers le conducteur. EYE_REF n'a pas besoin d'etre exact : seul le SIGNE du
	# produit scalaire compte, et l'oeil est a un demi-metre de la colonne.
	if axis.dot(EYE_REF - barrel_c) < 0.0:
		axis = -axis

	var pivot := _make_pivot(self, Transform3D(Basis(), barrel_c),
		["STR_Key", "STR_KeyHead"], self)
	pivot.name = "IgnitionPivot"

	var key: Node3D = IgnitionScript.new()
	key.name = "Ignition"
	pivot.add_child(key)
	key.setup(pivot, head, head_c, axis)
	ignition = key


## Articule les deux pare-soleil autour de leur tige.
##
## Le .glb les modelise inclines de 34,3 degres sous l'horizontale, epousant la
## pente du ciel de toit. La tige (BODY_VisorRod_*) donne l'axe : horizontale, le
## long de X. Le pivot se pose dessus, en (y, z) ; sa position en X n'a aucun
## effet sur une rotation autour de X, mais on le met au milieu du panneau, c'est
## plus lisible dans l'arbre.
##
## Seul le PANNEAU bascule. Le clip qui le retient range et le support sont
## visses au pavillon ; la tige est sur l'axe, la faire tourner ne se verrait pas.
func _build_visors(interior: Node) -> void:
	for name in VISORS:
		var panel := interior.find_child(name, true, false) as MeshInstance3D
		var rod := interior.find_child(VISORS[name], true, false) as MeshInstance3D
		if panel == null or rod == null:
			push_warning("%s ou sa tige introuvable : pare-soleil fixe" % name)
			continue

		var rod_box: AABB = _relative_to(rod, self) * rod.mesh.get_aabb()
		var panel_box: AABB = _relative_to(panel, self) * panel.mesh.get_aabb()
		var centre: Vector3 = panel_box.position + panel_box.size * 0.5
		var axis := Vector3(centre.x,
			rod_box.position.y + rod_box.size.y * 0.5,
			rod_box.position.z + rod_box.size.z * 0.5)

		var pivot := _make_pivot(self, Transform3D(Basis(), axis), [name], self)
		pivot.name = "VisorPivot" + name.right(1)

		var visor: Node3D = VisorScript.new()
		visor.name = "Visor" + name.right(1)
		pivot.add_child(visor)
		visor.setup(pivot, panel, centre)
		visors.append(visor)


# --------------------------------------------------------------------------
# Retroviseurs
# --------------------------------------------------------------------------

## Remplace les trois glaces peintes du modele par de vrais miroirs plans.
##
## Chaque glace du .glb donne tout ce qu'il faut : sa transform donne le repere
## (X droite, Y haut, Z normale) et l'AABB LOCALE donne les cotes du panneau.
## Prendre l'AABB monde serait faux — les glaces de portiere sont inclinees de
## 8 degres vers le conducteur, et une boite englobante inclinee est plus large
## que le panneau qu'elle contient.
func _build_mirrors() -> void:
	for name in MIRROR_GLASS:
		var glass := find_child(name, true, false) as MeshInstance3D
		if glass == null:
			push_warning("%s introuvable : ce retroviseur restera peint" % name)
			continue

		var box: AABB = glass.mesh.get_aabb()
		# Origine au CENTRE du panneau, pas a l'origine du mesh, et sortie sur la
		# face avant de la glace (l'epaisseur est en Z local).
		var centre: Vector3 = box.position + box.size * 0.5 \
			+ Vector3(0.0, 0.0, box.size.z * 0.5)
		var head := _swivel(name, _face(glass, centre))
		# On RELIT la glace apres reglage : elle a suivi le pivot. Recomposer sa
		# pose a la main marche aussi, mais c'est deux inversions de base de plus
		# a ne pas se tromper.
		var at := _face(glass, centre)

		var mirror: Node3D = MirrorScript.new()
		mirror.name = "Mirror" + name.trim_prefix("BODY_").trim_prefix("EXT_")
		if head == null:
			add_child(mirror)
			mirror.transform = at
		else:
			# ENFANT du pivot : regler le retroviseur doit emmener le boitier, la
			# glace et la camera virtuelle d'un bloc. Si le quad restait accroche
			# a la cabine, tourner la tete decalerait l'image du cadre.
			head.add_child(mirror)
			mirror.transform = head.transform.affine_inverse() * at
			mirror.adjustable(head)
			adjustables.append(mirror)
		mirror.build(Vector2(box.size.x, box.size.y))
		mirrors.append(mirror)

		# La glace d'origine ne sert plus a rien et ferait un fond sombre visible
		# sur les bords si le quad ne la couvrait pas exactement.
		glass.visible = false


## Regle un retroviseur, exactement comme on le ferait a la main.
##
## Le .glb monte la glace interieure A PLAT, normale plein arriere. Or un miroir
## renvoie l'image SYMETRIQUE du regard par rapport a sa normale : vu de la place
## du conducteur, 33 cm a gauche, une glace plate montre donc l'arriere-DROITE,
## et pas du tout ce qui suit la voiture. C'est pour ca qu'on oriente son
## retroviseur en montant dans une voiture.
##
## La normale a viser est la BISSECTRICE entre "vers l'oeil" et "vers ce qu'on
## veut voir". Ici ca fait pivoter la tete du retroviseur de 13 degres vers le
## conducteur. Les glaces de portiere, elles, sont deja orientees dans le modele
## (8 degres) et n'ont rien a corriger.
##
## On fait tourner le BOITIER avec la glace : ne bouger que la surface reflechie
## laisserait une glace de travers dans son cadre.
## Pose de la face reflechissante d'une glace, en espace voiture : sa base
## orthonormee (X droite, Y haut, Z normale) et son centre.
func _face(glass: Node3D, centre_local: Vector3) -> Transform3D:
	var t := _relative_to(glass, self)
	return Transform3D(t.basis.orthonormalized(), t * centre_local)


## Renvoie le pivot cree, ou `null` si la glace n'est pas reglable.
func _swivel(glass_name: String, at: Transform3D) -> Node3D:
	if not MIRROR_AIM.has(glass_name):
		return null
	var to_eye := (EYE_REF - at.origin).normalized()
	var want: Vector3 = (MIRROR_AIM[glass_name] as Vector3).normalized()
	var n := (to_eye + want).normalized()
	var r := Vector3.UP.cross(n).normalized()
	var aimed := Basis(r, n.cross(r), n)

	var head := _make_pivot(self, Transform3D(Basis(), at.origin),
		MIRROR_HEAD[glass_name], self)
	head.name = "MirrorHead"
	head.basis = aimed * at.basis.inverse()
	return head


## A appeler chaque image avec la position MONDE de l'oeil du joueur.
##
## Le reflet du pare-brise en fait partie : c'est une glace comme les autres,
## simplement tres grande, tres inclinee, et qu'on regarde AU TRAVERS. Sa camera
## se cale sur l'oeil exactement de la meme facon, et pour la meme raison — une
## image figee trahirait le truquage au premier mouvement de tete.
func aim_mirrors(eye: Vector3) -> void:
	for m in mirrors:
		m.aim(eye)
	if glare != null:
		glare.aim(eye)


# --------------------------------------------------------------------------
# Objets et surfaces de depose
# --------------------------------------------------------------------------

## Charge la forme relevee sur le .glb (assets/cabin_shape.res).
##
## PAS DE CORPS PHYSIQUE, et c'est inchange : la forme est interrogee
## analytiquement, en espace voiture, ou la camera, les objets et la tole sont
## immobiles les uns par rapport aux autres. Un corps statique accroche a une
## caisse qui roule ne transmet sa position au serveur physique qu'au pas
## suivant, et a 24 m/s le rayon tombe 40 cm a cote — c'etait "je ne peux pas
## saisir le paquet en roulant".
##
## Ce qui change est ce qu'on interroge : la tole elle-meme, au lieu de vingt-
## trois boites saisies a la main qui ne lui correspondaient pas.
func _load_shape() -> void:
	if not ResourceLoader.exists(SHAPE_PATH):
		push_error(("%s manquant : l'habitacle n'a pas de collision.\n" +
			"  Le cuire avec :  godot --headless --path . --script res://tools/bake_cabin.gd")
			% SHAPE_PATH)
		return
	shape = load(SHAPE_PATH)
	if shape == null or shape.nx <= 0:
		push_error("%s illisible ou vide : l'habitacle n'a pas de collision" % SHAPE_PATH)
		shape = null


## LE HAUT DE CAISSE, qui est en verre et n'est donc pas dans le releve.
##
## Le pare-brise est INCLINE — bas de baie a (COWL_Y, COWL_Z), haut de baie a
## (HEADER_Y, HEADER_Z) — et la pente n'est pas saisie, elle est DEDUITE de ces
## deux lignes, exactement comme le reflet du pare-brise (_build_glare). Bouger
## COWL/HEADER emmene les marches avec.
##
## Les marches font 6 cm et non plus 10 : elles servent maintenant aussi de
## chemin au mille-pattes, dont le corps fait 27 cm — six marches, il drape
## dessus sans qu'on les lise. Rien d'autre ne les voit, elles ne coutent rien.
func _build_shell() -> void:
	var steps := 6
	var y0 := COWL_Y
	var slope := (HEADER_Z - COWL_Z) / (HEADER_Y - COWL_Y)
	var h := (HEADER_Y - y0) / float(steps)
	for i in steps:
		var y := y0 + h * (float(i) + 0.5)
		var z := COWL_Z + (y - COWL_Y) * slope
		_shell(Vector3(1.52, h, 0.04), Vector3(0.0, y, z - 0.02))

	# La lunette arriere, et les glaces laterales AU-DESSUS DE LA CEINTURE : en
	# dessous c'est la garniture de portiere, et celle-la est dans le releve, a
	# sa vraie place (0,70) et non a celle de la tole (0,79) ou l'ancienne boite
	# l'avait mise. C'est la que les objets s'enfoncaient.
	_shell(Vector3(1.52, 0.10, 0.37), Vector3(0.0, 1.25, 1.245))
	for w in windows:
		var g: AABB = w.glass_box
		if g.size == Vector3.ZERO:
			continue
		# La glace remontee, epaissie vers l'exterieur : un objet s'y arrete a la
		# vitre, pas dans la portiere.
		var x: float = g.get_center().x
		_shell(Vector3(0.06, g.size.y + 0.06, g.size.z),
			Vector3(x + signf(x) * 0.02, BELT_Y + g.size.y * 0.5, g.get_center().z))


## Une boite du haut de caisse, en ESPACE VOITURE.
func _shell(size: Vector3, pos: Vector3) -> void:
	shell.append({"min": pos - size * 0.5, "max": pos + size * 0.5})


## LES ANCIENNES BOITES, gardees pour memoire et pour rien d'autre.
##
## Elles ne sont plus appelees par le jeu — `_ready()` ne les construit pas.
## tools/probe_surfaces.gd et tools/probe_collisions.gd les demandent encore,
## pour montrer chiffres a l'appui l'ecart entre ce qui etait DECLARE et ce qui
## est MODELISE : c'est cet ecart qui a motive le releve, et un avant/apres
## qu'on efface est un avant/apres qu'on ne peut plus refaire.
var surfaces: Array = []
var solids: Array = []


func _build_surfaces() -> void:
	surfaces.clear()
	solids.clear()
	# Les boites sont EPAISSES vers le bas. Elles sont invisibles, et une dalle
	# de 2 cm se fait traverser : un objet qui tombe parcourt 6 cm par image.
	_surface(Vector3(0.48, 0.30, 0.50), Vector3(0.33, 0.344, 0.24))     # assise passager
	_surface(Vector3(0.48, 0.30, 0.50), Vector3(-0.33, 0.344, 0.24))    # assise conducteur
	_surface(Vector3(1.28, 0.30, 0.44), Vector3(0.0, 0.338, 1.02))      # banquette arriere
	# La console EST son propre obstacle : une seule boite, pas un dessus pose
	# sur un caisson, sinon les deux se chevauchent et ejectent ce qui traine.
	_surface(Vector3(0.26, 0.28, 0.84), Vector3(0.0, 0.460, -0.24))     # console
	# Planche de bord en morceaux JOINTIFS, pas superposes : la casquette pleine
	# largeur au ras du pare-brise, puis la partie profonde cote passager. Cote
	# conducteur cette derniere est occupee par le bloc compteurs, d'ou l'absence
	# de boite.
	#
	# Les cotes sont RELEVEES SUR LE MAILLAGE (tools/probe_surfaces.gd), pas
	# estimees : un seul plan a 0,955 sur toute la planche faisait flotter ce
	# qu'on y posait de 8 a 22 mm sur la casquette, et de 35 mm sur la partie
	# passager. Un objet qui levite au-dessus de la tole se voit tout de suite.
	#
	# La casquette est GALBEE : elle sort a 0,933 au ras du pare-brise et monte a
	# 0,947 en arriere, sur le capot des compteurs. Deux bandes la suivent, la
	# seconde calee sur le point HAUT de ce qu'elle couvre — un plan sous le
	# maillage enfoncerait l'objet dans la tole, ce qui est pire que le flottement
	# qu'on corrige.
	# Chaque bande est calee sur les grilles de degivrage, qui DEPASSENT de la
	# tole : les ignorer parce qu'elles sont petites (21 et 3 triangles) mettait
	# le plan 5 mm sous elles, et un objet pose la s'enfoncait dans la grille.
	_surface(Vector3(1.40, 0.20, 0.14), Vector3(0.0, 0.845, -0.85))     # casquette, avant
	_surface(Vector3(1.40, 0.20, 0.08), Vector3(0.0, 0.850, -0.74))     # casquette, arriere
	# La planche passager s'arrete a z -0.57 : au-dela c'est le vide au-dessus de
	# la boite a gants, et la boite s'y etendait de 6 cm. Elle s'arrete aussi a
	# x 0.70 — a 0.75 son emprise mordait sur le montant A, qui monte a 1,09 et
	# tirait la couverture de la sonde a 73 %.
	#
	# Elle plonge vers l'arriere (0,944 au ras de la casquette, 0,915 au bord),
	# d'ou deux bandes ici aussi : un plan unique faisait flotter de 29 mm ce
	# qu'on posait au bord, la ou la tole redescend vers la boite a gants.
	_surface(Vector3(0.65, 0.20, 0.065), Vector3(0.375, 0.844, -0.6675))  # planche pass., avant
	_surface(Vector3(0.65, 0.20, 0.065), Vector3(0.375, 0.830, -0.6025))  # planche pass., arriere
	# Plancher en deux morceaux, de part et d'autre du tunnel de console, et sur
	# TOUTE la longueur de l'habitacle : arrete aux pieds, un objet qui glisse
	# vers l'arriere tombait dans le vide.
	_surface(Vector3(0.50, 0.24, 2.10), Vector3(-0.40, 0.23, 0.30))     # plancher G
	_surface(Vector3(0.50, 0.24, 2.10), Vector3(0.40, 0.23, 0.30))      # plancher D


## De quoi retenir les objets dans l'habitacle. Sans ces parois, le paquet
## glisse hors du siege au premier virage et traverse la caisse.
##
## Aucune boite ne doit en CHEVAUCHER une autre : un objet coince dans une
## intersection se fait ejecter violemment.
func _build_walls() -> void:
	_solid(Vector3(0.06, 0.60, 3.00), Vector3(-0.79, 0.70, 0.20))    # portiere G
	_solid(Vector3(0.06, 0.60, 3.00), Vector3(0.79, 0.70, 0.20))     # portiere D
	_solid(Vector3(1.60, 0.60, 0.06), Vector3(0.0, 0.70, -0.95))     # tablier
	_solid(Vector3(1.60, 0.80, 0.06), Vector3(0.0, 0.80, 1.46))      # fond de coffre
	for x in [SEAT_X, -SEAT_X]:
		_solid(Vector3(0.48, 0.55, 0.10), Vector3(x, 0.72, 0.58))    # dossiers

	# Au-dessus de la ceinture de caisse, l'habitacle etait OUVERT. Tant que les
	# objets ne faisaient que tomber et glisser, personne n'y montait jamais.
	#
	# Un objet LANCE, si (interaction.gd, clic molette) : jete vers le haut du
	# pare-brise il passait par-dessus le tablier, sortait de la caisse, et le
	# filet de securite de prop.gd le ramenait sur le siege. Une canette qui
	# disparait dans la vitre et reapparait sur vos genoux.
	#
	# Le pare-brise est INCLINE — bas de caisse a (0.93, -0.92), haut de baie a
	# (1.28, -0.34). Trois marches de 10 cm le ferment au centimetre pres, ce
	# qui est plus fin que le rebond qu'on y voit.
	_solid(Vector3(1.52, 0.10, 0.06), Vector3(0.0, 1.05, -0.72))     # pare-brise, bas
	_solid(Vector3(1.52, 0.10, 0.06), Vector3(0.0, 1.15, -0.56))     # pare-brise, milieu
	_solid(Vector3(1.52, 0.10, 0.06), Vector3(0.0, 1.25, -0.39))     # pare-brise, haut
	# Le pavillon deborde vers l'avant au-dessus du pare-brise : la ou il n'y a
	# plus de caisse, il n'y a plus rien a heurter non plus, et un objet monte
	# tout droit s'echapperait par la derniere marche.
	_solid(Vector3(1.52, 0.06, 1.86), Vector3(0.0, 1.33, 0.13))      # pavillon
	_solid(Vector3(1.52, 0.10, 0.37), Vector3(0.0, 1.25, 1.245))     # lunette arriere
	for x in [-0.79, 0.79]:
		_solid(Vector3(0.06, 0.30, 3.00), Vector3(x, 1.15, 0.20))    # glaces laterales


## Une surface horizontale : on en garde le dessus pour la visee analytique, et
## on lui donne un corps pour que les objets s'y posent vraiment.
func _surface(size: Vector3, pos: Vector3) -> void:
	surfaces.append({
		"y": pos.y + size.y * 0.5,
		"min": Vector2(pos.x - size.x * 0.5, pos.z - size.z * 0.5),
		"max": Vector2(pos.x + size.x * 0.5, pos.z + size.z * 0.5),
	})
	_solid(size, pos)


# --------------------------------------------------------------------------
# Bouches d'aeration
# --------------------------------------------------------------------------

## Releve les grilles nommees dans VENT_MOUTHS et en deduit par ou une bestiole
## en sort. Rien n'est saisi a la main : ni la position, ni la direction.
##
## L'AXE vient de la boite englobante. Une grille est un objet PLAT — 6 mm
## d'epaisseur pour 1,10 m de large sur le degivrage — donc son axe le plus
## MINCE est celui du flux d'air, et c'est par la qu'on passe. Le dire ainsi
## couvre les trois orientations du jeu sans les enumerer : les aerateurs de
## face soufflent vers l'arriere (z), le degivrage vers le haut (y), les
## haut-parleurs de portiere vers l'interieur (x).
##
## LE SENS, lui, pointe vers l'oeil du conducteur, parce que c'est a quoi sert
## une bouche d'aeration : elle souffle sur les occupants. Seul le SIGNE du
## produit scalaire compte, EYE_REF n'a donc pas besoin d'etre exact — meme
## argument que l'axe de la cle de contact, et il tombe juste sur les huit.
##
## Viser le centre de l'habitacle, lui, ne marcherait pas : il est PLUS BAS que
## le degivrage, qui se retrouverait a souffler dans le tableau de bord.
func _build_vents() -> void:
	for name in VENT_MOUTHS:
		var mesh := find_child(name, true, false) as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			push_warning("%s introuvable : une entree de moins" % name)
			continue
		var box: AABB = _relative_to(mesh, self) * mesh.mesh.get_aabb()
		var s := box.size
		var a := 0
		if s.y <= s.x and s.y <= s.z:
			a = 1
		elif s.z <= s.x and s.z <= s.y:
			a = 2

		var dir := Vector3.ZERO
		dir[a] = 1.0
		if dir.dot(EYE_REF - box.get_center()) < 0.0:
			dir = -dir

		# L'etendue de la FENTE, epaisseur retiree : de quoi sortir n'importe ou
		# le long du degivrage plutot que toujours en son milieu.
		var span := s * 0.5
		span[a] = 0.0

		vents.append({
			"label": VENT_MOUTHS[name],
			"pos": box.get_center() + dir * (s[a] * 0.5 + 0.002),
			"dir": dir,
			"span": span,
		})


## Le mille-pattes est enfant de l'HABITACLE, pas de la voiture, et ce n'est pas
## qu'une place dans l'arbre : il marche sur les boites d'ici, il entre par les
## bouches d'ici, et il n'a rien a demander a car.gd — sauf `frame_accel`, pour
## savoir quand se cramponner.
func _spawn_centipede() -> void:
	centipede = CentipedeScript.new()
	centipede.name = "Centipede"
	centipede.cabin = self
	var p := get_parent()
	if p != null and "frame_accel" in p:
		centipede.carrier = p
	add_child(centipede)


## Boite pleine, en ESPACE VOITURE. Aucun corps physique : cig_pack.gd resout
## lui-meme ses collisions contre ces boites, dans le repere de la voiture.
##
## C'est la seule facon d'avoir des objets stables dans une caisse qui roule :
## un collider enfant d'un CharacterBody3D se teleporte de 0,8 m par image a
## 170 km/h, le solveur y lit une penetration enorme et ejecte l'objet.
func _solid(size: Vector3, pos: Vector3) -> void:
	solids.append({
		"min": pos - size * 0.5,
		"max": pos + size * 0.5,
	})


# --------------------------------------------------------------------------
# Interieur (modele Blender)
# --------------------------------------------------------------------------

func _build_interior() -> void:
	var interior := INTERIOR.instantiate()
	interior.name = "Interior"
	if interior is Node3D:
		(interior as Node3D).transform = Transform3D()
	add_child(interior)

	# Le modele ne se voit que de l'interieur : il ne doit pas projeter d'ombre
	# sur la route, sinon les phares dessinent la caisse par terre.
	_no_shadows(interior)
	_dim(interior, INTERIOR_DIM, {})

	# PAS de rattrapage sur les pare-soleil. Il y en avait un (+0.075) du temps ou
	# le modele les posait a 1.18 m, rabattus en travers du pare-brise. Le .glb a
	# ete refait depuis — ils sont ranges d'origine, panneau a 1.163-1.237 contre
	# un ciel de toit qui commence a 1.234 — et le decalage les enfoncait dedans :
	# invisibles, tiges et supports passes au-dessus, hors de la caisse.
	# C'etait la reponse a "pourquoi je ne vois pas les pare-soleil ?".
	_build_visors(interior)

	# Plafonnier : la lentille du modele recoit son ampoule et sa bascule, voir
	# dome_light.gd. Sa position est lue dans le .glb, en espace voiture (le
	# modele est a la transform identite).
	var lens := interior.find_child("BODY_DomeLens", true, false) as MeshInstance3D
	if lens == null:
		push_warning("BODY_DomeLens introuvable dans le .glb : pas de plafonnier")
	else:
		dome_light = DomeLight.new()
		dome_light.name = "DomeLight"
		add_child(dome_light)
		dome_light.setup(lens, _relative_to(lens, interior).origin)
		# Et sa contrepartie : ce qu'il met dans le pare-brise.
		_build_glare()

	# Aiguilles des compteurs : un pivot au moyeu de chacune, que car.gd
	# oriente a chaque image avec set_gauges().
	var cluster := interior.find_child("DASH_ClusterRoot", true, false) as Node3D
	if cluster == null:
		push_warning("DASH_ClusterRoot introuvable dans le .glb : les aiguilles resteront fixes")
	else:
		speedo_needle = _make_needle(cluster, "CLU_Speedo_Needle", interior)
		tacho_needle = _make_needle(cluster, "CLU_Tacho_Needle", interior)

	wheel_tilt = interior.find_child("STR_Root", true, false)
	if wheel_tilt == null:
		push_warning("STR_Root introuvable dans le .glb : le volant ne tournera pas")
		return

	# Le siege du .glb est un peu loin du volant : 79 cm entre la face avant du
	# dossier et l'axe de la jante, la ou une Civic en fait 60 a 65. L'avant-bras
	# vise le POIGNET du modele (5 cm avant la jante, mains a 10 h 10) : avec 58 cm
	# de bras les coudes plient a ~130 degres. On rapproche encore la colonne de
	# 2 cm ; le fourreau, lui, reste contre la
	# planche de bord, sinon on verrait le trou par lequel la colonne y entre.
	var shroud := interior.find_child("STR_Shroud", true, false) as Node3D
	var shroud_at := wheel_tilt.transform * shroud.transform if shroud != null else Transform3D()
	wheel_tilt.position.z += COLUMN_PULL
	if shroud != null:
		shroud.transform = wheel_tilt.transform.affine_inverse() * shroud_at

	wheel_spin = _make_pivot(wheel_tilt, Transform3D(), WHEEL_SPINNING, interior)

	# Levier de vitesses : pivot a la base du soufflet.
	shift_pivot = _make_pivot(interior, Transform3D(Basis(), Vector3(0.0, 0.58, -0.30)),
		SHIFT_MOVING, interior)
	var knob := interior.find_child("CON_ShiftKnob", true, false) as Node3D
	if knob != null:
		knob_local = knob.position

	# Frein a main : pivot a la base, cote arriere. Le modele est deja pose
	# levier BAISSE, donc driver.gd applique un DELTA de rotation, pas un angle
	# absolu.
	brake_pivot = _make_pivot(interior, Transform3D(Basis(), Vector3(0.0, 0.46, 0.18)),
		BRAKE_MOVING, interior)
	var button := interior.find_child("CON_BrakeButton", true, false) as Node3D
	if button != null:
		grip_local = button.position


## Le reflet de l'habitacle dans le pare-brise (windshield_glare.gd) : ce que
## coute d'allumer le plafonnier la nuit.
##
## Le plan de la vitre n'est PAS releve sur le .glb, il est DEDUIT des deux
## lignes de baie que ce fichier declare deja — le bas (COWL_Y, COWL_Z) et le
## haut (HEADER_Y, HEADER_Z), celles-la memes qui ferment le pare-brise dans
## _build_walls(). Un pare-brise est plan : ces deux lignes le definissent
## entierement, et le reflet ne peut donc pas glisser a cote de la vitre sur
## laquelle il se pose.
func _build_glare() -> void:
	var base := Vector3(0.0, COWL_Y, COWL_Z)
	var up := (Vector3(0.0, HEADER_Y, HEADER_Z) - base).normalized()
	# Normale exterieure : perpendiculaire a la pente dans le plan YZ, tournee
	# vers le haut et vers l'avant. La vitre est couchee de 59 degres sur la
	# verticale, si bien qu'on la regarde presque en rasant — et c'est de la que
	# vient l'essentiel du reflet, bien plus que de la lampe elle-meme.
	var n := Vector3(0.0, up.z, -up.y)

	glare = GlareScript.new()
	glare.name = "WindshieldGlare"
	add_child(glare)
	glare.setup(base, up, n, dome_light)


## Cree un pivot sous `parent` et y reparente les objets nommes, en conservant
## leur position dans l'espace de la voiture.
func _make_pivot(parent: Node, at: Transform3D, names: Array, search_root: Node) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	parent.add_child(pivot)
	(pivot as Node3D).transform = at
	var inv := at.affine_inverse()

	for n in names:
		var part := search_root.find_child(n, true, false) as Node3D
		if part == null:
			continue
		var world := _relative_to(part, parent)
		part.reparent(pivot, false)
		part.transform = inv * world

	return pivot


## Transform de `part` exprimee dans l'espace de son ancetre `ancestor`. Hors de
## l'arbre, global_transform ne vaut rien : on remonte la chaine a la main.
## A appeler AVANT de reparenter la piece.
func _relative_to(part: Node3D, ancestor: Node) -> Transform3D:
	var t := part.transform
	var p := part.get_parent()
	while p != null and p != ancestor and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Pivot d'aiguille. Dans le .glb, l'aiguille est une barre dont l'axe long est
## +Y local, posee a mi-longueur de son moyeu : on retrouve donc le moyeu depuis
## sa propre transform, sans rien mesurer a la main. Le pivot prend l'orientation
## de l'aiguille, si bien qu'une fois reparentee elle pointe vers +Y (12 h) ;
## il ne reste qu'a tourner le pivot autour de z pour donner l'angle de cadran.
func _make_needle(cluster: Node3D, part_name: String, search_root: Node) -> Node3D:
	var needle := search_root.find_child(part_name, true, false) as MeshInstance3D
	if needle == null:
		push_warning("%s introuvable dans le .glb : l'aiguille restera fixe" % part_name)
		return null
	var local := _relative_to(needle, cluster)
	var half := needle.get_aabb().size.y * 0.5
	var hub := local.origin - local.basis.y * half
	return _make_pivot(cluster, Transform3D(local.basis, hub), [part_name], search_root)


## Oriente les aiguilles du compteur de vitesse et du compte-tours.
func set_gauges(kmh: float, rpm: float) -> void:
	_point_needle(speedo_needle, kmh / SPEEDO_MAX_KMH)
	_point_needle(tacho_needle, rpm / TACHO_MAX_RPM)


## `t` va de 0 (butee basse, 7 h 30) a 1 (butee haute, 4 h 30). Le cadran est
## dans le plan XY du pivot, face vers +Z, c'est-a-dire vers le conducteur : une
## rotation NEGATIVE autour de z fait tourner l'aiguille dans le sens horaire.
func _point_needle(pivot: Node3D, t: float) -> void:
	if pivot == null:
		return
	var a := GAUGE_SWEEP_DEG * (clampf(t, 0.0, 1.0) - 0.5)
	pivot.rotation.z = deg_to_rad(-a)


## Rabat les albedos du modele sur la palette de nuit du jeu.
##
## Le .glb est texture clair (interieur creme) : tel quel le montant A devient
## l'objet le plus lumineux de la scene, ce qui n'a aucun sens dans une voiture
## eclairee par la seule lueur des compteurs. On multiplie les couleurs plutot
## que de tout remplacer, pour garder les ecarts de matiere du modele.
##
## `cache` evite de re-assombrir deux fois un materiau partage.
func _dim(n: Node, factor: float, cache: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(s)
				if src == null:
					continue
				if not cache.has(src):
					var copy := src.duplicate()
					if copy is BaseMaterial3D:
						var mine := copy as BaseMaterial3D
						var c: Color = mine.albedo_color
						if src.resource_name == GLASS_MATERIAL:
							# Une vitre ne se rabat pas sur la palette de nuit :
							# elle n'a pas de couleur a elle, elle laisse passer
							# celle de ce qu'il y a derriere. On lui donne donc sa
							# teinte propre au lieu d'assombrir la sienne.
							mine.albedo_color = Color(
								GLASS_TINT.r, GLASS_TINT.g, GLASS_TINT.b, GLASS_ALPHA)
							# En melange normal, Godot multiplie TOUT le rendu de la
							# surface — reflet compris — par l'alpha : une vitre
							# transparente perdait donc 96 % de ses reflets et
							# devenait terne. En alpha premultiplie le fond est
							# attenue par l'alpha mais la lumiere de la vitre s'AJOUTE
							# a pleine force. C'est ce que fait une vraie glace :
							# elle transmet presque tout et pose son reflet dessus.
							mine.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
						else:
							mine.albedo_color = Color(
								c.r * factor, c.g * factor, c.b * factor, c.a)
					cache[src] = copy
				mi.set_surface_override_material(s, cache[src])
	for c in n.get_children():
		_dim(c, factor, cache)


func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)


# --------------------------------------------------------------------------
# Exterieur (modele Blender) : caisse, vitrage, roues
# --------------------------------------------------------------------------

## Instancie civic_exterior.glb (meme repere que l'interieur : rien a recaler)
## et prepare les roues : chaque roue tourne sur son essieu, les deux avant
## braquent en plus autour d'un pivot vertical cree a leur centre.
func _build_exterior() -> void:
	var exterior := EXTERIOR.instantiate()
	exterior.name = "Exterior"
	if exterior is Node3D:
		(exterior as Node3D).transform = Transform3D()
	add_child(exterior)
	# Comme l'interieur : pas d'ombre portee, sinon la caisse bloque ses propres
	# phares et se dessine par terre.
	_no_shadows(exterior)
	_dim(exterior, EXTERIOR_DIM, {})

	for n in WHEEL_NAMES:
		var wheel := exterior.find_child(n, true, false) as Node3D
		if wheel == null:
			push_warning("%s introuvable dans civic_exterior.glb" % n)
			continue
		var side: float = WHEEL_NAMES[n][0]
		var steer_pivot: Node3D = null
		if WHEEL_NAMES[n][1]:
			var at := Transform3D(Basis(), _relative_to(wheel, exterior).origin)
			steer_pivot = _make_pivot(exterior, at, [n], exterior)
			steer_pivot.name = "Steer%s" % n.trim_prefix("EXT_Wheel_")
		_wheels.append({"node": wheel, "side": side, "steer": steer_pivot})


## Fait rouler les roues avec la vitesse et braquer les roues avant.
## `speed` en m/s (positif vers l'avant), `steer` de -1 (droite) a +1 (gauche).
func set_wheels(speed: float, steer: float, delta: float) -> void:
	var spin := speed / WHEEL_R * delta
	for w in _wheels:
		# L'axe local +Y de chaque roue pointe vers l'exterieur : meme angle, signe
		# oppose d'un cote a l'autre, pour que les deux roulent vers l'avant.
		(w["node"] as Node3D).rotate_object_local(Vector3.UP, -w["side"] * spin)
		if w["steer"] != null:
			(w["steer"] as Node3D).rotation.y = steer * deg_to_rad(WHEEL_STEER_MAX)


# --------------------------------------------------------------------------

## Materiaux de secours (primitives eventuelles) ; les modeles apportent les leurs.
func _build_materials() -> void:
	_plastic = Retro.mat(Color(0.058, 0.057, 0.062), 0.94)
	_paint = Retro.mat(Color(0.085, 0.082, 0.080), 0.45, 0.30)
	_chrome = Retro.mat(Color(0.16, 0.16, 0.17), 0.30, 0.70)
	_rubber = Retro.mat(Color(0.028, 0.028, 0.030), 0.96)
	_lamp = Retro.mat(Color(0.30, 0.30, 0.32), 0.25, 0.20)
	_lamp_red = Retro.mat(Color(0.24, 0.030, 0.022), 0.25, 0.20)


# --------------------------------------------------------------------------
# Le berceau du telephone, et l'allume-cigare qui l'alimente
# --------------------------------------------------------------------------

## Ou le telephone se pose : a l'avant de la console, sous la radio, tourne
## vers le conducteur. La ou un vrai chauffeur le colle.
const PHONE_DOCK_AT := Vector3(0.0, 0.705, -0.560)
## L'oeil du conducteur, a peu pres (car.HEAD_POS) : l'ecran au berceau le
## regarde. Une approximation suffit — c'est une inclinaison, pas une visee.
const PHONE_DOCK_EYE := Vector3(-0.33, 1.10, 0.25)


## La pose EXACTE du telephone au berceau, en espace habitacle : origine au
## centre du boitier, +Y (la vitre) vers l'oeil, le haut en haut. C'est elle
## que l'aimant de depose d'interaction.gd applique.
func phone_dock_pose() -> Transform3D:
	var n := (PHONE_DOCK_EYE - PHONE_DOCK_AT).normalized()
	var zax := -(Vector3.UP - n * Vector3.UP.dot(n)).normalized()
	var xax := n.cross(zax).normalized()
	return Transform3D(Basis(xax, n, zax).orthonormalized(), PHONE_DOCK_AT)


func _build_phone_dock() -> void:
	phone_dock = Node3D.new()
	phone_dock.name = "PhoneDock"
	add_child(phone_dock)
	var pose := phone_dock_pose()

	# Le pied : une rotule sur la console, un bras court, deux machoires.
	var base := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.016
	bcyl.bottom_radius = 0.022
	bcyl.height = 0.020
	base.mesh = bcyl
	base.material_override = _plastic
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.position = Vector3(PHONE_DOCK_AT.x, 0.622, PHONE_DOCK_AT.z + 0.020)
	phone_dock.add_child(base)

	var arm := MeshInstance3D.new()
	var acyl := CylinderMesh.new()
	acyl.top_radius = 0.006
	acyl.bottom_radius = 0.006
	acyl.height = 0.075
	arm.mesh = acyl
	arm.material_override = _plastic
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.position = base.position.lerp(PHONE_DOCK_AT, 0.55) + Vector3(0.0, 0.0, 0.006)
	arm.rotation_degrees.x = 18.0
	phone_dock.add_child(arm)

	# Les machoires : deux petites levres sous le bas du boitier, dans le
	# plan du telephone (la pose du berceau les oriente).
	for side in [-1.0, 1.0]:
		var jaw := MeshInstance3D.new()
		var jbox := BoxMesh.new()
		jbox.size = Vector3(0.012, 0.018, 0.014)
		jaw.mesh = jbox
		jaw.material_override = _plastic
		jaw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		jaw.transform = pose * Transform3D(Basis(),
			Vector3(side * 0.030, -0.011, 0.062))
		phone_dock.add_child(jaw)

	# L'allume-cigare, sous la radio : un oeillet chrome. Decoratif, mais il
	# EXPLIQUE la charge — le cable y court depuis le berceau.
	var lighter := MeshInstance3D.new()
	var lcyl := CylinderMesh.new()
	lcyl.top_radius = 0.011
	lcyl.bottom_radius = 0.011
	lcyl.height = 0.008
	lighter.mesh = lcyl
	lighter.material_override = _chrome
	lighter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lighter.position = Vector3(0.055, 0.660, -0.575)
	lighter.rotation_degrees.x = 72.0
	phone_dock.add_child(lighter)

	# Le cable : une chainette figee de l'oeillet au bas du berceau.
	var from := lighter.position + Vector3(0.0, 0.004, 0.012)
	var to := pose * Vector3(0.0, -0.012, 0.068)
	for i in 5:
		var t0 := float(i) / 5.0
		var t1 := float(i + 1) / 5.0
		var sag := Vector3(0.0, -0.014, 0.0)
		var a := from.lerp(to, t0) + sag * sin(PI * t0)
		var b := from.lerp(to, t1) + sag * sin(PI * t1)
		var seg := MeshInstance3D.new()
		var scyl := CylinderMesh.new()
		scyl.top_radius = 0.0016
		scyl.bottom_radius = 0.0016
		scyl.height = a.distance_to(b)
		seg.mesh = scyl
		seg.material_override = _rubber
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.position = (a + b) * 0.5
		var d := (b - a).normalized()
		var axis := Vector3.UP.cross(d)
		if axis.length() > 0.001:
			seg.rotate(axis.normalized(), asin(clampf(axis.length(), -1.0, 1.0)))
		phone_dock.add_child(seg)
