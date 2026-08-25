extends Node
##
## Tout ce qu'on entend du siege en dehors du moteur : la route, le vent, le
## levier de vitesses et le frein a main. Boucles et one-shots synthetises par
## tools/make_cabin_sounds.py.
##
## La route et le vent dependent de la VITESSE, pas du regime : c'est leur
## ecart avec le moteur qui fait sentir les rapports (en 2e a fond le moteur
## hurle et le vent est timide ; en 5e, l'inverse).
##
## Le levier et le frein a main ne sont pas declenches par car.gd : ce noeud
## regarde `gear` et `handbrake_on` changer d'une image a l'autre. Pas de
## signal a brancher, pas de logique en double.
##

const DIR := "res://assets/audio/cabin/"

@export_group("Route et vent")
## Niveaux juges a l'oreille contre le moteur (volume_db -4 dans
## engine_audio.gd) : tools/render_audio_demo.py rend la balance hors ligne.
@export var road_volume_db := -13.0
@export var wind_volume_db := -15.0
## Vitesse (m/s) a laquelle le grondement de la route est a plein niveau.
@export var road_full_speed := 30.0
## Le vent commence a s'entendre a wind_start et sature a wind_full (m/s).
@export var wind_start := 4.0
@export var wind_full := 40.0

@export_group("Vitres ouvertes")
## Le vent qui s'engouffre : proportionnel a l'ouverture et a la vitesse.
@export var wind_open_volume_db := -8.0
## Le battement sourd ("wub-wub"), maximal vers 90 km/h avec une vitre ouverte.
@export var buffet_volume_db := -14.0
## Les pneus entendus par la vitre.
@export var road_open_volume_db := -16.0
## Le mecanisme de la manivelle, tant que la vitre bouge.
@export var crank_volume_db := -18.0

@export_group("Commandes")
@export var shift_volume_db := -11.0
@export var handbrake_volume_db := -13.0
## Variation de hauteur aleatoire des one-shots, pour ne pas entendre deux fois
## exactement le meme clac.
@export var shot_pitch_spread := 0.06

## Bus des sources EXTERIEURES : la route, le vent, ce qui traverse la caisse.
## car.gd y branche le passe-bas de la vitre. Le levier, le frein a main et la
## manivelle n'y passent PAS : ils sont dans l'habitacle avec le conducteur, il
## n'y a aucune vitre entre eux et l'oreille, les etouffer sonnerait faux.
## A poser avant l'entree dans l'arbre, _ready() cree les lectures.
var outside_bus := "Master"
## Bus des mecanismes de portiere : la manivelle. Ni dehors ni a l'air libre —
## enferme dans le caisson de la portiere, d'ou une sourdine a lui.
var door_bus := "Master"

var _road: AudioStreamPlayer
var _wind_lo: AudioStreamPlayer
var _wind_hi: AudioStreamPlayer
var _wind_open: AudioStreamPlayer
var _buffet: AudioStreamPlayer
var _road_open: AudioStreamPlayer
var _crank: AudioStreamPlayer
var _shift: AudioStreamPlayer
var _hb_pull: AudioStreamPlayer
var _hb_release: AudioStreamPlayer
var _last_gear := -1
var _last_hb := false
var _last_open := -1.0
var _crank_gain := 0.0
var _last_event := "-"
var _dbg_speed := 0.0
var _dbg_open := 0.0


func _ready() -> void:
	_road = _loop("road_roll.wav", outside_bus)
	_wind_lo = _loop("wind_low.wav", outside_bus)
	_wind_hi = _loop("wind_high.wav", outside_bus)
	_wind_open = _loop("wind_open.wav", outside_bus)
	_buffet = _loop("wind_buffet.wav", outside_bus)
	_road_open = _loop("road_open.wav", outside_bus)
	_crank = _loop("crank.wav", door_bus)
	_shift = _shot("gear_shift.wav")
	_hb_pull = _shot("handbrake_pull.wav")
	_hb_release = _shot("handbrake_release.wav")
	for p in [_road, _wind_lo, _wind_hi, _wind_open, _buffet, _road_open, _crank]:
		if p.stream:
			p.play()


func _exit_tree() -> void:
	for p in [_road, _wind_lo, _wind_hi, _wind_open, _buffet, _road_open, _crank,
			_shift, _hb_pull, _hb_release]:
		p.stop()


## A appeler a chaque image depuis la voiture.
## window_open : ouverture acoustique des vitres, 0 fermees, 1 grande ouverte.
func update(speed: float, gear: int, handbrake_on: bool, delta: float, window_open := 0.0) -> void:
	var v := absf(speed)
	_dbg_speed = v
	_dbg_open = window_open

	# --- route : monte vite puis plafonne, et grimpe un peu en hauteur -------
	var r := pow(clampf(v / road_full_speed, 0.0, 1.0), 0.8)
	_road.pitch_scale = 0.85 + 0.35 * clampf(v / 40.0, 0.0, 1.0)
	_road.volume_db = _to_db(r * db_to_linear(road_volume_db))

	# --- vent : rien en ville, tout sur la nationale --------------------------
	# Le souffle sourd cede la place au souffle ouvert a mesure qu'on accelere.
	# Les deux boucles partagent leurs rafales, un fondu a puissance constante
	# suffit.
	var w := clampf((v - wind_start) / (wind_full - wind_start), 0.0, 1.0)
	var wg := pow(w, 1.6) * db_to_linear(wind_volume_db)
	_wind_lo.volume_db = _to_db(wg * sqrt(1.0 - 0.75 * w))
	_wind_hi.volume_db = _to_db(wg * sqrt(w))

	# --- vitres ouvertes ------------------------------------------------------
	# Une fente suffit a siffler : l'effet monte vite (puissance 0,6), puis
	# c'est la vitesse qui fait tout.
	var fx := pow(clampf(window_open, 0.0, 1.0), 0.6)
	_wind_open.pitch_scale = 0.9 + 0.2 * clampf(v / 40.0, 0.0, 1.0)
	_wind_open.volume_db = _to_db(fx * pow(clampf(v / 35.0, 0.0, 1.0), 1.3)
		* db_to_linear(wind_open_volume_db))
	# Le battement ne vit qu'autour de 90 km/h : en dessous pas assez d'air,
	# au-dessus la turbulence le noie.
	var bell := exp(-pow((v - 25.0) / 12.0, 2.0))
	_buffet.volume_db = _to_db(fx * bell * db_to_linear(buffet_volume_db))
	_road_open.volume_db = _to_db(fx * clampf(v / 30.0, 0.0, 1.0) * db_to_linear(road_open_volume_db))
	# Manivelle : tant que l'ouverture change. Le fondu est ASYMETRIQUE. A la
	# prise, franc : le mecanisme mord tout de suite, un fondu lent ferait
	# glisser la manivelle avant d'accrocher. A la coupure, lent : le son est un
	# train de chocs pointus, et le trancher net sur un choc s'entend comme un
	# clic. 25/s dans les deux sens hachait le son des qu'on donnait de petits
	# tours, et c'est une des sources du gresillement.
	var moving := _last_open >= 0.0 and absf(window_open - _last_open) > 0.0001
	_last_open = window_open
	var gate_rate := 18.0 if moving else 7.0
	_crank_gain = lerpf(_crank_gain, 1.0 if moving else 0.0, clampf(delta * gate_rate, 0.0, 1.0))
	_crank.volume_db = _to_db(_crank_gain * db_to_linear(crank_volume_db))

	# --- levier ---------------------------------------------------------------
	if _last_gear >= 0 and gear != _last_gear:
		_play(_shift, shift_volume_db)
		_last_event = "levier"
	_last_gear = gear

	# --- frein a main ---------------------------------------------------------
	if handbrake_on != _last_hb:
		_play(_hb_pull if handbrake_on else _hb_release, handbrake_volume_db)
		_last_event = "frein tire" if handbrake_on else "frein lache"
	_last_hb = handbrake_on


func debug_line() -> String:
	return "vitesse %5.1f m/s  route %6.1f dB (pitch %.2f)  vent bas %6.1f dB  vent haut %6.1f dB  vitre %.2f : vent %6.1f dB  battement %6.1f dB  manivelle %6.1f dB  dernier : %s" % [
		_dbg_speed, _road.volume_db, _road.pitch_scale,
		_wind_lo.volume_db, _wind_hi.volume_db,
		_dbg_open, _wind_open.volume_db, _buffet.volume_db, _crank.volume_db, _last_event]


# --------------------------------------------------------------------------

func _loop(fname: String, to_bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = -80.0
	p.bus = to_bus
	var path := DIR + fname
	if ResourceLoader.exists(path):
		var stream: AudioStreamWAV = load(path)
		# La boucle est dans le WAV (chunk smpl) ; au cas ou, on boucle tout.
		if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		p.stream = stream
	else:
		push_warning("son habitacle : %s manque, lancer tools/make_cabin_sounds.py" % path)
	add_child(p)
	return p


func _shot(fname: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.max_polyphony = 2
	var path := DIR + fname
	if ResourceLoader.exists(path):
		p.stream = load(path)
	else:
		push_warning("son habitacle : %s manque, lancer tools/make_cabin_sounds.py" % path)
	add_child(p)
	return p


func _play(p: AudioStreamPlayer, db: float) -> void:
	if p.stream == null:
		return
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-shot_pitch_spread, shot_pitch_spread)
	p.play()


func _to_db(lin: float) -> float:
	return linear_to_db(lin) if lin > 0.0001 else -80.0
