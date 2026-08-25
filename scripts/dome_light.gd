extends Node3D
##
## Plafonnier. La lentille vient du modele Blender (BODY_DomeLens) ; ce noeud y
## ajoute l'ampoule qui eclaire l'habitacle et la bascule. Il est INTERACTABLE :
## interaction.gd le vise comme un objet et, au clic, la main du conducteur
## monte le toucher pour l'allumer ou l'eteindre.
##
## Le noeud est place juste SOUS la lentille, la ou les doigts arrivent ; la
## visee a un rayon assez large pour couvrir tout le luminaire.
##

## Allume au depart : sans lui, il ne reste que la lueur des compteurs.
@export var on := true
## Ampoule a incandescence : chaude et FAIBLE. A 1.1 elle cramait la casquette
## et le ciel de toit, qui sont a 15 cm d'elle.
@export var light_color := Color(1.0, 0.86, 0.68)
@export var light_energy := 0.45
@export var light_range := 2.6
@export var lens_emission := Color(1.0, 0.94, 0.82)
@export var lens_energy := 1.0
## Surbrillance quand on le vise : la lentille pulse doucement, meme eteinte,
## sinon rien ne dit qu'on peut y toucher.
@export var highlight_energy := 0.45

## Ecart entre la lentille et le point que la main vient toucher.
const FINGER_GAP := 0.05

var _light: OmniLight3D
var _lens_mats: Array[BaseMaterial3D] = []
var _glow := 0.0
var _pulse := 0.0
var _want := false


## `lens` est la lentille du .glb, `lens_pos` sa position en espace voiture.
func setup(lens: MeshInstance3D, lens_pos: Vector3) -> void:
	position = lens_pos - Vector3(0.0, FINGER_GAP, 0.0)

	# La lentille s'allume : sans ca, la lumiere semblerait venir de nulle part.
	# On duplique le materiau (deja assombri par cabin.gd) pour ne pas toucher
	# aux autres pieces qui le partagent.
	if lens.mesh != null:
		for s in lens.mesh.get_surface_count():
			var src := lens.get_surface_override_material(s)
			if src == null:
				src = lens.mesh.surface_get_material(s)
			if src == null:
				continue
			var lit := src.duplicate()
			if lit is BaseMaterial3D:
				(lit as BaseMaterial3D).emission_enabled = true
				(lit as BaseMaterial3D).emission = lens_emission
				_lens_mats.append(lit)
			lens.set_surface_override_material(s, lit)

	_light = OmniLight3D.new()
	_light.name = "Bulb"
	# Juste sous la lentille, pour que la lumiere parte bien du luminaire.
	_light.position = Vector3(0.0, FINGER_GAP - 0.012, 0.0)
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.omni_range = light_range
	_light.omni_attenuation = 1.6
	_light.light_volumetric_fog_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	_apply()


func _process(delta: float) -> void:
	# Le halo monte vite et redescend doucement, avec une pulsation lente.
	var was := _glow
	_glow = lerpf(_glow, 1.0 if _want else 0.0, clampf(delta * 9.0, 0.0, 1.0))
	if _glow < 0.001:
		if was >= 0.001:
			_apply()                 # halo eteint : on repose la valeur exacte
		return
	_pulse += delta * 2.4
	_set_lens((lens_energy if on else 0.0)
		+ highlight_energy * _glow * (0.72 + 0.28 * sin(_pulse)))


# --- interface pour interaction.gd -----------------------------------------

## Bascule. Appele quand la main est arrivee sur le luminaire.
func use() -> void:
	on = not on
	_apply()


func use_hint() -> String:
	return "Clic gauche : eteindre le plafonnier" if on else "Clic gauche : allumer le plafonnier"


func set_highlight(want: bool) -> void:
	_want = want


## Rayon de la sphere de visee : le luminaire fait 17 x 11 cm.
func grab_radius() -> float:
	return 0.10


## L'ampoule elle-meme, pour qui a besoin de ce qu'elle eclaire ailleurs —
## windshield_glare.gd y lit position, couleur, energie et attenuation plutot
## que de les recopier. Deux jeux de constantes finissent toujours par diverger ;
## celui-ci ne le peut pas.
func bulb() -> OmniLight3D:
	return _light


# --------------------------------------------------------------------------

func _apply() -> void:
	if _light != null:
		_light.visible = on
	_set_lens(lens_energy if on else 0.0)


func _set_lens(energy: float) -> void:
	for m in _lens_mats:
		m.emission_energy_multiplier = energy
