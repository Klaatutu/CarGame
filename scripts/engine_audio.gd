extends Node
##
## Son du moteur.
##
## On ne peut pas pitcher UNE boucle de 850 a 6800 tr/min : huit fois plus
## aigu, trois octaves, ca sonne comme un jouet parce que les resonances de la
## ligne d'echappement et de la caisse montent avec. Alors on a plusieurs
## boucles, synthetisees par tools/make_engine_sounds.py a des regimes fixes
## (900, 1300, 1800 ... 7000), et a chaque image :
##
##   1. on prend les deux boucles qui encadrent le regime courant ;
##   2. on les pitche pour qu'elles jouent EXACTEMENT a ce regime
##      (pitch = regime / regime_de_la_boucle), donc jamais plus de ~20 % ;
##   3. on les fond l'une dans l'autre, lineairement.
##
## Lineairement et pas "a puissance constante" : les boucles sont construites
## pour demarrer toutes sur l'explosion du cylindre 1, et elles sont toutes
## lancees a la meme image, donc elles restent en phase. Leurs impulsions
## s'additionnent, et un fondu lineaire garde l'amplitude constante.
##
## Chaque regime existe en deux couches, "on" (gaz) et "off" (frein moteur),
## fondues selon la charge, c'est-a-dire l'accelerateur lisse. Le reste est de
## la cosmetique : flottement du ralenti, rupteur qui hache, volume qui monte
## avec le regime.
##
## Pour ajouter un regime : un nombre dans RPM_POINTS du script Python, on le
## relance, et ce noeud decouvre les fichiers tout seul.
##

const DIR := "res://assets/audio/engine/"

## Les boucles sont a -15 dBFS RMS (gaz) et -19,5 (frein moteur) ; avec ce
## reglage le ralenti sort vers -32 dBFS et le plein gaz haut dans les tours
## vers -18, ce qui laisse de la place pour le reste.
@export var volume_db := -4.0
## Vitesse a laquelle la charge suit l'accelerateur (1/s). L'attaque est plus
## vive que le relachement : on entend le moteur se charger avant que le
## regime ne bouge, et il se "vide" un peu plus mollement.
@export var load_attack := 10.0
@export var load_release := 5.0
## Flottement du regime, en fraction. Rend le ralenti vivant ; presque nul a
## haut regime. 0 pour une boucle parfaitement stable.
@export var wobble := 0.007
## Zone du rupteur : a moins de ce nombre de tours de la ligne rouge, la charge
## suit l'accelerateur sans lissage, pour que la coupure d'allumage (qui vient
## de la physique, car.gd) hache net au lieu de trembler.
@export var limiter_band := 300.0

@export_group("Vitres ouvertes")
## La couche "out" (l'echappement entendu de dehors, le rapeux que la glace
## retirait) s'ajoute selon l'ouverture des vitres, et plus fort sous charge.
@export var window_volume_db := -7.0
## Et tout le moteur monte un peu : la glace n'isole plus.
@export var window_boost := 0.25

var idle_rpm := 850.0
var redline_rpm := 6800.0

var _points: Array[float] = []
var _on: Array[AudioStreamPlayer] = []
var _off: Array[AudioStreamPlayer] = []
var _out: Array[AudioStreamPlayer] = []     # null si la couche manque
var _load := 0.0
var _wobble_target := 0.0
var _wobble_val := 0.0
var _wobble_timer := 0.0
var _dbg_cut := false
# Pour le banc d'essai.
var _dbg_rpm := 0.0
var _dbg_i := 0
var _dbg_t := 0.0


func _ready() -> void:
	_load_loops()
	# Tous lances a la meme image : c'est ce qui les garde en phase.
	for p in _on:
		p.play()
	for p in _off:
		p.play()
	for p in _out:
		if p:
			p.play()


func _exit_tree() -> void:
	# Sinon les lectures restent accrochees au serveur audio a la sortie et
	# Godot se plaint de ressources encore en usage.
	for p in _on:
		p.stop()
	for p in _off:
		p.stop()
	for p in _out:
		if p:
			p.stop()


## A appeler a chaque image depuis la voiture.
## engaged : embrayage relache ET un rapport passe ; sinon le moteur tourne a
## vide et la charge est plus faible a accelerateur egal.
## limiter_cut : coupure d'allumage en cours (car.gd) ; la charge tombe a zero.
## window_open : ouverture acoustique des vitres, 0 fermees, 1 grande ouverte.
func update(rpm: float, throttle: float, engaged: bool, delta: float,
		limiter_cut := false, window_open := 0.0) -> void:
	if _points.size() < 2:
		return

	# --- charge ----------------------------------------------------------
	var target := throttle * (1.0 if engaged else 0.6)
	if limiter_cut:
		target = 0.0
	# Pres du rupteur, la charge suit sans lissage : la coupure doit hacher
	# net, pas trembler.
	var armed := limiter_cut or (throttle > 0.0 and rpm > redline_rpm - limiter_band)
	var rate := 40.0 if armed else (load_attack if target > _load else load_release)
	_load = lerpf(_load, target, clampf(rate * delta, 0.0, 1.0))
	_dbg_cut = limiter_cut

	# --- flottement ------------------------------------------------------
	_wobble_timer -= delta
	if _wobble_timer <= 0.0:
		_wobble_timer = randf_range(0.1, 0.25)
		_wobble_target = randf_range(-1.0, 1.0)
	_wobble_val = lerpf(_wobble_val, _wobble_target, clampf(8.0 * delta, 0.0, 1.0))
	var norm := clampf((rpm - idle_rpm) / (redline_rpm - idle_rpm), 0.0, 1.0)
	var r := rpm * (1.0 + wobble * _wobble_val * lerpf(1.0, 0.25, norm))

	# --- les deux boucles qui encadrent le regime -------------------------
	var i := 0
	while i < _points.size() - 2 and r >= _points[i + 1]:
		i += 1
	var t := clampf(inverse_lerp(_points[i], _points[i + 1], r), 0.0, 1.0)

	# --- volumes -----------------------------------------------------------
	# Vitre ouverte : une fente suffit a laisser passer le pot, d'ou la
	# puissance 0,6 ; la couche "dehors" est plus presente sous charge.
	var open_fx := pow(clampf(window_open, 0.0, 1.0), 0.6)
	var master := db_to_linear(volume_db) * lerpf(0.5, 1.0, norm) * lerpf(0.72, 1.0, _load) \
		* (1.0 + window_boost * open_fx)
	var g_on := _load * master
	var g_off := (1.0 - _load) * master
	var g_out := open_fx * master * lerpf(0.4, 1.0, _load) * db_to_linear(window_volume_db)
	for j in _points.size():
		var g := 0.0
		if j == i:
			g = 1.0 - t
		elif j == i + 1:
			g = t
		var pitch := clampf(r / _points[j], 0.05, 4.0)
		_on[j].pitch_scale = pitch
		_off[j].pitch_scale = pitch
		_on[j].volume_db = _to_db(g * g_on)
		_off[j].volume_db = _to_db(g * g_off)
		if _out[j]:
			_out[j].pitch_scale = pitch
			_out[j].volume_db = _to_db(g * g_out)

	_dbg_rpm = r
	_dbg_i = i
	_dbg_t = t


func loop_rpms() -> Array[float]:
	return _points


## Pour le banc d'essai : la boucle a-t-elle bien ete detectee a l'import ?
func loop_info() -> String:
	if _on.is_empty():
		return "aucune boucle"
	var s: AudioStreamWAV = _on[0].stream
	return "mode %d, de %d a %d, %.3f s, format %d (0 = PCM 8 bits, 1 = PCM 16 bits, 3 = QOA), %d octets" % [
		s.loop_mode, s.loop_begin, s.loop_end, s.get_length(), s.format, s.data.size()]


func debug_line() -> String:
	if _points.size() < 2:
		return "son moteur : aucune boucle"
	return "regime %4d  charge %.2f%s  boucles %d/%d (t=%.2f)  pitch %.3f/%.3f  on %.1f dB  off %.1f dB  dehors %.1f dB" % [
		int(round(_dbg_rpm)), _load, " COUPE" if _dbg_cut else "      ",
		int(_points[_dbg_i]), int(_points[_dbg_i + 1]), _dbg_t,
		_on[_dbg_i].pitch_scale, _on[_dbg_i + 1].pitch_scale,
		_on[_dbg_i].volume_db, _off[_dbg_i].volume_db,
		_out[_dbg_i].volume_db if _out[_dbg_i] else -80.0]


# --------------------------------------------------------------------------

## Decouvre les boucles dans DIR : engine_on_0900.wav, engine_off_0900.wav...
## En export, seuls les .import sont listes, d'ou le trim_suffix.
func _load_loops() -> void:
	var found := {}
	for f in DirAccess.get_files_at(DIR):
		var fname: String = f.trim_suffix(".import")
		if not fname.ends_with(".wav"):
			continue
		var parts := fname.trim_suffix(".wav").split("_")
		if parts.size() != 3 or parts[0] != "engine" or not parts[2].is_valid_int():
			continue
		var r := float(parts[2])
		if not found.has(r):
			found[r] = {}
		found[r][parts[1]] = DIR + fname

	var rpms: Array = found.keys()
	rpms.sort()
	for r in rpms:
		if not (found[r].has("on") and found[r].has("off")):
			push_warning("son moteur : il manque une couche a %d tr/min" % int(r))
			continue
		_points.append(r)
		_on.append(_make_player(found[r]["on"]))
		_off.append(_make_player(found[r]["off"]))
		# La couche "dehors" est facultative : sans elle, la vitre ouverte ne
		# change que le vent.
		_out.append(_make_player(found[r]["out"]) if found[r].has("out") else null)
	if _points.size() < 2:
		push_warning("son moteur : pas assez de boucles dans %s, lancer tools/make_engine_sounds.py" % DIR)


func _make_player(path: String) -> AudioStreamPlayer:
	var stream: AudioStreamWAV = load(path)
	# Le WAV porte sa boucle dans un chunk "smpl" que Godot detecte a l'import.
	# Si un jour elle est perdue, on boucle tout le fichier.
	if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	return p


func _to_db(lin: float) -> float:
	return linear_to_db(lin) if lin > 0.0001 else -80.0
