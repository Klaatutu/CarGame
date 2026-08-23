extends Node3D
##
## Vitre de portiere, descendue et remontee A LA MANIVELLE. Une Civic de 1990
## n'a pas de leve-vitres electriques : c'est la manivelle qu'on vise, qu'on
## attrape, et qu'on tourne.
##
## Le geste n'est PAS celui du retroviseur ni des pare-soleil. Ceux-la se
## placent a la souris, regard bloque : on les regarde en les reglant. Une
## manivelle, on l'attrape et on la tourne SANS la regarder — on garde les yeux
## sur la route. Donc :
##
##   - clic gauche MAINTENU : la main saisit la poignee et y reste ;
##   - la camera reste LIBRE, on continue de regarder ou on veut ;
##   - E ouvre, A ferme, tant qu'on tient la touche ;
##   - relacher le clic lache la poignee, la vitre reste ou elle en est.
##
## Le noeud se place SUR LA POIGNEE de la manivelle : c'est ce qu'on vise et
## c'est la que la main vient se poser.
##

## Course de la vitre, en metres. 0,265 : la glace fait 26 cm de haut et sa base
## affleure la ceinture de caisse. Descendue de sa propre hauteur, son bord
## superieur passe donc sous l'enjoliveur de ceinture — elle a disparu dans la
## portiere, ce qui est le but.
@export var travel := 0.265
## Tours de manivelle pour la course complete. Trois : c'est ce que demande une
## vraie, et ca reste lisible a l'oeil. Un seul tour ferait jouet.
@export var turns := 3.0
## Course par seconde de touche tenue. 0.5 : deux secondes du haut en bas, soit
## une vitre et demie de tour par seconde. C'est le rythme ou on tourne une
## manivelle sans forcer.
@export var open_rate := 0.5
## Surbrillance quand on vise la manivelle.
@export var highlight_color := Color(1.0, 0.62, 0.30)
@export var highlight_energy := 0.55

## 0 = vitre remontee, 1 = vitre entierement descendue.
var open := 0.0
## -1 portiere gauche, +1 portiere droite. Les deux manivelles tournent en
## miroir l'une de l'autre, comme sur la vraie voiture.
var side := -1.0

var _crank: Node3D          # pivot de la manivelle, axe X au moyeu
var _panes: Node3D          # pivot des deux vitres (interieure et exterieure)
var _knob_local := Vector3.ZERO
var _mats: Array[BaseMaterial3D] = []
var _glow := 0.0
var _pulse := 0.0
var _want := false


## `crank` porte bras et bouton, `panes` porte les deux glaces, `knob` est le
## centre du bouton en espace voiture.
func setup(crank: Node3D, panes: Node3D, knob: Vector3, which_side: float,
		knob_mesh: MeshInstance3D) -> void:
	_crank = crank
	_panes = panes
	side = which_side
	# Le bouton, exprime dans le pivot de la manivelle : il tourne avec elle, donc
	# le point de saisie suit la rotation au lieu de rester en l'air.
	_knob_local = crank.transform.affine_inverse() * knob
	position = _knob_local

	# Materiau dedie pour le bouton : celui du .glb est partage avec le reste de
	# la garniture de portiere. Sans duplication, viser la manivelle ferait
	# pulser toute la contre-porte.
	if knob_mesh == null or knob_mesh.mesh == null:
		return
	for s in knob_mesh.mesh.get_surface_count():
		var src := knob_mesh.get_surface_override_material(s)
		if src == null:
			src = knob_mesh.mesh.surface_get_material(s)
		if src == null:
			continue
		var mine := src.duplicate()
		if mine is BaseMaterial3D:
			(mine as BaseMaterial3D).emission_enabled = true
			(mine as BaseMaterial3D).emission = highlight_color
			(mine as BaseMaterial3D).emission_energy_multiplier = 0.0
			_mats.append(mine)
		knob_mesh.set_surface_override_material(s, mine)


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

## Un tour de manivelle. `dir` vaut +1 (on ouvre), -1 (on ferme) ou 0.
## Appele chaque image par interaction.gd tant que la poignee est tenue.
func wind(dir: float, delta: float) -> void:
	if dir == 0.0:
		return
	var was := open
	open = clampf(open + dir * open_rate * delta, 0.0, 1.0)
	if open == was:
		return                     # en butee : la manivelle ne tourne plus
	_crank.rotation.x = open * turns * TAU * side
	_panes.position.y = -travel * open


## La main se pose sur la POIGNEE, qui tourne : elle la suit donc au lieu de
## rester plantee au centre du moyeu.
func hand_point() -> Vector3:
	return _crank.global_transform * _knob_local


## Ce que le HUD affiche quand on la vise, puis quand on la tient.
func grip_hint() -> String:
	return "Maintiens clic gauche : saisir la manivelle"


func held_hint() -> String:
	if open <= 0.0:
		return "E : ouvrir"
	if open >= 1.0:
		return "A : fermer"
	return "E : ouvrir     A : fermer"


func set_highlight(want: bool) -> void:
	_want = want


## Rayon de la sphere de visee. Le bouton fait 3 cm : viser au pixel pres serait
## injouable, mais au-dela de 8 cm on accrocherait l'accoudoir.
func grab_radius() -> float:
	return 0.08


func _set_glow(energy: float) -> void:
	for m in _mats:
		m.emission_energy_multiplier = energy
