extends Node3D
##
## Pare-soleil. Le panneau vient du modele Blender (BODY_Visor_L/R) ; ce noeud le
## fait basculer autour de sa tige et l'expose a interaction.gd comme objet
## REGLABLE, exactement comme le retroviseur interieur : on le vise, on maintient
## le clic gauche, le regard se bloque et la souris le place ou on veut.
##
## Pas une bascule a deux positions : la souris en haut/bas donne l'angle qu'on
## veut, n'importe lequel, du plafond a la verticale.
##
## UN SEUL AXE, celui de la tige. Le pivotement lateral vers la vitre a ete
## essaye puis retire.
##
## Le noeud est place au CENTRE DU PANNEAU et enfant du pivot : la visee suit
## donc le pare-soleil au lieu de rester accrochee au plafond.
##

## Course, en degres autour de la tige, relativement a la pose du .glb — lequel
## presente le panneau incline de 34,3 degres sous l'horizontale, pointant vers
## le PARE-BRISE.
##
## RANGE : le panneau pointe vers le CONDUCTEUR, sous le pavillon. C'est la
## position d'un pare-soleil au repos, et c'est celle de depart. Le ramener a
## plat dans l'autre sens (+34,3) le collait contre le pare-brise, pointe en
## avant : on n'en voyait plus que la tranche.
##
## -138,7 et pas -145,7, qui serait l'horizontale exacte : la tige est a 1,242 m
## et le ciel de toit commence a 1,234. Rigoureusement a plat, le panneau se
## retrouve donc A LA HAUTEUR de la garniture, c'est-a-dire dedans — invisible,
## le defaut meme qu'on venait de corriger. Sept degres de plongee suffisent a
## faire descendre son extremite libre 17 mm sous la garniture, et ca reste tout
## a fait "a plat" a l'oeil. Un vrai pare-soleil range n'est jamais affleurant
## non plus.
##
## DEPLOYE : -55 l'amene a 89 degres sous l'horizontale, vertical en travers du
## pare-brise.
##
## Entre les deux, 90 degres de course : exactement le geste d'un vrai
## pare-soleil, du plafond a la verticale.
@export var angle_stowed := -138.7
@export var angle_deployed := -55.0
## Course de la souris, en degres par pixel. 0.2 : environ 450 pixels pour tout
## le debattement, du meme ordre que le reglage du retroviseur.
@export var degrees_per_pixel := 0.2
## Surbrillance quand on le vise.
@export var highlight_color := Color(1.0, 0.62, 0.30)
@export var highlight_energy := 0.55

## Angle courant, en degres. 0 = la pose du modele.
var angle := angle_stowed

var _pivot: Node3D
var _grip_local := Vector3.ZERO   # coin bas gauche du panneau, dans le repere du pivot (point de saisie de la main)
var _mats: Array[BaseMaterial3D] = []
var _glow := 0.0
var _pulse := 0.0
var _want := false


## `pivot` articule le panneau autour de la tige, `panel` en est le maillage,
## `centre` sa position en espace voiture.
func setup(pivot: Node3D, panel: MeshInstance3D, centre: Vector3) -> void:
	_pivot = pivot
	# Le centre du panneau, ramene dans le pivot. Celui-ci est encore sans
	# rotation a cet instant : c'est une simple translation.
	position = pivot.transform.affine_inverse() * centre
	# Et on le range, ce qui est sa place au repos.
	_pivot.rotation.x = deg_to_rad(angle)

	# Point de saisie : le coin GAUCHE (x min) le plus loin de la tige, c'est-a-dire
	# le bas du panneau une fois deploye. Un peu au-dela du coin, pour que le poing
	# l'enveloppe au lieu de le traverser. Calcule dans le repere du pivot, donc
	# valable quel que soit l'angle du panneau.
	if panel.mesh != null:
		var box: AABB = panel.transform * panel.mesh.get_aabb()
		var best := Vector3.ZERO
		var best_d := -1.0
		for i in 8:
			var c := box.get_endpoint(i)
			if c.x > box.position.x + 0.001:
				continue
			var d := c.y * c.y + c.z * c.z
			if d > best_d:
				best_d = d
				best = c
		var away := Vector3(0.0, best.y, best.z).normalized()
		_grip_local = best + away * 0.012 + Vector3(-0.015, 0.0, 0.0)

	# Materiau dedie : celui du .glb est partage avec le ciel de toit et les
	# montants (cabin.gd le met en cache pour n'assombrir qu'une fois). Sans
	# duplication, viser un pare-soleil ferait pulser la moitie de l'habitacle.
	if panel.mesh == null:
		return
	for s in panel.mesh.get_surface_count():
		var src := panel.get_surface_override_material(s)
		if src == null:
			src = panel.mesh.surface_get_material(s)
		if src == null:
			continue
		var mine := src.duplicate()
		if mine is BaseMaterial3D:
			(mine as BaseMaterial3D).emission_enabled = true
			(mine as BaseMaterial3D).emission = highlight_color
			(mine as BaseMaterial3D).emission_energy_multiplier = 0.0
			_mats.append(mine)
		panel.set_surface_override_material(s, mine)


func _process(delta: float) -> void:
	var was := _glow
	_glow = lerpf(_glow, 1.0 if _want else 0.0, clampf(delta * 9.0, 0.0, 1.0))
	if _glow < 0.001:
		if was >= 0.001:
			_set_glow(0.0)
		return
	_pulse += delta * 2.4
	_set_glow(highlight_energy * _glow * (0.72 + 0.28 * sin(_pulse)))


# --- interface pour interaction.gd -----------------------------------------

## Un cran de souris pendant le reglage. `rel` est en pixels : souris vers le bas
## (rel.y positif) rabat le pare-soleil, comme le regard descend quand on baisse
## la souris.
## Ou la main vient saisir le panneau (espace monde) : son coin bas gauche.
func hand_point() -> Vector3:
	return _pivot.global_transform * _grip_local


func swivel(rel: Vector2) -> void:
	angle = clampf(angle + rel.y * degrees_per_pixel, angle_stowed, angle_deployed)
	_pivot.rotation.x = deg_to_rad(angle)


func adjust_hint() -> String:
	return "Maintiens clic gauche : placer le pare-soleil"


func set_highlight(want: bool) -> void:
	_want = want


## Rayon de la sphere de visee. Le panneau fait 30 x 12 cm : demi-diagonale
## 16 cm, on en garde 13 pour ne pas mordre sur le retroviseur voisin.
func grab_radius() -> float:
	return 0.13


func _set_glow(energy: float) -> void:
	for m in _mats:
		m.emission_energy_multiplier = energy
