extends "res://scripts/prop.gd"
##
## Paquet de cigarettes : objet libre de l'habitacle, voir prop.gd pour la
## simulation (repere de la voiture, frottement de Coulomb, boites de cabin.gd).
## Ici : la geometrie (trois boites) et le halo de surbrillance.
##

const Retro := preload("res://scripts/retro.gd")

## Cotes reelles d'un paquet souple : 85 x 55 x 22 mm. Pose a plat, la
## grande face vers le haut.
const SIZE := Vector3(0.055, 0.022, 0.085)
const HALF := Vector3(0.0275, 0.011, 0.0425)
## Ou il revient s'il sort de l'habitacle, plutot que d'etre perdu.
const RESET_POINT := Vector3(0.30, 0.52, 0.10)

var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	half = HALF
	reset_point = RESET_POINT

	var paper := _mat(Color(0.52, 0.50, 0.46), 0.86)
	var lid := _mat(Color(0.30, 0.28, 0.26), 0.80)
	var label := _mat(Color(0.34, 0.05, 0.05), 0.62)

	_box(SIZE, Vector3.ZERO, paper)
	# Couvercle a rabat : le tiers superieur, legerement plus fonce.
	_box(Vector3(SIZE.x + 0.001, SIZE.y + 0.001, SIZE.z * 0.34),
		Vector3(0.0, 0.0, -SIZE.z * 0.33), lid)
	# Pastille de marque sur le dessus.
	_box(Vector3(SIZE.x * 0.5, 0.001, SIZE.z * 0.22),
		Vector3(0.0, SIZE.y * 0.5, SIZE.z * 0.12), label)


func _apply_glow(energy: float) -> void:
	for m in _materials:
		m.set_shader_parameter("emission", highlight_color * energy)


func _mat(color: Color, rough: float) -> ShaderMaterial:
	var m := Retro.mat(color, rough)
	_materials.append(m)
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Tenu debout : sa longueur (Z) le long du poing, l'etiquette (+Y, la grande
## face) tournee vers le joueur.
func grip_axis() -> Vector3:
	return Vector3.FORWARD


func front_axis() -> Vector3:
	return Vector3.UP

