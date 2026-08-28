extends Node3D
##
## LE CYCLE JOUR/NUIT — le proprietaire de l'ambiance du monde normal.
##
## Jusqu'ici la nuit etait une constante : _build_environment posait ses
## valeurs une fois et personne n'y retouchait. Elle devient un MOMENT d'un
## cycle : une horloge tourne (2 s reelles = 1 min de jeu, journee de 48 min),
## et l'ambiance entiere — ciel, lumiere ambiante, brouillard, saturation,
## soleil, lune — est interpolee continument entre quelques moments cles.
## Personne d'autre ne doit ecrire dans l'Environment : un seul proprietaire,
## ou les reglages se marchent dessus.
##
## LE JOUR EST BLEME, ET C'EST UN CHOIX.
## -------------------------------------------------------------------------
## Toute la palette du jeu — troncs a 0,075, sol a 0,075, geant a 0,070 — est
## ecrite pour la nuit et les phares. Un midi d'ete la trahirait : tout
## paraitrait peint en gris. Le jour est donc un jour COUVERT de brouillard,
## sans disque de soleil (il est derriere la couche), lumiere laiteuse et
## ombres eteintes — la campagne d'une fin d'automne. L'angoisse ne dort pas
## avec la lune.
##
## LE SOLEIL EST LE MONTAGE DE LA LUNE.
## -------------------------------------------------------------------------
## La lune du jeu, c'est un Node3D oriente (-elevation, 180-azimut) qui porte
## une DirectionalLight sans ombres. Le soleil reprend ce montage a
## l'identique, sans disque : la lumiere directionnelle seule, dont l'energie
## et la teinte suivent l'heure — chaude et rasante a l'aube, blanche et
## haute a midi. Pas d'ombres non plus : la moitie des meshes du jeu ne
## projettent pas (cast_shadow OFF), un soleil a ombres revelerait
## l'artifice au lieu d'habiller le monde.
##
## LA NUIT DE REFERENCE EST UN INSTANTANE, PAS UNE COPIE.
## -------------------------------------------------------------------------
## Le moment "nuit" n'est pas une table recopiee de _build_environment : il
## est PHOTOGRAPHIE sur l'Environment a l'initialisation, apres que main l'a
## construit. Regler la nuit dans main continue donc de regler la nuit du
## cycle, et a 23 h le monde est, au bit pres, celui d'avant le cycle — les
## bancs d'essai existants tournent geles sur cette heure-la et ne voient
## rien changer.
##
## `override` : la porte du cauchemar. Tant qu'il est vrai, le cycle avance
## mais N'ECRIT PLUS — un autre proprietaire (la bascule cauchemar) tient
## l'Environment. Au relachement, l'heure courante est re-appliquee : on
## peut s'endormir a minuit et se reveiller dans l'aube.
##

## Duree d'une journee de 24 h, en secondes reelles. 2880 : 2 s par minute de
## jeu — la nuit complete (21 h -> 7 h) dure 20 min, une course type 3 a 5.
@export var day_seconds := 2880.0
## Heure de depart d'une partie : la nuit tombe, les phares vont s'allumer.
@export var start_hour := 20.5

## L'heure, 0..24. Les bancs l'ecrivent via set_hour().
var time_h := 20.5
## Gele : l'horloge ne tourne plus (les bancs, l'ecran de fin).
var frozen := false
## Un autre proprietaire ecrit dans l'Environment (le cauchemar). Le cycle
## avance mais se tait ; le relachement re-applique l'heure courante.
var override := false:
	set(v):
		var was := override
		override = v
		if was and not v:
			apply_now()

## Poses par main.gd avant add_child.
var env: Environment
var moon: Node3D
## L'energie de la lune de main (export moon_energy) : le plein de la nuit.
var night_moon_energy := 0.15

## Les valeurs par defaut du shader de lune (moon.gdshader). Le materiau ne
## repond pas get_shader_parameter sur un uniform jamais ecrit : on tient les
## pleins ici, au meme chiffre que le shader.
const MOON_DISC_ENERGY := 1.9
const MOON_HALO_ENERGY := 0.55

var _sun: Node3D
var _sun_light: DirectionalLight3D
var _moon_light: DirectionalLight3D
var _moon_disc: MeshInstance3D
## Les moments du cycle, tries par heure. Chacun : h, et tous les champs
## d'ambiance. "night" est la nuitosite 0..1 (le sommeil la lira), "moonk" la
## presence de la lune, "sun_e"/"sun_c" la lumiere du soleil.
var _moments: Array = []


func _ready() -> void:
	_build_sun()
	_moon_light = moon.get_node("Light") as DirectionalLight3D
	_moon_disc = moon.get_node("Disc") as MeshInstance3D
	_build_moments()
	time_h = start_hour
	apply_now()


## Le soleil : le montage de la lune, sans disque. L'orientation est posee a
## chaque application selon l'heure.
func _build_sun() -> void:
	_sun = Node3D.new()
	_sun.name = "Sun"
	add_child(_sun)
	_sun_light = DirectionalLight3D.new()
	_sun_light.name = "Light"
	_sun_light.light_energy = 0.0
	_sun_light.shadow_enabled = false
	_sun.add_child(_sun_light)


## Les moments. La nuit est PHOTOGRAPHIEE sur l'Environment (voir l'en-tete) ;
## l'aube, le jour et le crepuscule sont poses en absolu. Deux moments "nuit"
## identiques encadrent minuit : entre 22 h et 5 h, l'interpolation entre deux
## points egaux est une constante — la nuit ne bouge pas.
func _build_moments() -> void:
	var night := {
		"h": 22.0,
		"bg": env.background_color,
		"amb": env.ambient_light_color, "amb_e": env.ambient_light_energy,
		"fog": env.fog_light_color, "fog_e": env.fog_light_energy,
		"fog_d": env.fog_density, "vol_d": env.volumetric_fog_density,
		"sat": env.adjustment_saturation, "con": env.adjustment_contrast,
		"sun_e": 0.0, "sun_c": Color(1.0, 0.8, 0.6),
		"moonk": 1.0, "night": 1.0,
	}
	var night2 := night.duplicate()
	night2["h"] = 5.0
	_moments = [
		night2,
		{"h": 6.3,                       # l'aube : le brouillard rougit en premier
			"bg": Color(0.16, 0.125, 0.135),
			"amb": Color(0.55, 0.47, 0.49), "amb_e": 0.16,
			"fog": Color(0.27, 0.19, 0.18), "fog_e": 0.80,
			"fog_d": 0.024, "vol_d": 0.010,
			"sat": 0.66, "con": 1.05,
			"sun_e": 0.22, "sun_c": Color(1.0, 0.60, 0.40),
			"moonk": 0.25, "night": 0.55},
		{"h": 8.5,                       # le matin : la couche s'installe
			"bg": Color(0.33, 0.35, 0.39),
			"amb": Color(0.70, 0.72, 0.76), "amb_e": 0.34,
			"fog": Color(0.38, 0.40, 0.44), "fog_e": 0.90,
			"fog_d": 0.016, "vol_d": 0.006,
			"sat": 0.62, "con": 1.02,
			"sun_e": 0.55, "sun_c": Color(0.96, 0.91, 0.83),
			"moonk": 0.0, "night": 0.12},
		{"h": 13.0,                      # plein jour bleme : le plafond de la journee
			"bg": Color(0.44, 0.47, 0.52),
			"amb": Color(0.74, 0.77, 0.82), "amb_e": 0.42,
			"fog": Color(0.47, 0.49, 0.54), "fog_e": 1.0,
			"fog_d": 0.012, "vol_d": 0.004,
			"sat": 0.60, "con": 1.0,
			"sun_e": 0.80, "sun_c": Color(0.93, 0.94, 0.97),
			"moonk": 0.0, "night": 0.0},
		{"h": 19.0,                      # le crepuscule : l'aube a rebours, en plus terne
			"bg": Color(0.145, 0.115, 0.125),
			"amb": Color(0.52, 0.43, 0.45), "amb_e": 0.14,
			"fog": Color(0.21, 0.15, 0.145), "fog_e": 0.75,
			"fog_d": 0.022, "vol_d": 0.010,
			"sat": 0.66, "con": 1.05,
			"sun_e": 0.18, "sun_c": Color(1.0, 0.55, 0.35),
			"moonk": 0.20, "night": 0.5},
		night,
	]


func _process(delta: float) -> void:
	if not frozen:
		time_h = fmod(time_h + delta * 24.0 / maxf(day_seconds, 1.0), 24.0)
	if not override:
		_apply()


func set_hour(h: float) -> void:
	time_h = fmod(h, 24.0)
	apply_now()


func apply_now() -> void:
	if not override:
		_apply()


## Le moment courant, interpole. Entre deux moments, smoothstep : la derivee
## est nulle aux points d'appui, le raccord ne se voit pas.
func _blend() -> Dictionary:
	var h := time_h
	var n := _moments.size()
	for i in n - 1:
		var a: Dictionary = _moments[i]
		var b: Dictionary = _moments[i + 1]
		var ha: float = a["h"]
		var hb: float = b["h"]
		if h >= ha and h <= hb:
			var t := smoothstep(0.0, 1.0, (h - ha) / maxf(hb - ha, 0.001))
			return _mix(a, b, t)
	# Hors de la plage 5..22 : la nuit, constante de part et d'autre de minuit.
	return _moments[0]


func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in a:
		if key == "h":
			continue
		var va = a[key]
		if va is Color:
			out[key] = (va as Color).lerp(b[key], t)
		else:
			out[key] = lerpf(va, b[key], t)
	return out


func _apply() -> void:
	var m := _blend()
	env.background_color = m["bg"]
	env.ambient_light_color = m["amb"]
	env.ambient_light_energy = m["amb_e"]
	env.fog_light_color = m["fog"]
	env.fog_light_energy = m["fog_e"]
	env.fog_density = m["fog_d"]
	env.volumetric_fog_density = m["vol_d"]
	env.adjustment_saturation = m["sat"]
	env.adjustment_contrast = m["con"]

	# Le soleil : energie et teinte du moment, course dans le ciel par l'heure.
	# La fenetre 6 h -> 20 h fait une arche en sinus qui culmine a 55 degres ;
	# l'azimut balaie l'est vers l'ouest par rapport a l'axe de depart.
	_sun_light.light_energy = m["sun_e"]
	_sun_light.light_color = m["sun_c"]
	var frac := clampf((time_h - 6.0) / 14.0, 0.0, 1.0)
	var elev := maxf(sin(frac * PI) * 55.0, 1.0)
	var azim := lerpf(95.0, -95.0, frac)
	_sun.rotation_degrees = Vector3(-elev, 180.0 - azim, 0.0)

	# La lune s'efface avec le jour : sa lumiere directionnelle ET son disque.
	var mk: float = m["moonk"]
	if _moon_light != null:
		_moon_light.light_energy = night_moon_energy * mk
	if _moon_disc != null:
		_moon_disc.visible = mk > 0.01
		var mat := _moon_disc.material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("disc_energy", MOON_DISC_ENERGY * mk)
			mat.set_shader_parameter("halo_energy", MOON_HALO_ENERGY * mk)


# --------------------------------------------------------------------------
# Ce que les autres systemes lisent
# --------------------------------------------------------------------------

## Nuitosite 0..1 : 1 en pleine nuit, 0 a midi. Le sommeil s'en servira pour
## le facteur circadien ; le telephone pour son theme sombre.
func night_amount() -> float:
	return _blend()["night"]


## L'heure en toutes lettres, pour le telephone et les bancs : "20h30".
func clock_text() -> String:
	var mins := int(round(fmod(time_h, 24.0) * 60.0))
	return "%dh%02d" % [mins / 60, mins % 60]
