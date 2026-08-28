extends Node3D
##
## L'AUTORADIO — la musique forte qui tient eveille, et qui agacera les
## clients.
##
## Une facade au centre de la planche de bord, un bouton de volume qui se
## TIENT comme la cle de contact : clic gauche maintenu, puis la molette cran
## par cran, la camera libre, les yeux sur la route (l'interface manivelle de
## ignition.gd, reprise a l'identique — wind() vide, crank() par crans).
##
## LE BUS "Radio" EST LE SIEN, ET CE N'EST PAS UN DETAIL.
## -------------------------------------------------------------------------
## Les sons du dehors passent par le bus "Cabine" et son passe-bas, que les
## vitres ouvrent (car.gd). Les haut-parleurs, EUX, sont dans l'habitacle
## avec l'oreille — comme le levier de vitesses (cabin_audio.gd) : la musique
## ne s'etouffe pas derriere sa propre vitre. Le bus se cree AVANT le lecteur
## (une lecture choisit son bus a la construction), idempotent au reload.
## C'est aussi la prise du cauchemar : le detunage s'accroche au lecteur.
##
## La musique vient de tools/make_radio_music.py : une boucle de 40 s exactes
## synthetisee — la petite station qui passe la nuit. Une seule station : la
## deuxieme attendra, le bouton des stations aussi.
##
## Le volume pousse la jauge de veille via car.on_radio (des le cran 4,
## facteur 0,55 dans sleep.gd) : la radio ne connait ni main ni sleep, elle
## previent la voiture qui la porte — le meme chemin que la canette bue.
##

const Retro := preload("res://scripts/retro.gd")

const STREAM_PATH := "res://assets/audio/radio/station_loop.wav"
const BUS := "Radio"
## dB par cran, 1..6. Le cran 0 ARRETE la lecture — le silence n'est pas un
## volume, et une boucle a -60 dB tournerait pour personne.
const CRAN_DB := [-100.0, -30.0, -24.0, -18.0, -13.0, -9.0, -6.0]
## Cran a partir duquel la musique est FORTE : la veille en profite (x0,55),
## les clients s'en plaindront.
const LOUD_AT := 4

## Cotes de la facade et du bouton.
const FACE := Vector3(0.186, 0.052, 0.020)
const KNOB_R := 0.011
const KNOB_LEN := 0.014

## Le cran courant, 0..6. Les bancs le lisent.
var volume := 0
## La voiture qui la porte (posee par car.gd) : le chemin vers la jauge.
var car: Node3D

var _player: AudioStreamPlayer
var _knob: MeshInstance3D
var _display_mat: ShaderMaterial
var _knob_mat: ShaderMaterial
var _want := false
var _glow := 0.0
var _pulse := 0.0


func _ready() -> void:
	_build_face()
	_build_audio()
	_apply()


## La facade : une barre sombre, un afficheur qui ne s'allume qu'en marche,
## le bouton de volume a gauche. Des primitives, comme tout ce qui n'existe
## pas dans le .glb.
func _build_face() -> void:
	var mat_body := Retro.mat(Color(0.030, 0.030, 0.034), 0.7)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = FACE
	body.mesh = box
	body.material_override = mat_body
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)

	# L'afficheur : une fente qui luit d'un vert d'appareil quand ca joue.
	_display_mat = Retro.mat(Color(0.02, 0.03, 0.02), 0.4)
	var disp := MeshInstance3D.new()
	var dbox := BoxMesh.new()
	dbox.size = Vector3(0.070, 0.014, 0.004)
	disp.mesh = dbox
	disp.material_override = _display_mat
	disp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disp.position = Vector3(0.012, 0.004, FACE.z * 0.5)
	add_child(disp)

	# Le bouton de volume. Axe vers l'habitacle (+Z) : il se tourne face a soi.
	_knob_mat = Retro.mat(Color(0.055, 0.055, 0.06), 0.55)
	_knob = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = KNOB_R
	cyl.bottom_radius = KNOB_R
	cyl.height = KNOB_LEN
	cyl.radial_segments = 10
	_knob.mesh = cyl
	_knob.material_override = _knob_mat
	_knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_knob.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_knob.position = Vector3(-FACE.x * 0.5 + 0.018, 0.0, FACE.z * 0.5 + KNOB_LEN * 0.5)
	add_child(_knob)
	# Le repere du bouton : un index clair, pour VOIR le cran.
	var tick := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(0.003, 0.0035, 0.009)
	tick.mesh = tbox
	tick.material_override = Retro.mat(Color(0.30, 0.29, 0.27), 0.5)
	tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tick.position = Vector3(0.0, KNOB_LEN * 0.5 + 0.001, -KNOB_R * 0.55)
	_knob.add_child(tick)


## Le bus d'abord, le lecteur ensuite — l'ordre est un contrat (car.gd,
## cabin_audio.gd : une lecture choisit son bus a la construction). Idempotent
## au reload : le bus retrouve est reutilise tel quel.
func _build_audio() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	if ResourceLoader.exists(STREAM_PATH):
		var stream := load(STREAM_PATH)
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		_player.stream = stream
	else:
		push_warning("radio : %s manque, lancer tools/make_radio_music.py" % STREAM_PATH)
	add_child(_player)


func _process(delta: float) -> void:
	# La surbrillance du bouton, au meme battement que la cle.
	if not _want and _glow <= 0.0:
		return
	_glow = move_toward(_glow, 1.0 if _want else 0.0, delta * 8.0)
	_pulse += delta * 2.4
	if _glow <= 0.0:
		_knob_mat.set_shader_parameter("emission", Color(0, 0, 0))
		return
	var e := 0.9 * _glow * (0.72 + 0.28 * sin(_pulse))
	_knob_mat.set_shader_parameter("emission", Color(0.9 * e, 0.55 * e, 0.25 * e))


func _apply() -> void:
	var playing := volume > 0 and _player.stream != null
	if playing and not _player.playing:
		_player.play()
	elif not playing and _player.playing:
		_player.stop()
	_player.volume_db = CRAN_DB[volume]
	# Le bouton tourne avec le cran, l'afficheur s'allume avec la musique.
	_knob.rotation_degrees.z = -32.0 * float(volume)
	_display_mat.set_shader_parameter("emission",
		Color(0.06, 0.22, 0.10) if playing else Color(0, 0, 0))
	if car != null and car.has_method("on_radio"):
		car.call("on_radio", volume)


## Le cauchemar detune la porteuse : la station est toujours la, mais elle
## n'est plus tout a fait a sa place.
func set_detuned(on: bool) -> void:
	_player.pitch_scale = 0.94 if on else 1.0


func loud() -> bool:
	return volume >= LOUD_AT


# --- interface pour interaction.gd (le contrat de la cle et des manivelles) --

## Sa presence fait passer le clic maintenu en GRIPPING. Rien a rattraper :
## le volume va au cran tout de suite.
func wind(_delta: float) -> void:
	pass


## Un cran de molette. interaction.gd envoie +1 vers le BAS : molette haut,
## plus fort — le sens de tous les boutons de volume du monde.
func crank(notches: float) -> void:
	volume = clampi(volume + (1 if notches < 0.0 else -1), 0, 6)
	_apply()


func release_grip() -> void:
	pass


func hand_point() -> Vector3:
	return _knob.global_position


func grip_hint() -> String:
	return "Maintiens clic gauche : prendre le bouton de la radio"


func held_hint() -> String:
	if volume == 0:
		return "Molette haut : allumer la radio"
	return "Molette : volume (%d/6)" % volume


func set_highlight(want: bool) -> void:
	_want = want


func grab_radius() -> float:
	return 0.06
