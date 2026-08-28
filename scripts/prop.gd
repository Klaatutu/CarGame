extends Node3D
##
## Objet libre de l'habitacle (paquet, canette...), simule DANS LE REPERE DE LA
## VOITURE. Classe de base : la geometrie et le halo sont a la charge des
## scripts derives (cig_pack.gd, can.gd), qui fixent `half` et `reset_point`.
##
## POURQUOI PAS UN RigidBody3D. Les collisions de l'habitacle sont accrochees a
## une caisse qui roule : a 170 km/h elles se teleportent de 0,8 m par image.
## Le solveur y lit une penetration enorme et ejecte l'objet — "le paquet vole
## dans tous les sens". Les tentatives intermediaires (AnimatableBody3D,
## adherence simulee) n'ont fait que deplacer le probleme.
##
## Dans le repere de la voiture, rien ne bouge : l'objet tombe, glisse et se
## cale contre les boites declarees par cabin.gd. C'est stable a n'importe
## quelle vitesse, parce qu'il n'y a plus de vitesse du tout de ce point de vue.
##
## Ce qu'on ressent quand la voiture accelere, freine ou tourne vient des forces
## d'inertie (`carrier.frame_accel`), pas d'un contact avec un plancher mouvant.
##

const GRAVITY := 9.81

## Culbute d'un objet lance, en tours par seconde et par metre par seconde.
## A 4,5 m/s ca fait un tour par seconde : de quoi lire le lancer sans que
## l'objet devienne une toupie illisible.
const TUMBLE_RATE := 1.4
## Vitesse a laquelle un objet lance se remet d'aplomb une fois pose, et vitesse
## en dessous de laquelle on considere qu'il a fini de rouler.
const SETTLE_RATE := 6.0
const SETTLE_SPEED := 0.25

@export var highlight_color := Color(1.0, 0.62, 0.30)
@export var highlight_energy := 0.9
## Adherence STATIQUE, en coefficient de frottement. Tant que la poussee reste
## sous mu * g (ici 23,5 m/s^2), l'objet ne bouge pas d'un pouce : c'est ce qui
## fait qu'un objet pose RESTE ou on l'a pose.
##
## Le seuil est au-dessus de TOUT ce que la conduite produit. Le pire cas n'est
## pas le frein seul (17 m/s^2) : c'est le frein PLUS le frein moteur, 3,4 de
## plus en 1re, soit 20,4. Le moteur (4,2) et les virages (8, car.gd
## max_lateral) sont loin derriere. Conduire ne derange donc rien, meme en
## plantant les freins.
##
## Il reste sous le plafond de car.gd (frame_accel borne a 60 m/s^2), ce qui
## laisse la bande 23,5-60 aux chocs : un impact, lui, decroche tout.
@export var static_mu := 2.4
## Adherence une fois qu'il glisse. Toujours plus faible que la statique.
@export var kinetic_mu := 0.55
## En dessous, on considere qu'il est immobile.
@export var slide_eps := 0.03
## Restitution. Un paquet de cigarettes ne rebondit quasiment pas.
@export var bounce := 0.10

var carrier                        # la voiture, pour ses forces d'inertie
var cabin                          # pour ses boites de collision
var held := false
## Vitesse EN ESPACE VOITURE.
var vel := Vector3.ZERO
## Rotation en vol, en radians par seconde, axe en espace voiture. PUREMENT
## VISUEL : la boite de collision reste alignee sur les axes, un objet qui
## tourne ne se cogne pas autrement qu'un objet droit.
var spin := Vector3.ZERO
## Demi-cotes de la boite de collision, autour de l'origine du noeud.
var half := Vector3(0.03, 0.03, 0.03)
## Ou il revient s'il sort de l'habitacle, plutot que d'etre perdu.
var reset_point := Vector3(0.30, 0.52, 0.10)

var _grounded := false
var _glow := 0.0
var _pulse := 0.0
var _want := false
var _tumbling := false
var _lit := false                  # le halo est-il ecrit dans le materiau ?


func _physics_process(delta: float) -> void:
	if held or carrier == null or cabin == null or delta <= 0.0:
		return

	# Une voiture qui accelere pousse ce qu'elle transporte vers l'arriere :
	# c'est l'oppose de son acceleration propre.
	var drive: Vector3 = -carrier.frame_accel
	drive.y = 0.0
	vel.y -= GRAVITY * delta

	# Frottement de Coulomb : un SEUIL, pas un amortissement. C'est toute la
	# difference entre un objet qui reste pose et un objet qui derive des qu'on
	# touche a l'accelerateur.
	if _grounded:
		var tang := Vector3(vel.x, 0.0, vel.z)
		if tang.length() <= slide_eps and drive.length() <= static_mu * GRAVITY:
			vel.x = 0.0
			vel.z = 0.0
			drive = Vector3.ZERO          # il colle
		else:
			var stop := kinetic_mu * GRAVITY * delta
			if tang.length() <= stop:
				vel.x = 0.0
				vel.z = 0.0
			else:
				var d := tang / tang.length()
				vel.x -= d.x * stop
				vel.z -= d.z * stop
	vel += drive * delta

	# Sous-pas. Il vaut la MOITIE d'une case de la grille (cabin_shape.gd, 2 cm) :
	# la tole y fait souvent une seule case d'epaisseur, et un objet qui
	# avancerait d'une case entiere pourrait se retrouver de part et d'autre sans
	# jamais etre dedans au moment du test. A un demi-pas, deux positions
	# successives se recouvrent toujours.
	var steps := clampi(int(ceil(vel.length() * delta / 0.01)), 1, 16)
	var h := delta / float(steps)
	for i in steps:
		position += vel * h
		_resolve(h)

	if _tumbling:
		_tumble(delta)

	# Filet de securite. Depuis la coque (_contain), plus aucun objet SIMULE ne
	# peut l'atteindre : il ne reste que ce qui arrive de l'exterieur de la
	# simulation — un objet place hors de la caisse dans la scene, une transform
	# ecrite a la main par le banc d'essai.
	#
	# Ce n'est plus lui qui rattrape les lancers. Il le faisait, et se voyait :
	# l'objet sortait par une fente de l'habitacle et se retrouvait d'un coup a
	# son point de depart, sans avoir touche quoi que ce soit.
	if position.y < -0.4 or position.y > 2.0 or absf(position.x) > 1.10 \
			or position.z < -1.60 or position.z > 2.00:
		position = reset_point
		vel = Vector3.ZERO


## Collisions contre la TOLE RELEVEE (cabin_shape.gd), puis contre le vitrage,
## puis la coque.
##
## CE QUI A CHANGE, ET POURQUOI LE JOUEUR LE VOIT.
##
## Avant, on parcourait une vingtaine de boites SAISIES A LA MAIN dans cabin.gd
## et on sortait de chacune INDEPENDAMMENT, par son axe de moindre penetration.
## Deux defauts, et le second est celui qu'on rapportait :
##
##   - Sortir boite par boite suppose qu'aucune ne recouvre l'autre, sans quoi
##     la seconde defait ce que la premiere vient de faire. cabin.gd s'imposait
##     donc la regle "aucune boite ne doit en chevaucher une autre" — et
##     l'enfreignait treize fois (tools/probe_collisions.gd). Ici on resout
##     contre l'UNION : le resultat ne depend plus de l'ordre, et il n'y a plus
##     rien a s'interdire.
##   - Surtout, ces boites ne collaient pas au modele. La portiere etait
##     declaree a x 0,79, qui est la tole ; la garniture visible est a 0,70. Un
##     objet lance s'arretait donc proprement — NEUF CENTIMETRES DERRIERE LE
##     PANNEAU — et le joueur le voyait "coince dans la paroi". Releve avant
##     correction : 28 % des lancers pour le paquet, 59 % pour une canette,
##     immobilises DANS une piece du modele.
##
## Le banc `-- throwtest`, lui, etait vert : il mesurait les FUITES hors de la
## caisse, et un objet enfonce dans une portiere n'a fui nulle part. Les deux
## defauts sont opposes, et la coque ne promettait que le premier.
##
## Trois etapes, du plus precis au plus grossier — chacune ne rattrape que ce
## que la precedente ne couvre pas :
##
##   1. LA TOLE, relevee case par case sur le .glb. C'est elle qui arrete tout
##      ce qui se voit : garnitures, sieges, planche, tunnel, bas de caisse.
##   2. LE VITRAGE, absent du releve puisqu'on regarde au travers.
##   3. LA COQUE, une borne par axe. Elle ne peut pas fuir, quels que soient
##      l'angle, la vitesse ou le pas de temps.
func _resolve(_delta: float) -> void:
	_grounded = false
	if cabin.shape != null:
		# Deux passes : sortir par un axe peut engager l'objet sur un autre, et
		# la relaxation converge en une de plus. Ce n'est pas une boucle ouverte
		# — deux passes bornent le cout, et la coque ferme le reste.
		for pass_i in 2:
			# Les bornes de l'habitacle sont passees a la grille : sans elles,
			# contre le bas de caisse, "la sortie la moins couteuse" est vers
			# l'exterieur de la voiture, et la coque et la grille se renvoient
			# l'objet a chaque image. Voir cabin_shape.gd, push_out().
			var r: Array = cabin.shape.push_out(position, half,
				cabin.HULL_MIN, cabin.HULL_MAX)
			if not r[2]:
				break
			position = r[0]
			_bounce_off(r[1])
	_push_shell()
	_contain()
	# ET ON SE POSE, UNE SEULE FOIS, A LA FIN. Sur la tole relevee et non sur le
	# bord de la case — voir cabin_shape.gd, settle(). L'ordre compte : pose sur
	# le triangle, l'objet est DANS la case qui le contient, et repasser la
	# resolution derriere le ferait remonter, redescendre, remonter.
	if _grounded and cabin.shape != null:
		position.y = cabin.shape.settle(position, half)


## Le vitrage (cabin.shell), resolu contre l'union comme la tole.
func _push_shell() -> void:
	var need := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var touched := false
	var b_lo := position - half
	var b_hi := position + half
	for s in cabin.shell:
		var lo: Vector3 = s["min"]
		var hi: Vector3 = s["max"]
		var d := Vector3(minf(hi.x, b_hi.x) - maxf(lo.x, b_lo.x),
			minf(hi.y, b_hi.y) - maxf(lo.y, b_lo.y),
			minf(hi.z, b_hi.z) - maxf(lo.z, b_lo.z))
		if d.x <= 0.0 or d.y <= 0.0 or d.z <= 0.0:
			continue
		touched = true
		need[0] = maxf(need[0], hi.x - b_lo.x)
		need[1] = maxf(need[1], b_hi.x - lo.x)
		need[2] = maxf(need[2], hi.y - b_lo.y)
		need[3] = maxf(need[3], b_hi.y - lo.y)
		need[4] = maxf(need[4], hi.z - b_lo.z)
		need[5] = maxf(need[5], b_hi.z - lo.z)
	if not touched:
		return
	var best := 0
	for a in range(1, 6):
		if need[a] < need[best]:
			best = a
	const DIRS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN,
		Vector3.BACK, Vector3.FORWARD]
	var n: Vector3 = DIRS[best]
	position += n * need[best]
	_bounce_off(n)


## Rebond et appui sur une normale de sortie. Seule une sortie VERS LE HAUT pose
## l'objet : c'est ce qui lui donne son frottement, et une paroi n'en donne pas.
func _bounce_off(n: Vector3) -> void:
	if n.y > 0.5:
		_grounded = true
	for a in 3:
		if absf(n[a]) < 0.5:
			continue
		vel[a] = -vel[a] * bounce if absf(vel[a]) > 0.5 else 0.0


## Retient l'objet DANS la coque (cabin.gd, HULL_MIN/HULL_MAX). L'exact inverse
## de _resolve() : les boites le poussent HORS d'elles, la coque le garde DEDANS.
##
## Le mobilier ci-dessus ne ferme pas l'habitacle — c'est une dizaine de boites
## posees cote a cote, et un objet LANCE finit par trouver la fente entre deux.
## Il sortait alors de la caisse et le filet de securite plus bas le renvoyait a
## son point de depart, ce qui se voyait comme "l'objet disparait et reapparait
## au meme endroit". Deux lancers sur trois y passaient.
##
## Une borne par axe ne peut pas fuir : il n'y a pas de recouvrement a detecter,
## donc pas d'angle ni de vitesse qui la prenne en defaut. C'est ce qui rend le
## filet de securite inatteignable, au lieu de l'appeler a la rescousse.
func _contain() -> void:
	if cabin == null:
		return
	var lo: Vector3 = cabin.HULL_MIN + half
	var hi: Vector3 = cabin.HULL_MAX - half

	if position.y < lo.y:
		position.y = lo.y
		_grounded = true              # la coque fait plancher : il faut y frotter
		vel.y = -vel.y * bounce if absf(vel.y) > 0.5 else 0.0
	elif position.y > hi.y:
		position.y = hi.y
		vel.y = -vel.y * bounce if absf(vel.y) > 0.5 else 0.0

	if position.x < lo.x or position.x > hi.x:
		position.x = clampf(position.x, lo.x, hi.x)
		vel.x = -vel.x * bounce if absf(vel.x) > 0.5 else 0.0

	if position.z < lo.z or position.z > hi.z:
		position.z = clampf(position.z, lo.z, hi.z)
		vel.z = -vel.z * bounce if absf(vel.z) > 0.5 else 0.0


## Culbute en vol, puis remise d'aplomb une fois pose.
##
## Un objet lance qui GARDERAIT son inclinaison en se posant s'enfoncerait dans
## le siege : sa boite de collision est alignee sur les axes, elle ne tourne pas
## avec lui. Il revient donc a la pose de repos du jeu — d'aplomb, son cap
## conserve — exactement celle que donne une depose au viseur (interaction.gd,
## `_rest_on`). Un objet pose est ainsi pose de la meme facon, qu'on l'ait
## depose ou jete.
func _tumble(delta: float) -> void:
	var w := spin.length()
	if w > 0.0001:
		basis = Basis(spin / w, w * delta) * basis
	# Tant qu'il vole ou qu'il roule encore, il tourne : le redresser en plein
	# rebond ferait un objet qui se fige en l'air.
	if not _grounded or vel.length() > SETTLE_SPEED:
		return

	spin = Vector3.ZERO
	var fwd := -basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.000001:
		fwd = Vector3.FORWARD
	var flat := Basis.looking_at(fwd.normalized(), Vector3.UP)
	basis = basis.orthonormalized().slerp(flat, clampf(delta * SETTLE_RATE, 0.0, 1.0))
	if basis.get_rotation_quaternion().angle_to(flat.get_rotation_quaternion()) < 0.01:
		basis = flat
		_tumbling = false


func _process(delta: float) -> void:
	# Le halo monte vite et redescend doucement, avec une pulsation lente :
	# dans le noir, un eclat fixe ne se distingue pas d'un reflet.
	_glow = lerpf(_glow, 1.0 if _want else 0.0, clampf(delta * 9.0, 0.0, 1.0))
	if _glow < 0.001:
		# ET ON ETEINT POUR DE BON. Sortir sans rien appliquer laissait au
		# materiau l'energie de l'image d'avant. D'ordinaire elle est deja
		# quasi nulle et personne ne le voit ; mais des que `delta * 9`
		# depasse 1 (un banc a time_scale 6, une image qui traine), la
		# descente se fait en UN SEUL pas et l'objet reste allume a fond,
		# pour toujours — le telephone en main brillait comme une lampe sur
		# les captures. Une image de plus, une seule, et le halo tombe.
		if _lit:
			_lit = false
			_apply_glow(0.0)
		return
	_lit = true
	_pulse += delta * 2.4
	_apply_glow(highlight_energy * _glow * (0.72 + 0.28 * sin(_pulse)))


## Applique l'intensite du halo aux materiaux : a la charge du script derive.
func _apply_glow(_energy: float) -> void:
	pass


func set_highlight(on: bool) -> void:
	_want = on


## Tenu en main : la simulation se tait, c'est la main qui commande.
func hold() -> void:
	held = true
	vel = Vector3.ZERO
	spin = Vector3.ZERO
	_tumbling = false


## Lache : il repart au repos PAR RAPPORT A LA VOITURE, ce qui est le cas quand
## on pose quelque chose. Il n'a aucune vitesse monde a rattraper.
func release() -> void:
	held = false
	vel = Vector3.ZERO
	spin = Vector3.ZERO
	_tumbling = false


## Lance : il repart avec la vitesse qu'on lui donne, EN ESPACE VOITURE.
##
## C'est tout ce qui le separe de release() : la vitesse n'est pas remise a
## zero. Et comme cet espace est celui ou il vit deja, un objet jete vers le
## pare-brise a 170 km/h traverse l'habitacle exactement comme a l'arret — la
## voiture ne le rattrape pas, elle l'emmene. C'est ce que fait un objet lance
## dans un vehicule.
func throw(v: Vector3) -> void:
	held = false
	vel = v
	# Il part de la main, et la main peut etre sortie de la coque : bras tendu
	# vers le pavillon, le poing passe au-dessus. Un objet ne NAIT pas dehors,
	# sinon la coque le rabat des la premiere image et le lancer commence par un
	# sursaut. On le pose au bord, la ou la main l'a vraiment amene.
	if cabin != null:
		position = position.clamp(cabin.HULL_MIN + half, cabin.HULL_MAX - half)
	# Une culbute autour d'un axe perpendiculaire au lancer, comme le poignet
	# l'imprime. Un objet qui traverserait la cabine sans tourner ne se lirait
	# pas comme un lancer mais comme un objet pousse.
	var axis := v.cross(Vector3.UP)
	if axis.length_squared() < 0.000001:
		axis = Vector3.RIGHT           # lance a la verticale : un axe en vaut un autre
	spin = axis.normalized() * (v.length() * TUMBLE_RATE)
	_tumbling = true
	_grounded = false


## Rayon de la sphere de visee. Genereux : viser un objet de 5 cm a un metre
## est sinon nettement trop exigeant.
func grab_radius() -> float:
	return 0.075


## De combien lever l'objet au-dessus de la surface pour qu'il y repose.
func rest_height() -> float:
	return half.y


## Axe de l'objet (repere local) qui se couche sur l'axe de prise du poing, cote
## pouce vers +. Par defaut sa hauteur : une canette se tient debout.
func grip_axis() -> Vector3:
	return Vector3.UP


## Face de l'objet (normale locale) a presenter au joueur quand il le tient.
func front_axis() -> Vector3:
	return Vector3.BACK

