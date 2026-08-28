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
## Tout est vivant : l'ACCUEIL (heure du cycle, batterie, solde, reseau —
## PAS DE RESEAU dans le cauchemar), les COURSES (l'offre qui sonne et ses
## deux boutons, la course qui roule — taxi.gd), le GPS (la carte du graphe
## et le point qui avance), les AVIS (la moyenne, les dix derniers). Les
## donnees remontent par la chaine des porteurs : le telephone connait sa
## voiture, la voiture son monde — jamais de singleton.
##

const MapScript := preload("res://scripts/map.gd")

## Les quatre pages, dans l'ordre de la barre d'onglets. La molette les
## parcourt (scroll), les onglets s'en construisent.
const PAGES := ["accueil", "courses", "gps", "avis"]

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
var _gps_line: Label
var _gps_amen: Label
var _gps_map: Control
var _fare_title: Label
var _fare_info: Label
var _fare_price: Label
var _fare_count: Label
var _btn_yes: Button
var _btn_no: Button
var _avis_head: Label
var _avis_rows: Array[Label] = []
var _pages := {}
var _tabs := {}


## La carte, dessinee a la main : les dix routes, les huit noms, et le
## point qui roule. Les coordonnees de map.gd sont en 0..1 — l'echelle est
## celle du Control, quel que soit l'ecran.
class GpsMap:
	extends Control
	var apps

	func _draw() -> void:
		var s := size
		var font := get_theme_default_font()
		var main = apps._main() if apps != null else null
		var route: Array = []
		if main != null and "nav" in main and not main.nav.is_empty():
			route = main.nav.get("route", [])
		for e in MapScript.EDGES:
			var a: Vector2 = MapScript.at(e[0]) * s
			var b: Vector2 = MapScript.at(e[1]) * s
			var on_route := false
			for i in route.size() - 1:
				if (route[i] == e[0] and route[i + 1] == e[1]) \
						or (route[i] == e[1] and route[i + 1] == e[0]):
					on_route = true
			draw_line(a, b, Color(0.95, 0.62, 0.25) if on_route
				else Color(0.30, 0.34, 0.42), 2.0 if on_route else 1.0)
		for t in MapScript.TOWNS:
			var p: Vector2 = MapScript.at(t) * s
			draw_circle(p, 3.0, Color(0.75, 0.80, 0.88))
			draw_string(font, p + Vector2(-26.0, -6.0), t,
				HORIZONTAL_ALIGNMENT_CENTER, 60.0, 9, Color(0.42, 0.46, 0.54))
		if main != null and "nav" in main and not main.nav.is_empty():
			var a2: Vector2 = MapScript.at(main.nav["at"]) * s
			var b2: Vector2 = MapScript.at(main.nav["to"]) * s
			var p2: Vector2 = a2.lerp(b2, main.nav_progress())
			draw_circle(p2, 4.5, Color(0.95, 0.62, 0.25))
			draw_circle(p2, 2.0, Color(0.10, 0.08, 0.05))


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

	# COURSES : l'offre qui sonne, la course qui roule, et les deux boutons
	# qui se touchent au reticule. Le contenu suit l'etat du taxi (taxi.gd).
	var fares := _page("courses")
	var sp3 := Control.new()
	sp3.custom_minimum_size = Vector2(0, 12)
	fares.add_child(sp3)
	_fare_title = _label(fares, "AUCUNE COURSE", 16, DIM)
	_fare_info = _label(fares, "Les demandes arriveront ici.", 12, DIM)
	_fare_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fare_info.custom_minimum_size = Vector2(0, 58)
	_fare_price = _label(fares, "", 22, ACCENT)
	_fare_count = _label(fares, "", 13, ALERT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	fares.add_child(row)
	_btn_yes = _fare_button(row, "ACCEPTER", ACCENT)
	_btn_no = _fare_button(row, "REFUSER", DIM)
	_btn_yes.pressed.connect(func() -> void:
		var m = _main()
		if m != null and "taxi" in m and m.taxi != null:
			m.taxi.accept_offer())
	_btn_no.pressed.connect(func() -> void:
		var m = _main()
		if m != null and "taxi" in m and m.taxi != null:
			m.taxi.refuse_offer())

	# GPS : la carte du graphe, dessinee au _draw — villes, routes, et la
	# position qui avance le long de l'arete courante.
	var gps := _page("gps")
	_gps_line = _label(gps, "—", 12, ACCENT)
	_gps_map = GpsMap.new()
	_gps_map.apps = self
	_gps_map.custom_minimum_size = Vector2(0, 210)
	_gps_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gps.add_child(_gps_map)
	_gps_amen = _label(gps, "", 10, DIM)

	# AVIS : la moyenne en tete, puis les dix derniers — remplis par
	# refresh(), jamais realloues : l'ecran se consulte a chaque image.
	var ratings := _page("avis")
	var sp5 := Control.new()
	sp5.custom_minimum_size = Vector2(0, 8)
	ratings.add_child(sp5)
	_avis_head = _label(ratings, "AUCUN AVIS", 16, DIM)
	_label(ratings, "", 4, DIM)
	for i in 7:
		var r := _label(ratings, "", 10, DIM)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_avis_rows.append(r)


## Un bouton de page, au meme gabarit que les onglets : 46 px de haut, on
## le touche au reticule et le reticule tremble.
func _fare_button(parent: Control, text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(48, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", color)
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
	parent.add_child(b)
	return b


func _build_tabs() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -50.0
	bar.offset_bottom = -4.0
	bar.offset_left = 4.0
	bar.offset_right = -4.0
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	for name in PAGES:
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

	# Les pages du metier suivent l'etat du taxi.
	var taxi = main.taxi if main != null and "taxi" in main else null
	_refresh_courses(taxi)
	_refresh_avis(taxi)

	# La page GPS : le bandeau d'en-tete, la carte redessinee, les
	# commodites de la ville visee — de quoi choisir ou finir la nuit.
	if main != null and "nav" in main and not main.nav.is_empty():
		var to: String = main.nav["to"]
		var len_m: float = MapScript.edge_length(main.nav["at"], to)
		var rest := int(maxf(len_m * (1.0 - main.nav_progress()), 0.0))
		if "road" in main and main.road.fork_state() in ["grow", "window"]:
			_gps_line.text = "Y : a gauche %s, a droite %s" % [
				main.road._fork_left, main.road._fork_right]
		else:
			_gps_line.text = "Vers %s — %d m" % [to, rest]
		var amen: Array = MapScript.amenities(to)
		_gps_amen.text = "%s : %s" % [to, ", ".join(amen)]
	else:
		_gps_line.text = "Pas d'itineraire en cours."
		_gps_amen.text = ""
	if _gps_map != null:
		_gps_map.queue_redraw()


## La page COURSES dit ou en est le metier : une offre et ses boutons, la
## course en cours, la note qui vient de tomber. Textes remplis, jamais de
## reconstruction — refresh passe a chaque image consultee.
func _refresh_courses(taxi) -> void:
	var st: String = taxi.state if taxi != null else "idle"
	var show_offer: bool = st == "offer" and not taxi.offer.is_empty()
	_btn_yes.visible = show_offer
	_btn_no.visible = show_offer
	_fare_price.text = ""
	_fare_count.text = ""
	if taxi == null or st == "idle":
		_fare_title.text = "AUCUNE COURSE"
		_fare_info.text = "Les demandes arriveront ici."
		return
	match st:
		"offer":
			_fare_title.text = "COURSE PROPOSEE"
			_fare_info.text = "%s\n%s  vers  %s" % [taxi.offer["who"],
				taxi.offer["from"], taxi.offer["to"]]
			_fare_price.text = "%.2f EUR" % taxi.offer["price"]
			_fare_count.text = "%d s pour repondre" % ceili(maxf(taxi.offer["left"], 0.0))
		"accepted", "pickup_zone":
			_fare_title.text = "COURSE ACCEPTEE"
			_fare_info.text = "Prendre %s a %s.\nZone d'arret a droite, a l'arret." % [
				taxi.fare["who"], taxi.fare["from"]]
			_fare_price.text = "%.2f EUR" % taxi.fare["price"]
		"boarding":
			_fare_title.text = "EMBARQUEMENT"
			_fare_info.text = "%s monte..." % taxi.fare["who"]
		"riding":
			_fare_title.text = "EN COURSE"
			_fare_info.text = "%s  vers  %s" % [taxi.fare["who"], taxi.fare["to"]]
			_fare_price.text = "%.2f EUR" % taxi.fare["price"]
		"drop_zone":
			_fare_title.text = "ARRIVEE"
			_fare_info.text = "Deposez %s.\nZone d'arret a droite, a l'arret." % taxi.fare["who"]
			_fare_price.text = "%.2f EUR" % taxi.fare["price"]
		"payment":
			_fare_title.text = "PAIEMENT"
			_fare_info.text = "%s regle la course." % taxi.fare["who"]
		"rated":
			_fare_title.text = "COURSE TERMINEE"
			if not taxi.reviews.is_empty():
				var r: Dictionary = taxi.reviews[0]
				_fare_info.text = "%s a note : %s" % [r["who"],
					_stars_text(r["stars"])]


## La reputation : la moyenne en tete, les derniers avis dessous — etoiles,
## mots du client, signature.
func _refresh_avis(taxi) -> void:
	if taxi == null or taxi.reviews.is_empty():
		_avis_head.text = "AUCUN AVIS"
		_avis_head.add_theme_color_override("font_color", DIM)
		for r in _avis_rows:
			r.text = ""
		return
	_avis_head.text = "%s  —  %d avis" % [_stars_text(taxi.stars_avg()),
		taxi.reviews.size()]
	_avis_head.add_theme_color_override("font_color", ACCENT)
	for i in _avis_rows.size():
		if i < taxi.reviews.size():
			var r: Dictionary = taxi.reviews[i]
			_avis_rows[i].text = "%s  %s  — %s" % [_stars_text(r["stars"]),
				r["text"], r["who"]]
		else:
			_avis_rows[i].text = ""


## "4,5/5" — le meme texte que le HUD, sans importer taxi.gd en dur.
static func _stars_text(stars: float) -> String:
	return ("%.1f/5" % stars).replace(".", ",")


## LA MOLETTE TOURNE LES PAGES, et c'est le geste qui compte en roulant.
##
## Le reticule sait viser les onglets depuis qu'il tombe dans l'ecran, mais
## viser demande de poser les yeux sur l'appareil. La molette, elle, ne vise
## rien : le telephone sonne, on roule un cran, la page COURSES est la. C'est
## le meme cran que la manivelle de vitre et le levier — on ne s'en sert
## jamais des deux facons a la fois, l'etat PHONE se l'approprie.
##
## Bornee, pas circulaire : quatre pages se comptent au poignet, et une boucle
## fait toujours depasser celle qu'on cherchait. Rend vrai si la page a
## change — le telephone en tire son petit clic.
func scroll(dir: int) -> bool:
	var i := PAGES.find(page)
	var j := clampi((0 if i < 0 else i) + dir, 0, PAGES.size() - 1)
	if i == j:
		return false
	set_page(PAGES[j])
	return true


## Le porteur du porteur : la voiture, puis main. Jamais de singleton — la
## chaine se remonte, et chaque maillon peut manquer (bancs, essais).
func _main() -> Node:
	if phone == null or phone.carrier == null:
		return null
	return phone.carrier.get_parent()
