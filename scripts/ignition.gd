extends Node3D
##
## Cle de contact. On DEMARRE ET ON COUPE A LA CLE, pas a une touche.
##
## Le geste est celui de la manivelle de vitre, et c'est voulu : viser, maintenir
## le clic gauche pour que la main vienne s'y poser, puis la MOLETTE. Vers le
## haut on lance le moteur, vers le bas on le coupe. La camera reste libre, comme
## a la manivelle — une cle, on la tourne sans la regarder.
##
## Pourquoi la molette et pas un clic : c'est le seul geste de la souris qui soit
## ROTATIF, et une cle de contact, ca tourne. Le sens tombe alors tout seul —
## vers le haut on arme, vers le bas on coupe — au lieu d'etre une convention a
## retenir. C'est le meme raisonnement que pour les vitres, et il vaut ici pour
## la meme raison.
##
## Pour interaction.gd, cet objet est une manivelle comme une autre : il expose
## `wind()`, donc le clic maintenu le fait passer en GRIPPING, et `crank()`, donc
## la molette lui parvient cran par cran. Rien n'a eu a changer la-bas.
##
## CE QUE LA CLE MONTRE, C'EST L'ETAT DU MOTEUR, pas ce qu'on lui a demande.
## Son angle est deduit de `car` a chaque image et jamais memorise ici : arret,
## contact, et la position demarreur pendant le lancement. Elle en revient donc
## toute seule quand le moteur prend, comme une vraie cle rappelee par son
## ressort, et elle reste juste meme si on lache le clic en plein lancement.
##

## Angle de la cle une fois le moteur en marche.
@export var run_angle := 30.0
## Angle pendant que le demarreur tourne. Au-dela du contact, et transitoire :
## c'est la position qu'on tient contre un ressort dans une vraie voiture.
@export var start_angle := 55.0
## Vitesse de rotation de la cle, en degres par seconde. Un poignet, pas un
## servomoteur : on la voit partir et revenir.
@export var turn_rate := 240.0
## Surbrillance quand on vise la cle.
@export var highlight_color := Color(1.0, 0.62, 0.30)
@export var highlight_energy := 0.55

## La voiture. Pose par car.gd apres la construction : c'est elle qui sait
## demarrer et couper, la cle ne fait que le lui demander.
var car

var _pivot: Node3D
var _head_local := Vector3.ZERO
var _axis := Vector3.RIGHT
var _rest := Basis()
var _angle := 0.0
var _mats: Array[BaseMaterial3D] = []
var _glow := 0.0
var _pulse := 0.0
var _want := false


## `pivot` porte la cle et sa tete, `head` est le mesh de la tete (pour la
## surbrillance), `head_c` son centre en espace voiture, `axis` l'axe du barillet
## ORIENTE VERS LE CONDUCTEUR.
func setup(pivot: Node3D, head: MeshInstance3D, head_c: Vector3, axis: Vector3) -> void:
	_pivot = pivot
	_rest = pivot.transform.basis
	_axis = axis.normalized()
	# La tete, exprimee dans le pivot : elle tourne avec la cle, donc le point ou
	# la main se pose suit la rotation au lieu de rester plante sur le barillet.
	_head_local = pivot.transform.affine_inverse() * head_c
	position = _head_local

	# Materiau dedie : celui du .glb est partage avec le reste de la plastique
	# sombre de la colonne. Sans duplication, viser la cle ferait pulser le
	# cache-colonne entier — exactement le defaut qu'on a corrige aux pare-soleil.
	if head == null or head.mesh == null:
		return
	for s in head.mesh.get_surface_count():
		var src := head.get_surface_override_material(s)
		if src == null:
			src = head.mesh.surface_get_material(s)
		if src == null:
			continue
		var mine := src.duplicate()
		if mine is BaseMaterial3D:
			(mine as BaseMaterial3D).emission_enabled = true
			(mine as BaseMaterial3D).emission = highlight_color
			(mine as BaseMaterial3D).emission_energy_multiplier = 0.0
			_mats.append(mine)
		head.set_surface_override_material(s, mine)


func _process(delta: float) -> void:
	# L'angle suit l'etat du moteur, et il le suit TOUJOURS — pas seulement
	# pendant qu'on tient la cle. C'est ce qui la fait revenir de la position
	# demarreur toute seule quand le moteur prend, et rester juste si on lache le
	# clic en plein lancement.
	_angle = move_toward(_angle, _target_angle(), turn_rate * delta)
	if _pivot:
		_pivot.transform.basis = _rest.rotated(_axis, deg_to_rad(_angle))
		position = _head_local.rotated(_axis, deg_to_rad(_angle))

	var was := _glow
	_glow = lerpf(_glow, 1.0 if _want else 0.0, clampf(delta * 9.0, 0.0, 1.0))
	if _glow < 0.001:
		if was >= 0.001:
			_set_glow(0.0)
		return
	_pulse += delta * 2.4
	_set_glow(highlight_energy * _glow * (0.72 + 0.28 * sin(_pulse)))


## Ou la cle doit etre, vu l'etat du moteur. Negatif : une cle de contact tourne
## dans le SENS HORAIRE vu du conducteur, et l'axe pointe vers lui.
func _target_angle() -> float:
	if car == null:
		return 0.0
	if car.cranking:
		return -start_angle
	return 0.0 if car.stalled else -run_angle


# --- interface pour interaction.gd -----------------------------------------

## Un cran de molette. interaction.gd envoie +1 vers le BAS et -1 vers le HAUT.
##
## Haut : on lance. Bas : on coupe. Il n'y a pas de position intermediaire a
## traverser — une cle en a une (contact sans demarrage), mais elle ne
## commanderait rien dans ce jeu, et un cran qui ne fait rien se lit comme un
## cran perdu.
func crank(notches: float) -> void:
	if car == null:
		return
	if notches < 0.0:
		car.key_start()
	else:
		car.key_off()


## Le contrat de interaction.gd : c'est la presence de cette methode qui fait
## passer le clic maintenu en GRIPPING plutot qu'en simple prise.
##
## Elle n'a rien a faire. Une manivelle de vitre rattrape ici les crans qu'on lui
## a empiles ; une cle, non : elle n'a que trois positions, elle y va tout de
## suite, et son angle est de toute facon rejoue a chaque image dans _process()
## depuis l'etat du moteur.
func wind(_delta: float) -> void:
	pass


func release_grip() -> void:
	pass


## La main se pose sur la TETE de la cle, qui tourne avec elle.
func hand_point() -> Vector3:
	return _pivot.global_transform * _head_local.rotated(_axis, deg_to_rad(_angle))


func grip_hint() -> String:
	return "Maintiens clic gauche : prendre la cle"


func held_hint() -> String:
	if car == null:
		return ""
	if car.cranking:
		return "..."
	if car.stalled:
		return "Molette haut : demarrer"
	return "Molette bas : couper le moteur"


func set_highlight(want: bool) -> void:
	_want = want


## Rayon de la sphere de visee. La tete de cle fait 16 mm : la viser au pixel
## pres serait injouable, et a 7 cm on est encore loin du levier de clignotants.
func grab_radius() -> float:
	return 0.07


func _set_glow(energy: float) -> void:
	for m in _mats:
		m.emission_energy_multiplier = energy
