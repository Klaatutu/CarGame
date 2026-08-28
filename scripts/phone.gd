extends "res://scripts/prop.gd"
##
## LE TELEPHONE — l'ecran qu'on touche du regard.
##
## Un objet libre comme le paquet et les canettes (prop.gd : il tombe, glisse
## et se lance), avec un ECRAN VIVANT : un SubViewport 2D — des Controls
## construits en code, pas de camera — plaque en texture sur la face avant,
## le montage exact des retroviseurs (mirror.gd) sans l'inversion gauche-
## droite. Le tramage plein ecran passe par-dessus comme sur tout le reste :
## l'ecran est trame gratuitement, il appartient a la meme nuit.
##
## FACON DOOM 3 : PAS DE CURSEUR, C'EST LE RETICULE QUI TOUCHE.
## -------------------------------------------------------------------------
## Consulte en main (clic droit maintenu, l'etat PHONE d'interaction.gd), la
## camera reste libre et le point du HUD sert de doigt : screen_uv() resout
## analytiquement rayon du regard -> plan du quad -> coordonnees d'ecran, et
## les clics sont POUSSES au viewport en evenements souris synthetiques
## (push_input) — les Button de Godot font le reste, survol compris. Aucun
## raycast physique : le telephone et l'oeil vivent dans le meme repere
## voiture, la geometrie de la meme image ne ment pas (README, la visee sans
## physique).
##
## LA BATTERIE EST UNE JAUGE QU'ON BRANCHE.
## -------------------------------------------------------------------------
## L'ecran allume tire -2,5 %/min, la veille -0,5 ; pose sur son support
## (cabin.gd, le berceau a la pile centrale), il charge a +12 %/min — MOTEUR
## TOURNANT : l'allume-cigare ne donne rien moteur cale, et c'est une raison
## de plus de ne pas caler. A 0 % : ecran mort, plus d'offres, plus de GPS —
## la sanction n'est pas un game over, c'est une nuit sans revenu.
##
## L'economie de rendu suit mirror.gd : UPDATE_ALWAYS consulte, une image
## toutes les 0,5 s au support (l'horloge qui luit dans l'habitacle), rien
## du tout eteint.
##

const PhoneApps := preload("res://scripts/phone_apps.gd")

## Cotes du boitier (demi-cotes pour prop.gd) et de l'ecran utile.
const BODY := Vector3(0.070, 0.016, 0.140)
const SCREEN_W := 0.058
const SCREEN_H := 0.110
## Definition du viewport : ~4 px/mm, NEAREST — des pixels nets, pas du flou.
const VIEW_SIZE := Vector2i(216, 384)

## Debits de batterie, en % par minute.
const DRAIN_ON := 2.5
const DRAIN_IDLE := 0.5
const CHARGE_DOCKED := 12.0

## Batterie 0..100. Les bancs l'ecrivent.
var battery := 100.0
## Pose au berceau (cabin.phone_dock) : epingle, en charge moteur tournant.
var docked := false
## Consulte en main (l'etat PHONE d'interaction.gd le leve et le baisse).
var viewing := false

var _screen: Node3D                 ## +Z = normale ecran, +Y = haut d'ecran
var _view: SubViewport
var _apps: Control
var _quad: MeshInstance3D
var _mat_screen: StandardMaterial3D
var _dock_pulse := 0.0
var _ring_snd: AudioStreamPlayer3D
var _tap_snd: AudioStreamPlayer3D


func _ready() -> void:
	half = BODY * 0.5
	_build_body()
	_build_screen()
	_build_audio()
	set_screen_power(true)


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _build_body() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	var box := BoxMesh.new()
	box.size = BODY
	mi.mesh = box
	mi.material_override = _make_body_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _make_body_mat() -> StandardMaterial3D:
	# Un boitier sombre et mat. StandardMaterial : la surbrillance passe par
	# l'emission, comme les canettes.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.035, 0.035, 0.040)
	m.roughness = 0.55
	m.emission_enabled = true
	m.emission = highlight_color
	m.emission_energy_multiplier = 0.0
	_body_mats.append(m)
	return m


var _body_mats: Array[StandardMaterial3D] = []


func _apply_glow(energy: float) -> void:
	for m in _body_mats:
		m.emission_energy_multiplier = energy


## L'ecran : un noeud repere (+Z normale, +Y haut) qui porte le viewport et
## le quad texture. Le haut de l'ecran regarde le -Z du boitier : pose a
## plat, l'appareil se lit depuis le siege.
func _build_screen() -> void:
	_screen = Node3D.new()
	_screen.name = "Screen"
	_screen.position = Vector3(0.0, BODY.y * 0.5 + 0.0006, 0.006)
	# X -90 et RIEN d'autre : +Z sort de la vitre, +Y (le v du texte) vers le
	# haut du boitier. Un Y 180 de plus semblait anodin — il retournait le
	# texte en miroir, releve sur la capture du banc.
	_screen.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(_screen)

	_view = SubViewport.new()
	_view.name = "View"
	_view.size = VIEW_SIZE
	_view.disable_3d = true
	_view.transparent_bg = false
	_view.handle_input_locally = true
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view.msaa_2d = Viewport.MSAA_DISABLED
	_screen.add_child(_view)

	_apps = PhoneApps.new()
	_apps.name = "Apps"
	_apps.phone = self
	_view.add_child(_apps)

	var quad := QuadMesh.new()
	quad.size = Vector2(SCREEN_W, SCREEN_H)
	_quad = MeshInstance3D.new()
	_quad.name = "Glass"
	_quad.mesh = quad
	_mat_screen = StandardMaterial3D.new()
	_mat_screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_screen.albedo_texture = _view.get_texture()
	_mat_screen.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# La texture du viewport arrive la tete en bas sur le quad (releve a la
	# capture : les onglets en haut). Le redressement se fait AU MATERIAU,
	# comme l'inversion gauche-droite des retroviseurs (mirror.gd) — la voie
	# stable, prouvee sur les deux rendus.
	_mat_screen.uv1_scale = Vector3(1.0, -1.0, 1.0)
	_mat_screen.uv1_offset = Vector3(0.0, 1.0, 0.0)
	_quad.material_override = _mat_screen
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_screen.add_child(_quad)


func _build_audio() -> void:
	var bus := "Cabine" if AudioServer.get_bus_index("Cabine") >= 0 else "Master"
	_ring_snd = _phone_sound("res://assets/audio/taxi/ring.wav", bus, -6.0)
	_tap_snd = _phone_sound("res://assets/audio/taxi/tap.wav", bus, -8.0)


func _phone_sound(path: String, bus: String, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.volume_db = db
	p.unit_size = 2.0
	p.max_distance = 0.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if ResourceLoader.exists(path):
		p.stream = load(path)
	else:
		push_warning("telephone : %s manque, lancer tools/make_taxi_sounds.py" % path)
	add_child(p)
	return p


# --------------------------------------------------------------------------
# La batterie et l'ecran
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)

	# La jauge. Le moteur tournant se lit sur la voiture qui nous porte.
	var rate := -DRAIN_IDLE
	if docked and carrier != null and not carrier.stalled:
		rate = CHARGE_DOCKED
	elif screen_on():
		rate = -DRAIN_ON
	battery = clampf(battery + rate * delta / 60.0, 0.0, 100.0)

	if battery <= 0.0 and _view.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		set_screen_power(false)

	# L'economie de rendu, et le rythme du support : une image de temps en
	# temps suffit a une horloge.
	if battery > 0.0:
		if viewing:
			_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		elif docked:
			_dock_pulse += delta
			if _dock_pulse >= 0.5:
				_dock_pulse = 0.0
				_apps.refresh()
				_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		else:
			_view.render_target_update_mode = SubViewport.UPDATE_DISABLED


func screen_on() -> bool:
	return battery > 0.0 and (viewing or docked)


func set_screen_power(on: bool) -> void:
	if on and battery > 0.0:
		_quad.visible = true
		_apps.refresh()
		_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		# Ecran mort : une vitre noire, pas une texture figee.
		_quad.visible = false
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED


func set_viewing(on: bool) -> void:
	viewing = on
	if on and battery > 0.0:
		_quad.visible = true
		_apps.refresh()


func set_docked(on: bool) -> void:
	docked = on
	if on:
		# Epingle au berceau : la simulation de prop.gd se tait tant que
		# `held` est vrai — le meme verrou que la main, tenu par le support.
		held = true
		vel = Vector3.ZERO
		spin = Vector3.ZERO
		if battery > 0.0:
			_quad.visible = true
			_apps.refresh()
			_view.render_target_update_mode = SubViewport.UPDATE_ONCE


## Pris en main : le berceau le lache.
func hold() -> void:
	super.hold()
	docked = false


# --------------------------------------------------------------------------
# L'ecran qu'on touche du regard
# --------------------------------------------------------------------------

## Rayon du regard (MONDE) -> coordonnees d'ecran 0..1, ou null a cote.
## Analytique : le plan du quad, rien d'autre.
func screen_uv(eye_w: Vector3, dir_w: Vector3) -> Variant:
	if not _quad.visible:
		return null
	var t := _screen.global_transform
	var n := t.basis.z.normalized()
	var denom := dir_w.dot(n)
	if absf(denom) < 0.0001:
		return null
	var d := (t.origin - eye_w).dot(n) / denom
	if d < 0.0 or d > 1.4:
		return null
	var lp := t.affine_inverse() * (eye_w + dir_w * d)
	var u := 0.5 + lp.x / SCREEN_W
	var v := 0.5 - lp.y / SCREEN_H
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return null
	return Vector2(u, v)


## Le point d'ecran en MONDE (la main du geste TAPPING va la).
func screen_point(uv: Vector2) -> Vector3:
	return _screen.global_transform * Vector3(
		(uv.x - 0.5) * SCREEN_W, (0.5 - uv.y) * SCREEN_H, 0.0)


## Le survol : un mouvement de souris synthetique pousse au viewport — les
## Button de Godot allument leur hover tout seuls.
func hover(uv: Vector2) -> void:
	if battery <= 0.0:
		return
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(uv.x * float(VIEW_SIZE.x), uv.y * float(VIEW_SIZE.y))
	_view.push_input(ev)


## Le doigt. Un clic complet (pression puis relachement) au meme point : les
## Button repondent au relachement, les deux partent ensemble.
func tap(uv: Vector2) -> void:
	if battery <= 0.0:
		return
	var at := Vector2(uv.x * float(VIEW_SIZE.x), uv.y * float(VIEW_SIZE.y))
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		_view.push_input(ev)
	if _tap_snd != null and _tap_snd.stream != null:
		_tap_snd.play()


func scroll(dir: int) -> void:
	_apps.scroll(dir)


func ring() -> void:
	if _ring_snd != null and _ring_snd.stream != null:
		_ring_snd.play()


func stop_ring() -> void:
	if _ring_snd != null:
		_ring_snd.stop()


# --------------------------------------------------------------------------
# Le contrat de prop / interaction
# --------------------------------------------------------------------------

## Tenu par la tranche basse, ecran vers le pouce.
func grip_axis() -> Vector3:
	return Vector3.FORWARD


func front_axis() -> Vector3:
	return Vector3.UP


func grip_radius() -> float:
	return 0.012


## Rayon de VISEE (pas de prise) : tout l'ecran doit se viser, coins de la
## barre d'onglets compris — la sphere couvre le boitier entier.
func grab_radius() -> float:
	return 0.095


func rest_height() -> float:
	return half.y


func hold_point() -> Vector3:
	# La main empoigne le tiers bas (+Z : le bas du boitier, le haut de
	# l'ecran regardant -Z).
	return Vector3(0.0, 0.0, 0.048)
