extends Node3D
##
## Voiture de police garee sur l'accotement, gyrophares allumes.
##
## Le modele vient de assets/models/police_car.glb (build_police_car.py, meme
## technique que la Civic, meme repere : avant = -Z). Une version basse-poly
## (police_car_simple.glb, build_police_car_simple.py, ~2 200 triangles, vitres
## opaques) existe aussi et porte les memes noms de noeuds : il suffit de
## changer MODEL pour l'utiliser.
## Rien n'est fabrique ici en primitives : on adopte les deux gyrophares du .glb
## et on les ANIME.
##
## Un gyrophare de 1990 n'est pas un stroboscope : c'est une ampoule fixe devant
## un miroir parabolique qui TOURNE. Chaque dome a donc son pivot
## (POL_BeaconMirror_L/R) qu'on fait tourner, avec un SpotLight3D accroche
## dessus : c'est lui qui balaie la route et le brouillard — le faisceau bleu
## qui passe sur les arbres est toute l'ambiance. Le dome, lui, ne brille fort
## que quand le miroir est tourne vers le joueur, comme en vrai.
##
## Les deux miroirs tournent en opposition de phase, un flash sur deux de
## chaque cote.
##

const MODEL := preload("res://assets/models/police_car.glb")

## Assombrissement des albedos, comme la carrosserie de la Civic (EXTERIOR_DIM).
const DIM := 0.85
const BEACONS := ["L", "R"]
const BLUE := Color(0.25, 0.45, 1.0)

@export_group("Gyrophares")
## Tours par seconde du miroir. Les gyrophares rotatifs tournent a 1,5-2 Hz.
@export var turn_hz := 1.6
## Faisceau balayant : intensite et portee du spot porte par le miroir.
@export var beam_energy := 9.0
@export var beam_range := 32.0
@export var beam_angle := 34.0
## Halo fixe au dome, pour que la caisse blanche prenne le bleu de pres.
@export var halo_energy := 1.2
@export var halo_range := 8.0
## Ce que le faisceau et le halo injectent dans le brouillard volumetrique.
## Avec 2.5, tout le brouillard virait au bleu a 40 m ; le faisceau doit se
## lire comme un pinceau qui tourne, pas comme un ciel bleu.
@export var beam_fog := 1.0
@export var halo_fog := 0.25
## Emission du dome : plancher (toujours un peu lumineux) et crete (miroir vers nous).
@export var dome_floor := 0.6
@export var dome_peak := 6.0

var _model: Node3D
var _beacons: Array[Dictionary] = []
var _phase := 0.0


func _ready() -> void:
	_model = MODEL.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	_dim(_model, DIM, {})
	_build_beacons()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * turn_hz * TAU, TAU)
	var cam := get_viewport().get_camera_3d()
	for i in _beacons.size():
		var b: Dictionary = _beacons[i]
		var pivot := b["pivot"] as Node3D
		# Opposition de phase entre les deux domes.
		pivot.rotation.y = _phase + PI * float(i)
		# Le dome brille quand le miroir regarde le joueur : cos^3 de l'angle
		# entre le faisceau et la direction de la camera, c'est assez pointu pour
		# lire un "flash" et assez large pour ne pas sauter d'une image a l'autre.
		var mat := b["mat"] as StandardMaterial3D
		if cam == null:
			mat.emission_energy_multiplier = dome_floor
			continue
		var beam: Vector3 = -pivot.global_transform.basis.z
		var to_cam: Vector3 = (cam.global_position - pivot.global_position).normalized()
		var facing := maxf(beam.dot(to_cam), 0.0)
		mat.emission_energy_multiplier = dome_floor + (dome_peak - dome_floor) * facing * facing * facing


## Un gyrophare = le dome du .glb (materiau rendu unique pour pulser l'emission),
## le pivot du miroir qu'on fait tourner, un spot sur le pivot et un halo fixe.
func _build_beacons() -> void:
	for side in BEACONS:
		var dome := _model.find_child("POL_Beacon_%s" % side, true, false) as MeshInstance3D
		var pivot := _model.find_child("POL_BeaconMirror_%s" % side, true, false) as Node3D
		if dome == null or pivot == null:
			push_warning("gyrophare %s introuvable dans police_car.glb" % side)
			continue
		var src := dome.get_active_material(0)
		var mat := (src.duplicate() if src != null else StandardMaterial3D.new()) as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = BLUE
		mat.emission_energy_multiplier = dome_floor
		dome.set_surface_override_material(0, mat)
		# Le dome est translucide : il ne doit pas projeter d'ombre sur sa propre
		# ampoule ni sur le toit, et il ne bloque pas le spot qui est dedans.
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var beam := SpotLight3D.new()
		beam.name = "Beam"
		# A l'ampoule, visant comme le miroir : -Z local du pivot.
		beam.position = Vector3(0.0, 0.05, 0.0)
		beam.light_color = BLUE
		beam.light_energy = beam_energy
		beam.spot_range = beam_range
		beam.spot_angle = beam_angle
		beam.spot_angle_attenuation = 0.8
		beam.spot_attenuation = 0.9
		# C'est dans le brouillard volumetrique qu'on voit le faisceau tourner.
		beam.light_volumetric_fog_energy = beam_fog
		beam.shadow_enabled = false
		pivot.add_child(beam)
		# Le miroir et l'ampoule du .glb ne doivent pas masquer leur propre spot.
		for c in pivot.get_children():
			if c is GeometryInstance3D:
				(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var halo := OmniLight3D.new()
		halo.name = "Halo"
		halo.light_color = BLUE
		halo.light_energy = halo_energy
		halo.omni_range = halo_range
		halo.omni_attenuation = 1.2
		halo.light_volumetric_fog_energy = halo_fog
		halo.shadow_enabled = false
		dome.add_child(halo)
		halo.position = Vector3(0.0, 0.07, 0.0)

		_beacons.append({"dome": dome, "pivot": pivot, "mat": mat})


## Copie de cabin.gd : les albedos du .glb sont faits pour Blender, trop clairs
## pour une scene de nuit. Un materiau par materiau source, partage.
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
