extends Node
##
## LE SOMMEIL — la jauge que le jeu ne montre pas.
##
## Pas de barre a l'ecran : l'effet EST la jauge. La vigilance descend en
## silence, puis la route se dedouble (les paupieres se ferment par vagues,
## la tete pique), puis tout se ferme — et derriere ce noir-la, main.gd
## echange le monde : on se reveille dans le cauchemar. Voir la machine
## d'a-cote, "doom", qui a fourni le patron des paupieres (l'assombrissement
## pulse de l'etranglement).
##
## LA FORMULE EST UN PRODUIT DE CIRCONSTANCES.
## -------------------------------------------------------------------------
## Une base (une jauge pleine dure 4 min), multipliee par ce qui endort —
## la nuit profonde (le facteur circadien lit daycycle.night_amount()), la
## lenteur, la MONOTONIE (vitesse etale ET volant immobile : l'autoroute a
## 2 h du matin) — et divisee par ce qui reveille : les vitres ouvertes, la
## vitesse, la radio (posee de l'exterieur, radio_factor). Le produit des
## remedes est plafonne : on ne conduit pas une nuit entiere a coups de
## courants d'air. Boire (drink_boost) rend d'un coup, avec des rendements
## qui s'ecroulent si on enchaine — la dette de cafeine.
##
## Chaque remede a sa contrepartie ailleurs : les vitres ouvertes sont une
## porte pour le mille-pattes (centipede.gd, poids x14), la vitesse et la
## radio deplairont aux clients. Ce fichier ne juge pas : il compte.
##

signal fell_asleep

## La voiture et le cycle : poses par main.gd avant add_child.
var car
var daycycle

@export_group("La jauge")
## Duree d'une jauge pleine sans rien faire, en secondes (facteurs a 1).
@export var full_span := 240.0
## Facteur circadien : de jour -> nuit profonde.
@export var circ_day := 0.8
@export var circ_night := 1.5
## La monotonie : vitesse etale et volant immobile pendant ce temps...
@export var mono_after := 10.0
## ... et ce que ca coute.
@export var mono_factor := 1.6
## Sous 40 km/h, la torpeur (villes, bouchons, arrets).
@export var slow_factor := 1.3
## Les remedes : vitres ouvertes (> 0,4), vitesse (> 90 km/h), et le plancher
## de leur produit — les courants d'air ne remplacent pas une nuit de sommeil.
@export var windows_factor := 0.7
@export var speed_factor := 0.75
@export var remedy_floor := 0.25

@export_group("Boire")
## Ce que rend chaque canette, par marque (can.gd : drink).
@export var boost_nosleep := 0.28
@export var boost_cariboon := 0.22
@export var boost_kombo := 0.18
## En dessous de cet ecart entre deux canettes, la deuxieme rend x0,6.
@export var caffeine_window := 90.0

@export_group("Les paupieres")
## Seuil de vigilance sous lequel elles tombent, et la periode des fermetures
## (de lente a pressante a mesure que la jauge s'ecrase).
@export var lids_below := 0.35
@export var lid_period_slack := 9.0
@export var lid_period_urgent := 3.0
## Duree d'une fermeture, et le noir de la toute derniere (inarretable).
@export var lid_close_time := 0.9
@export var final_close_time := 1.4

## La jauge, 0..1. Les bancs l'ecrivent pour forcer un etat.
var vigilance := 1.0
## Gele tout (cauchemar, etranglement, fins de partie) : la jauge ne bouge
## plus, les paupieres se taisent, la camera est rendue.
var suspended := false:
	set(v):
		var was := suspended
		suspended = v
		if v and not was and not _dying:
			_release_camera()
## Pose par la radio (J3) : 1.0 sans musique, 0.55 a fond.
var radio_factor := 1.0
## Combien de fois on s'est endormi cette nuit. Le portail du cauchemar
## s'eloigne a chaque fois (main.gd).
var times_slept := 0

var _mono_t := 0.0
var _speed_avg := 0.0
var _since_drink := 1.0e9
var _lid_t := 0.0                     ## horloge de la fermeture en cours
var _lid_period := 9.0
var _dying := false                   ## la derniere fermeture est partie
var _die_t := 0.0
var _warned := [false, false, false]  ## messages aux seuils 0,5 / 0,35 / 0,2
var _lids: ColorRect


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SleepLids"
	layer.layer = 2
	add_child(layer)
	_lids = ColorRect.new()
	_lids.name = "Lids"
	_lids.color = Color(0.0, 0.0, 0.0, 0.0)
	_lids.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lids.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_lids)


func _process(delta: float) -> void:
	_since_drink += delta
	if _dying:
		_die(delta)
		return
	if suspended:
		return

	vigilance = clampf(vigilance - drain_rate() * delta, 0.0, 1.0)
	_warn()
	_lid_pose(delta)

	if vigilance <= 0.0:
		# La derniere fermeture : rien ne la rouvre. Derriere elle, main.gd
		# echangera le monde — fell_asleep part quand le noir est complet.
		_dying = true
		_die_t = 0.0


## Le debit courant de la jauge, par seconde. Public : le banc compare la
## jauge a l'integrale de ce que cette fonction annonce — la jauge doit
## suivre sa propre formule, pas une deuxieme ecrite ailleurs.
func drain_rate() -> float:
	return (1.0 / full_span) * _sleepers() * _remedies()


## Ce qui endort : circadien, lenteur, monotonie.
func _sleepers() -> float:
	var f: float = lerpf(circ_day, circ_night, daycycle.night_amount())
	var v: float = absf(car.speed)
	if v < 11.1:
		f *= slow_factor
	if _mono_t >= mono_after:
		f *= mono_factor
	return f


## Ce qui reveille, produit plafonne.
func _remedies() -> float:
	var f := radio_factor
	if car.window_openness() > 0.4:
		f *= windows_factor
	if absf(car.speed) > 25.0:
		f *= speed_factor
	return maxf(f, remedy_floor)


## La monotonie se mesure a l'ecart entre la vitesse et sa propre moyenne
## glissante, volant compris : une vitesse ETALE au volant IMMOBILE. Freiner,
## relancer ou tourner remet le compteur a zero — conduire reveille.
func _watch_monotony(delta: float) -> void:
	var v: float = absf(car.speed)
	_speed_avg = lerpf(_speed_avg, v, clampf(delta * 0.2, 0.0, 1.0))
	if absf(v - _speed_avg) < 1.5 and absf(car.steer) < 0.04:
		_mono_t += delta
	else:
		_mono_t = 0.0


func _physics_process(delta: float) -> void:
	if not suspended and not _dying:
		_watch_monotony(delta)


## Les paupieres. Sous le seuil : des fermetures periodiques dont la periode
## se resserre et le noir s'epaissit — le patron exact de l'etranglement
## (main.gd, _process_doom), au service d'un autre etouffement.
func _lid_pose(delta: float) -> void:
	if vigilance >= lids_below:
		_lids.color.a = move_toward(_lids.color.a, 0.0, delta * 2.0)
		_release_camera()
		return
	var urge := clampf((lids_below - vigilance) / (lids_below - 0.05), 0.0, 1.0)
	_lid_period = lerpf(lid_period_slack, lid_period_urgent, urge)
	_lid_t += delta
	if _lid_t >= _lid_period:
		_lid_t = 0.0
	# L'enveloppe d'une fermeture : un battement en debut de periode, le
	# reste du temps un voile de fond qui monte avec l'urgence.
	var e := 0.0
	if _lid_t < lid_close_time:
		e = sin(PI * _lid_t / lid_close_time)
	var peak := lerpf(0.35, 0.9, urge)
	_lids.color.a = clampf(0.22 * urge + peak * e, 0.0, 1.0)
	# La tete pique avec la fermeture, et derive un peu : le meme canal que
	# l'etranglement (h/v_offset), jamais en meme temps que lui — main gele
	# ce systeme des que doom_mode s'allume.
	car.cam.v_offset = -0.055 * e * urge
	car.cam.h_offset = sin(_lid_t * 3.1) * 0.008 * urge


func _release_camera() -> void:
	if car != null and car.cam != null:
		car.cam.v_offset = 0.0
		car.cam.h_offset = 0.0


## La derniere fermeture, inarretable. Noir complet -> fell_asleep, une fois.
func _die(delta: float) -> void:
	_die_t += delta
	_lids.color.a = clampf(_die_t / final_close_time, 0.0, 1.0)
	if _die_t >= final_close_time:
		_dying = false
		_release_camera()
		times_slept += 1
		fell_asleep.emit()


## Rouvre les yeux (le reveil du cauchemar) : le noir se leve en `dur`.
func open_lids(dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_lids, "color:a", 0.0, dur)


## Ferme tout de suite (les transitions que main choregraphie).
func close_lids() -> void:
	_lids.color.a = 1.0


func lid_alpha() -> float:
	return _lids.color.a


## Une canette bue (can.gd, via le geste DRINKING — J3). Rendements
## decroissants : la deuxieme dans la fenetre de cafeine rend x0,6.
func drink_boost(kind: String) -> void:
	var boost := boost_kombo
	match kind:
		"nosleep":
			boost = boost_nosleep
		"cariboon":
			boost = boost_cariboon
	if _since_drink < caffeine_window:
		boost *= 0.6
	_since_drink = 0.0
	vigilance = clampf(vigilance + boost, 0.0, 1.0)


## Les messages aux seuils, une fois chacun tant qu'on ne remonte pas.
func _warn() -> void:
	var marks := [0.5, 0.35, 0.2]
	var texts := ["La route se dedouble", "Tes paupieres pesent", "Tu pars"]
	for i in 3:
		if vigilance < marks[i] and not _warned[i]:
			_warned[i] = true
			if car.has_method("_show_flash"):
				car._show_flash(texts[i])
		elif vigilance > marks[i] + 0.06:
			_warned[i] = false
