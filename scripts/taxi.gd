extends Node
##
## LES COURSES — le metier, et la boucle qui se ferme.
##
## Le telephone sonne : quelqu'un attend dans une ville de la carte, veut
## aller dans une autre, et paie au bareme — 2 EUR de prise en charge plus
## 0,90 EUR du kilometre de plus court chemin. Accepter se fait SUR L'ECRAN
## (phone_apps.gd) : pas de touche magique, il faut lacher une main du
## volant. Le client est ABSTRAIT — une portiere qui s'ouvre, un poids qui
## s'assoit dans les suspensions, des repliques — mais il a un avis, et
## l'avis reste : cinq etoiles, dix derniers, la moyenne en vitrine.
##
## Le CONFORT est la contrepartie de tout ce qui tient eveille : la radio
## forte, les vitres ouvertes, la vitesse — echantillonne a 2 Hz pendant la
## course, chaque seuil depasse fait parler le client UNE fois (l'arbitrage
## doit se lire), et la note tombe a l'arrivee : 5 moins l'inconfort
## normalise par la duree, arrondie a la demi-etoile. Le pourboire suit par
## palier — carte : au centime ; especes : meme esperance, plus de variance.
##
## S'endormir avec un client a bord ANNULE la course : une etoile, l'avis
## le dit, et l'argent n'arrive jamais. Le cauchemar n'a pas de reseau —
## aucune offre n'y sonne, celle en cours s'eteint.
##
## La machine a etats, en toutes lettres :
##   idle -> offer -> accepted -> pickup_zone -> boarding -> riding
##        -> drop_zone -> payment -> rated -> idle
##
## Le taxi ne touche les portieres qu'en monde normal — dans le cauchemar
## elles appartiennent a l'etrangleur.
##

const MapScript := preload("res://scripts/map.gd")

## Le bareme : prise en charge, et le kilometre de plus court chemin.
const FARE_BASE := 2.0
const FARE_PER_KM := 0.90
## Une offre attend tant de secondes avant d'aller voir un autre taxi.
const OFFER_WINDOW := 25.0
## Entre deux offres, et apres un refus : le silence du standard.
const LULL_MIN := 20.0
const LULL_MAX := 35.0
## Pas d'offre pour une ville qu'on est deja en train de traverser : il
## reste au moins ca de metres avant le panneau, sinon on repropose plus tard.
const OFFER_MIN_AHEAD := 220.0

## La portiere passager : angle d'ouverture, et le poids du client qui
## s'assoit — un enfoncement de suspension SOUS le seuil de 2,4 g des objets
## poses (prop.gd) : les canettes ne sautent pas quand quelqu'un monte.
const DOOR_OPEN := 65.0
const SIT_IMPACT := Vector3(0.0, -3.2, 0.0)
const RISE_IMPACT := Vector3(0.0, 2.0, 0.0)

## Les seuils du confort, et le poids de chaque depassement par echantillon
## (2 Hz). La note : norm = points / (echantillons x 1,5), etoiles = 5 - 4n.
const SPEED_MAX := 29.2         # m/s, 105 km/h
const LATERAL_MAX := 4.5        # m/s^2 dans les virages
const JOLT_MAX := 6.0           # m/s^2 d'a-coup longitudinal
const WINDOW_MAX := 0.4         # ouverture des vitres
const OFFROAD_AT := 5.8         # m de l'axe : au-dela, c'est le champ
const COMFORT_FULL := 1.5       # points/echantillon qui valent 1 etoile

## La zone d'arret d'une ville (town.gd pose le pave a droite du panneau) :
## la voiture arretee dedans, en repere ville — x a droite, z devant.
const ZONE_X_MIN := 0.8
const ZONE_X_MAX := 9.5
const ZONE_Z_MIN := -48.0
const ZONE_Z_MAX := -6.0
const STOPPED_AT := 0.4         # m/s : en dessous, on est arrete

## Les clients de la nuit. Des noms, pas des corps.
const NAMES := ["Mme Verdier", "M. Anselme", "Lucie", "Abel", "Nadia",
	"M. Tissier", "Mme Onfray", "Ferenc", "Le veilleur", "Mme Capel",
	"Iris", "M. Delatre"]

## Ce que chaque seuil fait dire au client, UNE fois par course.
const COMPLAINTS := {
	"speed": "On n'est pas presses, hein.",
	"lateral": "Doucement dans les virages...",
	"jolt": "Aie.",
	"radio": "Vous pouvez baisser un peu ?",
	"windows": "On gele, la. Vous pouvez remonter ?",
	"offroad": "C'est plus la route, ca !",
	"stall": "Ca repart ?",
}

## La voiture et la route (poses par main.gd avant add_child).
var car: Node3D
var road: Node3D

## Le standard ne sonne qu'en partie reelle : les bancs qui demarrent le
## monde normal (maptest, sleeptest) gardent un telephone muet.
var enabled := false

var state := "idle"
## L'offre en attente : {from, to, route, price, who, left}.
var offer := {}
## La course en cours (l'offre acceptee, plus le confort qui s'accumule).
var fare := {}
## La recette de la nuit, en euros, arrondie au centime a chaque encaissement.
var money := 0.0
## Les dix derniers avis, le plus recent en tete : {stars, text, who}.
var reviews: Array = []

## Banc d'essai : force "cb" ou "cash" pour rendre le pourboire previsible.
var pay_override := ""

var _cooldown := 12.0           # avant la premiere offre, le temps d'entrer
var _seq := 0.0                 # l'horloge des sequences (embarquement, paie)
var _rated_t := 0.0
var _sample_t := 0.0
var _prev_yaw := 0.0
var _prev_speed := 0.0

var _say_label: Label
var _say_t := 0.0
var _door_snd: AudioStreamPlayer
var _tpe_snd: AudioStreamPlayer
var _cash_snd: AudioStreamPlayer
var _phone_node: Node


func _ready() -> void:
	road.town_reached.connect(_on_town_reached)
	var m := get_parent()
	if m != null and "sleep" in m and m.sleep != null:
		m.sleep.fell_asleep.connect(_on_fell_asleep)
	_build_hud()
	_door_snd = _sound("res://assets/audio/taxi/door.wav", -4.0)
	_tpe_snd = _sound("res://assets/audio/taxi/tpe.wav", -8.0)
	_cash_snd = _sound("res://assets/audio/taxi/cash.wav", -8.0)


func _process(delta: float) -> void:
	if _say_t > 0.0:
		_say_t -= delta
		_say_label.modulate.a = clampf(_say_t / 0.6, 0.0, 1.0)
	if not enabled or car == null:
		return
	var normal: bool = _world_mode() == "normal"

	match state:
		"idle":
			if normal and _phone_ok():
				_cooldown -= delta
				if _cooldown <= 0.0:
					_spawn_offer()
		"offer":
			offer["left"] -= delta
			if not normal or not _phone_ok():
				_drop_offer()               # pas de reseau : l'offre s'eteint
			elif offer["left"] <= 0.0:
				_drop_offer()
				_say("", "Course manquee.")
		"pickup_zone":
			if _zone_stop(fare["from"]):
				_begin_boarding()
			elif _pickup_missed():
				_cancel_fare("%s : \"Tant pis, je me suis debrouille.\"" % fare["who"], false)
		"boarding":
			_run_boarding(delta)
		"riding":
			_sample_comfort(delta)
		"drop_zone":
			_sample_comfort(delta)
			if _zone_stop(fare["to"]):
				_begin_payment()
			elif _drop_missed():
				_say(fare["who"], "C'etait la ! Bon, a la prochaine ville alors.")
				fare["points"] += 3.0
				fare["over"] = true
				state = "riding"
		"payment":
			_run_payment(delta)
		"rated":
			_rated_t -= delta
			if _rated_t <= 0.0:
				state = "idle"
				_cooldown = randf_range(LULL_MIN, LULL_MAX)


# --------------------------------------------------------------------------
# Les offres
# --------------------------------------------------------------------------

## Une offre part de la ville VERS LAQUELLE on roule (pas de demi-tour dans
## cette nuit), vers une ville a une ou deux aretes — jamais en repassant par
## celle d'ou l'on vient. Le prix est au bareme, fixe a l'avance : se perdre
## en chemin ne se facture pas.
func _spawn_offer() -> void:
	var m := get_parent()
	if m == null or not "nav" in m or m.nav.is_empty():
		_cooldown = 6.0
		return
	var from: String = m.nav["to"]
	var back: String = m.nav["at"]
	# Trop pres du panneau : le client n'aurait pas le temps de descendre.
	var ahead: float = MapScript.edge_length(back, from) * (1.0 - m.nav_progress())
	if ahead < OFFER_MIN_AHEAD:
		_cooldown = 6.0
		return
	var picks := []
	for t in MapScript.towns():
		if t == from or t == back:
			continue
		var r := MapScript.path(from, t)
		if r.size() >= 2 and r.size() <= 3 and r[1] != back:
			picks.append(r)
	if picks.is_empty():
		_cooldown = 6.0
		return
	var route: Array = picks[randi() % picks.size()]
	var price := roundf((FARE_BASE
		+ FARE_PER_KM * MapScript.path_length(route) / 1000.0) * 100.0) / 100.0
	offer = {"from": from, "to": route.back(), "route": route, "price": price,
		"who": NAMES[randi() % NAMES.size()], "left": OFFER_WINDOW}
	state = "offer"
	if _phone() != null:
		_phone().ring()


## Le bouton ACCEPTER de l'ecran (phone_apps.gd). L'itineraire du client
## devient celui du GPS : les Y suivront sa route.
func accept_offer() -> void:
	if state != "offer":
		return
	if _phone() != null:
		_phone().stop_ring()
	fare = offer.duplicate()
	fare["points"] = 0.0
	fare["samples"] = 0
	fare["flags"] = {}
	fare["over"] = false
	offer = {}
	var m := get_parent()
	if m != null and "nav" in m:
		m.nav["route"] = MapScript.path(fare["from"], fare["to"])
	# Le panneau deja passe pendant qu'on hesitait : le client attend la, on
	# est dans la traversee — sinon on roule vers lui.
	var there: bool = m != null and "nav" in m and not m.nav.is_empty() \
		and m.nav["at"] == fare["from"]
	state = "pickup_zone" if there else "accepted"
	_say("", "Course acceptee : %s, a %s." % [fare["who"], fare["from"]])


func refuse_offer() -> void:
	if state != "offer":
		return
	_drop_offer()
	_say("", "Course refusee.")


func _drop_offer() -> void:
	if _phone() != null:
		_phone().stop_ring()
	offer = {}
	state = "idle"
	_cooldown = randf_range(LULL_MIN, LULL_MAX)


# --------------------------------------------------------------------------
# La ville, la zone, la portiere
# --------------------------------------------------------------------------

func _on_town_reached(id: String) -> void:
	match state:
		"accepted":
			if id == fare["from"]:
				state = "pickup_zone"
				_say("", "%s attend — zone d'arret a droite, au pas." % fare["who"])
		"riding":
			if id == fare["to"] or fare["over"]:
				fare["to"] = id if fare["over"] else fare["to"]
				state = "drop_zone"
				_say("", "Deposez %s — zone d'arret a droite." % fare["who"])


## Arrete dans la zone d'arret de LA ville attendue. Repere ville : x a
## droite du panneau, z file devant — le pave de town.gd, avec de la marge.
func _zone_stop(town_id: String) -> bool:
	var t: Node3D = road.town
	if t == null or not t.visible or t.town_name != town_id:
		return false
	if absf(car.speed) > STOPPED_AT:
		return false
	var l: Vector3 = t.global_transform.affine_inverse() * car.global_position
	return l.x > ZONE_X_MIN and l.x < ZONE_X_MAX \
		and l.z > ZONE_Z_MIN and l.z < ZONE_Z_MAX


## Le client de la prise en charge ne court pas apres la voiture : la ville
## eteinte ou remplacee, c'est rate.
func _pickup_missed() -> bool:
	var t: Node3D = road.town
	return t == null or not t.visible or t.town_name != fare["from"]


func _drop_missed() -> bool:
	var t: Node3D = road.town
	return t == null or not t.visible or t.town_name != fare["to"]


## L'embarquement, en secondes de sequence : le client arrive, la portiere
## s'ouvre, le poids s'assoit, la portiere claque. Tout est pilote par _seq
## — les grosses images n'avalent que du temps, jamais un jalon.
func _begin_boarding() -> void:
	state = "boarding"
	_seq = 0.0
	_say("", "%s arrive..." % fare["who"])


func _run_boarding(delta: float) -> void:
	var was := _seq
	_seq += delta
	if _world_mode() == "normal":
		car.cabin.set_door("R", deg_to_rad(DOOR_OPEN) * _door_curve(_seq, 1.0, 1.9, 2.5, 3.1))
	if _crossed(was, _seq, 2.3):
		car.impact(SIT_IMPACT)
	if _crossed(was, _seq, 3.1):
		_door_snd.play()
	if _seq >= 3.4:
		state = "riding"
		_sample_t = 0.0
		_prev_yaw = car.rotation.y
		_prev_speed = car.speed
		_say(fare["who"], "Bonsoir. %s, s'il vous plait." % fare["to"])


## Le paiement : la machine ou les billets, l'argent au centime, puis la
## portiere — et la caisse remonte quand le poids descend.
func _begin_payment() -> void:
	state = "payment"
	_seq = 0.0
	var stars := _stars()
	fare["stars"] = stars
	var method: String = pay_override
	if method == "":
		method = "cb" if randf() < 0.6 else "cash"
	fare["method"] = method
	var tip := _tip_for(stars, fare["price"], method)
	fare["tip"] = tip


func _run_payment(delta: float) -> void:
	var was := _seq
	_seq += delta
	if _crossed(was, _seq, 0.3):
		if fare["method"] == "cb":
			_tpe_snd.play()
		else:
			_cash_snd.play()
		_say("", "%s paie %.2f EUR (%s)." % [fare["who"], fare["price"],
			"carte" if fare["method"] == "cb" else "especes"])
	if _crossed(was, _seq, 1.2):
		money = roundf((money + fare["price"] + fare["tip"]) * 100.0) / 100.0
	if _world_mode() == "normal":
		car.cabin.set_door("R", deg_to_rad(DOOR_OPEN) * _door_curve(_seq, 1.6, 2.4, 3.0, 3.6))
	if _crossed(was, _seq, 2.8):
		car.impact(RISE_IMPACT)
	if _crossed(was, _seq, 3.6):
		_door_snd.play()
	if _seq >= 4.0:
		_finish_ride()


## L'angle de portiere d'une sequence : 0 avant o0, ouvre de o0 a o1, tient,
## referme de c0 a c1. Une seule fonction pour monter et descendre.
func _door_curve(t: float, o0: float, o1: float, c0: float, c1: float) -> float:
	if t <= o0:
		return 0.0
	if t < o1:
		return (t - o0) / (o1 - o0)
	if t <= c0:
		return 1.0
	if t < c1:
		return 1.0 - (t - c0) / (c1 - c0)
	return 0.0


func _crossed(before: float, now: float, mark: float) -> bool:
	return before < mark and now >= mark


# --------------------------------------------------------------------------
# Le confort, la note, l'avis
# --------------------------------------------------------------------------

## Deux fois par seconde, le client juge. Chaque seuil depasse pese des
## points ; le premier depassement de chacun le fait PARLER — l'arbitrage
## veille/confort doit se lire dans l'habitacle, pas dans un tableau.
## Les taux (virage, a-coup) se mesurent PAR IMAGE : une grosse image lisse
## sur sa duree, elle n'invente pas d'a-coup — les echantillons ne font que
## peser ce que l'image a mesure.
func _sample_comfort(delta: float) -> void:
	var yaw: float = car.rotation.y
	var lateral: float = absf(wrapf(yaw - _prev_yaw, -PI, PI)) \
		/ maxf(delta, 1.0e-4) * absf(car.speed)
	var jolt: float = absf(car.speed - _prev_speed) / maxf(delta, 1.0e-4)
	_prev_yaw = yaw
	_prev_speed = car.speed
	_sample_t += delta
	while _sample_t >= 0.5:
		_sample_t -= 0.5
		fare["samples"] += 1
		_judge("speed", car.speed > SPEED_MAX, 1.0)
		_judge("lateral", lateral > LATERAL_MAX, 1.0)
		_judge("jolt", jolt > JOLT_MAX, 1.5)
		_judge("radio", car.radio != null and car.radio.loud(), 0.6)
		_judge("windows", car.window_openness() > WINDOW_MAX, 0.4)
		_judge("offroad", road._closest_dist(road._pos, car.global_position) > OFFROAD_AT, 1.5)
		_judge("stall", car.stalled, 1.5)


func _judge(what: String, bad: bool, weight: float) -> void:
	if not bad:
		return
	fare["points"] += weight
	if not fare["flags"].has(what):
		fare["flags"][what] = 0.0
		_say(fare["who"], COMPLAINTS[what])
	fare["flags"][what] += weight


## La note : 5 moins l'inconfort moyen, a la demi-etoile, plancher 1.
func _stars() -> float:
	var n: int = maxi(fare["samples"], 1)
	var norm: float = clampf(fare["points"] / (float(n) * COMFORT_FULL), 0.0, 1.0)
	return clampf(roundf((5.0 - 4.0 * norm) * 2.0) / 2.0, 1.0, 5.0)


## Le pourboire par palier. Carte : le montant exact. Especes : la meme
## esperance, mais la piece qu'on a — variance, et arrondi aux 10 centimes.
func _tip_for(stars: float, price: float, method: String) -> float:
	var rate := 0.0
	if stars >= 4.5:
		rate = 0.15
	elif stars >= 3.5:
		rate = 0.08
	elif stars >= 2.5:
		rate = 0.03
	var tip: float = price * rate
	if method == "cash":
		tip = roundf(tip * randf_range(0.5, 1.5) * 10.0) / 10.0
	return roundf(tip * 100.0) / 100.0


func _finish_ride() -> void:
	var stars: float = fare["stars"]
	_push_review(stars, _review_text(stars), fare["who"])
	_say("", "Note : %s.  Pourboire : %.2f EUR." % [_stars_text(stars), fare["tip"]])
	fare = {}
	state = "rated"
	_rated_t = 4.0


## L'avis dit le palier, et la plainte DOMINANTE s'il y en a une : le client
## se souvient de ce qui l'a le plus derange.
func _review_text(stars: float) -> String:
	var text := "A eviter."
	if stars >= 4.5:
		return "Conduite douce, trajet direct. Rien a redire."
	elif stars >= 3.5:
		text = "Bon trajet."
	elif stars >= 2.5:
		text = "Correct, sans plus."
	elif stars >= 1.5:
		text = "Conduite rude, client malmene."
	var notes := {"speed": "Trop vite.", "lateral": "Secoue dans les virages.",
		"jolt": "Des a-coups tout du long.", "radio": "La radio, quand meme...",
		"windows": "Et ce froid.", "offroad": "On a quitte la route !",
		"stall": "Cale en pleine nuit."}
	var worst := ""
	var wp := 0.0
	for what in fare["flags"]:
		if fare["flags"][what] > wp:
			wp = fare["flags"][what]
			worst = what
	return text if worst == "" else text + " " + notes[worst]


func _push_review(stars: float, text: String, who: String) -> void:
	reviews.push_front({"stars": stars, "text": text, "who": who})
	if reviews.size() > 10:
		reviews.resize(10)


func stars_avg() -> float:
	if reviews.is_empty():
		return 0.0
	var s := 0.0
	for r in reviews:
		s += r["stars"]
	return s / float(reviews.size())


static func _stars_text(stars: float) -> String:
	return ("%.1f/5" % stars).replace(".", ",")


# --------------------------------------------------------------------------
# S'endormir, annuler
# --------------------------------------------------------------------------

## La jauge est arrivee au bout (sleep.gd) : le monde bascule (main.gd a la
## main), et la course ne survit pas. Client a bord : une etoile, et l'avis
## restera. La portiere se referme quoi qu'il arrive — l'etrangleur ne doit
## pas la trouver ouverte en heritant du monde.
func _on_fell_asleep() -> void:
	match state:
		"offer":
			_drop_offer()
		"accepted", "pickup_zone", "boarding":
			_cancel_fare("Course annulee.", false)
		"riding", "drop_zone", "payment":
			_cancel_fare("%s : \"VOUS DORMIEZ !\"" % fare["who"], true)


func _cancel_fare(message: String, rated_one: bool) -> void:
	if rated_one:
		_push_review(1.0, "S'est endormi au volant. Course abandonnee.", fare["who"])
	car.cabin.set_door("R", 0.0)
	var m := get_parent()
	if m != null and "nav" in m and not m.nav.is_empty():
		m.nav["route"] = []
	fare = {}
	state = "idle"
	_cooldown = randf_range(LULL_MIN, LULL_MAX)
	_say("", message)


# --------------------------------------------------------------------------
# Les repliques, les sons, les maillons
# --------------------------------------------------------------------------

## La voix du client (et du standard) : une ligne au bas de l'ecran, qui
## s'efface seule. Couche 1, comme le reste du HUD de conduite.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_say_label = Label.new()
	_say_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_say_label.offset_left = -340.0
	_say_label.offset_right = 340.0
	_say_label.offset_top = -128.0
	_say_label.offset_bottom = -98.0
	_say_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_say_label.add_theme_font_size_override("font_size", 15)
	_say_label.add_theme_color_override("font_color", Color(0.87, 0.84, 0.76, 0.95))
	_say_label.modulate.a = 0.0
	layer.add_child(_say_label)


func _say(who: String, text: String) -> void:
	_say_label.text = text if who == "" else "%s : \"%s\"" % [who, text]
	_say_t = 4.5


func _sound(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Cabine" if AudioServer.get_bus_index("Cabine") >= 0 else "Master"
	p.volume_db = db
	if ResourceLoader.exists(path):
		p.stream = load(path)
	else:
		push_warning("son du taxi : %s manque, lancer tools/make_taxi_sounds.py" % path)
	add_child(p)
	return p


func _world_mode() -> String:
	var m := get_parent()
	return m.world_mode if m != null and "world_mode" in m else "normal"


## Le telephone : le dernier des prehensibles (car.gd le pose en dernier),
## reconnu a sa sonnerie — jamais par sa place, les bancs y comptent ailleurs.
func _phone() -> Node:
	if _phone_node == null and car != null and car.interaction != null:
		for g in car.interaction.grabbables:
			if g != null and g.has_method("ring"):
				_phone_node = g
	return _phone_node


func _phone_ok() -> bool:
	return _phone() != null and _phone().battery > 0.5
