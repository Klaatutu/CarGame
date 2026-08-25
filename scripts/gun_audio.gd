extends Node
##
## Ce qu'on entend du revolver : le coup de feu et les quatre temps du
## rechargement. One-shots synthetises par tools/make_gun_sounds.py.
##
## Ce noeud ne surveille rien. cabin_audio.gd, lui, regarde `gear` et
## `handbrake_on` changer d'une image a l'autre — un levier n'a que deux etats,
## il suffit de voir qu'il a bouge. La mecanique du Webley, elle, a des temps
## INTERMEDIAIRES que nulle variable ne rend : le canon qui arrive en butee,
## l'etoile qui chasse les etuis, le verrou qui se rabat. C'est donc revolver.gd
## qui appelle l'evenement a l'image ou la piece bouge.
##
## Les fichiers sont TAILLES sur sa chronologie : `open` couvre tout le geste,
## du clic du verrou au clonc de la charniere ; `shut` court de la remontee du
## canon jusqu'au claquement. Deplacer R_LATCH & co. dans revolver.gd demande
## donc de relancer le generateur, sinon le bruit tombe a cote de l'image.
##
## Tout sort sur le bus par defaut. L'arme est dans l'habitacle, a cinquante
## centimetres de l'oreille : rien ne s'interpose, surtout pas le passe-bas des
## vitres que porte CABIN_BUS. La caisse, elle, est deja DANS les fichiers —
## c'est elle qui fait le coup de feu, et elle a ete convoluee au rendu.
##

const DIR := "res://assets/audio/gun/"

## Un coup de feu dans une voiture fermee est ce qu'on entend de plus fort dans
## le jeu : il doit ecraser le moteur (-4 dB) sans discussion.
@export var shot_volume_db := -3.0
## Le chien sur une chambre vide. Fort, lui aussi : c'est tout ce que le joueur
## recoit pour comprendre qu'il est a sec.
@export var dry_volume_db := -11.0
## La detente, le rochet, le verrou du barillet. Sous le coup, mais nets — dans
## un habitacle au ralenti, on entend une arme s'armer.
@export var cock_volume_db := -17.0
@export var open_volume_db := -12.0
@export var eject_volume_db := -12.0
@export var fill_volume_db := -13.0
@export var shut_volume_db := -10.0
## Variation de hauteur des one-shots : six coups d'affilee ne doivent pas etre
## six fois le meme fichier.
@export var pitch_spread := 0.05
## Discrete sur le coup de feu : au-dela, on entend l'arme changer de calibre
## d'un coup a l'autre.
@export var shot_pitch_spread := 0.02

var _cock: AudioStreamPlayer
var _shot: AudioStreamPlayer
var _dry: AudioStreamPlayer
var _open: AudioStreamPlayer
var _eject: AudioStreamPlayer
var _fill: AudioStreamPlayer
var _shut: AudioStreamPlayer
var _last := "-"


func _ready() -> void:
	# Le coup de feu traine plus d'une seconde et peut repartir toutes les
	# 0,34 s (FIRE_TIME) : quatre voix, sinon le sixieme coup coupe la queue du
	# cinquieme et le barillet se vide dans un silence.
	_shot = _player("shot.wav", 4)
	_cock = _player("cock.wav", 2)
	_dry = _player("dry.wav", 2)
	_open = _player("open.wav", 1)
	_eject = _player("eject.wav", 1)
	_fill = _player("fill.wav", 1)
	_shut = _player("shut.wav", 1)


func _exit_tree() -> void:
	for p in [_cock, _shot, _dry, _open, _eject, _fill, _shut]:
		if p != null:
			p.stop()


# --------------------------------------------------------------------------
# Les evenements. revolver.gd les appelle, ce noeud ne fait que jouer.
# --------------------------------------------------------------------------

## La detente part : le rochet pousse le barillet, le verrou tombe dans son
## cran. Tient dans les 130 ms qui separent le clic du coup (HAMMER_DROP).
func cock() -> void:
	_play(_cock, cock_volume_db, pitch_spread, "armement")


func shot() -> void:
	_play(_shot, shot_volume_db, shot_pitch_spread, "coup de feu")


func dry() -> void:
	_play(_dry, dry_volume_db, pitch_spread, "chambre vide")


## Le pouce pousse le verrou et le canon bascule jusqu'a sa butee. Le geste ne
## s'appelle pas `open` : Object a deja ce nom.
func break_open() -> void:
	_play(_open, open_volume_db, pitch_spread, "ouverture")


func eject() -> void:
	_play(_eject, eject_volume_db, pitch_spread, "ejection")


func fill() -> void:
	_play(_fill, fill_volume_db, pitch_spread, "chargement")


func shut() -> void:
	_play(_shut, shut_volume_db, pitch_spread, "fermeture")


func debug_line() -> String:
	return "son revolver : %s" % _last


# --------------------------------------------------------------------------

func _player(fname: String, polyphony: int) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.max_polyphony = polyphony
	var path := DIR + fname
	if ResourceLoader.exists(path):
		p.stream = load(path)
	else:
		push_warning("son du revolver : %s manque, lancer tools/make_gun_sounds.py" % path)
	add_child(p)
	return p


func _play(p: AudioStreamPlayer, db: float, spread: float, what: String) -> void:
	if p == null or p.stream == null:
		return
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-spread, spread)
	p.play()
	_last = what
