extends MeshInstance3D
##
## Ce que coute le plafonnier : le reflet de l'habitacle dans le pare-brise.
##
## C'EST UN VRAI MIROIR, monte comme les retroviseurs (mirror.gd) : un
## SubViewport, une Camera3D posee au SYMETRIQUE DE L'OEIL par rapport au plan de
## la vitre, un frustum ASYMETRIQUE dont la fenetre au plan proche est exactement
## le rectangle du quad. Le pare-brise n'est qu'une glace de plus, simplement
## tres grande et tres inclinee.
##
## Deux differences avec un retroviseur, et elles font tout :
##
##   - le melange est ADDITIF et pondere par le FRESNEL (windshield_glare.gdshader).
##     Un retroviseur remplace ce qu'il y a derriere ; un pare-brise laisse
##     passer 96 % du paysage et POSE son reflet dessus. C'est ce qui ecrase le
##     contraste de la route au lieu de la masquer ;
##   - la camera regarde vers l'INTERIEUR. Elle voit la planche de bord, la
##     console, les sieges — l'habitacle eclaire par le plafonnier. Eteint,
##     l'habitacle est noir et l'image l'est aussi : le reflet s'eteint tout seul,
##     sans qu'on ait a le lui dire.
##
## `far` est court (l'habitacle fait 3 m) : au-dela il n'y a que la lunette
## arriere et la nuit, ca ne coute rien de ne pas les rendre.
##
## Le quad s'arrete sous le frit noir (4 cm tout autour du vitrage) et sous les
## arrondis d'angle, et le shader eteint encore son pourtour : il n'y a aucun
## bord a voir, quelle que soit la position de la tete.
##
## L'ETAT N'EST PAS MEMORISE : le reflet lit `on` du plafonnier a chaque image.
## Une bascule doublee ici pourrait se desynchroniser de la lampe — on aurait le
## reflet sans la lumiere, ou l'inverse, et ce serait indebuggable. C'est le meme
## choix qu'au frein a main.
##

## Couche de rendu vue par le reflet. La MEME que les retroviseurs, et pour la
## meme raison : le conducteur est sur DRIVER_LAYER, son modele est fait pour la
## vue subjective et un buste sans tete dans la vitre serait pire que rien.
const REFLECT_LAYER := 1
## Hauteur de rendu, en pixels. Volontairement basse : un reflet de pare-brise
## est ETALE, on n'y lit pas des details. Le flou du redimensionnement travaille
## ici dans le bon sens, et c'est une passe de rendu de plus par image.
const RES_H := 128
## De combien le plan proche est repousse DERRIERE la vitre. Il coupe deja tout
## ce qui est entre la camera virtuelle et la glace (le capot, la route qui
## defile) ; ces deux centimetres de plus lui font avaler le vitrage, le frit et
## ce quad lui-meme, qui sinon se verrait par la tranche dans sa propre image.
const NEAR_MARGIN := 0.02
## Profondeur utile : l'habitacle, et rien de plus.
const FAR := 6.0

## Ou le quad se pose sous la ligne de baie INTERIEURE, le long de la normale.
## Le vitrage d'habitacle est lui-meme 3,4 mm sous cette ligne et le frit 4,4 :
## a 7 mm on est donc DEVANT les deux (cote conducteur), avec 2,6 mm de marge —
## assez pour qu'aucun z-fighting ne soit possible, trop peu pour se voir.
const INSET := 0.007
## Emprise du quad le long de la pente du pare-brise, en metres depuis le bas de
## baie interieure, qui en fait 0,677 en tout. On laisse 9 cm en bas (la
## casquette de planche de bord vient s'y loger) et 8 cm en haut (le bandeau et
## les pare-soleil ranges).
const PANE_FROM := 0.09
const PANE_TO := 0.60
## Demi-largeur. La baie fait 0,745 en bas et 0,715 en haut, moins 4 cm de frit
## de chaque cote : 0,67 passe partout, arrondis d'angle compris.
const PANE_HALF_W := 0.67
## Fondu a l'allumage et a l'extinction. Une ampoule a incandescence n'est pas
## instantanee non plus, et un quad de cette taille qui apparait d'une image a
## l'autre se lit comme un defaut d'affichage.
const FADE_RATE := 11.0

## PRESENCE DU REFLET, et c'est le seul reglage de jouabilite : monte-le pour
## une lampe qui coute cher, descends-le pour une lampe qu'on peut se permettre.
## Le Fresnel donne la forme du reflet, celui-ci sa force.
##
## Il est pose ICI et pas seulement dans le shader, pour deux raisons : il se
## regle dans l'inspecteur comme le reste du plafonnier, et un uniforme jamais
## assigne se relit `null` — de quoi casser net un banc d'essai qui voudrait le
## lire pour le remettre en place.
@export var strength := 2.8

## Le plafonnier (dome_light.gd) dont ce reflet est la contrepartie.
var dome: Node3D

var _view: SubViewport
var _cam: Camera3D
var _mat: ShaderMaterial
var _half := Vector2(PANE_HALF_W, (PANE_TO - PANE_FROM) * 0.5)
var _energy := -1.0


## `up` est la direction montante du pare-brise et `n` sa normale exterieure,
## toutes deux en espace voiture ; `base` est le bas de baie interieure.
## A appeler APRES add_child.
func setup(base: Vector3, up: Vector3, n: Vector3, lamp: Node3D) -> void:
	dome = lamp

	# Base droitiere : X reste la droite de la voiture, Y monte le long de la
	# vitre, Z regarde vers l'HABITACLE — un QuadMesh montre sa face +Z, et ce
	# reflet n'existe que vu de l'interieur. C'est aussi le repere qu'attend
	# `aim()`, calque sur celui d'une glace de retroviseur.
	transform = Transform3D(Basis(Vector3.RIGHT, up, -n),
		base + up * (PANE_FROM + _half.y) - n * INSET)

	_view = SubViewport.new()
	_view.name = "View"
	_view.size = Vector2i(maxi(int(round(RES_H * _half.x / _half.y)), 8), RES_H)
	# Sans ca le SubViewport se fabrique un World3D vide : ni habitacle, ni
	# plafonnier, ni rien a refleter.
	_view.own_world_3d = false
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.handle_input_locally = false
	_view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_view)

	_cam = Camera3D.new()
	_cam.name = "Eye"
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.far = FAR
	_cam.cull_mask = REFLECT_LAYER
	_view.add_child(_cam)
	_cam.current = true

	# Largeur deduite du viewport REEL : l'arrondi en pixels change l'aspect de
	# quelques millimes, et c'est le quad qui doit s'y plier, sinon l'image du
	# reflet est etiree par rapport a l'habitacle qu'elle montre.
	var quad := QuadMesh.new()
	quad.size = Vector2(
		2.0 * _half.y * float(_view.size.x) / float(_view.size.y), 2.0 * _half.y)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/windshield_glare.gdshader")
	# Apres la vitre. Les deux sont transparents et separes de 7 mm : le tri par
	# distance les departagerait dans le bon ordre neuf fois sur dix, ce qui est
	# une fois de trop. La priorite le fixe.
	_mat.render_priority = 1
	_mat.set_shader_parameter("reflection", _view.get_texture())
	_mat.set_shader_parameter("pane_half", Vector2(quad.size.x * 0.5, _half.y))
	_mat.set_shader_parameter("strength", strength)
	material_override = _mat

	_set_energy(1.0 if _lamp_on() else 0.0)


## A appeler chaque image avec la position MONDE de l'oeil du joueur, en meme
## temps que les retroviseurs (cabin.aim_mirrors). Le calcul est le leur, au
## commentaire pres : voir mirror.gd, ou il est explique en detail.
func aim(eye: Vector3) -> void:
	if _cam == null or not visible:
		return
	var gt := global_transform
	var right := gt.basis.x.normalized()
	var up := gt.basis.y.normalized()
	var normal := gt.basis.z.normalized()

	var dist := (eye - gt.origin).dot(normal)
	if dist < 0.05:
		# L'oeil est passe derriere la vitre — tete a la portiere, vue
		# exterieure. Il n'y a plus de reflet a montrer, et un `near` negatif
		# casserait la projection.
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var eye_r := eye - 2.0 * dist * normal
	_cam.global_transform = Transform3D(Basis(-right, up, -normal), eye_r)

	var to_glass := gt.origin - eye_r
	_cam.near = maxf(to_glass.dot(normal), 0.05) + NEAR_MARGIN
	_cam.size = 2.0 * _half.y
	_cam.frustum_offset = Vector2(to_glass.dot(-right), to_glass.dot(up))


func _process(delta: float) -> void:
	_set_energy(lerpf(_energy, 1.0 if _lamp_on() else 0.0,
		clampf(delta * FADE_RATE, 0.0, 1.0)))


func _lamp_on() -> bool:
	return dome != null and dome.on


func _set_energy(e: float) -> void:
	if absf(e - _energy) < 0.0005:
		return
	_energy = e
	_mat.set_shader_parameter("energy", e)
	# Eteint, le quad ne coute plus rien : ni fragment, ni transparence a trier,
	# et surtout plus de passe de rendu — le SubViewport s'arrete avec lui.
	visible = e > 0.001
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible \
		else SubViewport.UPDATE_DISABLED
