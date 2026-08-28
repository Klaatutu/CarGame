extends "res://scripts/prop.gd"
##
## Canette (NoSleep, Cariboon, Kombo), intacte ou ecrasee : objet libre de
## l'habitacle, voir prop.gd pour la simulation. La geometrie vient des .glb
## construits par assets/blender/build_can.py (meme maillage dans les deux
## etats, l'ecrasee est deformee a la source).
##
## Le .glb a son origine a la BASE de la canette, logo vers +Z : une fois
## reposee par interaction.gd, qui oriente +Z vers l'oeil, l'etiquette regarde
## le conducteur. Le noeud, lui, a son origine au CENTRE du volume comme le
## paquet : prop.gd raisonne en demi-cotes autour de l'origine, d'ou le
## maillage decale vers le bas de la moitie de sa hauteur.
##

const SCENES := {
	"nosleep": preload("res://assets/models/can_nosleep.glb"),
	"nosleep_crushed": preload("res://assets/models/can_nosleep_crushed.glb"),
	"cariboon": preload("res://assets/models/can_cariboon.glb"),
	"cariboon_crushed": preload("res://assets/models/can_cariboon_crushed.glb"),
	"kombo": preload("res://assets/models/can_kombo.glb"),
	"kombo_crushed": preload("res://assets/models/can_kombo_crushed.glb"),
}

## Boisson : "nosleep", "cariboon" ou "kombo".
var drink := "nosleep"
## Version ecrasee (detritus) plutot qu'intacte.
var crushed := false
## Pleine : une intacte se BOIT (voir sip/drain — le geste est dans
## interaction.gd, l'effet dans sleep.gd). Une ecrasee est un souvenir.
var full := false

var _materials: Array[StandardMaterial3D] = []
var _gulp_snd: AudioStreamPlayer3D
var _crush_snd: AudioStreamPlayer3D


func _ready() -> void:
	full = not crushed
	_build_mesh(drink + ("_crushed" if crushed else ""))
	_build_audio()


## Monte (ou remonte) le maillage d'un des six etats. Sert au demarrage, et
## au passage intacte -> ecrasee quand on la vide : meme canette, meme noeud,
## la simulation continue — seules les cotes changent, et prop.gd les relit.
func _build_mesh(key: String) -> void:
	if not SCENES.has(key):
		push_error("canette inconnue : %s" % key)
		return
	var model: Node = SCENES[key].instantiate()
	var src := _first_mesh(model)
	if src == null or src.mesh == null:
		push_error("%s : aucun maillage dans le .glb" % key)
		model.free()
		return

	var old := get_node_or_null("Mesh")
	if old != null:
		old.name = "MeshOld"
		old.queue_free()
	_materials.clear()

	# Le maillage est adopte DIRECTEMENT sous ce noeud, pas la scene importee :
	# interaction.gd fabrique le fantome de depose a partir des MeshInstance3D
	# enfants, et un noeud intermediaire le laisserait vide.
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = src.mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	model.free()

	# Cotes lues sur le maillage : une ecrasee n'a ni la hauteur ni la
	# symetrie d'une intacte (elle penche, et son enfoncement est d'un cote).
	var aabb := mi.mesh.get_aabb()
	half = Vector3(maxf(-aabb.position.x, aabb.end.x), aabb.size.y * 0.5,
		maxf(-aabb.position.z, aabb.end.z))
	mi.position.y = -(aabb.position.y + half.y)       # centre du volume a l'origine

	_prepare_materials(mi)


# --------------------------------------------------------------------------
# Boire
# --------------------------------------------------------------------------

## interaction.gd demande : y a-t-il quelque chose a boire ? Oui -> le
## glouglou part avec le geste (il s'interrompt avec lui, voir stop_sip).
func sip() -> bool:
	if not full:
		return false
	if _gulp_snd != null and _gulp_snd.stream != null:
		_gulp_snd.play()
	return true


## Le geste s'est interrompu avant la fin : la canette reste pleine.
func stop_sip() -> void:
	if _gulp_snd != null:
		_gulp_snd.stop()


## Bue jusqu'au bout. La canette S'ECRASE dans la main — le crunch, l'echange
## de maillage vers la variante ecrasee (prechargee depuis toujours), et les
## cotes relues : celles qui trainaient au plancher depuis le premier jour
## racontent retroactivement le quotidien du chauffeur.
func drain() -> void:
	if not full:
		return
	full = false
	crushed = true
	_build_mesh(drink + "_crushed")
	if _crush_snd != null and _crush_snd.stream != null:
		_crush_snd.play()


func _build_audio() -> void:
	var bus := "Cabine" if AudioServer.get_bus_index("Cabine") >= 0 else "Master"
	_gulp_snd = _sound("res://assets/audio/taxi/gulp.wav", bus, -4.0)
	_crush_snd = _sound("res://assets/audio/taxi/crush.wav", bus, -6.0)


func _sound(path: String, bus: String, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.volume_db = db
	p.unit_size = 2.0
	p.max_distance = 0.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if ResourceLoader.exists(path):
		p.stream = load(path)
	else:
		push_warning("son de canette : %s manque, lancer tools/make_taxi_sounds.py" % path)
	add_child(p)
	return p


## Albedo rabattu sur la palette de nuit (cabin.gd INTERIOR_DIM, comme tout le
## .glb de l'habitacle), texture en plus proche voisin (pixels nets, look PS1)
## et une emission eteinte qui servira de halo de surbrillance.
func _prepare_materials(mi: MeshInstance3D) -> void:
	var dim: float = cabin.INTERIOR_DIM if cabin != null else 1.0
	for s in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(s)
		if src == null:
			continue
		var m := src.duplicate() as StandardMaterial3D
		if m == null:
			continue
		var c := m.albedo_color
		m.albedo_color = Color(c.r * dim, c.g * dim, c.b * dim, c.a)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.emission_enabled = true
		m.emission = highlight_color
		m.emission_energy_multiplier = 0.0
		mi.set_surface_override_material(s, m)
		_materials.append(m)


func _apply_glow(energy: float) -> void:
	for m in _materials:
		m.emission_energy_multiplier = energy


## Le seul maillage du .glb, ou qu'il soit dans la scene importee.
func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var found := _first_mesh(c)
		if found != null:
			return found
	return null
