extends Node3D
##
## UNE VILLE — sa presence minimale au bord de la route.
##
## Le graphe (map.gd) a des noms ; la route a besoin de LIEUX. Une ville,
## dans cette passe, c'est : un panneau d'entree au nom de l'endroit, quatre
## lampadaires dont UN SEUL porte une vraie lumiere (le budget : les phares
## ont deja deux spots ombres), une ZONE D'ARRET — un pave d'asphalte elargi
## sur l'accotement droit, la ou les clients attendent — et deux ou trois
## silhouettes de batiments cote oppose, une fenetre allumee chacune. Assez
## pour qu'on SACHE qu'on traverse quelque chose ; le reste dort dans le noir.
##
## Un seul exemplaire, en pool dans road.gd comme la voiture de police :
## arme a l'echantillon programme, eteint une fois depasse.
##
## Le panneau se reutilise pour les bifurcations (make_sign) : un Y annonce
## ses deux villes avec la meme tole et la meme peinture.
##

const Retro := preload("res://scripts/retro.gd")

## Longueur de la zone d'arret, et sa largeur au-dela de l'accotement.
const PAD_LEN := 30.0
const PAD_W := 3.0

var town_name := ""

var _label: Label3D
var _lamp_light: OmniLight3D
var _mat_metal: ShaderMaterial
var _mat_pole: ShaderMaterial
var _mat_pad: ShaderMaterial
var _mat_house: ShaderMaterial
var _mat_window: ShaderMaterial


func _ready() -> void:
	_mat_metal = Retro.mat(Color(0.10, 0.11, 0.13), 0.5)
	_mat_pole = Retro.mat(Color(0.055, 0.055, 0.06), 0.9)
	_mat_pad = Retro.mat(Color(0.052, 0.054, 0.050), 0.96)
	_mat_house = Retro.mat(Color(0.030, 0.030, 0.034), 0.95)
	_mat_window = Retro.mat(Color(0.09, 0.075, 0.045), 0.6)
	_mat_window.set_shader_parameter("emission", Color(0.55, 0.38, 0.16))
	_build()
	visible = false


## Pose la ville : `at` est la transform du ruban a l'echantillon d'entree
## (X = droite de la route, -Z = sens de la marche), le decor s'etale DEVANT.
func arm(at: Transform3D, name_: String) -> void:
	global_transform = at
	town_name = name_
	_label.text = name_.to_upper()
	visible = true


func sleep() -> void:
	visible = false


func _build() -> void:
	# Le panneau d'entree, a droite, a hauteur d'yeux de conducteur.
	var sign := make_sign(_mat_metal, _mat_pole)
	sign.position = Vector3(5.2, 0.0, 0.0)
	add_child(sign)
	_label = sign.get_node("Name") as Label3D

	# La zone d'arret : un pave d'asphalte au-dela de l'accotement droit, sur
	# PAD_LEN au coeur de la traversee. C'est la que les clients attendront.
	var pad := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(PAD_W + 2.4, PAD_LEN)
	pad.mesh = pmesh
	pad.material_override = _mat_pad
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.position = Vector3(3.4 + (PAD_W + 2.4) * 0.5 - 1.2, 0.012, -PAD_LEN * 0.9)
	add_child(pad)

	# Les lampadaires : quatre tetes qui luisent, UNE vraie lumiere — posee
	# au milieu de la zone d'arret, la ou il faut voir quelqu'un attendre.
	for i in 4:
		var z := -8.0 - 22.0 * float(i)
		var lamp := _lamp(Vector3(5.0, 0.0, z), i == 1)
		add_child(lamp)

	# Les silhouettes, cote gauche : des boites noires en retrait, une
	# fenetre tiede chacune. Un bourg endormi, pas un decor de theatre.
	for i in 3:
		var house := Node3D.new()
		var w := 7.0 + 3.0 * float(i % 2)
		var h := 4.6 + 1.6 * float((i + 1) % 2)
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w, h, 6.0)
		body.mesh = box
		body.material_override = _mat_house
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.position = Vector3(0.0, h * 0.5, 0.0)
		house.add_child(body)
		var win := MeshInstance3D.new()
		var wbox := BoxMesh.new()
		wbox.size = Vector3(0.7, 0.9, 0.06)
		win.mesh = wbox
		win.material_override = _mat_window
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		win.position = Vector3(w * 0.22, 2.1, 3.02)
		house.add_child(win)
		house.position = Vector3(-11.0 - 2.5 * float(i % 2), 0.0,
			-16.0 - 26.0 * float(i))
		house.rotation.y = deg_to_rad(6.0 * float(i - 1))
		add_child(house)


## Un panneau au nom d'une ville : poteau, tole, texte. Reutilise tel quel
## par la signalisation des Y (road.gd), d'ou la fabrique publique.
static func make_sign(mat_metal: Material, mat_pole: Material) -> Node3D:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.045
	pcyl.bottom_radius = 0.055
	pcyl.height = 2.4
	pole.mesh = pcyl
	pole.material_override = mat_pole
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position = Vector3(0.0, 1.2, 0.0)
	root.add_child(pole)

	var plate := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(2.1, 0.62, 0.04)
	plate.mesh = pbox
	plate.material_override = mat_metal
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.position = Vector3(0.0, 2.15, 0.0)
	root.add_child(plate)

	var label := Label3D.new()
	label.name = "Name"
	label.text = "?"
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(0.72, 0.74, 0.70)
	label.outline_size = 0
	label.position = Vector3(0.0, 2.15, 0.035)
	root.add_child(label)
	return root


func _lamp(at: Vector3, lit: bool) -> Node3D:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.05
	pcyl.bottom_radius = 0.07
	pcyl.height = 5.2
	pole.mesh = pcyl
	pole.material_override = _mat_pole
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position = Vector3(0.0, 2.6, 0.0)
	root.add_child(pole)

	var head := MeshInstance3D.new()
	var hbox := BoxMesh.new()
	hbox.size = Vector3(0.55, 0.14, 0.22)
	head.mesh = hbox
	var mat_head := Retro.mat(Color(0.06, 0.06, 0.05), 0.5)
	# La tete luit — sodium fatigue — meme la ou il n'y a pas de lumiere :
	# de nuit, quatre tetes orange font une rue, une seule OmniLight le budget.
	mat_head.set_shader_parameter("emission", Color(0.75, 0.45, 0.12))
	head.material_override = mat_head
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.position = Vector3(-0.55, 5.18, 0.0)
	root.add_child(head)

	if lit:
		_lamp_light = OmniLight3D.new()
		_lamp_light.light_color = Color(1.0, 0.62, 0.22)
		_lamp_light.light_energy = 1.4
		_lamp_light.omni_range = 14.0
		_lamp_light.omni_attenuation = 1.6
		_lamp_light.shadow_enabled = false
		_lamp_light.position = Vector3(-0.55, 5.0, 0.0)
		root.add_child(_lamp_light)

	root.position = at
	return root
