extends CharacterBody3D
##
## Honda Civic EF (1990), boite manuelle 5 rapports + marche arriere.
## Vue premiere personne depuis le siege conducteur.
##
## Le modele est volontairement arcade : pas de simulation de couple moteur ni
## de patinage d'embrayage. Chaque rapport a une vitesse au rupteur et une
## poussee. Ca suffit pour que la boite se PILOTE comme une vraie : partir en
## 4e patine, rester en 2e hurle, rater un rapport se sent tout de suite.
##
## Reglages a bidouiller en priorite : GEAR_TOP, GEAR_PULL, engine_power,
## steer_rate, steer_return / steer_return_speed pour le rappel du volant, et
## camera_shake si le tremblement gene.
##

const CabinScript := preload("res://scripts/cabin.gd")
const DriverScript := preload("res://scripts/driver.gd")
const InteractionScript := preload("res://scripts/interaction.gd")
const CigPackScript := preload("res://scripts/cig_pack.gd")
const CanScript := preload("res://scripts/can.gd")
const RevolverScript := preload("res://scripts/revolver.gd")
const EngineAudioScript := preload("res://scripts/engine_audio.gd")
const CabinAudioScript := preload("res://scripts/cabin_audio.gd")
const RadioScript := preload("res://scripts/radio.gd")

# Position du conducteur (volant a gauche). L'oeil est a 1,15 m du sol.
const SEAT_X := -0.33
## Assis AU FOND du siege : le dossier du .glb presente sa face avant a z=0.410,
## le buste fait une dizaine de centimetres, l'epaule tombe donc a 0.30 et l'oeil
## juste devant, a 0.28. Avant il etait a 0.10 : le conducteur etait perche sur
## l'avant de l'assise, le nez sur le volant.
const HEAD_POS := Vector3(SEAT_X, 1.15, 0.28)
## Tete sortie par la vitre conducteur. A 1.14 m elle passe au-dessus de la
## ceinture de caisse (0.97) et sous le pavillon (1.275) : le trajet est degage,
## elle ne traverse ni la portiere ni le montant.
const HEAD_OUT := Vector3(-0.92, 1.14, 0.28)
## Tete quand on se retourne a droite : elle vient se placer entre les deux
## appuis-tete, la ou on regarde reellement par la lunette arriere. Deplacement
## comparable a celui de la vitre, 30 cm sur le cote et 24 cm en arriere.
## Verifie degage : entre les appuis-tete (x -0.21..-0.45 et 0.21..0.45),
## au-dessus d'eux (1.165) et sous le pavillon (1.275).
const HEAD_BACK := Vector3(SEAT_X + 0.30, 1.19, 0.50)
## Ou la tete se place quand on s'ENROULE autour du siege : passee entre les
## deux dossiers, basse, au-dessus du plancher arriere. De la, l'epaule droite
## tombe derriere le plan des dossiers et le bras atteint la banquette.
##
## C'est une POSE FIXE, et c'est tout l'interet. L'enroulement est declenche par
## la rotation de la tete ; s'il deplacait la tete LE LONG DU REGARD comme le
## fait le clic droit, tourner ferait avancer et reculer la camera sur son
## propre axe — un zoom, et rien d'autre. Ici, une fois qu'on y est, tourner la
## tete ne deplace plus rien : on regarde autour de soi depuis une place qu'on a
## prise, exactement comme quand on s'est vraiment retourne dans une voiture.
const HEAD_WRAP := Vector3(-0.02, 0.98, 0.86)

## --- se pencher (clic droit maintenu) --------------------------------------
## La tete part DANS L'AXE DU REGARD : on se penche devant le siege passager
## pour voir la boite a gants et le plancher, et on passe entre les deux sieges
## pour attraper ce qui traine sur la banquette. C'est le seul mouvement du jeu
## que le joueur declenche lui-meme — tout le reste (se retourner, sortir la
## tete) est deduit de l'angle de la tete.
##
## La boite ou la tete a le droit d'aller, relevee sur le modele de l'habitacle.
## En x : la vitre conducteur d'un cote (-0.76 pour le panneau de portiere), le
## siege passager de l'autre. En z : la planche de bord devant, l'aplomb de la
## banquette derriere — au-dela on entrerait dans le dossier arriere. En y : le
## pavillon en haut (1.30), assez bas pour aller regarder au plancher.
## Le plancher a 0.70 et pas 0.84 : ce n'est pas lui qui doit retenir la tete,
## c'est `lean_clear`, qui la remonte au-dessus de ce qui est pose dessous. Tant
## qu'aucune borne ne mord, le buste avance EXACTEMENT sur le rayon du regard et
## ce qu'on visait reste sous le viseur. Des que le plancher mordait, il
## poussait la tete HORS de ce rayon, et l'objet passait sous le menton — a 70
## degres de plongee pour 62 de debattement, on ne pouvait plus le viser.
const LEAN_MIN := Vector3(-0.55, 0.70, -0.42)
## Le fond a 1.10 et pas 0.88, pour la meme raison que le plancher a 0.70 : ce
## n'est pas la boite qui doit retenir la tete, c'est `lean_clear`. A 0.88 elle
## mordait des qu'on s'enroulait pour aller chercher derriere son siege, et
## poussait la tete HORS du rayon du regard — l'objet passait alors sur le cote
## au lieu de rester devant, et changeait d'epaule. C'est ce qui le rendait
## improuvable a viser : a un demi-tour de la, le lacet requis bascule d'un bord
## a l'autre pour quelques centimetres de tete.
const LEAN_MAX := Vector3(0.52, 1.21, 1.10)
## Le volant est le seul obstacle DANS le passage. Au-dessus de lui — a gauche
## et en avant — la tete ne descend pas plus bas que sa jante ; ailleurs elle va
## jusqu'a LEAN_MIN.y. Sans cette exception, plonger vers le plancher cote
## conducteur faisait traverser le volant a la camera.
const LEAN_WHEEL_Y := 0.99

# --- son -------------------------------------------------------------------
## Bus audio ou passe tout ce qui vient de dehors, cree a la volee par
## _setup_cabin_bus(). Il porte le passe-bas de la vitre et l'attenuation de
## l'habitacle ; c'est le seul endroit ou le bruit de la voiture est etouffe.
const CABIN_BUS := "Cabine"
## Bus des mecanismes de portiere — pour l'instant la seule manivelle de vitre.
## Sourdine FIXE, contrairement a CABIN_BUS : le mecanisme est enferme dans le
## caisson de la portiere, derriere la garniture, et il l'est tout autant vitre
## montee que vitre baissee. Le faire dependre de l'ouverture serait absurde,
## et surtout ca le rouvrirait pile pendant qu'on tourne la manivelle.
const DOOR_BUS := "Portiere"

# --- boite de vitesses -----------------------------------------------------
const GEAR_NAMES := ["R", "N", "1", "2", "3", "4", "5"]
const GEAR_R := 0
const GEAR_N := 1
## Vitesse au rupteur, rapport par rapport (m/s). C'est CE tableau qui fixe la
## vitesse maxi de chaque rapport : ~50 / 86 / 122 / 155 / 180 km/h.
const GEAR_TOP := [8.0, 0.0, 14.0, 24.0, 34.0, 43.0, 50.0]
## Poussee relative : un rapport court tire fort, un rapport long ne tire plus.
const GEAR_PULL := [0.85, 0.0, 1.0, 0.68, 0.46, 0.33, 0.24]

@export_group("Moteur")
## m/s^2 en 1re, a plein couple. 4.2 et pas 6.0 : a 6 la voiture abattait le
## 0-100 en 8,1 s, soit une Civic Si. La voila a 12,0 s, ce qu'est vraiment une
## EF de base. Les vitesses maxi ne changent pas, elles viennent de GEAR_TOP et
## du rupteur ; seul le temps pour y arriver s'allonge.
@export var engine_power := 4.2
@export var engine_brake := 3.4        # frein moteur en 1re
@export var coast_drag := 0.9          # deceleration au point mort
@export var over_rev_brake := 10.0     # freinage moteur en sur-regime
@export var idle_rpm := 850.0
@export var redline_rpm := 6800.0
## Sous ce regime, en prise, le moteur meurt. 450 tr/min : un moteur chaud tient
## son ralenti a 850 et s'arrete vers 400-500 quand la boite le tire plus bas.
@export var stall_rpm := 450.0
## Combien de temps le moteur broute avant de mourir.
##
## Ce n'est pas de la clemence, c'est ce qui rend le depart possible. A l'instant
## ou l'on lache l'embrayage a l'arret, la vitesse est nulle, donc le regime
## aussi : sans ce delai, tout depart calerait, y compris plein gaz. Avec, la
## voiture a le temps de prendre les quelques km/h qui remontent le regime — et
## si le pied reste leve, elle ne les prend pas et ca cale. C'est exactement le
## comportement qu'on veut, et il tombe tout seul.
##
## Un vrai moteur ne s'arrete pas non plus sur une image : il tousse d'abord.
@export var stall_grace := 0.7
## Regime auquel le demarreur entraine le moteur. A garder egal a STARTER_RPM de
## tools/make_starter_sounds.py : la cadence des compressions du fichier est
## calculee dessus, et l'aiguille la contredirait.
@export var starter_rpm := 250.0
## Combien de temps le demarreur tourne avant que le moteur prenne.
@export var start_time := 0.6
## Frein moteur d'un moteur ARRETE, en prise, en 1re. Plus fort que le frein
## moteur ordinaire : un moteur qui tourne est emporte par sa propre inertie,
## un moteur cale ne fait que resister. C'est ce qui plante la voiture quand on
## cale en roulant.
@export var stall_drag := 6.0
## Vitesse a laquelle le regime retombe A VIDE (debraye ou au point mort), en
## tr/min par seconde, lineaire : le volant moteur freine a couple constant.
## 3500, c'est la ligne rouge au ralenti en 1,7 s. Avant il retombait en lerp
## a 7/s comme la montee : 6000 -> 1700 en un quart de seconde, inaudible.
@export var rpm_fall_rate := 3500.0
## Rupteur : duree de la coupure d'allumage quand le regime touche la ligne
## rouge. Plus c'est long, plus le rebond est ample et lent.
@export var limiter_cut_time := 0.06
## Faux, on peut passer les rapports sans debrayer.
@export var require_clutch := true
## Temps de neutralisation entre deux passages. Sans lui, un seul cran de
## molette envoie plusieurs evenements et on saute deux ou trois rapports.
@export var shift_cooldown := 0.35
## Outil de reglage : plein gaz permanent, sans passer par les touches.
@export var debug_full_throttle := false
## Idem pour le frein, afin de mesurer ce qui decroche dans l'habitacle.
@export var debug_full_brake := false
## Braquage force, -1 a 1. 0 = les touches reprennent la main.
@export var debug_full_steer := 0.0
## Trace dans la console chaque evenement clavier vise par le frein a main.
## Utile si la bascule se remet a partir en vrille.
@export var debug_input := false

@export_group("Chassis")
@export var brake_force := 17.0
## Frein a main en roulant. C'est un frein ARRIERE seulement : il ralentit, il
## n'arrete pas la voiture net. 4 m/s^2, contre 17 pour la pedale.
@export var handbrake_force := 4.0
## Sous 4 m/s il se raidit, sinon "serrer le frein" ne tiendrait pas la voiture.
@export var handbrake_hold := 20.0
## Traînee : proportionnelle a la vitesse, donc elle plafonne la vitesse maxi.
## A 0.16 elle ecrasait tout : chaque rapport butait a 60 km/h, 5e comprise.
@export var rolling_drag := 0.012
@export var max_reverse := 9.0
@export var steer_rate := 1.15         # rad/s a plein braquage et vitesse moyenne
## Acceleration laterale maxi, en m/s^2. C'est l'adherence des pneus : une Civic
## de 1990 sur pneus de route tient 0,8 g, pas 2. Elle fixe le rayon de braquage
## a haute vitesse (r = v^2 / max_lateral) et, par ricochet, ce qui reste en
## place dans l'habitacle en virage.
@export var max_lateral := 8.0
## Vitesse de braquage du volant, en braquage complet par seconde. 1.7 : il faut
## 0.6 s pour aller du centre a la butee, soit un peu moins de 500 degres de
## jante par seconde. A 2.9 on y arrivait en un tiers de seconde, ce qui, avec
## les 270 degres de course, jetait le volant d'un bord a l'autre.
@export var steer_attack := 1.7
## Le volant durcit avec la vitesse : facteur applique a steer_attack a haute
## vitesse. A 0.5 on met deux fois plus longtemps a aller d'une butee a l'autre
## a 130 km/h qu'a l'arret. C'est ce qui enleve le cote nerveux en ligne droite
## sans rien retirer a la maniabilite en manoeuvre.
@export var steer_attack_fast := 0.5
## Inertie du volant. C'est LUI qui enleve la brutalite : sans inertie le volant
## prend sa vitesse de rotation d'un coup a l'appui sur la touche et s'arrete net
## au relachement, ce qu'aucune piece qui pese ne fait. La valeur est la vitesse
## a laquelle la jante prend et perd son elan : 9.0 = environ un dixieme de
## seconde de mise en train. Monter = plus sec, descendre = plus mou et flottant.
@export var steer_inertia := 9.0
## Force du rappel du volant au centre, A PLEINE VITESSE. Ce n'est pas un retour
## automatique de curseur : c'est le couple d'auto-alignement des roues avant
## (la chasse), et il n'existe que si la voiture roule. Le rappel etant
## proportionnel a l'angle, il s'eteint en arrivant au centre : la valeur est
## celle du DEPART, quand le volant est a la butee.
##
## 1.4 : le volant se redresse, mais il prend son temps — a 50 km/h il lui faut
## une bonne seconde et demie pour rentrer depuis la butee. C'est volontairement
## mou. Une direction qui claque au centre des qu'on lache la touche donne
## l'impression de conduire un ressort, pas une voiture.
@export var steer_return := 1.4
## Vitesse (m/s) a laquelle ce rappel atteint sa pleine force. En dessous il
## monte progressivement : nul a l'arret, a peine sensible au pas, franc au-dela.
## 20 m/s = 72 km/h. Monte de 14 a 20 pour que le volant ne se redresse pas tout
## seul en ville : a 50 km/h il ne recoit plus que 70 % du rappel.
@export var steer_return_speed := 20.0
## Part du rappel qui agit a couple constant, independamment de l'angle. Sans
## elle, l'exponentielle approche le centre sans jamais l'atteindre et il reste
## un filet de braquage en ligne droite.
@export var steer_return_floor := 0.22

@export_group("Son")
## Isolation de l'habitacle, en dB, appliquee a tout ce qui vient DE DEHORS :
## moteur, echappement, pneus, vent. C'est le bouton unique pour monter ou
## baisser la voiture entiere sans toucher a la balance entre les sources, qui
## a ete reglee a l'oreille source par source.
##
## Le levier, le frein a main et la manivelle n'y passent pas : ils sont dans
## l'habitacle avec le conducteur, il n'y a pas de vitre entre eux et l'oreille.
@export var cabin_muffle_db := -9.0
## Coupure du passe-bas, vitres FERMEES. Une glace ne baisse pas le son, elle
## en mange le haut : c'est ce qui separe un moteur simplement lointain d'un
## moteur etouffe. Baisser cette valeur enferme davantage, la monter rouvre.
@export var cabin_muffle_hz := 1300.0
## Et vitres grandes ouvertes : le filtre s'efface, le pot revient en clair.
@export var cabin_open_hz := 11000.0
## Coupure du passe-bas de la manivelle. Le son brut est un train de 24 chocs
## par seconde, tres pointu : sa crete est ~19 dB au-dessus de sa moyenne, et
## entendu en clair ca gresille. Le caisson de portiere lui mange le haut, et
## c'est ce qui en fait un "tonc tonc" de mecanisme au lieu d'un raclement.
@export var door_muffle_hz := 700.0
## Attenuation de la manivelle. Elle etait restee au niveau fort pendant que
## tout le reste passait a cabin_muffle_db, donc elle ressortait bien trop.
@export var door_muffle_db := -10.0

@export_group("Camera")
@export var look_sensitivity := 0.0022
## Large des deux cotes : a droite on se retourne dans l'habitacle, a gauche on
## sort la tete par la vitre.
## 165 et pas 130 : la tete etant dehors, c'est seulement au-dela de 150 qu'on
## regarde vraiment le long du flanc de la voiture, et pas dans le champ.
@export var yaw_limit_left := 165.0
## 160 : torsion du buste (40) plus rotation du cou (120). Au-dela, la pose
## n'est plus tenable pour un humain assis dans un siege.
@export var yaw_limit_right := 160.0
## Au-dela de cet angle vers la droite, le conducteur se retourne : le buste
## pivote et la main droite va se poser sur l'appui-tete passager.
@export var look_back_start := 62.0
## Idem vers la gauche : le buste se penche, la tete sort par la vitre et la
## main gauche va se poser sur le haut de la portiere.
@export var lean_out_start := 62.0
## 70 et pas 62 : enroule autour du siege, on est PENCHE AU-DESSUS de ce qu'on
## va chercher, et le regard y plonge de plus de 60 degres. A 62, une canette
## posee derriere son propre siege demandait 63 degres — un de trop, et elle
## devenait invisible donc improuvable a viser, donc impossible a prendre. 70
## degres vers le bas restent dans ce qu'une nuque fait sans effort.
@export var pitch_limit := 70.0
## 50 et pas 46 : la planche de bord du modele Blender est plus profonde que
## l'ancienne en primitives, et a 46 le volant passait sous le cadre.
@export var fov_base := 50.0
@export var fov_fast := 58.0
## Tremblement de caisse. 0 = camera parfaitement stable.
@export var camera_shake := 0.35
## Frequence propre de la suspension apres un coup, en Hz. Une caisse sur ses
## ressorts oscille entre 1 et 2 Hz ; 2,4 parce qu'on regarde la TETE du
## conducteur, qui ajoute sa propre nuque a celle de la voiture.
@export var jolt_hz := 2.4
## Amortissement. 0,3 laisse voir deux ou trois oscillations : au-dela le coup
## se resume a un saut d'image, en dessous la voiture flotte comme un bateau.
@export var jolt_damping := 0.30
## Combien de vitesse de camera (m/s) donne 1 m/s^2 de choc. A 60 m/s^2 — le
## plafond — cela fait 0,096 m/s, soit 6 mm d'amplitude a 2,4 Hz. C'est enorme
## a l'ecran : le tremblement de route ordinaire est a un dixieme de millimetre.
@export var jolt_gain := 0.0016
## Tangage de la tete par metre de debattement, en radians. 6 mm donnent 1,7 deg.
@export var jolt_pitch := 5.0
## De combien la tete avance dans la direction du regard, clic droit maintenu.
## 0,42 m : c'est ce qu'il faut pour passer la tete entre les deux appuis-tete
## et amener l'epaule droite a portee de la banquette. Sans se pencher elle en
## est a 0,80 m, pour 0,58 m de bras — le geste existait, mais l'avant-bras
## s'etirait pour arriver au bout.
@export var lean_reach := 0.55
## De combien la tete reste AU-DESSUS de ce qui est pose sous elle : assises,
## banquette, console, planche, plancher. C'est la seule chose qui l'empeche de
## s'enfoncer dedans, et c'est une correction VERTICALE — voir _fit_cabin.
##
## Ce fut un temps une distance d'arret le long du regard, ce qui paraissait
## plus juste et ne l'etait pas : la longueur du penchement se mettait alors a
## suivre ce qu'on regardait, et tourner la tete faisait avancer et reculer la
## camera sur son propre axe. Un zoom.
@export var lean_clear := 0.25
## Degres de rotation SUPPLEMENTAIRES vers la droite quand on est penche.
##
## Les 160 degres assis sont la limite d'un dos cale contre son dossier. Penche
## et retenu par un bras, le buste n'est plus tenu par le siege : il pivote pour
## de bon, comme quand on se met de trois quarts pour fouiller a l'arriere. 30
## de plus donnent 190, et c'est exactement ce qu'il faut — le banc d'essai a
## montre qu'atteindre la banquette DERRIERE LE SIEGE CONDUCTEUR demande 179
## degres. A 160 on ne pouvait meme pas la regarder, donc pas la viser, donc pas
## y prendre quoi que ce soit : le seul angle mort de l'habitacle.
@export var lean_yaw_bonus := 30.0
## Vitesse d'etablissement du mouvement (1/s). 4,5 : un quart de seconde.
@export var lean_speed := 4.5
## --- s'enrouler autour du siege --------------------------------------------
## CES DEUX SEUILS NE DECLENCHENT RIEN A EUX SEULS : ils ne font que choisir, LE
## CLIC DROIT DEJA TENU, entre se pencher vers ce qu'on regarde et contourner son
## propre siege. Se retourner sans rien tenir ne deplace jamais le corps.
##
## Lacet a droite a partir duquel se pencher, c'est contourner le siege plutot
## que d'aller vers l'avant. 105 : le siege passager se regarde a 99 degres, la
## banquette a partir de 123 — le seuil passe entre les deux.
@export var wrap_yaw := 105.0
## Et plongee minimale, en degres sous l'horizontale : on contourne son siege
## pour aller chercher quelque chose, donc en le REGARDANT. Penche vers l'arriere
## le regard a plat, on regarde par la lunette, et la tete n'a rien a faire entre
## les sieges.
@export var wrap_pitch := 12.0
## Marges de relachement, en degres. Un joueur arrete a la limite verrait sinon
## le buste partir et revenir a chaque frisson de souris — et comme s'enrouler
## ouvre la butee droite a 190, cette oscillation-la emmenerait le regard avec
## elle.
##
## Elles sont LARGES, et pas par prudence : s'enrouler deplace la tete de plus
## d'un demi-metre, ce qui change de plusieurs dizaines de degres le releve de
## ce qu'on regarde. Une canette visee a 123 degres depuis le siege n'est plus
## qu'a 68 une fois qu'on est entre les dossiers. Avec une marge etroite, la
## suivre des yeux faisait sortir de la zone, donc revenir au siege, donc la
## renvoyer a 123 : le buste faisait la navette et l'objet devenait
## inattrapable. On s'enroule sur un geste franc, on se deroule quand on
## revient vers l'avant ou qu'on releve les yeux — pas entre les deux.
const WRAP_YAW_RELEASE := 55.0
## Celle de la PLONGEE, elle, est petite — et ce n'est pas une inconsequence,
## c'est ce que mesure le banc. S'enrouler deplace la tete PRESQUE LE LONG DU
## REGARD : le releve de ce qu'on vise ne bouge donc quasiment pas, la ou son
## gisement, lui, fait un bond. Sur la canette de banquette, le banc lit un lacet
## qui passe de 123 a 68 degres (55 d'ecart, d'ou la marge ci-dessus) pour une
## plongee qui ne va que de 52 a 58 (6 d'ecart). Une marge de 25 sur cet axe ne
## protegeait donc de rien : elle obligeait seulement a lever les yeux de 13
## degres AU-DESSUS de l'horizontale pour se derouler. Relever la tete vers la
## route laissait le joueur enroule entre les sieges, camera avancee, sans aucun
## moyen evident d'en sortir. A 9, la bande morte couvre largement les 6 degres
## mesures, et remettre le regard a plat suffit a revenir s'asseoir.
const WRAP_PITCH_RELEASE := 9.0

var speed := 0.0
var steer := 0.0
## Le volant rentre au centre de lui-meme (chasse des roues), le joueur n'y est
## pour rien : c'est ce qui fait glisser la jante sous les paumes du conducteur.
var wheel_returning := false
## Vitesse de rotation du volant, en braquage complet par seconde. C'est l'etat
## que l'inertie fait vivre d'une image a l'autre : sans lui le volant n'aurait
## aucune memoire de son mouvement et repartirait de zero a chaque image.
var _steer_vel := 0.0
var throttle := 0.0
var braking := 0.0
var clutch := false
## Etat effectif du frein a main, lu par le HUD et le conducteur.
var handbrake_on := false
## Serre a l'arret : il reste actif sans tenir la touche.
var handbrake_latched := false
var _hb_press_used := false        # l'appui en cours a servi a desserrer
var gear := GEAR_N
var rpm := 850.0
## Acceleration de la caisse dans son propre repere, lue par les objets libres.
## Somme de l'inertie de conduite (_accel) et des chocs encaisses (_shock).
var frame_accel := Vector3.ZERO
## L'inertie de conduite seule : virages, freinages, reprises.
var _accel := Vector3.ZERO
## Ce qu'un choc exterieur ajoute, et qui s'eteint tout seul. Voir impact().
var _shock := Vector3.ZERO
## Intensite du dernier choc encaisse, en m/s^2, telle qu'elle a ete INJECTEE.
## Ce n'est pas la meme chose que la pointe relevee dans frame_accel : le temps
## qu'une image passe, le choc a deja perdu un tiers. Les bancs d'essai lisent
## celle-ci pour savoir ce que le coup valait, et l'autre pour savoir ce qui en
## est arrive jusqu'aux objets.
var last_impact := 0.0
## Suspension apres un coup : un ressort amorti dont le deplacement est celui de
## la camera. Purement visuel — ce que les objets ressentent passe par _shock.
var _jolt := Vector3.ZERO
var _jolt_vel := Vector3.ZERO
var _prev_speed := 0.0
## Vrai pendant une coupure d'allumage du rupteur. Lu par le son.
var limiter_cut := false
var _limiter_timer := 0.0
## Moteur arrete. Il ne pousse plus, il freine, et il faut le demarreur.
var stalled := false
## Vrai tant que le demarreur tourne. Lu par le son et par le HUD.
var cranking := false
## Plus personne au volant : l'etrangleur a sorti le conducteur (main.gd le
## pose). Les entrees sont ignorees, la voiture finit sa course toute seule.
var driverless := false
var _stall_timer := 0.0
var _start_timer := 0.0
var _starter_snd: AudioStreamPlayer
var _stall_snd: AudioStreamPlayer

var head: Node3D
var cam: Camera3D
var cabin
var driver
var interaction
## L'autoradio (radio.gd), monte au centre de la planche.
var radio
var engine_audio
var cabin_audio
## Le passe-bas de la vitre, porte par le bus CABIN_BUS. Sa coupure suit
## l'ouverture des vitres a chaque image, voir _process().
var _cabin_lp: AudioEffectLowPassFilter

var _headlights: Array[SpotLight3D] = []
var _taillights: Array[SpotLight3D] = []
var _reverse_lights: Array[SpotLight3D] = []
var _lights_on := true
var _bob := 0.0
var _shift_timer := 0.0
## 0 = assis au fond du siege, 1 = penche a fond dans la direction du regard.
var _lean := 0.0
## Longueur du deplacement en cours, relevee pour le banc d'essai.
var _lean_travel := 0.0
## Vrai quand le regard demande de s'enrouler autour du siege. Il porte
## l'hysteresis : c'est LUI qu'on relit pour savoir de quel seuil on depend.
var _wrapping := false
## Sa version fondue : 0 = le penchement suit le regard, 1 = il rejoint la pose
## fixe d'enroulement (HEAD_WRAP).
var _wrap := 0.0
var _cam_offset := Vector3.ZERO
var _hud: Label
var _flash: Label
var _flash_timer := 0.0
var _hint: Label
var _fps: Label
var _hint_timer := 11.0


func _ready() -> void:
	_setup_cabin_bus()      # avant les noeuds audio : ils y branchent leurs lectures
	_build_collision()

	cabin = CabinScript.new()
	cabin.name = "Cabin"
	add_child(cabin)

	driver = DriverScript.new()
	driver.name = "Driver"
	add_child(driver)

	engine_audio = EngineAudioScript.new()
	engine_audio.name = "EngineAudio"
	engine_audio.idle_rpm = idle_rpm
	engine_audio.redline_rpm = redline_rpm
	# Le bus se pose AVANT add_child : c'est _ready() du noeud audio qui cree
	# les lectures, et une lecture choisit son bus a la construction.
	engine_audio.bus = CABIN_BUS
	add_child(engine_audio)

	cabin_audio = CabinAudioScript.new()
	cabin_audio.name = "CabinAudio"
	cabin_audio.outside_bus = CABIN_BUS
	cabin_audio.door_bus = DOOR_BUS
	add_child(cabin_audio)

	_build_starter_audio()
	# Le conducteur anime le volant et les leviers du modele Blender plutot que
	# d'en fabriquer en primitives.
	driver.use_controls(cabin.wheel_tilt, cabin.wheel_spin, cabin.shift_pivot,
		cabin.brake_pivot, cabin.knob_local, cabin.grip_local)

	_build_head()

	# Prendre et reposer les objets de l'habitacle. A construire apres la tete :
	# il lui faut la camera.
	interaction = InteractionScript.new()
	interaction.name = "Interaction"
	add_child(interaction)
	interaction.cam = cam
	interaction.driver = driver
	interaction.cabin = cabin
	interaction.carrier = self
	# Le plafonnier s'actionne a la main, comme on attrape un objet.
	if cabin.dome_light != null:
		interaction.usables.append(cabin.dome_light)
	# Retroviseur interieur et pare-soleil : on les place en maintenant le clic.
	interaction.adjustables = cabin.adjustables.duplicate()
	interaction.adjustables.append_array(cabin.visors)
	interaction.adjustables.append_array(cabin.windows)
	# La cle de contact : meme geste que la manivelle, donc meme liste. C'est sa
	# methode wind() qui lui vaut d'etre TENUE plutot que prise, pas cette ligne.
	if cabin.ignition != null:
		cabin.ignition.car = self
		interaction.adjustables.append(cabin.ignition)
	# L'autoradio, au centre de la planche : RELEVE sur la bouche de degivrage
	# centrale — la seule cote sure du milieu de planche — puis descendu sous
	# la casquette, face a l'habitacle. Son bouton rejoint la liste de la cle.
	radio = RadioScript.new()
	radio.name = "Radio"
	radio.car = self
	var radio_anchor := Vector3(0.0, 0.86, -0.62)
	for v in cabin.vents:
		if v["label"] == "degivrage central":
			radio_anchor = v["pos"]
	radio.position = Vector3(radio_anchor.x, radio_anchor.y - 0.115,
		radio_anchor.z + 0.115)
	# La facade regarde legerement vers le haut : vue du siege, on la voit de
	# face et pas par la tranche.
	radio.rotation_degrees.x = -14.0
	cabin.add_child(radio)
	interaction.adjustables.append(radio)
	_spawn_props()

	_build_lights()
	_build_hud()


func _physics_process(delta: float) -> void:
	throttle = 1.0 if debug_full_throttle else Input.get_action_strength("accelerate")
	braking = 1.0 if debug_full_brake else Input.get_action_strength("brake")
	clutch = Input.is_action_pressed("clutch")
	var steer_input := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	if debug_full_steer != 0.0:
		steer_input = debug_full_steer

	# Plus personne au volant (l'etrangleur a sorti le conducteur) : les
	# pedales retombent, la jante file. La voiture continue SA vie — elle
	# roule, ralentit au frein moteur, finira par caler — c'est precisement ce
	# qu'on veut regarder depuis le bitume.
	if driverless:
		throttle = 0.0
		braking = 0.0
		clutch = false
		steer_input = 0.0

	# Frein a main : maintenu en roulant, verrouille a l'arret.
	# L'etat "tenu" vient directement de l'entree, pas d'une bascule : c'est ce
	# qui rend le comportement impossible a desynchroniser.
	var hb_held := Input.is_action_pressed("handbrake") and not _hb_press_used
	handbrake_on = hb_held or handbrake_latched

	var v := absf(speed)
	var engaged := not clutch and gear != GEAR_N

	# --- demarreur -------------------------------------------------------
	# Il tourne SEUL une fois lance, jusqu'au bout de son temps : la cle donne un
	# coup de demarreur, elle ne le tient pas. C'est ce que permet un geste
	# ponctuel (un cran de molette) la ou une touche se maintenait.
	if cranking:
		_start_timer -= delta
		if _start_timer <= 0.0:
			cranking = false
			# On ne demarre qu'embraye ou au point mort. Une EF de 1990 n'a aucun
			# contacteur qui l'impose — c'est la MECANIQUE : lancer un moteur mort
			# avec un rapport engage, c'est demander au demarreur de pousser la
			# voiture. Il n'en a pas la force, elle sursaute et rien ne part.
			if clutch or gear == GEAR_N:
				stalled = false
				rpm = idle_rpm
				_stall_timer = 0.0
			else:
				_show_flash("DEBRAYE POUR DEMARRER (MAJ)")
	_update_starter_sound()

	# --- rupteur ---------------------------------------------------------
	# Coupure d'allumage : des que le regime touche la ligne rouge, plus de
	# poussee pendant limiter_cut_time, frein moteur, puis ca repart. C'est ce
	# qui fixe la vitesse maxi de chaque rapport (GEAR_TOP), et ce qui fait
	# rebondir l'aiguille a vide. En prise on regarde la vitesse plutot que le
	# regime lisse : lui n'atteint la ligne rouge qu'asymptotiquement.
	_limiter_timer = maxf(_limiter_timer - delta, 0.0)
	var at_redline: bool = v >= GEAR_TOP[gear] if engaged else rpm >= redline_rpm - 1.0
	if throttle > 0.0 and at_redline and _limiter_timer <= 0.0:
		_limiter_timer = limiter_cut_time
	limiter_cut = _limiter_timer > 0.0

	# --- transmission ----------------------------------------------------
	if engaged:
		var top: float = GEAR_TOP[gear]
		var pull: float = GEAR_PULL[gear]
		if stalled and cranking:
			# Rapport engage : le demarreur pousse LA VOITURE au lieu de lancer
			# le moteur, et il n'en a pas la force. Elle avance de quelques
			# centimetres, elle sursaute, et rien ne part. C'est la raison
			# mecanique pour laquelle on demarre embraye — pas une regle du jeu.
			var dir := -1.0 if gear == GEAR_R else 1.0
			speed = move_toward(speed, dir * 0.45, 2.0 * delta)
		elif stalled:
			# Moteur mort : l'accelerateur ne commande plus rien, et la boite
			# traine un moteur qui resiste. C'est ce qui plante la voiture.
			speed = move_toward(speed, 0.0, stall_drag * pull * delta)
		elif throttle > 0.0 and not limiter_cut:
			var dir := -1.0 if gear == GEAR_R else 1.0
			speed += dir * engine_power * pull * throttle * _torque(rpm) * delta
		else:
			# Pied leve, ou allumage coupe par le rupteur : frein moteur.
			speed = move_toward(speed, 0.0, engine_brake * pull * delta)

		# Sur-regime : retrograder trop bas fait hurler le moteur, et freine fort.
		if v > top:
			speed = move_toward(speed, signf(speed) * top, over_rev_brake * delta)
	else:
		speed = move_toward(speed, 0.0, coast_drag * delta)

	if braking > 0.0:
		speed = move_toward(speed, 0.0, brake_force * braking * delta)
	# Frein a main : faible en roulant, ferme a l'arret.
	if handbrake_on:
		var grab := lerpf(handbrake_force, handbrake_hold,
			clampf(1.0 - absf(speed) / 4.0, 0.0, 1.0))
		speed = move_toward(speed, 0.0, grab * delta)

	speed -= speed * rolling_drag * delta
	speed = clampf(speed, -max_reverse, GEAR_TOP[GEAR_NAMES.size() - 1])

	# Si on tient le frein jusqu'a l'arret complet, il se verrouille : c'est
	# devenu un frein de stationnement, il faudra un nouvel appui pour l'oter.
	if hb_held and absf(speed) < 0.3:
		handbrake_latched = true

	# --- regime moteur ---------------------------------------------------
	var target_rpm := 0.0
	if stalled:
		# Moteur arrete. Le demarreur, lui, le fait tourner a son propre regime
		# — c'est ce qu'on voit a l'aiguille quand on tient la cle.
		target_rpm = starter_rpm if cranking else 0.0
	elif engaged:
		# Type explicite : GEAR_TOP est un tableau const non type, ses elements
		# sortent en Variant et `:=` ne peut rien en inferer.
		var mapped: float = idle_rpm + (v / GEAR_TOP[gear]) * (redline_rpm - idle_rpm)
		# SOUS la vitesse a laquelle ce rapport tourne au ralenti, c'est la boite
		# qui mene le moteur, et elle le mene de moins en moins vite : le regime
		# s'effondre au lieu de rester colle au ralenti. C'est ce facteur, et
		# rien d'autre, qui rend le calage possible — sans lui le modele donnait
		# 850 tr/min a l'arret en 5e, embrayage lache.
		#
		# Au-dessus, il vaut exactement 1 et le modele est celui d'avant, au
		# tr/min pres : les vitesses maxi, le 0-100 et la courbe de couple de ce
		# README ont tous ete mesures la, et aucun ne bouge.
		target_rpm = mapped * clampf(v / _creep_speed(gear), 0.0, 1.0)
	elif limiter_cut:
		target_rpm = idle_rpm          # allumage coupe : le regime retombe
	else:
		# Debraye ou au point mort : le moteur suit l'accelerateur, et vise
		# AU-DELA de la ligne rouge. C'est le rupteur qui l'arrete, pas un
		# plafond : avec un lerp, un plafond ne serait jamais atteint.
		target_rpm = lerpf(idle_rpm, redline_rpm * 1.06, throttle)
	if not engaged and target_rpm < rpm:
		# A vide, le regime retombe a couple constant, donc lineairement :
		# l'inertie du volant moteur. C'est ce qui donne a entendre la descente,
		# et ce qui fait que le rupteur rebondit de 200 tr/min et pas de 1000.
		rpm = move_toward(rpm, target_rpm, rpm_fall_rate * delta)
	else:
		rpm = lerpf(rpm, target_rpm, clampf(delta * 7.0, 0.0, 1.0))
	# Plancher a ZERO, plus au ralenti : un moteur qu'on tire sous son ralenti
	# descend pour de bon, et c'est la moitie du mecanisme du calage.
	rpm = clampf(rpm, 0.0, redline_rpm)

	# --- le moteur cale --------------------------------------------------
	# Seulement EN PRISE : debraye ou au point mort, rien ne tire le moteur vers
	# le bas, il tient son ralenti quoi qu'il arrive. C'est bien "lacher
	# l'embrayage trop bas" qui cale, pas "rouler doucement".
	if not stalled and engaged and rpm < stall_rpm:
		_stall_timer += delta
		if _stall_timer >= stall_grace:
			_stall()
	else:
		_stall_timer = 0.0

	# --- braquage --------------------------------------------------------
	# Le volant est une PIECE MECANIQUE, pas un curseur : il garde l'angle ou on
	# l'a laisse. Ce qui le ramene au centre, ce n'est pas un ressort de jeu
	# video, c'est le couple d'auto-alignement des roues avant — la chasse — et
	# ce couple n'existe QUE si la voiture roule. A l'arret on braque, on lache,
	# ca reste braque, exactement comme dans une vraie voiture.
	v = absf(speed)

	# Le volant durcit avec la vitesse : a 130 km/h on ne le jette plus d'une
	# butee a l'autre. En manoeuvre il reste vif.
	var attack := steer_attack * lerpf(1.0, steer_attack_fast, clampf(v / 35.0, 0.0, 1.0))

	# Ou le volant CHERCHE a aller cette image. Ce n'est pas encore ou il ira :
	# l'inertie plus bas decide de ce qu'il en fait vraiment.
	var goal := steer
	# Le volant revient-il TOUT SEUL ? Le conducteur ne le ramene pas a la main :
	# il desserre et le laisse filer sous ses paumes (driver.wheel_slip). C'est
	# ici, et nulle part ailleurs, qu'on sait faire la difference entre une jante
	# qu'on tourne et une jante qui rentre.
	wheel_returning = false
	if absf(steer_input) > 0.01:
		goal = move_toward(steer, steer_input, attack * delta)
	else:
		# Rappel proportionnel a la vitesse ET a l'angle. Proportionnel a l'angle
		# donc exponentiel : il tire fort quand le volant est loin du centre et
		# s'eteint en arrivant, au lieu du retour a vitesse constante d'avant, qui
		# faisait servomoteur. Proportionnel a la vitesse, donc nul a l'arret.
		var centering := steer_return * clampf(v / steer_return_speed, 0.0, 1.0)
		if centering > 0.0:
			goal = lerpf(steer, 0.0, clampf(1.0 - exp(-centering * delta), 0.0, 1.0))
			goal = move_toward(goal, 0.0, centering * steer_return_floor * delta)
			# Sous 2 degres de jante il n'y a plus rien qui file : sans ce seuil,
			# les mains resteraient desserrees en ligne droite.
			wheel_returning = absf(steer) > 0.008

	# Inertie de la jante. On ne pose pas l'angle, on passe par la VITESSE de
	# rotation, et cette vitesse met un temps fini a s'etablir comme a retomber.
	# C'est toute la difference entre un volant qu'on tourne et un curseur qu'on
	# deplace : au debut de l'appui la jante s'ebranle au lieu de partir a pleine
	# vitesse, et au relachement elle finit son mouvement au lieu de se figer.
	# Le rappel en profite aussi — il n'arrache plus le volant des l'instant ou
	# on lache la touche.
	var want_vel := (goal - steer) / maxf(delta, 0.0001)
	_steer_vel = lerpf(_steer_vel, want_vel, clampf(delta * steer_inertia, 0.0, 1.0))
	steer += _steer_vel * delta
	steer = clampf(steer, -1.0, 1.0)

	# Il faut rouler pour tourner, et on braque moins fort a haute vitesse.
	var grip := clampf(v / 5.0, 0.0, 1.0)
	var stability := lerpf(1.0, 0.38, clampf(v / 40.0, 0.0, 1.0))
	var yaw_rate := steer * steer_rate * grip * stability * signf(speed)
	# Plafond d'adherence. Un pneu ne tient qu'une acceleration laterale donnee ;
	# au-dela la voiture SOUS-VIRE, elle ne pivote pas plus vite. Sans ce plafond
	# le modele generait jusqu'a 2,1 g et un rayon de 42 m a 100 km/h — de quoi
	# arracher tout ce qui traine dans l'habitacle a chaque courbe.
	if v > 0.5:
		var cap := max_lateral / v
		yaw_rate = clampf(yaw_rate, -cap, cap)
	rotate_y(yaw_rate * delta)

	# Acceleration de la caisse dans SON PROPRE repere. Les objets poses dedans
	# en ressentent l'oppose : c'est ce qui les fait glisser au freinage et en
	# virage. Lateral = acceleration centripete (omega * v), longitudinal = la
	# variation de vitesse, l'avant etant -Z.
	if delta > 0.0:
		# Bornee et lissee : un changement de rapport ou le rupteur font sauter
		# `speed` d'une image a l'autre, ce qui donnerait une pointe a plusieurs
		# centaines de m/s^2 et catapulterait tout ce qui traine dans l'habitacle.
		# 60 et pas 25 : le plafond doit laisser passer un CHOC (6 g), sinon rien
		# ne peut plus decrocher ce qui est pose. Voir prop.gd static_mu.
		var raw := Vector3(-yaw_rate * speed, 0.0, -(speed - _prev_speed) / delta)
		_accel = _accel.lerp(raw.limit_length(60.0),
			clampf(delta * 20.0, 0.0, 1.0))
	# Le choc encaisse (impact()) s'AJOUTE a l'inertie de conduite et s'eteint en
	# une soixantaine de millisecondes : c'est un coup, pas un regime. Il passe
	# par la meme limite : au-dela de 60 m/s^2 le jeu ne sait rien transmettre.
	_shock = _shock.lerp(Vector3.ZERO, clampf(delta * 16.0, 0.0, 1.0))
	frame_accel = (_accel + _shock).limit_length(60.0)
	_prev_speed = speed

	velocity = -global_transform.basis.z * speed
	velocity.y = 0.0
	move_and_slide()


func _process(delta: float) -> void:
	_shift_timer = maxf(_shift_timer - delta, 0.0)
	var v := absf(speed)

	# --- regard : se retourner a droite, sortir la tete a gauche ----------
	# La butee droite se resserre quand on se redresse : sans ce rappel, on
	# resterait bloque a 190 degres, assis au fond du siege, la nuque tordue.
	#
	# Elle est lue AVANT le penchement de cette image, et plus apres : celui-ci
	# depend desormais de l'angle du regard (l'enroulement, juste dessous), et
	# l'angle depend de la butee, qui depend du penchement. Se servir de la butee
	# de l'image precedente ouvre la boucle ; celle de l'image en cours la
	# refermerait sur elle-meme.
	head.rotation.y = clampf(head.rotation.y, -_yaw_cap(), _yaw_cap_left())
	var yaw := rad_to_deg(head.rotation.y)

	# --- se pencher : CLIC DROIT, ET RIEN D'AUTRE -------------------------
	# Le buste part la ou on regarde. Pas quand le clic droit sert a lever
	# l'arme, ni quand une main tient une manivelle ou un retroviseur :
	# interaction.gd le dit lui-meme.
	# `interaction` n'est pas type : sans l'annotation, l'inference echoue.
	#
	# SE RETOURNER NE DEPLACE PAS LE CORPS. Une version l'a essaye : au-dela d'un
	# certain lacet a droite, le regard plonge declenchait le penchement tout
	# seul, pour mettre la banquette a portee sans rien demander au joueur. Le
	# resultat etait qu'on se retrouvait A GENOUX SUR LA BANQUETTE juste pour
	# avoir regarde derriere soi — et regarder derriere soi, on le fait tout le
	# temps : pour reculer, pour surveiller, par reflexe. Un mouvement de tete
	# ordinaire ne doit pas emmener le corps avec lui.
	#
	# Se retourner rend donc exactement ce qu'il a toujours rendu : la tete
	# pivote et vient entre les appuis-tete (HEAD_BACK), le buste se vrille sur
	# place, le dos reste cale contre le dossier. Aller chercher quelque chose
	# derriere, ca reste un geste qu'on DEMANDE, en tenant le clic droit.
	var free_hands: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and not interaction.lean_blocked()
	var hold := Input.is_action_pressed("lean") and free_hands

	# --- s'enrouler autour du siege ---------------------------------------
	# Penche ET retourne a droite, le penchement ne suit plus le regard : il
	# rejoint la pose fixe d'enroulement (HEAD_WRAP), qui passe l'epaule derriere
	# le plan du dossier et met la banquette a portee du bras. C'est ce qui
	# distingue "je me penche vers l'avant" de "je contourne mon siege".
	#
	# `hold` en est desormais une condition a part entiere : sans lui, l'angle du
	# regard seul suffisait a l'armer, et c'est precisement ce qu'on ne veut
	# plus. L'hysteresis, elle, reste — une fois le geste engage, on ne veut pas
	# qu'il se defasse parce que suivre l'objet des yeux a fait repasser le lacet
	# sous le seuil.
	var yaw_rel := WRAP_YAW_RELEASE if _wrapping else 0.0
	var pitch_rel := WRAP_PITCH_RELEASE if _wrapping else 0.0
	_wrapping = hold \
		and -yaw >= wrap_yaw - yaw_rel \
		and rad_to_deg(head.rotation.x) <= -(wrap_pitch - pitch_rel)

	# LEQUEL des deux mouvements, ETABLI AVANT le penchement lui-meme.
	#
	# L'ordre n'est pas cosmetique. _lean_offset vaut
	# `follow.lerp(wrapped, _wrap) * _lean` : tant que `_wrap` traine vers 1 au
	# meme rythme que `_lean`, le debut du mouvement est domine par `follow`,
	# c'est-a-dire par le deplacement LE LONG DU REGARD. Regard plonge, la tete
	# partait donc vers l'avant et vers le bas avant d'etre ramenee sur la pose
	# fixe : une AVANCEE franche suivie d'un rattrapage.
	#
	# Quand rien n'est encore penche, il n'y a rien a fondre : `_wrap` se pose
	# d'un coup, et la tete rejoint la pose d'enroulement EN LIGNE DROITE. Le
	# fondu ne sert qu'a changer de mouvement en cours de penchement — tourner la
	# tete vers l'arriere alors qu'on est deja penche, par exemple.
	var wrap_goal := 1.0 if _wrapping else 0.0
	if _lean < 0.02:
		_wrap = wrap_goal
	else:
		_wrap = lerpf(_wrap, wrap_goal, clampf(delta * lean_speed, 0.0, 1.0))

	_lean = lerpf(_lean, 1.0 if hold else 0.0,
		clampf(delta * lean_speed, 0.0, 1.0))
	# Le haut de la plage suit la butee du moment. Penche, elle va jusqu'a 190 :
	# le buste doit continuer a s'enrouler sur toute la course, sinon il sature
	# a 152 degres et les 38 derniers tombent entierement sur la nuque.
	var look_back := smoothstep(look_back_start,
		yaw_limit_right + lean_yaw_bonus * _lean - 8.0, -yaw)

	# Sortir la tete par la vitre est DEDUIT de l'angle du regard ; se pencher
	# est VOULU. Le second efface donc le premier. Sans ca, une fois penche
	# entre les deux sieges, tourner les yeux vers le cote gauche de la
	# banquette envoyait la tete dehors — le lacet avait depasse 62 degres, et
	# le code n'avait aucun moyen de savoir qu'on regardait EN ARRIERE et pas
	# le long du flanc. C'etait le banc d'essai qui le montrait : on visait une
	# canette sur la banquette et on se retrouvait le nez au vent.
	var look_out := smoothstep(lean_out_start, yaw_limit_left - 8.0, yaw) \
		* (1.0 - _lean)

	# La camera se DEPLACE, comme dans Euro Truck : on se penche, on ne fait pas
	# que pivoter la tete. Le lerp donne du poids au mouvement.
	var seated := HEAD_POS.lerp(HEAD_BACK, look_back).lerp(HEAD_OUT, look_out)
	var lean_vec := _lean_offset(seated)
	_lean_travel = lean_vec.length()
	head.position = head.position.lerp(seated + lean_vec, clampf(delta * 7.0, 0.0, 1.0))

	for r in _reverse_lights:
		r.visible = gear == GEAR_R

	# --- camera ----------------------------------------------------------
	# Tremblement de caisse : lent et minuscule. A 60 cm du volant, un centimetre
	# de camera se voit enormement, d'ou des amplitudes de l'ordre du millimetre.
	_bob += delta * (1.3 + v * 0.14)
	var shake := (0.0007 + v * 0.00011) * camera_shake
	# La suspension apres un coup : ressort amorti relance par impact(). Integre
	# en semi-implicite (la vitesse d'abord, la position ensuite avec la vitesse
	# NEUVE) : c'est le seul schema simple qui ne diverge pas quand le pas de
	# temps saute, et il saute au premier ecran de chargement venu.
	# ... mais semi-implicite ne suffit plus quand w * delta depasse 2 : une
	# image de deux secondes (time_scale des bancs sur machine chargee, ecran
	# de chargement) et le ressort EXPLOSE en NaN — releve au banc du sommeil,
	# la camera partait et les retroviseurs visaient l'infini. On integre donc
	# par sous-pas bornes : le meme schema, jamais au-dela de sa stabilite.
	var w := TAU * jolt_hz
	var left := delta
	while left > 0.0:
		var h := minf(left, 1.0 / 60.0)
		left -= h
		_jolt_vel += (-w * w * _jolt - 2.0 * jolt_damping * w * _jolt_vel) * h
		_jolt += _jolt_vel * h
	cam.position = _cam_offset + _jolt \
		+ Vector3(sin(_bob * 1.15) * shake * 1.2, sin(_bob * 1.9) * shake, 0.0)
	# La tete pique du nez avec la caisse. Sans ce tangage, un coup ne fait que
	# translater l'image et se lit comme une secousse de camera, pas comme une
	# voiture qui encaisse.
	cam.rotation.x = _jolt.y * jolt_pitch

	# Roulis : inclinaison dans les virages, plus l'epaule qui tombe quand on se
	# penche a la vitre ou qu'on se retourne.
	var roll := -steer * 0.022 * clampf(v / 8.0, 0.0, 1.0) \
		+ look_out * 0.10 - look_back * 0.05
	# Bornes : un lerp a k * delta > 1 EXTRAPOLE — au premier gros pas de
	# temps, le fov sortait de [1, 179] (releve au banc de boite en
	# time_scale 6 sur machine chargee).
	cam.rotation.z = lerpf(cam.rotation.z, roll, clampf(4.0 * delta, 0.0, 1.0))
	cam.fov = lerpf(cam.fov, lerpf(fov_base, fov_fast, clampf(v / 40.0, 0.0, 1.0)),
		clampf(3.0 * delta, 0.0, 1.0))

	# Tant que le frein est simplement tenu, la main reste sur le levier ;
	# une fois verrouille, elle repart au volant.
	driver.wheel_slip = 1.0 if wheel_returning else 0.0
	driver.update_pose(steer, throttle, braking, clutch, gear,
		handbrake_on, handbrake_on and not handbrake_latched,
		look_back, look_out, lean_vec, delta)
	var win_open := _window_openness()
	# La vitre s'ouvre, le filtre s'efface. Meme puissance 0,6 qu'ailleurs : une
	# fente suffit a laisser rentrer le pot, ce n'est pas proportionnel a la
	# course de la glace.
	if _cabin_lp != null:
		_cabin_lp.cutoff_hz = lerpf(cabin_muffle_hz, cabin_open_hz,
			pow(clampf(win_open, 0.0, 1.0), 0.6))
	# Moteur mort : le son s'eteint AU RYTHME DU REGIME, qui plonge de son cote.
	# C'est ce qui fait entendre un moteur qui meurt plutot qu'un volume qu'on
	# baisse. Pendant le demarreur, en revanche, on coupe net : starter.wav
	# contient deja les compressions du moteur entraine, et les deux ensemble
	# feraient deux moteurs.
	var running := 1.0
	if stalled:
		running = 0.0 if cranking else clampf(rpm / idle_rpm, 0.0, 1.0)
	engine_audio.update(rpm, throttle, not clutch and gear != GEAR_N, delta,
		limiter_cut, win_open, running)
	cabin_audio.update(speed, gear, handbrake_on, delta, win_open)
	cabin.set_gauges(absf(speed) * 3.6, rpm)
	cabin.set_wheels(speed, steer, delta)
	# Apres la camera : les miroirs se calent sur l'oeil, pas sur la voiture.
	# Plus d'oeil dedans (conducteur jete dehors), plus de calage : une camera
	# de miroir visee depuis le bitume a un frustum degenere, et une erreur par
	# image. Ils gardent leur derniere image.
	if not driverless:
		cabin.aim_mirrors(cam.global_position)
	_update_hud(delta)


## De combien la tete se deplace en se penchant, dans le repere de la voiture.
##
## On avance EXACTEMENT LE LONG DU REGARD. C'est ce qui fait que le geste se
## pilote : ce qu'on a sous le viseur y reste, puisqu'on se deplace sur son
## rayon. Une premiere version n'en prenait que la composante horizontale, la
## verticale reduite — et le buste passait AU-DESSUS de ce qu'il visait. La
## canette sur la banquette finissait sous le menton, a 87 degres de plongee
## pour 62 de debattement de nuque : plus moyen de la viser, donc plus moyen de
## la prendre. C'est le banc d'essai qui l'a montre.
##
## `seated` est la pose assise du moment (elle bouge deja quand on se retourne
## ou qu'on sort la tete) : c'est le point de depart, et le plancher de
## l'enveloppe, puisqu'elle, elle est deja connue pour tenir dans la caisse.
##
## LA LONGUEUR EST CONSTANTE. Une version l'ecourtait le long du regard pour
## s'arreter court de la premiere surface rencontree : tres bien tant qu'on ne
## bouge pas la tete, catastrophique des qu'on tourne. En balayant la vue, la
## distance a la surface visee change en permanence — la planche est a 90 cm, la
## console a 60, le vide a l'infini — donc la longueur du penchement avec elle.
## La camera avançait et reculait le long de son propre axe : un ZOOM, et rien
## d'autre. Ce qui empeche de s'enfoncer dans les sieges, c'est desormais la
## garde VERTICALE de _fit_cabin, qui remonte la tete au lieu de la reculer.
func _lean_offset(seated: Vector3) -> Vector3:
	if _lean < 0.001:
		return Vector3.ZERO
	var fwd := -head.transform.basis.z
	if fwd.length_squared() < 0.000001:
		return Vector3.ZERO
	fwd = fwd.normalized()
	# DEUX mouvements, pas un.
	#
	# Le clic droit SUIT LE REGARD : on va vers ce qu'on vise, et ce qu'on vise
	# reste sous le viseur puisqu'on se deplace sur son rayon. C'est un geste
	# volontaire, la camera bouge quand on le demande.
	#
	# L'enroulement rejoint une POSE FIXE. Lui est declenche par la rotation de
	# la tete : s'il suivait aussi le regard, tourner ferait avancer et reculer
	# la camera sur son propre axe, ce qui se lit comme un zoom et pas comme un
	# corps qui se retourne. Une fois la place prise, tourner ne deplace rien.
	var follow := fwd * lean_reach
	var wrapped := HEAD_WRAP - seated
	return _fit_cabin(seated + follow.lerp(wrapped, _wrap) * _lean, seated) - seated


## Hauteur de la tole SOUS ce point, lue dans le releve (cabin_shape.gd) : la
## meme surface que celle ou se posent les objets, puisqu'il n'y en a plus
## qu'une. -INF s'il n'y a rien dessous.
##
## Le test "sous ce point" compte : le releve rend le dessus de la COLONNE, et
## sous la planche de bord ce dessus est la planche elle-meme, 60 cm au-dessus
## des pieds. Une tete qui plonge vers le plancher ne doit pas etre remontee
## par une planche qu'elle a deja passee.
func _surface_under(p: Vector3) -> float:
	if cabin.shape == null:
		return -INF
	var y: float = cabin.shape.height_at(p.x, p.z)
	if y < -90.0 or y > p.y:
		return -INF
	return y


## Ramene un point dans l'habitacle : la boite LEAN_MIN..LEAN_MAX, ELARGIE a ce
## que la pose assise demande deja (tete sortie par la vitre : x -0.92, bien
## au-dela de la boite), plus le volant, qui interdit de descendre la ou il est.
##
## Le plafond du volant est amene en fondu et pas par un test franc : une
## marche, et la camera sauterait de 15 cm des qu'on passe la console.
##
## C'est ici, et seulement ici, qu'on empeche la tete de s'enfoncer dans ce qui
## est pose dessous : on la REMONTE de `lean_clear` au-dessus de la surface. Une
## correction verticale, pas un raccourcissement du mouvement — reculer le long
## du regard pour eviter un obstacle, c'est un zoom des qu'on tourne la tete.
func _fit_cabin(p: Vector3, seated: Vector3) -> Vector3:
	var over_wheel := (1.0 - smoothstep(-0.24, 0.04, p.x)) \
		* (1.0 - smoothstep(-0.04, 0.22, p.z))
	var floor_y := maxf(lerpf(LEAN_MIN.y, LEAN_WHEEL_Y, over_wheel),
		_surface_under(p) + lean_clear)
	var lo := Vector3(LEAN_MIN.x, floor_y, LEAN_MIN.z)
	return p.clamp(lo.min(seated), LEAN_MAX.max(seated))


## Butee de rotation vers la DROITE, en radians. Elle s'ouvre en se penchant :
## voir `lean_yaw_bonus`. Lue au clavier comme a chaque image, pour que les deux
## soient toujours d'accord.
func _yaw_cap() -> float:
	return deg_to_rad(yaw_limit_right + lean_yaw_bonus * _lean)


## Et vers la GAUCHE. Elle s'ouvre AUSSI, du meme angle.
##
## Pas par symetrie decorative : la direction du regard est un seul nombre, et
## les deux butees en decoupent un intervalle. Tant qu'il ne couvre pas le tour
## complet, il reste un secteur — juste derriere — qu'on ne peut atteindre par
## AUCUN des deux cotes, alors qu'il est physiquement devant les yeux. Ouvrir
## les deux a 190 donne 380 degres, donc un recouvrement : ce qui est plein
## arriere se rattrape par la droite comme par la gauche.
func _yaw_cap_left() -> float:
	return deg_to_rad(yaw_limit_left + lean_yaw_bonus * _lean)


## De combien le buste s'est penche, 0 a 1. Sert au banc d'essai.
func lean_amount() -> float:
	return _lean


## Longueur du deplacement du penchement (m). Sert au banc : si elle VARIE quand
## on tourne la tete, la camera avance et recule le long de son propre axe, et
## ca se voit comme un zoom. A penchement etabli, elle doit rester plate.
func lean_travel() -> float:
	return _lean_travel


## Vrai quand le penchement en cours contourne le siege au lieu de suivre le
## regard. Implique le clic droit tenu : se retourner seul ne l'arme jamais.
## Sert au banc d'essai.
func wrapping() -> bool:
	return _wrapping


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Reglage d'un retroviseur : la souris l'oriente, LUI, et le regard est
		# bloque. Viser et orienter avec le meme geste est impossible — on
		# perdrait la glace de vue au premier mouvement.
		if interaction.adjusting:
			interaction.adjust(event.relative)
			return
		head.rotation.y = clampf(
			head.rotation.y - event.relative.x * look_sensitivity,
			-_yaw_cap(), _yaw_cap_left())
		head.rotation.x = clampf(
			head.rotation.x - event.relative.y * look_sensitivity,
			-deg_to_rad(pitch_limit), deg_to_rad(pitch_limit))
	elif event.is_action_pressed("gear_up"):
		_change_gear(1)
	elif event.is_action_pressed("gear_down"):
		_change_gear(-1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		# Clic molette : point mort direct (debraye). Le meme bouton LANCE ce
		# qu'on a en main, et interaction.gd le consomme alors avant nous — il
		# est notre enfant. On ne le recoit donc que les mains vides.
		_select_gear(GEAR_N)
	elif event is InputEventKey and event.is_action("handbrake"):
		_handbrake_key(event)
	elif event.is_action_pressed("headlights"):
		_lights_on = not _lights_on
		for l in _headlights:
			l.visible = _lights_on
		for t in _taillights:
			t.visible = _lights_on


## Un appui sur Espace ne sert qu'a DESSERRER le frein de stationnement.
## Le reste du temps c'est le maintien de la touche qui agit, lu directement
## dans _physics_process.
func _handbrake_key(event: InputEventKey) -> void:
	if event.pressed and not event.is_echo():
		if handbrake_latched:
			handbrake_latched = false
			# Le meme appui ne doit pas re-serrer aussitot : on le neutralise
			# jusqu'au relachement.
			_hb_press_used = true
		else:
			_hb_press_used = false
	elif not event.pressed:
		_hb_press_used = false
	if debug_input:
		print("[frein a main] pressed=%s echo=%s serre=%s neutralise=%s" % [
			event.pressed, event.is_echo(), handbrake_latched, _hb_press_used])


## Cree le bus "Cabine" et son passe-bas. Fait a la volee plutot que dans un
## default_bus_layout.tres : la voiture se construit entierement par code, et un
## fichier de bus a maintenir a part se serait desynchronise du premier coup.
## Idempotent — au rechargement de la scene on retrouve le bus deja la, on ne
## fait que remplacer son effet.
func _setup_cabin_bus() -> void:
	_cabin_lp = _make_muffled_bus(CABIN_BUS, cabin_muffle_hz, cabin_muffle_db)
	# La coupure de celui-la ne bougera plus : voir DOOR_BUS.
	_make_muffled_bus(DOOR_BUS, door_muffle_hz, door_muffle_db)


## Un bus qui envoie vers Master a travers un passe-bas, cree s'il manque.
## Renvoie le filtre, pour qui veut en piloter la coupure.
func _make_muffled_bus(bus_name: String, cutoff: float, volume: float) -> AudioEffectLowPassFilter:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	# Un seul passe-bas sur le bus : sans ce menage, un rechargement de scene en
	# empilerait un de plus a chaque fois et le son s'eteindrait par paliers.
	for e in range(AudioServer.get_bus_effect_count(idx) - 1, -1, -1):
		AudioServer.remove_bus_effect(idx, e)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = cutoff
	AudioServer.add_bus_effect(idx, lp)
	AudioServer.set_bus_volume_db(idx, volume)
	return lp


## Ouverture "acoustique" des vitres, de 0 (fermees) a 1 (une grande ouverte),
## lue par le son. Celle du conducteur compte plein, celle du passager 70 % :
## elle est plus loin de l'oreille. Deux vitres ouvertes ne font pas deux fois
## plus de bruit, d'ou le produit des fermetures.
## La meme ouverture, en public : le sommeil (sleep.gd) la lit — l'air de la
## nuit tient eveille — et le confort des clients la lira aussi.
func window_openness() -> float:
	return _window_openness()


## Une canette bue (interaction.gd, geste DRINKING). La jauge de veille vit
## chez main : la voiture fait le facteur, comme pour la radio.
func on_drink(kind: String) -> void:
	var m := get_parent()
	if m != null and "sleep" in m and m.sleep != null:
		m.sleep.drink_boost(kind)
	_show_flash("Ca reveille")


## La radio a change de cran. Forte, elle tient eveille (x0,55 dans sleep.gd)
## — et elle agacera les clients, mais ca, c'est pour plus tard.
func on_radio(volume: int) -> void:
	var m := get_parent()
	if m != null and "sleep" in m and m.sleep != null:
		m.sleep.radio_factor = 0.55 if volume >= RadioScript.LOUD_AT else 1.0


func _window_openness() -> float:
	var closed := 1.0
	for w in cabin.windows:
		closed *= 1.0 - w.open * (1.0 if w.side < 0.0 else 0.7)
	# Une portiere ouverte (l'etrangleur ne les referme pas) ouvre l'habitacle
	# comme la vitre du meme cote, en plus grand : des 20 degres il n'y a plus
	# de filtre du tout de ce cote-la.
	for side in ["L", "R"]:
		var d: float = clampf(cabin.door_amount(side) / deg_to_rad(20.0), 0.0, 1.0)
		closed *= 1.0 - d * (1.0 if side == "L" else 0.7)
	return 1.0 - closed


## Un choc encaisse par la caisse : un pied de geant qui tombe a cote, ou
## dessus. `accel` est l'acceleration de pointe, en m/s^2, DANS LE REPERE DE LA
## CAISSE (Y en haut, -Z devant).
##
## Elle part a deux endroits, et c'est tout l'interet : dans `frame_accel`, d'ou
## tout ce qui traine dans l'habitacle decolle des que le coup passe 2,4 g (voir
## prop.gd, static_mu) ; et dans la suspension, d'ou la camera tressaute et la
## tete pique du nez. Un choc qui ne ferait que secouer l'image serait un effet
## de post-traitement ; celui-la fait sauter les canettes du siege.
##
## On ne CUMULE pas : deux pieds qui tombent coup sur coup ne font pas un choc
## deux fois plus dur, ils font le plus dur des deux. Cumuler les enverrait tout
## droit au plafond de 60 m/s^2 des qu'il court a cote de la voiture.
func impact(accel: Vector3) -> void:
	last_impact = accel.length()
	if last_impact > _shock.length():
		_shock = accel
	_jolt_vel += accel * jolt_gain


## Courbe de couple grossiere : creux sous 2000 tr/min, plein entre 3200 et
## 5000, ca retombe vers le rupteur. C'est ce qui rend le choix du rapport utile.
func _torque(r: float) -> float:
	var rise := clampf((r - 800.0) / 2400.0, 0.0, 1.0)
	var fade := clampf((redline_rpm - r) / 1800.0, 0.0, 1.0)
	return (0.35 + 0.65 * rise) * lerpf(0.55, 1.0, fade)


## Vitesse a laquelle un rapport fait tourner le moteur A SON RALENTI.
##
## C'est la vitesse en dessous de laquelle il faut debrayer. Elle sort du meme
## tableau que tout le reste : le rapport atteint la ligne rouge a GEAR_TOP,
## donc le ralenti a GEAR_TOP * ralenti / ligne rouge. Rien a regler a la main,
## et rien qui puisse se desynchroniser de GEAR_TOP.
##
##   1re 6,3   2e 10,8   3e 15,3   4e 19,4   5e 22,5   R 3,6  (km/h)
##
## C'est pour ca qu'on cale bien plus facilement en 5e qu'en 1re, sans qu'aucun
## chiffre ne le dise nulle part : c'est la demultiplication qui le veut.
func _creep_speed(g: int) -> float:
	if g == GEAR_N:
		return 0.0
	return GEAR_TOP[g] * idle_rpm / redline_rpm


## Le moteur meurt.
func _stall() -> void:
	stalled = true
	cranking = false
	_stall_timer = 0.0
	_start_timer = 0.0
	if _stall_snd:
		_stall_snd.play()
	_show_flash("CALE — TOURNE LA CLE")


## La cle est tournee vers le demarreur (ignition.gd, molette vers le haut).
##
## Un COUP de demarreur, pas un demarreur qu'on tient : il tourne `start_time`
## puis rend son verdict. Un geste ponctuel ne peut pas se maintenir, et un
## demarreur qui s'arreterait au relachement du clic serait intenable a la
## molette.
func key_start() -> void:
	if not stalled or cranking:
		return
	cranking = true
	_start_timer = start_time


## La cle est ramenee sur l'arret (molette vers le bas). Couper n'est pas caler :
## le moteur s'arrete parce qu'on lui a coupe l'allumage, pas parce que la boite
## l'a etouffe. Meme extinction, autre cause — et le HUD ne raconte donc pas la
## meme chose.
func key_off() -> void:
	if stalled:
		return
	stalled = true
	cranking = false
	_stall_timer = 0.0
	_start_timer = 0.0
	if _stall_snd:
		_stall_snd.play()
	_show_flash("CONTACT COUPE")


## Le demarreur tourne tant qu'on tient la touche. Le son est une BOUCLE, donc
## on le lance et on l'arrete, on ne le rejoue pas : le relancer a chaque image
## le remettrait a zero et on n'entendrait qu'une attaque repetee.
func _update_starter_sound() -> void:
	if not _starter_snd:
		return
	if cranking and not _starter_snd.playing:
		_starter_snd.play()
	elif not cranking and _starter_snd.playing:
		_starter_snd.stop()


## Charge les deux sons du demarreur. Ils vivent dans le bus de l'habitacle,
## comme le moteur : ils viennent tous du meme endroit, sous le tablier.
func _build_starter_audio() -> void:
	_starter_snd = _load_snd("res://assets/audio/starter/starter.wav", -6.0)
	_stall_snd = _load_snd("res://assets/audio/starter/stall.wav", -3.0)


func _load_snd(path: String, db: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		push_warning("son absent : %s (lancer tools/make_starter_sounds.py)" % path)
		return null
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	p.bus = CABIN_BUS
	add_child(p)
	return p


## Molette vers le haut : R -> N -> 1 -> 2 ... Vers le bas : l'inverse.
func _change_gear(step: int) -> void:
	_select_gear(clampi(gear + step, 0, GEAR_NAMES.size() - 1))


## Passe directement au rapport `next` (molette, ou clic molette pour le point
## mort). Memes garde-fous que la molette : cooldown, embrayage, marche arriere.
func _select_gear(next: int) -> void:
	# La boite est verrouillee juste apres un passage : un cran de molette
	# produit plusieurs evenements, sans ca on saute deux ou trois rapports.
	# Silencieux exprès, sinon le HUD clignoterait a chaque cran avale.
	if _shift_timer > 0.0:
		return
	if require_clutch and not clutch:
		_show_flash("DEBRAYE (MAJ)")
		return
	if next == gear:
		return
	if next == GEAR_R and speed > 2.0:
		_show_flash("TROP RAPIDE POUR LA MARCHE ARRIERE")
		return
	gear = next
	_shift_timer = shift_cooldown


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

## Les objets ramassables sont enfants de la caisse et se simulent dans SON
## repere : voir cig_pack.gd. Ils ne touchent jamais au serveur physique.
func _spawn_props() -> void:
	var pack := CigPackScript.new()
	pack.name = "CigPack"
	pack.carrier = self
	pack.cabin = cabin
	cabin.add_child(pack)
	pack.position = CabinScript.PACK_SPAWN
	pack.rotation.y = deg_to_rad(-24.0)
	interaction.grabbables.append(pack)          # reste le premier : les bancs d'essai le cherchent la

	# Canettes, intactes et ecrasees, aux emplacements de cabin.gd.
	for spec in CabinScript.CAN_SPAWNS:
		var can := CanScript.new()
		can.name = "Can_%s%s" % [spec[0], "_Crushed" if spec[1] else ""]
		can.drink = spec[0]
		can.crushed = spec[1]
		can.carrier = self
		can.cabin = cabin
		can.reset_point = spec[2]
		cabin.add_child(can)
		can.position = spec[2]
		can.rotation.y = deg_to_rad(spec[3])
		interaction.grabbables.append(can)

	# Le revolver. Un ramassable comme les autres pour interaction.gd, a ceci
	# pres qu'il expose fire() : c'est ce qui lui vaut de pouvoir etre leve.
	var gun := RevolverScript.new()
	gun.name = "Revolver"
	gun.carrier = self
	gun.cabin = cabin
	cabin.add_child(gun)
	gun.position = CabinScript.REVOLVER_SPAWN
	gun.rotation.y = deg_to_rad(CabinScript.REVOLVER_YAW)
	interaction.grabbables.append(gun)

	# Le mille-pattes s'attrape comme le reste — c'est meme le seul geste qui
	# le sorte de la voiture, si une vitre est assez baissee pour le jeter
	# (centipede.gd, section "La main").
	interaction.grabbables.append(cabin.centipede)


func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.675, 1.34, 3.965)     # cotes reelles d'une Civic EF
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 0.67, 0.0)
	add_child(col)


func _build_head() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = HEAD_POS
	add_child(head)

	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = fov_base
	cam.near = 0.04
	cam.far = 400.0
	head.add_child(cam)
	_cam_offset = Vector3.ZERO


func _build_lights() -> void:
	for side in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.name = "Headlight%s" % ("L" if side < 0.0 else "R")
		l.position = Vector3(side * 0.53, 0.78, -2.04)
		l.rotation_degrees = Vector3(-3.5, side * 3.0, 0.0)
		l.light_color = Color(1.0, 0.95, 0.86)
		l.light_energy = 12.0
		l.spot_range = 80.0
		l.spot_angle = 36.0
		l.spot_angle_attenuation = 0.35
		l.spot_attenuation = 0.85
		# Bas volontairement : sinon la boule de brouillard autour de l'ampoule
		# deborde du capot et se voit depuis le siege.
		l.light_volumetric_fog_energy = 0.12
		l.shadow_enabled = true
		l.shadow_bias = 0.05
		add_child(l)
		_headlights.append(l)

	# Feux arriere. Ils ne servent pas a voir : ils posent une flaque rouge de
	# quelques metres derriere la caisse, et c'est la SEULE chose que les
	# retroviseurs ont a refleter la nuit sur une route deserte. Sans eux les
	# trois glaces sont noires et le joueur croit qu'elles ne marchent pas.
	for side in [-1.0, 1.0]:
		var t := SpotLight3D.new()
		t.name = "Tail%s" % ("L" if side < 0.0 else "R")
		t.position = Vector3(side * 0.62, 0.88, 1.96)
		# Peu plongeant, et une portee de 16 m : les glaces de portiere cadrent la
		# chaussee entre 7 et 14 m en arriere. Une flaque tombee au pied de la
		# caisse serait sous leur champ, donc invisible.
		t.rotation_degrees = Vector3(-11.0, 180.0, 0.0)  # le spot eclaire vers -Z
		t.light_color = Color(1.0, 0.14, 0.09)
		t.light_energy = 3.0
		t.spot_range = 16.0
		t.spot_angle = 62.0
		t.spot_angle_attenuation = 0.6
		t.light_volumetric_fog_energy = 0.16
		t.shadow_enabled = false
		add_child(t)
		_taillights.append(t)

	# Feux de recul : sans eux, se retourner ne montre qu'un mur noir.
	for side in [-1.0, 1.0]:
		var r := SpotLight3D.new()
		r.name = "Reverse%s" % ("L" if side < 0.0 else "R")
		r.position = Vector3(side * 0.45, 0.72, 2.02)
		r.rotation_degrees = Vector3(-9.0, 180.0, 0.0)   # le spot eclaire vers -Z
		r.light_color = Color(0.92, 0.95, 1.0)
		r.light_energy = 5.5
		r.spot_range = 26.0
		r.spot_angle = 48.0
		r.spot_angle_attenuation = 0.5
		r.light_volumetric_fog_energy = 0.10
		r.shadow_enabled = false
		r.visible = false
		add_child(r)
		_reverse_lights.append(r)

	# Pas de lumiere d'habitacle ici : le plafonnier (dome_light.gd, cree par la
	# cabine) est la seule, et il s'allume et s'eteint a la main.


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud.offset_left = -300.0
	_hud.offset_top = -118.0
	_hud.offset_right = -24.0
	_hud.offset_bottom = -22.0
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_color", Color(1.0, 0.45, 0.22, 0.85))
	layer.add_child(_hud)

	_flash = Label.new()
	_flash.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_flash.offset_left = -260.0
	_flash.offset_top = -170.0
	_flash.offset_right = 260.0
	_flash.offset_bottom = -140.0
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.add_theme_font_size_override("font_size", 17)
	_flash.add_theme_color_override("font_color", Color(1.0, 0.35, 0.20, 0.9))
	_flash.modulate.a = 0.0
	layer.add_child(_flash)

	_fps = Label.new()
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.offset_left = -140.0
	_fps.offset_top = 16.0
	_fps.offset_right = -20.0
	_fps.offset_bottom = 40.0
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps.add_theme_font_size_override("font_size", 13)
	_fps.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 0.35))
	layer.add_child(_fps)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 24.0
	_hint.offset_top = -76.0
	_hint.offset_right = 700.0
	_hint.offset_bottom = -22.0
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.text = "ZQSD / WASD / fleches : conduire    Maj : embrayage    Molette : rapports, clic : point mort (ou lancer)\nH : phares    Espace : frein a main    Souris : regarder    Vise la cle et maintiens clic gauche : demarrer"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88, 0.5))
	layer.add_child(_hint)


func _show_flash(text: String) -> void:
	_flash.text = text
	_flash_timer = 1.4


func _update_hud(delta: float) -> void:
	var kmh := int(round(absf(speed) * 3.6))
	# Moteur arrete : on le dit a la place du regime. Zero tr/min se lit comme un
	# compteur en panne, pas comme un moteur mort.
	var line := "MOTEUR ARRETE" if stalled and not cranking \
		else ("DEMARREUR" if cranking else "%d tr/min" % int(round(rpm)))
	_hud.text = "%s    %d km/h\n%s%s" % [
		GEAR_NAMES[gear], kmh, line,
		"\nFREIN A MAIN" if handbrake_on else ""]
	_hud.add_theme_color_override("font_color",
		Color(1.0, 0.25, 0.15, 0.95) if rpm > redline_rpm * 0.9 or stalled
		else Color(1.0, 0.45, 0.22, 0.85))

	_fps.text = "%d ips" % Engine.get_frames_per_second()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		_flash.modulate.a = clampf(_flash_timer / 0.5, 0.0, 1.0)

	if _hint_timer > 0.0:
		_hint_timer -= delta
		_hint.modulate.a = clampf(_hint_timer / 2.5, 0.0, 1.0)
