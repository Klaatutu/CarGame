extends RefCounted
##
## LE BANC : est-ce que le jeu tourne pour quelqu'un, ou pour une mesure ?
##
## POURQUOI CE FICHIER EXISTE, ET CE QU'IL REND A CELUI QUI EST DEVANT L'ECRAN.
## -------------------------------------------------------------------------
## Un banc d'essai n'a pas de mains. Il pousse ses clics et ses mouvements de
## souris avec Input.parse_input_event, et le jeu les recoit comme les vrais —
## a une condition pres : car.gd et interaction.gd ne lisent la souris QUE
## capturee (Input.MOUSE_MODE_CAPTURED). C'est juste, en jeu : on ne conduit
## pas avec un curseur qui traine sur le bureau, et une glace qu'on oriente a
## la souris n'a pas de sens si la souris appartient encore a Windows.
##
## D'ou la capture au demarrage, et d'ou le probleme : elle ARRACHE le curseur
## de celui qui est devant l'ecran. Un chantier de villes, c'est deux cents
## lancements de bancs — la souris ne s'appartient plus de la matinee, et le
## joueur n'a rien demande.
##
## Or le banc n'a AUCUN besoin de cette capture : ses evenements sont
## synthetiques, ils n'ont jamais touche un peripherique. Ce qu'il lui faut,
## c'est le DROIT D'ENTREE, pas le curseur. On separe donc les deux — le banc
## entre, le curseur reste a son proprietaire.
##
## COMMENT ON SAIT QU'ON EST UN BANC : les arguments utilisateur de la ligne
## de commande. `godot --path . -- phonetest` en passe un ; le jeu normal n'en
## passe aucun, et main.gd dispatche deja dessus. La reponse est mise en cache
## a la premiere question : elle ne peut pas changer en cours de partie.
##

static var _tested := false
static var _on := false


## Vrai quand le jeu a ete lance pour un banc d'essai.
static func active() -> bool:
	if not _tested:
		_tested = true
		_on = not OS.get_cmdline_user_args().is_empty()
	return _on


## La souris est-elle a nous ? Capturee, ou bien c'est un banc qui pousse ses
## propres evenements — et ceux-la n'ont pas de curseur a capturer.
##
## C'est le SEUL test que doivent faire car.gd et interaction.gd. Comparer
## directement a MOUSE_MODE_CAPTURED remettrait le banc a la porte.
static func mouse_ours() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or active()


## Prendre la souris — sauf pour un banc. Tous les points de capture du jeu
## passent par ici : il n'y en a pas un seul qui ait une raison de voler le
## curseur a quelqu'un qui ne joue pas.
static func capture() -> void:
	if not active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
