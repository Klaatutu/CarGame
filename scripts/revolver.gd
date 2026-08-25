extends "res://scripts/prop.gd"
##
## Webley Mk VI. Objet libre de l'habitacle comme le paquet et les canettes
## (prop.gd : simulation dans le repere de la voiture), mais qu'on peut EN PLUS
## LEVER et TIRER. interaction.gd pilote les trois gestes : clic droit maintenu
## pour viser, clic gauche pour tirer, R pour recharger.
##
## REPERE DU NOEUD. Le .glb sort bouche vers -Z, dessus vers +Y, crosse vers +Z,
## origine a la charniere du bloc canon. Ce noeud, lui, obeit a deux contraintes
## de prop.gd : son origine au CENTRE du volume (les demi-cotes `half` sont pris
## autour), et son +Y vers le haut quand l'objet est POSE — interaction.gd
## `_rest_on` couche le +Y local sur la verticale et le +Z local vers le joueur.
##
## Or un revolver pose ne tient pas sur sa crosse : il repose sur son flanc. D'ou
## la rotation de +90 degres autour de Z appliquee au modele. Le flanc DROIT
## regarde alors le ciel (l'arme est couchee sur son flanc gauche, comme on la
## pose quand on est droitier), la bouche reste sur -Z — elle pointera a l'oppose
## du joueur — et la crosse sur +Z, offerte a la main.
##
## Tout ce que le reste du code lit de la geometrie (bouche, poignee, axes) est
## donc exprime EN ESPACE ARME dans les constantes _GUN, puis passe par la
## transform du modele : une seule rotation a comprendre, et rien a refaire si le
## modele bouge.
##
## MECANIQUE. Le .glb est rigue (assets/blender/build_webley.py) : chaque piece
## mobile a son origine sur son axe. On ne joue donc aucune animation importee,
## on ecrit les angles a la main, ce qui laisse le tir et le rechargement
## s'interrompre et se melanger proprement.
##

const DriverScript := preload("res://scripts/driver.gd")
const GunAudioScript := preload("res://scripts/gun_audio.gd")
const WEBLEY := preload("res://assets/models/webley.glb")

## Debattements des pieces mobiles, en degres (voir l'entete de build_webley.py).
const HAMMER_COCK := 35.0
const TRIGGER_PULL := -12.0
const LATCH_OPEN := 25.0
const BARREL_BREAK := -60.0
## Course de l'etoile d'extraction, le long de l'axe du barillet.
const EJECT_TRAVEL := 0.030

const CHAMBERS := 6

## Tir en double action : une seule pression arme, fait tourner le barillet et
## lache le chien. Le coup part a HAMMER_DROP, pas au clic.
const FIRE_TIME := 0.34
const HAMMER_DROP := 0.13
## Le recul se resorbe plus vite que le geste : l'arme est retombee avant que le
## doigt ait fini de revenir.
## L'AMPLEUR du recul (de combien l'arme se cabre) appartient a interaction.gd,
## qui dessine la pose : ici on ne dit que s'il y a recul, et combien il en reste.
const RECOIL_FALL := 0.22
## Un vrai eclair de bouche dure deux millisecondes. Celui-ci doit durer TROIS
## IMAGES : plus court, il tombe entre deux et le coup part sans que rien
## n'eclaire, une fois sur trois et au hasard.
const FLASH_TIME := 0.09

## Rechargement : ouvrir, ejecter, regarnir, refermer.
const RELOAD_TIME := 1.55
const R_LATCH := 0.16          # le verrou bascule
const R_OPEN := 0.52           # le canon a fini de piquer
const R_EJECT := 0.72          # l'etoile a chasse les etuis
const R_FILL := 0.98           # six neuves en place
const R_SHUT := 1.34           # le canon est referme

## Portee du rayon de tir. Au-dela, dans le brouillard, il n'y a rien a toucher.
const RANGE := 220.0

## En espace ARME (avant la rotation du modele).
## Axe de la poignee, du talon vers le haut de la crosse : c'est lui qui se
## couche sur l'axe du poing, pouce vers +. Mesure sur les plaquettes du modele
## (y -0.0948..-0.0124, z 0.0369..0.0847), qui donnent sa fuite vers l'arriere.
const GRIP_AXIS_GUN := Vector3(0.0, 0.865, -0.502)
## Perpendiculaire a l'axe de la poignee, du dos de la crosse (dans la paume)
## vers l'avant : c'est la direction qui s'eloigne de la paume.
const PALM_AWAY_GUN := Vector3(0.0, -0.502, -0.865)
## Milieu des plaquettes : le centre du poing.
const HOLD_POINT_GUN := Vector3(0.0, -0.055, 0.060)
## Rayon de la prise. La poignee fait ~35 mm dans sa largeur utile ; sans ce
## chiffre, interaction.gd le deduirait des demi-cotes et ouvrirait la main a la
## longueur du canon.
const GRIP_RADIUS := 0.017

## Ou il revient s'il sort de l'habitacle.
const RESET_POINT := Vector3(0.42, 0.60, 0.06)

## Cartouches en chambre. Six au depart : on ne monte pas en voiture avec un
## barillet vide.
var rounds := CHAMBERS

var _model: Node3D
var _barrel_pivot: Node3D
var _cylinder: Node3D
var _extractor: Node3D
var _hammer: Node3D
var _trigger: Node3D
var _latch: Node3D
var _carts: Array[Node3D] = []
var _flash: OmniLight3D
## Le son (gun_audio.gd). C'est ce noeud-ci qui l'appelle, parce que c'est lui
## qui sait a quelle image la piece arrive en butee.
var _audio: Node
var _materials: Array[StandardMaterial3D] = []

## Etats d'animation, tous en 0..1 sauf le barillet (en chambres).
var _cock := 0.0
var _pull := 0.0
var _open := 0.0
var _eject := 0.0
var _recoil := 0.0
var _cyl := 0.0                    # position du barillet, en chambres
var _cyl_from := 0.0
var _fire_t := -1.0
var _reload_t := -1.0
var _flash_t := 0.0
var _extractor_rest := 0.0
var _last_shot := "-"
var _peak_recoil := 0.0
var _peak_flash := 0.0

## Axes et points ci-dessus, ramenes dans le repere du NOEUD.
var _grip_axis := Vector3.UP
var _palm_away := Vector3.BACK
var _hold_point := Vector3.ZERO
var _muzzle := Vector3.FORWARD
var _hand_local := Basis()


func _ready() -> void:
	reset_point = RESET_POINT
	# Halo de surbrillance beaucoup plus discret que celui des canettes. Une
	# canette a un albedo clair et imprime : l'emission la teinte. L'acier bruni,
	# lui, est presque noir — a 0,9 l'arme devenait une silhouette orange pleine,
	# sans un detail. Il ne s'agit que de dire "on peut le prendre".
	highlight_energy = 0.30
	_build_model()
	_measure()
	_build_flash()
	_build_audio()


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

## Le .glb entier est adopte sous un noeud `Model` qui porte la rotation et le
## recentrage. On garde la hierarchie : ce sont ses pivots qu'on anime.
func _build_model() -> void:
	var scene := WEBLEY.instantiate()
	var frame := scene.find_child("WBL_Frame", true, false) as Node3D
	if frame == null:
		push_error("webley.glb : WBL_Frame introuvable")
		scene.free()
		return

	_model = Node3D.new()
	_model.name = "Model"
	# +90 degres autour de Z : le flanc droit de l'arme (+X) monte sur le +Y du
	# noeud, la bouche (-Z) et la crosse (+Z) ne bougent pas.
	_model.basis = Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(90.0)))
	add_child(_model)

	frame.get_parent().remove_child(frame)
	_disown(frame)
	_model.add_child(frame)
	frame.transform = Transform3D()
	scene.free()

	_barrel_pivot = frame.find_child("WBL_BarrelPivot", true, false) as Node3D
	_cylinder = frame.find_child("WBL_Cylinder", true, false) as Node3D
	_extractor = frame.find_child("WBL_Extractor", true, false) as Node3D
	_hammer = frame.find_child("WBL_Hammer", true, false) as Node3D
	_trigger = frame.find_child("WBL_Trigger", true, false) as Node3D
	_latch = frame.find_child("WBL_Latch", true, false) as Node3D
	for i in CHAMBERS:
		var c := frame.find_child("WBL_Cart_%d" % (i + 1), true, false) as Node3D
		if c != null:
			_carts.append(c)
	if _barrel_pivot == null or _cylinder == null or _hammer == null:
		push_warning("webley.glb : pieces mobiles absentes, l'arme restera figee")
	if _extractor != null:
		_extractor_rest = _extractor.position.z

	_prepare_materials(self)
	_no_shadows(self)


## Demi-cotes, point de prise et bouche, mesures sur le modele une fois pose.
## Rien n'est devine : `half` vient de l'englobant reel, et le modele est decale
## pour que le centre de ce volume tombe sur l'origine du noeud, comme l'exige
## prop.gd.
func _measure() -> void:
	if _model == null:
		return
	var box := _bounds(_model, _model.transform)
	if box.size == Vector3.ZERO:
		return
	_model.position -= box.position + box.size * 0.5
	half = box.size * 0.5

	var tf := _model.transform
	_grip_axis = (tf.basis * GRIP_AXIS_GUN).normalized()
	_palm_away = (tf.basis * PALM_AWAY_GUN).normalized()
	_hold_point = tf * HOLD_POINT_GUN
	_hand_local = _fist_basis()

	# Bouche : centre de la face de sortie du canon, dans le repere du noeud.
	var barrel := _model.find_child("WBL_Barrel", true, false) as MeshInstance3D
	if barrel != null and barrel.mesh != null:
		var b := _local_transform(barrel) * barrel.mesh.get_aabb()
		_muzzle = Vector3(b.position.x + b.size.x * 0.5,
			b.position.y + b.size.y * 0.5, b.position.z)
	else:
		_muzzle = Vector3(0.0, 0.0, -half.z)


## Orientation que doit prendre le POING pour tenir l'arme, exprimee dans le
## repere du noeud (voir hand_local()).
##
## Les poses de main du modele sont construites autour d'une barre tangente a la
## paume : dans le repere de la main, l'axe de cette barre est -Z et la direction
## qui s'eloigne de la paume est PALM_AWAY_R. Il suffit d'envoyer ces deux
## directions sur celles de la poignee, par changement de base — la meme
## mecanique que _open_grip() du conducteur.
func _fist_basis() -> Basis:
	var target := Basis(_grip_axis, _palm_away, _grip_axis.cross(_palm_away))
	var bar := Vector3(0.0, 0.0, -1.0)
	var palm: Vector3 = DriverScript.PALM_AWAY_R
	var local := Basis(bar, palm, bar.cross(palm))
	return target * local.transposed()


## L'eclair de bouche. Une lumiere, pas un sprite : de nuit, dans un habitacle
## noir, c'est ce qui eclaire la scene qui fait le coup de feu, pas le dessin.
func _build_flash() -> void:
	_flash = OmniLight3D.new()
	_flash.name = "MuzzleFlash"
	_flash.position = _muzzle
	_flash.light_color = Color(1.0, 0.80, 0.48)
	_flash.omni_range = 9.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)


## Le son. Un noeud fils de l'arme, comme l'eclair : il n'a rien a faire dans
## la voiture, il part avec le revolver si on le sort de l'habitacle.
func _build_audio() -> void:
	_audio = GunAudioScript.new()
	_audio.name = "GunAudio"
	add_child(_audio)


# --------------------------------------------------------------------------
# Gestes. interaction.gd les declenche, ce noeud les deroule.
# --------------------------------------------------------------------------

## Presser la detente. Renvoie vrai si un coup est parti (pour le son, la HUD et
## le recul du reste du monde) — faux sur chambre vide ou geste deja en cours.
func fire() -> bool:
	if _fire_t >= 0.0 or _reload_t >= 0.0:
		return false
	_fire_t = 0.0
	_cyl_from = _cyl
	# Le rochet et le verrou du barillet, tout de suite : ils appartiennent a la
	# pression sur la detente, pas au coup. Sur chambre vide, c'est meme tout ce
	# qu'on entendra avant le chien sur l'acier.
	_audio.cock()
	if rounds <= 0:
		_last_shot = "chambre vide"
		return false
	return true


## Basculer le canon, chasser les etuis, regarnir, refermer. Un seul geste : on
## ne recharge pas cartouche par cartouche, c'est tout l'interet d'un Webley.
func reload() -> bool:
	if _reload_t >= 0.0 or _fire_t >= 0.0 or rounds >= CHAMBERS:
		return false
	_reload_t = 0.0
	# Un seul fichier couvre le verrou, la bascule et la butee : le geste est
	# continu, le decouper en trois ferait entendre trois objets.
	_audio.break_open()
	return true


func can_fire() -> bool:
	return rounds > 0 and _fire_t < 0.0 and _reload_t < 0.0


func busy() -> bool:
	return _fire_t >= 0.0 or _reload_t >= 0.0


func reloading() -> bool:
	return _reload_t >= 0.0


## Ouverture du bloc canon, 0 ferme, 1 bascule a fond. Sert au banc d'essai.
func open_amount() -> float:
	return _open


## Recul en cours, 0..1. interaction.gd le fait cabrer l'arme.
func recoil() -> float:
	return _recoil


## Intensite de l'eclair de bouche. Sert au banc d'essai.
func flash_energy() -> float:
	return _flash.light_energy if _flash != null else 0.0


## Sommets de recul et d'eclair depuis le dernier appel. Sert au banc d'essai :
## c'est la seule mesure fiable d'un evenement qui ne dure que trois images.
func take_peaks() -> Vector2:
	var p := Vector2(_peak_recoil, _peak_flash)
	_peak_recoil = 0.0
	_peak_flash = 0.0
	return p


func ammo_hint() -> String:
	if _reload_t >= 0.0:
		return "Rechargement"
	if rounds <= 0:
		return "Barillet vide    R : recharger"
	return "%d/%d    clic gauche : tirer    R : recharger" % [rounds, CHAMBERS]


func debug_line() -> String:
	return "revolver %d/%d  chien %.2f  detente %.2f  canon %.2f  barillet %.2f  recul %.2f  eclair %.3f/%.1f (noeud=%s)  dernier : %s" % [
		rounds, CHAMBERS, _cock, _pull, _open, _cyl, _recoil,
		_flash_t, flash_energy(), _flash != null, _last_shot]


# --------------------------------------------------------------------------
# Deroule
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	_advance_fire(delta)
	_advance_reload(delta)
	if _flash_t > 0.0:
		_flash.light_energy = 14.0 * (_flash_t / FLASH_TIME)
		_flash.visible = true
		_flash_t = maxf(_flash_t - delta, 0.0)
	elif _flash.visible:
		_flash.light_energy = 0.0
		_flash.visible = false
	# Sommets atteints depuis le dernier coup : un banc d'essai qui echantillonne
	# image par image rate une fenetre de trois images une fois sur deux, et
	# conclurait a tort qu'il ne se passe rien.
	_peak_recoil = maxf(_peak_recoil, _recoil)
	_peak_flash = maxf(_peak_flash, _flash.light_energy)
	_recoil = maxf(_recoil - delta / RECOIL_FALL, 0.0)
	_apply_pose()


func _advance_fire(delta: float) -> void:
	if _fire_t < 0.0:
		return
	var was := _fire_t
	_fire_t += delta

	if _fire_t < HAMMER_DROP:
		# Armement : le chien monte, la detente recule, le barillet indexe.
		var u := _fire_t / HAMMER_DROP
		_cock = u
		_pull = u
		_cyl = _cyl_from + u
		return

	# Le chien tombe : c'est ici que le coup part, une seule fois.
	if was < HAMMER_DROP:
		_cock = 0.0
		_cyl = _cyl_from + 1.0
		if rounds > 0:
			rounds -= 1
			_recoil = 1.0
			_flash_t = FLASH_TIME
			_last_shot = "coup parti"
			_audio.shot()
			_shoot()
		else:
			# Chambre vide : le chien va au bout de sa course et ne rencontre
			# que l'acier. Ce clic est le seul retour qu'a le joueur, l'eclair
			# et le recul ne viendront pas le lui dire.
			_audio.dry()

	# Retour de la detente.
	var v := clampf((_fire_t - HAMMER_DROP) / (FIRE_TIME - HAMMER_DROP), 0.0, 1.0)
	_cock = 0.0
	_pull = 1.0 - v
	if _fire_t >= FIRE_TIME:
		_fire_t = -1.0
		_pull = 0.0


func _advance_reload(delta: float) -> void:
	if _reload_t < 0.0:
		return
	var was := _reload_t
	_reload_t += delta
	var t := _reload_t

	# Les trois autres sons se posent aux PASSAGES, pas aux etats : chacun
	# couvre le temps qui commence, et le fichier a ete taille a sa longueur.
	if was < R_OPEN and t >= R_OPEN:
		_audio.eject()
	if was < R_EJECT and t >= R_EJECT:
		_audio.fill()
	if was < R_SHUT and t >= R_SHUT:
		_audio.shut()

	# Le verrou bascule d'abord et ne se rabat qu'une fois le canon referme.
	if t < R_SHUT:
		_latch_amount(clampf(t / R_LATCH, 0.0, 1.0))
	else:
		_latch_amount(clampf((RELOAD_TIME - t) / (RELOAD_TIME - R_SHUT), 0.0, 1.0))

	if t < R_LATCH:
		_open = 0.0
	elif t < R_OPEN:
		_open = smoothstep(0.0, 1.0, (t - R_LATCH) / (R_OPEN - R_LATCH))
	elif t < R_SHUT:
		_open = 1.0
	else:
		_open = 1.0 - smoothstep(0.0, 1.0, (t - R_SHUT) / (RELOAD_TIME - R_SHUT))

	# L'etoile sort, les etuis partent avec elle, puis elle rentre et six neuves
	# sont en place.
	if t < R_OPEN:
		_eject = 0.0
	elif t < R_EJECT:
		_eject = smoothstep(0.0, 1.0, (t - R_OPEN) / (R_EJECT - R_OPEN))
	elif t < R_FILL:
		_eject = 1.0 - smoothstep(0.0, 1.0, (t - R_EJECT) / (R_FILL - R_EJECT))
	else:
		_eject = 0.0

	# Les etuis disparaissent au sommet de la course, les cartouches neuves
	# reapparaissent quand l'etoile est rentree.
	var loaded := t < R_EJECT or t >= R_FILL
	for c in _carts:
		c.visible = loaded
	if was < R_FILL and t >= R_FILL:
		rounds = CHAMBERS
		_last_shot = "recharge"

	if t >= RELOAD_TIME:
		_reload_t = -1.0
		_open = 0.0
		_eject = 0.0
		_latch_amount(0.0)


func _latch_amount(a: float) -> void:
	if _latch != null:
		_latch.rotation.x = deg_to_rad(LATCH_OPEN) * a


## Ecrit les angles sur les pivots. Une seule fonction : les deux gestes peuvent
## se chevaucher sans se marcher dessus.
func _apply_pose() -> void:
	if _hammer != null:
		# Le chien est repousse par le canon des qu'il s'ouvre : on prend le plus
		# grand des deux, sinon il traverserait la culasse pendant le chargement.
		_hammer.rotation.x = deg_to_rad(HAMMER_COCK) * maxf(_cock, _open * 0.35)
	if _trigger != null:
		_trigger.rotation.x = deg_to_rad(TRIGGER_PULL) * _pull
	if _barrel_pivot != null:
		_barrel_pivot.rotation.x = deg_to_rad(BARREL_BREAK) * _open
	if _cylinder != null:
		_cylinder.rotation.z = TAU / float(CHAMBERS) * _cyl
	if _extractor != null:
		_extractor.position.z = _extractor_rest + EJECT_TRAVEL * _eject


## Le coup lui-meme. Un rayon depuis la bouche : il n'y a encore rien qui sache
## etre touche, mais ce qui le saura un jour n'aura qu'a exposer `hit()`.
func _shoot() -> void:
	var world := get_world_3d()
	if world == null:
		return
	var from := global_transform * _muzzle
	var dir := (global_transform.basis * aim_axis()).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	q.collide_with_areas = false
	# Sans quoi le premier obstacle est la caisse dans laquelle on est assis.
	if carrier is CollisionObject3D:
		q.exclude = [(carrier as CollisionObject3D).get_rid()]
	var hit := world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var who = hit.get("collider")
	_last_shot = "touche %s" % (who.name if who is Node else "?")
	if who is Node and who.has_method("hit"):
		who.call("hit", hit["position"], hit["normal"])


# --------------------------------------------------------------------------
# Ce que interaction.gd et le conducteur lisent
# --------------------------------------------------------------------------

## Axe de l'arme qui se couche sur l'axe du poing (pouce vers +).
func grip_axis() -> Vector3:
	return _grip_axis


## Face presentee au joueur quand il tient l'arme sans viser : le flanc gauche,
## barillet en vue. C'est le -Y du noeud, le flanc droit etant sur +Y.
func front_axis() -> Vector3:
	return Vector3.DOWN


## Point de l'arme qui tombe dans le poing. Sans lui, la main la tiendrait par le
## centre de son volume, c'est-a-dire par le barillet.
func hold_point() -> Vector3:
	return _hold_point


## Direction de la bouche, repere du noeud.
func aim_axis() -> Vector3:
	return Vector3.FORWARD


## Dessus de l'arme (bande de visee), repere du noeud : c'est lui qu'on met vers
## le ciel quand on epaule.
func up_axis() -> Vector3:
	return Vector3.LEFT


## Orientation du poing par rapport a l'arme. interaction.gd la compose avec la
## pose de l'arme et la passe au conducteur, pour que la main suive vraiment ce
## qu'elle tient au lieu de s'orienter d'apres le coude.
func hand_local() -> Basis:
	return _hand_local


func grip_radius() -> float:
	return GRIP_RADIUS


## Genereux : l'arme est longue mais mince, la viser au pixel serait penible.
func grab_radius() -> float:
	return 0.09


# --------------------------------------------------------------------------

func _apply_glow(energy: float) -> void:
	for m in _materials:
		m.emission_energy_multiplier = energy


## Meme traitement que les canettes : albedo rabattu sur la palette de nuit de
## l'habitacle, filtrage au plus proche voisin, et une emission eteinte qui
## servira de halo.
func _prepare_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
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
	for c in n.get_children():
		_prepare_materials(c)


## Englobant de tous les maillages, dans le repere de ce noeud.
func _bounds(n: Node, tf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		box = tf * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var sub := _bounds(c, tf * (c as Node3D).transform)
		if sub.size == Vector3.ZERO:
			continue
		box = sub if first else box.merge(sub)
		first = false
	return box


## Transform d'un noeud du modele dans le repere de ce noeud-ci.
func _local_transform(n: Node3D) -> Transform3D:
	var tf := n.transform
	var p := n.get_parent()
	while p is Node3D and p != self:
		tf = (p as Node3D).transform * tf
		p = p.get_parent()
	return tf


func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)


func _disown(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_disown(c)
