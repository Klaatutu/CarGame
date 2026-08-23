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
const INTERIOR := preload("res://assets/models/civic_interior.glb")
const EXTERIOR := preload("res://assets/models/civic_exterior.glb")
const CigPack := preload("res://scripts/cig_pack.gd")
const MirrorScript := preload("res://scripts/mirror.gd")
const VisorScript := preload("res://scripts/visor.gd")
const WindowScript := preload("res://scripts/window.gd")
const DomeLight := preload("res://scripts/dome_light.gd")

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

const SEAT_X := -0.33
## Facteur applique aux albedos du .glb pour les ramener dans la palette de nuit.
const INTERIOR_DIM := 0.62
const EXTERIOR_DIM := 0.85
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

## Surfaces de depose, exposees a interaction.gd (visee analytique).
var surfaces: Array = []
## Boites pleines de l'habitacle, en espace voiture (collision des objets).
var solids: Array = []

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
## Retroviseurs (mirror.gd) : voir aim_mirrors().
var mirrors: Array = []
## Ceux qu'on peut regler a la souris, exposes a interaction.gd.
var adjustables: Array[Node3D] = []
## Pare-soleil (visor.gd), exposes a interaction.gd comme objets utilisables.
var visors: Array[Node3D] = []
## Vitres de portiere (window.gd), manoeuvrees a la manivelle.
var windows: Array[Node3D] = []
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
	_build_surfaces()
	_build_walls()
	_build_exterior()
	_build_windows()      # apres l'exterieur : la glace exterieure en fait partie
	_build_mirrors()


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
		windows.append(win)


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
func aim_mirrors(eye: Vector3) -> void:
	for m in mirrors:
		m.aim(eye)


# --------------------------------------------------------------------------
# Objets et surfaces de depose
# --------------------------------------------------------------------------

## Surfaces sur lesquelles on peut reposer un objet, en ESPACE VOITURE.
##
## Pas de corps physique : elles sont declarees comme de simples boites
## horizontales et interaction.gd les teste analytiquement. Un corps statique
## accroche a une caisse qui roule ne transmet sa position au serveur physique
## qu'au pas suivant, et le rayon tombe a cote des qu'on avance.
##
## Sept boites relevees sur le modele couvrent tout ce qui est plat et
## atteignable ; generer la collision des 300 meshes du .glb serait absurde.
func _build_surfaces() -> void:
	# Les boites sont EPAISSES vers le bas. Elles sont invisibles, et une dalle
	# de 2 cm se fait traverser : un objet qui tombe parcourt 6 cm par image.
	_surface(Vector3(0.48, 0.30, 0.50), Vector3(0.33, 0.344, 0.24))     # assise passager
	_surface(Vector3(0.48, 0.30, 0.50), Vector3(-0.33, 0.344, 0.24))    # assise conducteur
	_surface(Vector3(1.28, 0.30, 0.44), Vector3(0.0, 0.338, 1.02))      # banquette arriere
	# La console EST son propre obstacle : une seule boite, pas un dessus pose
	# sur un caisson, sinon les deux se chevauchent et ejectent ce qui traine.
	_surface(Vector3(0.26, 0.28, 0.84), Vector3(0.0, 0.460, -0.24))     # console
	# Planche de bord en deux morceaux JOINTIFS, pas superposes : la casquette
	# pleine largeur au ras du pare-brise (z -0.92 a -0.70), puis la partie
	# profonde cote passager (z -0.70 a -0.50). Cote conducteur cette
	# derniere est occupee par le bloc compteurs, d'ou l'absence de boite.
	_surface(Vector3(1.45, 0.20, 0.22), Vector3(0.0, 0.855, -0.81))     # haut de planche
	_surface(Vector3(0.70, 0.20, 0.20), Vector3(0.40, 0.855, -0.60))    # planche passager
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


## Une surface horizontale : on en garde le dessus pour la visee analytique, et
## on lui donne un corps pour que les objets s'y posent vraiment.
func _surface(size: Vector3, pos: Vector3) -> void:
	surfaces.append({
		"y": pos.y + size.y * 0.5,
		"min": Vector2(pos.x - size.x * 0.5, pos.z - size.z * 0.5),
		"max": Vector2(pos.x + size.x * 0.5, pos.z + size.z * 0.5),
	})
	_solid(size, pos)


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
						var c: Color = (copy as BaseMaterial3D).albedo_color
						(copy as BaseMaterial3D).albedo_color = Color(
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
