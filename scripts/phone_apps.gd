extends Control
##
## L'INTERFACE DU TELEPHONE — ce qui vit dans le SubViewport de phone.gd.
##
## Des Controls construits en code, comme tout le HUD du jeu : pas de theme,
## pas de scene, des Labels et des Buttons regles a la main. Quatre pages —
## ACCUEIL, COURSES, GPS, AVIS — et une barre d'onglets en bas dont chaque
## bouton fait 48 px de haut : on les touche AU RETICULE, pas a la souris,
## et un doigt de regard tremble plus qu'un curseur.
##
## Cette passe-ci pose l'appareil : l'ACCUEIL est vivant (heure du cycle,
## batterie, solde, reseau — PAS DE RESEAU dans le cauchemar), les trois
## autres pages annoncent ce qu'elles deviendront (la carte au jalon des
## villes, les courses et les avis a celui des clients). Les donnees
## remontent par la chaine des porteurs : le telephone connait sa voiture,
## la voiture son monde — jamais de singleton.
##

const BG := Color(0.055, 0.065, 0.085)
const PANEL := Color(0.085, 0.10, 0.13)
const INK := Color(0.75, 0.80, 0.88)
const DIM := Color(0.42, 0.46, 0.54)
const ACCENT := Color(0.95, 0.62, 0.25)
const ALERT := Color(0.90, 0.30, 0.25)

## Le telephone qui nous porte (pose avant add_child).
var phone

var page := "accueil"

var _clock_big: Label
var _status_clock: Label
var _status_batt: Label
var _batt_line: Label
var _money_line: Label
var _network_line: Label
var _pages := {}
var _tabs := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_status_bar()
	_build_pages()
	_build_tabs()
	set_page("accueil")
	refresh()


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _build_status_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8.0
	bar.offset_right = -8.0
	bar.offset_top = 4.0
	bar.offset_bottom = 22.0
	add_child(bar)
	_status_clock = _label(bar, "--h--", 12, DIM)
	_status_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_batt = _label(bar, "100%", 12, DIM)
	_status_batt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _page(name: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.name = name.capitalize()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 10.0
	p.offset_right = -10.0
	p.offset_top = 30.0
	p.offset_bottom = -56.0
	p.add_theme_constant_override("separation", 8)
	add_child(p)
	_pages[name] = p
	return p


func _build_pages() -> void:
	# ACCUEIL : l'heure en grand, la batterie, le solde, le reseau.
	var home := _page("accueil")
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	home.add_child(spacer)
	_clock_big = _label(home, "--h--", 46, INK)
	_label(home, "nuit de garde", 12, DIM)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 18)
	home.add_child(spacer2)
	_batt_line = _label(home, "batterie 100%", 14, INK)
	_money_line = _label(home, "0,00 EUR", 20, ACCENT)
	_network_line = _label(home, "reseau : ok", 13, DIM)

	# COURSES : vide pour l'instant, et il le dit.
	var fares := _page("courses")
	var sp3 := Control.new()
	sp3.custom_minimum_size = Vector2(0, 60)
	fares.add_child(sp3)
	_label(fares, "AUCUNE COURSE", 16, DIM)
	_label(fares, "Les demandes arriveront ici.", 12, DIM)

	# GPS : la carte viendra avec les villes.
	var gps := _page("gps")
	var sp4 := Control.new()
	sp4.custom_minimum_size = Vector2(0, 60)
	gps.add_child(sp4)
	_label(gps, "GPS", 16, DIM)
	_label(gps, "Pas d'itineraire en cours.", 12, DIM)

	# AVIS : la reputation, encore vierge.
	var ratings := _page("avis")
	var sp5 := Control.new()
	sp5.custom_minimum_size = Vector2(0, 60)
	ratings.add_child(sp5)
	_label(ratings, "AUCUN AVIS", 16, DIM)
	_label(ratings, "Les clients vous noteront ici.", 12, DIM)


func _build_tabs() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -50.0
	bar.offset_bottom = -4.0
	bar.offset_left = 4.0
	bar.offset_right = -4.0
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	for name in ["accueil", "courses", "gps", "avis"]:
		var b := Button.new()
		b.text = name.to_upper()
		b.custom_minimum_size = Vector2(48, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", ACCENT)
		var sb := StyleBoxFlat.new()
		sb.bg_color = PANEL
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		b.add_theme_stylebox_override("normal", sb)
		var sbh := sb.duplicate() as StyleBoxFlat
		sbh.bg_color = PANEL.lightened(0.08)
		b.add_theme_stylebox_override("hover", sbh)
		var sbp := sb.duplicate() as StyleBoxFlat
		sbp.bg_color = PANEL.darkened(0.25)
		b.add_theme_stylebox_override("pressed", sbp)
		b.pressed.connect(set_page.bind(name))
		bar.add_child(b)
		_tabs[name] = b


# --------------------------------------------------------------------------
# Vie
# --------------------------------------------------------------------------

func set_page(name: String) -> void:
	page = name
	for key in _pages:
		(_pages[key] as Control).visible = key == name
	for key in _tabs:
		(_tabs[key] as Button).add_theme_color_override("font_color",
			ACCENT if key == name else DIM)
	refresh()


## Remet les chiffres a jour. Appele par phone.gd au rythme du rendu (chaque
## image consulte, une sur deux secondes au support) : pas de _process ici,
## l'ecran ne calcule que quand il est regarde.
func refresh() -> void:
	var main = _main()
	var clock := "--h--"
	var network := "reseau : ok"
	var network_color := DIM
	if main != null:
		if "daycycle" in main and main.daycycle != null:
			clock = main.daycycle.clock_text()
		if "world_mode" in main and main.world_mode == "nightmare":
			network = "PAS DE RESEAU"
			network_color = ALERT
	_status_clock.text = clock
	if _clock_big != null:
		_clock_big.text = clock
	var b := int(round(phone.battery)) if phone != null else 0
	_status_batt.text = "%d%%" % b
	_status_batt.add_theme_color_override("font_color",
		ALERT if b <= 15 else DIM)
	_batt_line.text = "batterie %d%%%s" % [b,
		"  (en charge)" if phone != null and phone.docked
		and phone.carrier != null and not phone.carrier.stalled else ""]
	var money := 0.0
	if main != null and "taxi" in main and main.taxi != null:
		money = main.taxi.money
	_money_line.text = "%.2f EUR" % money
	_network_line.text = network
	_network_line.add_theme_color_override("font_color", network_color)


## La molette pendant la consultation. Les pages de cette passe tiennent a
## l'ecran ; le defilement servira aux listes (avis, offres).
func scroll(_dir: int) -> void:
	pass


## Le porteur du porteur : la voiture, puis main. Jamais de singleton — la
## chaine se remonte, et chaque maillon peut manquer (bancs, essais).
func _main() -> Node:
	if phone == null or phone.carrier == null:
		return null
	return phone.carrier.get_parent()
