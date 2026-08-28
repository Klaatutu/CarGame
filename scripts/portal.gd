extends Node3D
##
## LE PORTAIL — la sortie du cauchemar.
##
## On n'echappe pas au cauchemar en s'arretant : on s'en echappe en ROULANT.
## Au bout d'une certaine distance parcourue endormi, la route pose ceci en
## travers de la voie : deux montants, un linteau, et un voile de lumiere
## froide — la seule chose froide d'un monde teinte rouge. Le franchir, c'est
## se reveiller ; c'est main.gd qui detecte le franchissement (produit
## scalaire le long de l'axe de la route, aucune physique — rien de physique
## ne vise la caisse dans ce depot) et qui rallume le monde normal.
##
## Le noeud vit en pool dans road.gd, comme la voiture de police : un seul
## exemplaire, arme puis rendormi. Le voile s'anime tout seul (TIME dans son
## shader) : le portail n'a pas de _process.
##

const Retro := preload("res://scripts/retro.gd")

## Demi-ecartement des montants : la chaussee (3,4) plus un demi-accotement.
const PYLON_HALF := 4.2
const PYLON_H := 5.6
const VEIL_W := 8.0
const VEIL_H := 5.0

## Le sens de la marche au point de pose : ce qu'il faut franchir. Pose par
## road.set_portal, lu par main a chaque image.
var travel_dir := Vector3.FORWARD
var active := false

var _veil_mat: ShaderMaterial


func _ready() -> void:
	# Les montants : deux os dresses, a peine visibles — c'est le voile qu'on
	# voit de loin, eux ne se lisent qu'aux phares.
	var mat_bone := Retro.mat(Color(0.16, 0.155, 0.17), 0.85)
	var pylon := CylinderMesh.new()
	pylon.top_radius = 0.14
	pylon.bottom_radius = 0.22
	pylon.height = PYLON_H
	pylon.radial_segments = 8
	pylon.rings = 1
	for side in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		m.mesh = pylon
		m.material_override = mat_bone
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = Vector3(side * PYLON_HALF, PYLON_H * 0.5, 0.0)
		add_child(m)
	var lintel := BoxMesh.new()
	lintel.size = Vector3(PYLON_HALF * 2.0 + 0.6, 0.26, 0.30)
	var lm := MeshInstance3D.new()
	lm.mesh = lintel
	lm.material_override = mat_bone
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lm.position = Vector3(0.0, PYLON_H, 0.0)
	add_child(lm)

	# Le voile. blend_add et fog_disabled : il se voit a 130 m dans un
	# brouillard qui eteint tout le reste — c'est une sortie, pas un decor.
	var quad := QuadMesh.new()
	quad.size = Vector2(VEIL_W, VEIL_H)
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = preload("res://shaders/portal_veil.gdshader")
	var vm := MeshInstance3D.new()
	vm.name = "Veil"
	vm.mesh = quad
	vm.material_override = _veil_mat
	vm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vm.position = Vector3(0.0, 0.35 + VEIL_H * 0.5, 0.0)
	add_child(vm)

	visible = false


## Pose le portail sur la transform d'un echantillon de route (sample_at) :
## l'origine au centre de la chaussee, le voile EN TRAVERS de la voie.
func arm(at: Transform3D) -> void:
	# sample_at rend X = droite de la route, -Z = sens de la marche. Le quad
	# du voile vit dans le plan XY de son noeud : l'orientation de la route
	## convient telle quelle, le voile barre la voie.
	global_transform = at
	travel_dir = -at.basis.z
	active = true
	visible = true


func sleep() -> void:
	active = false
	visible = false


## La voiture est-elle passee au travers ? Un demi-metre de marge derriere le
## plan, pour ne pas declarer le reveil sur un frolement de bord.
func crossed_by(p: Vector3) -> bool:
	return active and (p - global_position).dot(travel_dir) > 0.5
