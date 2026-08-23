extends Node3D
##
## Un vrai miroir plan : SubViewport + Camera3D placee a l'OEIL REFLECHI, et un
## quad qui affiche ce rendu a la place de la glace du modele.
##
## LE REPERE DU NOEUD EST CELUI DE LA GLACE : +X vers la droite de la glace,
## +Y vers le haut, +Z la normale (vers le conducteur). Tout se calcule donc en
## lisant global_transform, ce qui suit la voiture sans effort particulier.
##
## La camera n'est PAS posee "au miroir, tournee vers l'arriere". Elle est au
## symetrique de l'oeil par rapport au plan de la glace, avec un frustum
## ASYMETRIQUE dont la fenetre au plan proche est exactement le rectangle de la
## glace. Deux consequences, et c'est tout l'interet :
##
##   - l'image bouge quand on penche la tete, comme un vrai miroir ; sur une
##     camera fixe elle resterait collee et trahirait le truquage des qu'on se
##     penche (et ici on se penche beaucoup : regard arriere, tete a la vitre) ;
##   - elle se plaque pile sur le cadre, sans reglage de champ a la main.
##
## `near` vaut la distance oeil-glace : tout ce qui est entre la camera
## virtuelle et le plan du miroir est donc coupe. C'est gratuit et c'est ce
## qu'on veut — sans ca le retroviseur interieur montrerait le pare-brise et le
## capot, qui sont devant lui.
##

## Couche de rendu vue par les miroirs. Le conducteur est sur une autre couche :
## le modele est fait pour la vue subjective (tete masquee), un buste sans tete
## dans le retroviseur serait pire que pas de buste du tout.
const MIRROR_LAYER := 1

## Hauteur de rendu, en pixels. Basse volontairement : une glace de 5 cm sur une
## image tramee n'a pas besoin de plus, et il y a trois rendus par image.
const RES_H := 96

## Reglage a la souris. Un miroir DOUBLE l'angle : tourner la glace d'un degre
## deplace l'image de deux. La sensibilite est donc la moitie de celle du regard
## (car.gd look_sensitivity), sinon le reglage est increvable de nervosite.
@export var swivel_speed := 0.0011
## Debattement, en radians. Une rotule de retroviseur ne fait pas le tour.
@export var yaw_limit := 0.42          # 24 degres
@export var pitch_limit := 0.26        # 15 degres

## Pivot de la tete du retroviseur (boitier + glace + ce noeud), fabrique par
## cabin.gd. Nul si la glace n'est pas reglable.
var head: Node3D
var highlight_color := Color(1.5, 1.15, 0.85)

var _view: SubViewport
var _cam: Camera3D
var _quad: MeshInstance3D
var _mat: StandardMaterial3D
var _half_h := 0.05
var _half_w := 0.1
var _rest := Basis()
var _yaw := 0.0
var _pitch := 0.0
var _want := false
var _glow := 0.0
var _pulse := 0.0


## `size` : largeur et hauteur de la glace, en metres. A appeler APRES add_child
## et apres avoir pose la transform du noeud.
func build(size: Vector2) -> void:
	_half_h = size.y * 0.5
	_half_w = size.x * 0.5

	_view = SubViewport.new()
	_view.name = "View"
	_view.size = Vector2i(maxi(int(round(RES_H * size.x / size.y)), 8), RES_H)
	# Sans ca le SubViewport se fabrique un World3D vide et le miroir ne montre
	# rien : ni la route, ni le brouillard, ni l'eclairage de la scene.
	_view.own_world_3d = false
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.handle_input_locally = false
	_view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_view)

	_cam = Camera3D.new()
	_cam.name = "Eye"
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.far = 400.0
	_cam.cull_mask = MIRROR_LAYER
	_view.add_child(_cam)
	_cam.current = true

	# Largeur deduite du viewport REEL : l'arrondi en pixels change l'aspect de
	# quelques millimes, et c'est le quad qui doit s'y plier, pas l'inverse,
	# sinon l'image est etiree.
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size.y * float(_view.size.x) / float(_view.size.y), size.y)

	var mat := StandardMaterial3D.new()
	_mat = mat
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _view.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Un miroir echange la gauche et la droite. La camera virtuelle, elle, rend
	# la scene telle quelle : c'est au placage de retourner l'image.
	mat.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	mat.uv1_offset = Vector3(1.0, 0.0, 0.0)

	_quad = MeshInstance3D.new()
	_quad.name = "Glass"
	_quad.mesh = mesh
	_quad.material_override = mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Deux millimetres devant la glace du modele, qu'on masque par ailleurs.
	_quad.position = Vector3(0.0, 0.0, 0.002)
	add_child(_quad)


# --------------------------------------------------------------------------
# Reglage
# --------------------------------------------------------------------------

## Branche le pivot de la tete, fabrique par cabin.gd. Sa rotation de depart est
## le reglage d'usine : tous les mouvements de souris partent de la.
## Ou la main vient saisir la glace (espace monde) : son bord droit.
func hand_point() -> Vector3:
	return global_transform * Vector3(_half_w + 0.02, 0.0, 0.0)


func adjustable(pivot: Node3D) -> void:
	head = pivot
	_rest = pivot.basis


## Un cran de souris. `rel` est le deplacement en pixels, comme pour le regard.
func swivel(rel: Vector2) -> void:
	if head == null:
		return
	_yaw = clampf(_yaw + rel.x * swivel_speed, -yaw_limit, yaw_limit)
	_pitch = clampf(_pitch + rel.y * swivel_speed, -pitch_limit, pitch_limit)
	# Tangage en repere voiture PUIS lacet : dans cet ordre l'horizon de la glace
	# ne roule pas, comme un regard. L'inverse la fait pencher dans son cadre.
	head.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * _rest


## Rayon de la sphere de visee. La glace fait 23 x 4,8 cm : une sphere de 10 cm
## la couvre sans obliger a viser une bande de deux pixels de haut.
func grab_radius() -> float:
	return 0.10


func set_highlight(on: bool) -> void:
	_want = on


func adjust_hint() -> String:
	return "Maintiens clic gauche : regler le retroviseur"


func _process(delta: float) -> void:
	if head == null:
		return
	# Meme halo pulse que les objets attrapables : dans le noir, un eclat fixe ne
	# se distingue pas d'un reflet. Ici c'est l'albedo du quad qu'on pousse, il
	# n'y a pas de materiau eclaire a faire emettre.
	var to := 1.0 if _want else 0.0
	_glow = lerpf(_glow, to, clampf(delta * 9.0, 0.0, 1.0))
	if _glow < 0.001 and _mat.albedo_color == Color.WHITE:
		return
	_pulse += delta * 2.4
	_mat.albedo_color = Color.WHITE.lerp(highlight_color,
		_glow * (0.72 + 0.28 * sin(_pulse)))


## A appeler chaque image avec la position MONDE de l'oeil du joueur.
func aim(eye: Vector3) -> void:
	if _cam == null:
		return
	var gt := global_transform
	var right := gt.basis.x.normalized()
	var up := gt.basis.y.normalized()
	var normal := gt.basis.z.normalized()

	var dist := (eye - gt.origin).dot(normal)
	if dist < 0.05:
		# L'oeil est passe derriere la glace (tete a la vitre, par exemple) :
		# il n'y a plus rien a refleter, et un `near` negatif casserait la
		# projection. On gele le rendu, ca economise en plus une passe.
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Oeil symetrique par rapport au plan de la glace.
	var eye_r := eye - 2.0 * dist * normal
	# Base droitiere : avec X = -right, X x Y donne bien Z = -normal, donc la
	# camera regarde vers +normal, c'est-a-dire a travers la glace.
	_cam.global_transform = Transform3D(Basis(-right, up, -normal), eye_r)

	# Fenetre du frustum au plan proche = le rectangle de la glace, exprime dans
	# les axes de la camera.
	var to_glass := gt.origin - eye_r
	_cam.near = maxf(to_glass.dot(normal), 0.05)
	_cam.size = 2.0 * _half_h
	_cam.frustum_offset = Vector2(to_glass.dot(-right), to_glass.dot(up))
