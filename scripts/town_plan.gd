extends RefCounted
##
## LE PLAN D'UNE VILLE — de la donnee, et rien d'autre.
##
## Aucun Node, aucun Mesh, aucune texture : des tableaux de nombres qui disent
## ou passent les rues, ou sont les murs, et quelles fenetres brulent. Le monde
## n'en est qu'une LECTURE — town.gd extrude les memes chiffres que ceux dont
## gps_map.gd tire ses traits. C'est pour ca que la carte du telephone ne peut
## pas mentir sur une ville : elle n'est pas un schema de la ville, elle EST la
## ville, au metre pres.
##
## LE REPERE. Tout vit en coordonnees curvilignes (s, u) : `s` = metres le long
## de la traversante depuis le panneau d'entree (positif vers l'avant), `u` =
## decalage lateral (positif a droite). Dans le monde, la traversante COURBE —
## road.gd la bride a 0,0015 rad/m et pas a zero, parce que 340 m de regle
## plate reveilleraient la monotonie de sleep.gd (mono_after 10 s). Dans (s, u)
## elle est droite. C'est ce qui fait qu'un carrefour est un RECTANGLE et pas
## un eventail : toute rue est parallele ou perpendiculaire au tronc, l'angle
## vaut 90 degres exactement, sans un seul calcul d'angle ni un seul 1/|sin|.
## Une fois deplies dans le monde, les ilots deviennent legerement
## trapezoidaux — c'est plus organique, pas moins.
##
## CE QUI EST ECRIT A LA MAIN : la forme — une ECHELLE : un tronc, trois ou
## quatre transversales, une ou deux paralleles — et les noms de rue. C'est ce
## qu'est un bourg francais, et c'est ce qui permet de faire le tour du pate
## quand on s'est trompe de rue.
## CE QUI EST TIRE : le nombre de rues, leurs abscisses, leur etendue, les
## batiments, les fenetres allumees. La graine vient de map.seed_of(id) : deux
## parties ont la MEME Corbeny, et un bourg laid se re-tire en changeant un
## entier dans map.gd, sans toucher a une ligne de geometrie.
##
## DEUX PROPRIETES GARANTIES PAR CONSTRUCTION, jamais par chance :
##  - tout carrefour est un rectangle (voir ci-dessus) ;
##  - le graphe des rues est CONNEXE et porte au moins un CYCLE. Chaque
##    transversale coupe le tronc (u = 0 est toujours dans son etendue, qui va
##    au moins de -34 a +34) ET chaque parallele — les paralleles sont tirees
##    APRES les transversales, sous la contrainte de rester a RAIL_MARGIN en
##    deca du bras le plus court, jamais l'inverse. Le nombre cyclomatique vaut
##    alors paralleles x (transversales - 1), soit 2 au minimum. Sans cycle, se
##    tromper de rue serait une impasse ; avec, c'est un detour.
##
## LA MEMOIRE, mesuree au tas et pas estimee. Batiments, lampadaires et
## carrefours sont des PackedFloat32Array PLATS et paralleles : dans Godot 4,
## un Dictionary de quatre cles pese 675 octets et un de neuf cles 980, quand
## les nombres qu'il porte en font seize. Poser les 73 carrefours des huit
## villes en Dictionary coutait 49,3 Ko ; a plat, 1,6 Ko.
##
## Les huit plans pesent 150 Ko, pas les ~50 annonces. Le reste tient aux 81
## Dictionary qui portent des NOMS — 49 rues et 32 adresses, 79 Ko — et a la
## grille de nearest, 30 Ko. Ce sont les deux seuls endroits ou l'on paie une
## table de hachage, et les deux sont ceux ou l'on lit par nom.
##
## Les fenetres allumees d'un batiment tiennent dans UN float du 7-uplet, en
## masque de bits : 8 travees x 3 etages = 24 bits, et un float32 represente
## exactement les entiers jusqu'a 2^24. Vingt-cinq bits ne passeraient plus —
## d'ou les plafonds WIN_BAYS_MAX et WIN_FLOORS_MAX, qui ne sont pas
## decoratifs.
##

const MapScript := preload("res://scripts/map.gd")

## = la constante STEP de road.gd. Pas de preload : road.gd charge deja
## town.gd, qui chargera ce fichier — on ne referme pas la boucle pour un 2,0.
## (On cite une constante, pas une ligne : le renvoi « road.gd:32 » qui tenait
## ici designait deja autre chose.)
const STEP := 2.0

const CROSS := 130          # echantillons de traversee = 260 m, panneau -> sortie
const PAD := 20             # echantillons dessines avant/apres = 40 m de chaque cote

# Les largeurs. TRUNK_HALF et SHOULDER valent ROAD_HALF et SHOULDER du ruban
# national (road.gd) : la couture l'exige, la ville ne les choisit pas.
const TRUNK_HALF := 3.4
const SHOULDER := 2.4
const WALK_TRUNK := 2.2     # trottoir en plus, de 5,8 a 8,0 m de l'axe
const STREET_HALF := 2.6    # 5,2 m de chaussee : deux voitures se croisent au pas
const WALK := 1.6           # trottoir de rue, de 2,6 a 4,2 m

const SETBACK := 6.0        # facade / axe de rue (3,4 m de trottoir libre devant)
const SETBACK_TR := 10.0    # facade / axe de la traversante
## Aucun batiment a moins de ca d'un carrefour, mesure de l'EMPREINTE de la
## maison — pas de son centre. C'est ce qui rend un carrefour LISIBLE dans les
## phares : on voit le trou avant d'etre dedans, et ce qu'on voit, c'est un MUR.
##
## L'INVARIANT PORTAIT SUR LES CENTRES, ET C'EST LA QU'IL MENTAIT. Il tenait,
## d'ailleurs — 15,62 m au plus juste pour 12 demandes —, mais le curseur
## sautait a CORNER_FREE pile et la maison, elle, a une largeur : le mur le plus
## proche d'un croisement etait a 7,59 m de son milieu, et 120 couples
## mur/carrefour sur 5 102 passaient sous les 12 m. Le plan, lui, promet 12 m
## sans dire de quoi. Le curseur saute donc maintenant a CORNER_FREE plus la
## demi-largeur de la plus etroite des facades (3,0 m), et le rabot de largeur
## de _lay_blds retaille les plus larges : 12,73 m au plus juste, zero couple
## sur 4 691 sous les 12 m.
##
## CE QUE LA PROMESSE COUTE, releve en recompilant le fichier des cinq facons
## (maisons sur les huit villes, mur le plus proche d'un carrefour, couples
## mur/carrefour sous les 12 m) :
##   saut sur le centre (l'etat d'avant)  562 maisons, mur a 7,59 m, 120 fautes
##   refus pur, garde sur le centre       512 maisons, 8,40 m, 55 fautes
##   refus pur, garde sur l'empreinte     462 maisons, 13,04 m, zero
##   SAUT sur l'empreinte (ici)           515 maisons, 12,73 m, zero
##   saut de 12 + la demi-largeur MAXI    442 maisons, 13,49 m, zero
## 47 maisons sur 562, soit 5,9 par bourg, et le compte de densite plus bas les
## porte. C'est le prix d'une promesse tenue : la ligne retenue est la seule des
## cinq qui rende plus de maisons que l'ancien refus (515 contre 512) ET le trou
## que le plan annonce.
const CORNER_FREE := 12.0
## Ce qu'un mur laisse AU-DELA du bord de trottoir d'une rue qui n'est pas la
## sienne. Une MARGE, et non plus un nombre absolu — le changement n'est pas
## cosmetique : le bourg a DEUX emprises, 4,2 m de demi-emprise pour une rue et
## 8,0 pour le tronc, et l'ancien 4,5 m unique derivait de la premiere. Releve
## avant la correction, marge mini facade/axe par genre : tronc 7,792 m,
## transversale 5,606, parallele 4,560 — soit deux maisons de Vieux-Bourg a
## 0,21 m DANS le trottoir de la nationale. CORNER_FREE sauvait le reste par
## accident, pas par construction. Apres : 8,519 / 5,303 / 4,748, et zero
## empietement. La garde vaut donc edge_half(rue) + ca — 8,5 m pour le tronc,
## 4,7 pour une rue —, et _flatten la range a plat dans _se pour ne pas la
## relire dans un Dictionary 4 700 fois par ville.
const KEEP_CLEAR := 0.5

const LAMP_EVERY := 30.0    # m de rue entre deux lampadaires

## COMBIEN DE MAISONS UNE VILLE PEUT PORTER, et pourquoi ce n'est pas 120.
## Le plan annonce « 880 m x 2 cotes / 11,5 m moins les abords de carrefour
## ~= 120 » — PLAN_VILLES.md, section 4.3 « Ilots et batiments », ou il porte
## desormais sa propre correction ; le renvoi « PLAN_VILLES.md:283 » qui tenait
## ici designait un tout autre paragraphe, et le depot cite une section, pas
## une ligne. Les deux premiers termes sont justes, le troisieme n'a jamais ete
## soustrait. Releve sur les huit villes : 1 843 m de lineaire de facade par
## bourg (921 m de rue, deux cotes) dont les abords de carrefour —
## 15 m de part et d'autre de neuf carrefours, sur les DEUX rues de chacun et
## les deux trottoirs de chaque rue, unions faites — retirent 52 %. Il reste
## 885 m, soit 77 emplacements a 11,5 m d'entraxe : c'est le PLAFOND
## GEOMETRIQUE, et il vaut 77, pas 120. Pour tenir 120 il faudrait un entraxe
## de 7,4 m, donc une facade moyenne de 5,9 m quand BLD_W en promet 6 a 13. Le
## plan se contredit lui-meme, et c'est LUI qu'il faut corriger (le budget de
## sommets de sa surface 5 avec).
##
## Ces 15 m sont CORNER_FREE plus la demi-largeur de la plus etroite des
## facades : c'est ce que le curseur saute vraiment depuis que l'abord de
## carrefour se mesure sur l'empreinte. Avec les 12 m d'avant, le meme calcul
## rendait 43 % d'abords, 1 051 m utiles et un plafond de 91.
##
## Sous ce plafond, le coin d'ilot prend encore sa part : deux rangees
## perpendiculaires se disputent le meme carre a chaque quart de carrefour, et
## la seconde posee y perd sa maison — 154 candidats sur 705. Releve final :
## 64,4 maisons par bourg (de 60 a 70), 8,05 m de facade moyenne, 58,6 % du
## lineaire utile bati. C'etaient 70,3 quand l'abord se mesurait sur les
## centres — et le taux de remplissage, lui, n'a pas bouge d'un dixieme : 58,6 %
## avant comme apres. Ce n'est pas la rangee qui s'est desserree, c'est le
## carrefour qui a pris sa place.
##
## Et l'entraxe, lui, ne bride qu'a peine — mesure, en recompilant le fichier
## avec d'autres valeurs : 9-14 m rend 64,4 maisons par ville, 8-13 en rend
## 67,0, 7,5-12 en rend 66,9, 7-11 en rend 66,8, 6,5-10 en rend 64,9, 10-15 en
## rend 61,9, 11-16 en rend 58,5. Le descendre a 8-13 rapporterait donc 2,6
## maisons par bourg ; ce n'etait pas vrai du temps de la garde sur les
## centres, ou toute valeur plus serree en PERDAIT. On garde quand meme les
## 9 a 14 m du plan : un ecart au plan se decide dans le plan.
const BLD_PITCH := Vector2(9.0, 14.0)     # entraxe des facades
const BLD_W := Vector2(6.0, 13.0)
const BLD_D := Vector2(8.0, 12.0)
const BLD_H := Vector2(4.6, 9.4)
## Vide mini entre deux facades voisines. La largeur d'un batiment est BRIDEE
## par l'entraxe qui le precede : sans ca, 13 m de facade a 9 m d'entraxe font
## deux maisons qui se traversent, et le brouillard ne le cache pas de pres.
const BLD_GAP := 1.5
const BLD_YAW := 4.0        # lacet maxi, en degres : pose la, pas aligne au cordeau

const WIN_P := 0.30         # une travee-etage sur trois est allumee
const WIN_BAY := 1.6
const WIN_FLOOR := 2.6
const WIN_BAYS_MAX := 8     # 8 x 3 = 24 bits : la limite exacte du float32
const WIN_FLOORS_MAX := 3

## QUATRE portes par bourg, jamais voisines de palier. La BAIE de validation
## (16 x 4,5 m le long du bon trottoir) ne vit pas ici : c'est le taxi qui juge
## un arret, pas le plan qui range des nombres. Ses deux constantes ont trop
## longtemps dormi dans ce fichier sans qu'une seule ligne les lise — elles
## naitront ou elles servent.
const ADDR_N := 4
const ADDR_APART := 25.0    # deux adresses ne sont jamais voisines de palier

## Transversales : TROIS OU QUATRE. Le plan en annoncait "3 a 5" ;
## l'arithmetique dit non. Cinq transversales espacees d'au moins 48 m
## demandent 4 x 48 = 192 m, et la plage [40, 220] n'en offre que 180. On garde
## la plage et l'espacement — ce sont eux qui font l'ilot : 48 m moins deux
## fois les 15 m que le curseur saute a chaque carrefour laissent 18 m de
## facade, de quoi poser une maison, deux quand l'entraxe tire court (9 m au
## plus court, et 15 + 9 = 24 tient encore) — et on plafonne le compte. Tous
## les autres chiffres annonces (huit
## carrefours, ~880 m de rue cumulee) sont ceux de quatre transversales : ils
## tombent juste.
const CROSS_N := Vector2i(3, 4)
const CROSS_S := Vector2(40.0, 220.0)
const CROSS_GAP := 48.0
const ARM := Vector2(34.0, 62.0)          # etendue d'une transversale, de chaque cote

## Paralleles : UNE OU DEUX. Le plan disait "0 a 2" ; zero est interdit ici.
## Sans parallele, le graphe est un peigne : nombre cyclomatique nul, aucun
## tour du pate possible, et le bourg n'est plus qu'un couloir. C'est la seule
## rue qui donne une SECONDE CHANCE quand on a rate la bonne.
const RAIL_N := Vector2i(1, 2)
const RAIL_U := Vector2(26.0, 44.0)
## De combien une TRANSVERSALE doit depasser la parallele qu'elle croise : le
## tirage de u est borne par le bras le plus court, moins ca. C'est tout ce que
## cette marge promet, et l'ancien commentaire promettait davantage — « en deca,
## le carrefour tomberait au bout de la rue : un T, pas un croisement ». Les
## paralleles, elles, vont de s_first a s_last : leurs carrefours avec la
## PREMIERE et la DERNIERE transversale tombent exactement sur leurs propres
## bouts. Releve : 26 des 73 carrefours des huit villes sont des T, par
## construction. Ce n'est pas un defaut de geometrie — une venelle de bourg
## s'arrete sur la rue qu'elle rejoint, elle ne la depasse pas de huit metres
## pour finir en cul-de-sac. Le cycle, lui, ne tient pas a ces bouts : il tient
## a ce que CHAQUE transversale traverse CHAQUE parallele, et c'est cette marge
## qui le garantit.
const RAIL_MARGIN := 8.0

## Le pas de la grille de nearest(). Vingt metres, soit un peu plus qu'une
## largeur d'ilot : DANS le bourg, une requete visite un ou deux troncons
## (quatre au pire sur les huit villes), jamais les sept. Dehors, la grille
## n'est plus ouverte du tout et les sept rues se balaient — c'est moins cher
## que de chercher des cases la ou il n'y en a pas (voir nearest).
const GRID := 20.0

## Les noms, ecrits a la main. Les huit bourgs de la carte se PARTAGENT la
## liste : NAMES_PER_TOWN noms chacun, dans l'ordre ou map.gd les ecrit, et une
## ville n'en consomme jamais plus de six (quatre transversales, deux
## paralleles). Deux villes ne peuvent donc pas porter la meme plaque, et ce
## n'est pas une chance, c'est une partition — une ville se reconnait a ses
## noms de rue avant de se reconnaitre a son plan. Meme chose pour la
## Grand-Rue : une par ville, prise a son rang.
##
## Une ville qui n'est PAS sur la carte — les bancs en arment — pioche dans
## toute la liste : elle a droit a un plan, pas a un quartier reserve.
##
## DEUX PIEGES DE CETTE PARTITION, ecrits parce qu'ils ne se voient pas.
##  1. NAMES compte 56 entrees = 8 x 7, pas une de rab. Ajouter une neuvieme
##     ville a map.gd sans allonger NAMES demandait la tranche [56, 63), qui est
##     VIDE : _take rendait "rue Sans-Nom" sur toutes les plaques sauf celle du
##     tronc, sans une erreur et sans un avertissement. Mesure en retrecissant
##     la partition a quatre quartiers : la cinquieme ville sortait avec 5 de
##     ses 6 rues nommees "rue Sans-Nom". D'ou le garde-fou de
##     _generate, qui compte les quartiers au lieu de les supposer — desormais
##     elle pioche dans toute la liste, et elle le dit.
##  2. Le rang est une POSITION dans le dictionnaire de map.gd, pas une
##     identite. Inserer une ville ailleurs qu'en fin de liste decale le rang de
##     toutes les suivantes et RENOMME leurs rues, alors que leur graine n'a pas
##     bouge : le plan est le meme, les plaques ont change. Aucun partage par
##     rang ne peut y echapper ; le jour ou ca genera, la reponse est une cle
##     "names" ecrite a la main dans map.gd, pas un calcul ici.
const NAMES_PER_TOWN := 7

const TRUNK_NAMES := [
	"Grand-Rue", "rue de la Republique", "route de Paris", "avenue de la Gare",
	"rue Nationale", "rue du Pont", "cours Saint-Roch", "route des Forges",
	"rue de la Poste", "rue Basse",
]

const NAMES := [
	"rue des Tanneurs", "quai de la Vanne", "ruelle du Four", "rue du Pressoir",
	"rue de l'Abreuvoir", "impasse des Lavandieres", "rue du Bief",
	"chemin des Aulnes", "rue de l'Eglise", "rue du Puits-Sale",
	"ruelle des Chats", "rue des Halles", "rue du Chevet",
	"venelle des Meuniers", "rue de la Tuilerie", "rue des Corroyeurs",
	"chemin du Lavoir", "rue du Cimetiere", "rue des Sabotiers",
	"ruelle du Cadran", "rue de la Boucherie", "rue des Vignes",
	"quai des Foulons", "rue du Marechal-Ferrant", "rue de la Herse",
	"chemin des Osiers", "rue des Cordiers", "impasse du Colombier",
	"rue du Vieux-Marche", "rue de la Fontaine", "ruelle des Ecoles",
	"rue des Chaudronniers", "chemin de la Garenne", "rue du Beffroi",
	"rue des Roseaux", "venelle du Guet", "rue de la Cure",
	"rue des Charbonniers", "quai de l'Ecluse", "rue du Sechoir",
	"rue des Jardins", "ruelle Traversiere", "rue de la Poterne",
	"chemin des Sauniers", "rue du Guichet", "chemin des Peupliers",
	"rue de la Monnaie", "ruelle Saint-Blaise", "rue des Etuves",
	"quai du Moulin-Neuf", "rue de la Trinite", "chemin des Sablons",
	"rue des Bateliers", "venelle du Puy", "rue de la Croix-Verte",
	"impasse des Merciers",
]

var id := ""

## Les rues. Chacune est un Dictionary :
##   kind  "trunk" (la traversante), "cross" (perpendiculaire), "rail" (parallele)
##   s, u  la coordonnee FIXE : `s` pour une transversale, `u` pour les autres
##   a, b  l'etendue le long de l'axe libre, en metres
##   half / shoulder / walk  demi-chaussee, accotement, trottoir
##   name  ce qui est ecrit sur la plaque
## Le champ `shoulder` ne figurait pas au plan : il est necessaire parce que le
## trottoir du tronc est au-DELA de l'accotement (de 5,8 a 8,0 m) et pas
## au-dela de la chaussee. Sans lui, half vaudrait 5,8 pour le tronc et la
## couture avec le ruban national, qui exige 3,4, serait perdue.
var streets: Array = []

## Les carrefours, en 4-uplets (rue_a, rue_b, s, u). Toujours un rectangle
## 2 x half_a par 2 x half_b, jamais un eventail : rue_a est la transversale,
## rue_b le tronc ou une parallele, et elles sont perpendiculaires.
##
## A PLAT et pas en Dictionary, contre ce que le plan annoncait — pour la meme
## raison qu'il donne pour les batiments, mais mesuree : un Dictionary de
## quatre cles coute 675 octets dans Godot 4, quand les quatre nombres en font
## seize. Sur les 73 carrefours des huit villes, ca faisait 49,3 Ko de
## dictionnaires pour 1,2 Ko de chiffres. On lit par junction_a / junction_b /
## junction_su.
var junctions := PackedFloat32Array()

## Triplets (rue, abscisse t, cote). Le cote vaut +1 ou -1 et designe le SIGNE
## DU DECALAGE dans l'axe perpendiculaire curviligne (+u pour un tronc ou une
## parallele, +s pour une transversale) — pas la droite du conducteur, qui
## depend du sens dans lequel il arrive.
var lamps := PackedFloat32Array()

## 7-uplets (s, u, largeur, profondeur, hauteur, lacet, fenetres).
## (s, u) est le CENTRE au sol. Le lacet est l'angle de la direction de FACADE
## — celle qui regarde la rue — mesure depuis +s vers +u : la largeur lui est
## perpendiculaire, la profondeur le suit. Les fenetres sont un masque de 24
## bits, bit (etage * 8 + travee), sur la seule face qui donne sur la rue.
var blds := PackedFloat32Array()

## {name, num, street, t, side, amen}. `name` est l'adresse ecrite en toutes
## lettres ("12 rue des Tanneurs"), `num` le seul numero, celui qu'on peint
## sous le porche.
var addrs: Array = []

## L'enveloppe du bourg en (s, u), emprises des rues et empreintes des
## batiments comprises.
var bounds := Rect2()

var _grid := {}             # Vector2i -> masque de bits des rues de la case
## Anneaux de grille visites avant d'abandonner. La valeur ecrite ici n'est
## JAMAIS celle qui sert : _lay_bounds la recalcule depuis l'enveloppe du bourg
## (une vingtaine) avant le premier nearest(). Elle vaut zero et pas huit pour
## que ca se voie — et si un jour un appel passait avant _lay_bounds, zero ne
## rendrait pas une reponse fausse : nearest() n'aurait simplement pas sa
## preuve et retomberait sur le balayage des sept rues.
var _rings := 0

## Le meme `streets`, a plat. Il existe pour un chiffre : lire "kind", "s",
## "u", "a" et "b" dans un Dictionary coute cinq recherches de hachage, et
## _street_dist est appele sept fois par batiment candidat a la construction
## (4 700 fois par ville) ET par le GPS a chaque image. A plat, tirer un plan
## est passe de 1,92 a 1,62 ms. Ces tableaux sont derives de `streets` et se
## refont avec lui : ils ne sont jamais la source.
var _sx := PackedFloat32Array()      # la coordonnee FIXE de chaque rue
var _sa := PackedFloat32Array()      # son etendue, debut
var _sb := PackedFloat32Array()      # son etendue, fin
var _sc := PackedByteArray()         # 1 si c'est une transversale
## Ce qu'il faut laisser libre autour de l'axe de chaque rue : son bord de
## trottoir plus KEEP_CLEAR. Ni un mur ni un mat n'entrent la-dedans. A plat
## pour la meme raison que le reste — c'est lu dans la boucle la plus chaude du
## fichier.
var _se := PackedFloat32Array()

static var _cache := {}


## Le plan d'une ville, memoise. Huit plans, jamais liberes : la ville d'a cote
## se rearme trois fois par nuit, et si le plan changeait entre deux armements,
## l'adresse ou l'on vient de deposer un client aurait bouge.
static func of(town: String) -> RefCounted:
	if _cache.has(town):
		return _cache[town]
	var p := new()
	p.id = town
	p._generate(MapScript.seed_of(town))
	_cache[town] = p
	return p


## La traversee, panneau a panneau de sortie : 260 m. C'est ce que la voiture
## paie en vigilance (21 s a 45 km/h, drain x 1,73) et ce que le bareme
## facture deja, parce qu'une arete se mesure de panneau a panneau.
func cross_len() -> float:
	return float(CROSS) * STEP


# --------------------------------------------------------------------------
# Lire le plan
# --------------------------------------------------------------------------

## La direction d'une rue dans le plan (s, u), unitaire.
func street_dir(i: int) -> Vector2:
	return Vector2(0.0, 1.0) if _sc[i] != 0 else Vector2(1.0, 0.0)


## Le point (s, u) de la rue `i` a l'abscisse `t`, decale de `off` sur le cote.
## C'est `point` qui porte la perpendiculaire : elle valait aussi une fonction
## street_side(), que personne n'appelait — ni le monde, ni le GPS, ni le banc.
## Elle est partie ; `off` dit la meme chose et sert, lui.
func point(i: int, t: float, off := 0.0) -> Vector2:
	if _sc[i] != 0:
		return Vector2(_sx[i] + off, t)
	return Vector2(t, _sx[i] + off)


## Le milieu du trottoir : la ou se posent les lampadaires et ou attend un
## client. 6,9 m sur le tronc (au-dela de l'accotement), 3,4 m sur une rue.
func walk_mid(i: int) -> float:
	var st: Dictionary = streets[i]
	return float(st["half"]) + float(st["shoulder"]) + float(st["walk"]) * 0.5


## La demi-emprise, bord de trottoir compris : 8,0 m sur le tronc, 4,2 sur une
## rue.
func edge_half(i: int) -> float:
	var st: Dictionary = streets[i]
	return float(st["half"]) + float(st["shoulder"]) + float(st["walk"])


func street_len(i: int) -> float:
	return float(streets[i]["b"]) - float(streets[i]["a"])


func total_len() -> float:
	var d := 0.0
	for i in streets.size():
		d += street_len(i)
	return d


func bld_count() -> int:
	return blds.size() / 7


func lamp_count() -> int:
	return lamps.size() / 3


func junction_count() -> int:
	return junctions.size() / 4


## La transversale d'un carrefour.
func junction_a(j: int) -> int:
	return int(junctions[j * 4])


## Le tronc ou la parallele qu'elle croise.
func junction_b(j: int) -> int:
	return int(junctions[j * 4 + 1])


## Ou il tombe, dans le plan.
func junction_su(j: int) -> Vector2:
	return Vector2(junctions[j * 4 + 2], junctions[j * 4 + 3])


## Le point (s, u) d'une adresse : sur le trottoir, du bon cote.
func addr_su(k: int) -> Vector2:
	var a: Dictionary = addrs[k]
	var i: int = a["street"]
	return point(i, float(a["t"]), float(a["side"]) * walk_mid(i))


## La rue la plus proche d'un point du plan : {street, dist, t, seen}.
## `t` est l'abscisse le long de la rue, deja bornee a son etendue. `seen` est
## le nombre de troncons reellement examines — c'est ce que le banc compte.
##
## La grille de 20 m ne sert pas a aller vite (il y a sept rues) : elle sert a
## ce que le GPS puisse appeler ca a chaque image sans que le cout depende de
## la taille du bourg. Les anneaux s'arretent des que le meilleur candidat est
## plus proche que le prochain anneau ne peut l'etre : la reponse est alors
## EXACTE, et le banc la compare au balayage complet.
##
## MAIS LA PREUVE PEUT NE PAS VENIR, et le commentaire d'avant l'oubliait — il
## affirmait l'exactitude sans condition. La boucle peut aussi finir par
## EPUISEMENT des anneaux, sans que le meilleur ait ete prouve optimal ; elle
## rendait alors ce meilleur-la, faux. Releve sur 4 000 points par ville, dans
## bounds.grow(+20), (+300) et (+600) : zero faux, zero faux, et 577 FAUX sur
## 32 000, ecart maxi 90,08 m — Brumaire, point (452, -452) : venelle du Puy
## rendue a 566,8 m quand le vrai est route des Forges a 476,8. Un point a
## 600 m du bourg, c'est le GPS qui interroge le plan de la ville d'a cote, ou
## un banc. Depuis, les trois lignes rendent zero.
##
## Desormais : sans preuve, on balaie — les rues deja vues sont sautees grace au
## masque, il en reste au plus sept, et `seen` monte a 7 au pire, sous les 12
## que le banc exige.
##
## ET LE COUT NE SUIVAIT PAS LA TAILLE DU BOURG : IL SUIVAIT LA DISTANCE. Hors
## de l'enveloppe, la grille n'a plus une seule case a offrir — elle n'en tient
## que la ou passent les rues — et les anneaux balayaient du vide jusqu'a
## epuisement avant d'en venir au balayage qu'on pouvait faire tout de suite.
## Releve sur Corbeny, les deux etats du fichier dans la MEME execution :
##                              avant     apres
##   au coeur du bourg          4,95 us   3,63 us
##   600 m hors du bourg      626,54 us   2,62 us   (10 660 cases de grille
##                                                    balayees pour rien, zero)
##   2 km hors du bourg       625,07 us   2,63 us
##   4 000 points, grow(20)     7,25 us   4,51 us
##   4 000 points, grow(600)  515,40 us   2,75 us
## Les 626 us, c'est 7 % d'une image de 8,69 ms et pres de QUATRE FOIS le
## budget entier que le plan donne au dessin du GPS (165 us) — quand route()
## appelle nearest() deux fois et que la voiture est hors du bourg la plupart
## du temps. Zero reponse fausse des deux cotes, sur les 8 000 points : c'est le
## cout qui etait faux, pas la reponse.
##
## OU BASCULER, ET POURQUOI PAS A GRID. A deux mailles hors de l'enveloppe. Ce
## n'est pas un point d'equilibre : le balayage des sept rues coute 2,6 us quoi
## qu'il arrive, la grille 3,6 au coeur du bourg. La grille n'est pas moins
## chere, elle est BORNEE PAR LA VILLE — c'est ce qui tiendra le jour ou un
## bourg portera quinze rues. Les deux mailles, elles, sont une marge sur le
## banc : plantest tire ses 2 000 points dans bounds.grow(20) PILE et exige que
## pas un seul ne soit paye au prix du balayage complet (main.gd). Basculer a
## GRID poserait la bascule sur le bord meme de sa zone.
##
## Et l'anneau se balaie par son BORD. Le double `for` parcourait le carre
## plein et jetait l'interieur d'un `continue` : (2r+1)^2 cases par anneau la ou
## un anneau en compte 8r. Releve sur 4 000 points dans bounds.grow(20) : 37,9
## cases par appel en moyenne et 286 au pire, contre 23,9 et 121 depuis. C'est
## de la, et de la seule, que vient le gain de la ligne grow(20) du tableau :
## dans cette zone-la, la bascule ne peut pas jouer.
func nearest(su: Vector2) -> Dictionary:
	var best := 1.0e18
	var bi := -1
	var bt := 0.0
	var seen := 0
	# Un masque de bits a la place d'un Dictionary de visites : sept rues
	# tiennent dans un entier, et rien ne s'alloue par image.
	var mask := 0
	# La preuve, et rien d'autre : vrai seulement si la boucle a rompu parce
	# qu'aucun anneau plus loin ne pouvait faire mieux.
	var proved := false
	# Deux mailles hors de l'enveloppe, tous les anneaux qu'on balaierait
	# seraient vides : on descend droit au balayage, qui est exact.
	if bounds.grow(GRID * 2.0).has_point(su):
		var cx := int(floor(su.x / GRID))
		var cy := int(floor(su.y / GRID))
		var r := 0
		while r <= _rings:
			if bi >= 0 and float(r - 1) * GRID > best:
				proved = true
				break
			for dy in range(-r, r + 1):
				# Le BORD de l'anneau et pas le carre plein : les deux lignes
				# extremes en entier, deux cases pour chacune des autres.
				for dx in range(-r, r + 1, 1 if absi(dy) == r else 2 * r):
					var key := Vector2i(cx + dx, cy + dy)
					if not _grid.has(key):
						continue
					var bits: int = int(_grid[key]) & ~mask
					mask |= bits
					var i := 0
					while bits != 0:
						if bits & 1:
							seen += 1
							var dt := _street_dist(i, su)
							if dt.x < best:
								best = dt.x
								bi = i
								bt = dt.y
						bits >>= 1
						i += 1
			r += 1
	if not proved:
		# Pas de preuve : ou bien le point est hors du bourg et la grille n'a
		# meme pas ete ouverte, ou bien les anneaux se sont epuises sans qu'on
		# ait pu prouver que le meilleur etait le bon. Les deux cas se
		# reglent pareil, et c'est le seul endroit qui rende la reponse
		# exacte : on finit a la main. Le masque evite de recompter ce que
		# les anneaux ont deja mesure ; il ne reste jamais plus de sept rues.
		for i in streets.size():
			if mask & (1 << i) != 0:
				continue
			seen += 1
			var dt := _street_dist(i, su)
			if dt.x < best:
				best = dt.x
				bi = i
				bt = dt.y
	return {"street": bi, "dist": best, "t": bt, "seen": seen}


## L'itineraire dans le bourg : la suite des RUES a emprunter, de celle qui
## porte le depart a celle qui porte l'arrivee.
##
## Dijkstra tourne sur les CARREFOURS (douze au plus), mais ce qu'on rend, ce
## sont les rues : c'est ce dont le bandeau du GPS a besoin pour dire "a droite
## dans 60 m — rue des Tanneurs", et c'est sans ambiguite, parce que deux rues
## consecutives de la liste se croisent en un carrefour et un seul (l'une est
## perpendiculaire a l'autre). Depart et arrivee sur la meme rue rendent une
## liste d'un element, jamais une liste vide : "tout droit" est une reponse.
func route(su_from: Vector2, su_to: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var nf := nearest(su_from)
	var nt := nearest(su_to)
	var sf: int = nf["street"]
	var st: int = nt["street"]
	if sf < 0 or st < 0:
		return out
	out.append(sf)
	if sf == st:
		return out

	var nj := junction_count()
	var dist := PackedFloat32Array()
	dist.resize(nj)
	dist.fill(1.0e18)
	var prev := PackedInt32Array()
	prev.resize(nj)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(nj)

	for j in nj:
		var t0 := _junction_t(j, sf)
		if t0 < 1.0e17:
			dist[j] = absf(t0 - float(nf["t"]))

	# Dijkstra naif sur douze noeuds : une file a priorite serait plus longue
	# a ecrire qu'a executer.
	for _k in nj:
		var b := -1
		var bd := 1.0e18
		for j in nj:
			if done[j] == 0 and dist[j] < bd:
				bd = dist[j]
				b = j
		if b < 0:
			break
		done[b] = 1
		for j in nj:
			if done[j] != 0:
				continue
			var sh := _shared(b, j)
			if sh < 0:
				continue
			var nd: float = dist[b] + absf(_junction_t(b, sh) - _junction_t(j, sh))
			if nd < dist[j]:
				dist[j] = nd
				prev[j] = b

	var end := -1
	var bd2 := 1.0e18
	for j in nj:
		var t1 := _junction_t(j, st)
		if t1 > 1.0e17 or dist[j] > 1.0e17:
			continue
		var tot: float = dist[j] + absf(t1 - float(nt["t"]))
		if tot < bd2:
			bd2 = tot
			end = j
	if end < 0:
		return out

	var chain := PackedInt32Array()
	var cur := end
	while cur >= 0:
		chain.insert(0, cur)
		cur = prev[cur]
	for k in chain.size() - 1:
		var sh := _shared(chain[k], chain[k + 1])
		if sh >= 0 and out[out.size() - 1] != sh:
			out.append(sh)
	if out[out.size() - 1] != st:
		out.append(st)
	return out


# --------------------------------------------------------------------------
# Tirer le plan
# --------------------------------------------------------------------------

func _generate(sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd

	# Le rang de la ville dans la carte lui donne son quartier de noms. Hors de
	# la partition — une ville de banc (rang -1), ou une neuvieme ville ajoutee
	# a map.gd sans allonger NAMES —, elle pioche dans toute la liste. Le second
	# cas est une FAUTE et se dit : sans ce garde-fou, NAMES.slice(56, 63)
	# rendait un tableau vide et les sept plaques du bourg affichaient
	# "rue Sans-Nom", en silence.
	# Le compte des quartiers se CALCULE ici, il ne se recopie pas dans une
	# constante : un 8 ecrit a la main aurait menti le jour ou l'on allonge
	# NAMES, et c'est exactement le mensonge que ce garde-fou existe pour
	# attraper.
	var quartiers := NAMES.size() / NAMES_PER_TOWN
	var slot: int = MapScript.towns().find(id)
	if slot >= quartiers:
		push_warning(("town_plan : %s est la %de ville de la carte, et NAMES n'en "
			+ "sert que %d (%d noms, %d par ville). Elle piochera dans toute la "
			+ "liste et pourra partager ses plaques avec une autre.")
			% [id, slot + 1, quartiers, NAMES.size(), NAMES_PER_TOWN])
		slot = -1
	var pool := NAMES.duplicate()
	var grand: String = TRUNK_NAMES[rng.randi() % TRUNK_NAMES.size()]
	if slot >= 0:
		pool = NAMES.slice(slot * NAMES_PER_TOWN, (slot + 1) * NAMES_PER_TOWN)
		grand = TRUNK_NAMES[slot % TRUNK_NAMES.size()]

	_lay_streets(rng, pool, grand)
	_lay_junctions()
	_lay_grid()
	_lay_lamps()
	var slots := _lay_blds(rng)
	_lay_addrs(rng, slots)
	_lay_bounds()


func _lay_streets(rng: RandomNumberGenerator, pool: Array, grand: String) -> void:
	streets = []

	# Le tronc : la traversante elle-meme. Elle est dessinee 40 m avant le
	# panneau et 40 m apres la sortie (PAD), pour que la ville ne commence pas
	# net sur une couture.
	streets.append(_street("trunk", 0.0, 0.0,
		-float(PAD) * STEP, float(CROSS + PAD) * STEP,
		TRUNK_HALF, SHOULDER, WALK_TRUNK, grand))

	# Les transversales. Les abscisses sont tirees d'un coup et triees : c'est
	# la seule facon d'obtenir un tirage UNIFORME sous contrainte d'ecart
	# minimal, la ou un tirage-rejet aurait pu boucler.
	var nc := rng.randi_range(CROSS_N.x, CROSS_N.y)
	var slack := (CROSS_S.y - CROSS_S.x) - float(nc - 1) * CROSS_GAP
	var xs := PackedFloat32Array()
	for i in nc:
		xs.append(rng.randf_range(0.0, slack))
	xs.sort()
	for i in nc:
		# Cale sur le pas du ruban : un carrefour tombe sur un echantillon de
		# route, donc sur un point que road.gd possede deja.
		var s_i := CROSS_S.x + float(i) * CROSS_GAP + snappedf(xs[i], STEP)
		streets.append(_street("cross", s_i, 0.0,
			-snappedf(rng.randf_range(ARM.x, ARM.y), 2.0),
			snappedf(rng.randf_range(ARM.x, ARM.y), 2.0),
			STREET_HALF, 0.0, WALK, _take(rng, pool)))

	# Les paralleles. Elles vont de la premiere a la derniere transversale, et
	# leur ecart est BORNE par le bras le plus court : c'est la que se joue la
	# connexite. Une parallele que les transversales n'atteindraient pas serait
	# une rue qu'on voit sur la carte et ou l'on n'entre jamais.
	var s_first: float = streets[1]["s"]
	var s_last: float = streets[nc]["s"]
	var lim_l := 1.0e9
	var lim_r := 1.0e9
	for i in range(1, nc + 1):
		lim_l = minf(lim_l, -float(streets[i]["a"]))
		lim_r = minf(lim_r, float(streets[i]["b"]))
	var nr := rng.randi_range(RAIL_N.x, RAIL_N.y)
	var sides := []
	if nr == 1:
		sides.append(1.0 if rng.randf() < 0.5 else -1.0)
	else:
		# Deux paralleles : une de chaque cote. Un bourg a une ruelle derriere
		# chaque rangee, pas deux du meme cote.
		sides = [1.0, -1.0]
	for sgn in sides:
		var lim: float = maxf((lim_r if sgn > 0.0 else lim_l) - RAIL_MARGIN, RAIL_U.x)
		var u_i := clampf(snappedf(rng.randf_range(RAIL_U.x, minf(RAIL_U.y, lim)), 2.0),
			RAIL_U.x, lim)
		streets.append(_street("rail", 0.0, sgn * u_i, s_first, s_last,
			STREET_HALF, 0.0, WALK, _take(rng, pool)))

	_flatten()


func _lay_junctions() -> void:
	junctions = PackedFloat32Array()
	for ci in streets.size():
		if _sc[ci] == 0:
			continue
		for ri in streets.size():
			if _sc[ri] != 0:
				continue
			junctions.append(float(ci))
			junctions.append(float(ri))
			junctions.append(_sx[ci])
			junctions.append(_sx[ri])


## La grille de nearest(). Une rue est inscrite dans TOUTES les cases que son
## axe traverse : c'est ce qui rend la recherche par anneaux exacte, parce que
## le point le plus proche d'une rue est forcement dans une case ou cette rue
## est inscrite.
func _lay_grid() -> void:
	_grid = {}
	for i in streets.size():
		var st: Dictionary = streets[i]
		var a: float = st["a"]
		var b: float = st["b"]
		if st["kind"] == "cross":
			var cx := int(floor(float(st["s"]) / GRID))
			for cy in range(int(floor(a / GRID)), int(floor(b / GRID)) + 1):
				_mark(Vector2i(cx, cy), i)
		else:
			var cy2 := int(floor(float(st["u"]) / GRID))
			for cx2 in range(int(floor(a / GRID)), int(floor(b / GRID)) + 1):
				_mark(Vector2i(cx2, cy2), i)


## Une case ne retient pas la LISTE des rues qui la traversent mais leur
## MASQUE : sept rues tiennent dans un entier, la ou un PackedInt32Array par
## case payait son en-tete et son bloc de tas. Releve sur les 341 cases des
## huit villes : 54,4 Ko avant, 30,4 Ko apres, et nearest() y gagne une
## indirection par case.
func _mark(key: Vector2i, i: int) -> void:
	_grid[key] = int(_grid[key]) | (1 << i) if _grid.has(key) else (1 << i)


## Les lampadaires : un tous les 30 m de rue, cotes alternes — SAUF la ou le mat
## tomberait dans l'emprise d'une AUTRE rue.
##
## Ce refus n'est pas une coquetterie, c'est le seul abord de carrefour que les
## mats n'avaient pas. Les batiments ont CORNER_FREE ; les mats n'avaient rien,
## et la pose partait de a + 15 m tous les 30 sans regarder ce qu'il y avait
## en travers. Releve avant la correction, sur les 243 mats des huit villes :
## 23 tombaient dans la CHAUSSEE d'une autre rue, dont 8 dans la nationale, et
## 56 dans son emprise ; le pire etait a 1,00 m d'un axe, soit 1,60 m DANS la
## voie. La ville n'ayant pas de collision, le joueur ne l'aurait pas senti — il
## aurait traverse le poteau. Et en J3 ces triplets deviennent des mats a tete
## emissive dont trois portent une OmniLight : un lampadaire allume au milieu du
## bitume, qu'on traverse.
##
## Une rue perd ainsi un ou deux mats a chacun de ses carrefours : 243 mats
## avant, 187 apres, soit 23 par bourg au lieu de 30 — et zero dans une
## chaussee. C'est ce qu'on voit dehors : un croisement n'a pas de reverbere en
## son milieu. Trois de ces mats porteront une vraie OmniLight (town.gd) ; les
## vingt autres luisent par emission de materiau, et dans un brouillard a 0,030
## ce sont les tetes orange qui font la ville de nuit, pas les lumieres.
func _lay_lamps() -> void:
	lamps = PackedFloat32Array()
	for i in streets.size():
		var st: Dictionary = streets[i]
		var t: float = float(st["a"]) + LAMP_EVERY * 0.5
		var k := 0
		while t <= float(st["b"]):
			# L'alternance suit la POSITION le long de la rue, pas le compte des
			# mats poses : `k` avance meme sur un refus. Sinon deux mats
			# consecutifs se retrouveraient du meme cote de part et d'autre d'un
			# carrefour, et ca se voit de loin dans le brouillard.
			var side := 1.0 if k % 2 == 0 else -1.0
			var su := point(i, t, side * walk_mid(i))
			var free := true
			for j in streets.size():
				# Sa propre rue ne se teste pas : c'est SON trottoir.
				if j == i:
					continue
				if _street_dist(j, su).x < _se[j]:
					free = false
					break
			if free:
				lamps.append(float(i))
				lamps.append(t)
				lamps.append(side)
			t += LAMP_EVERY
			k += 1


## Les batiments, le long de chaque rue, des deux cotes.
##
## Un saut et deux refus, et aucun n'est cosmetique :
##  1. l'abord des carrefours (CORNER_FREE) se SAUTE — sans lui on ne voit pas
##     le trou dans les phares ; en le SAUTANT plutot qu'en le refusant, les
##     huit villes gardent 515 maisons contre 462 (voir la boucle) ;
##  2. l'emprise de TOUTE rue, plus KEEP_CLEAR (_se) — sans ca, une maison de
##     la parallele pousse dans la chaussee de la transversale qui la coupe, et
##     une maison de transversale mord le trottoir de la nationale ;
##  3. le recouvrement avec un batiment deja pose — deux rues perpendiculaires
##     se disputent le coin de leur ilot, et le retrait seul ne les separe pas.
##
## L'ordre de pose compte : le tronc d'abord, puis les transversales, puis les
## paralleles. C'est la rue la plus passante qui garde ses maisons ; une
## parallele posee a 26 m du tronc perd sa rangee interieure, et c'est
## exactement ce que fait un vrai bourg — une venelle n'est batie que d'un cote.
##
## Rend, pour chaque batiment pose, sa rue, son abscisse et son cote : les
## adresses s'y accrochent, pour qu'un numero tombe sur une VRAIE porte.
func _lay_blds(rng: RandomNumberGenerator) -> Array:
	blds = PackedFloat32Array()
	var sl_st := PackedInt32Array()
	var sl_t := PackedFloat32Array()
	var sl_side := PackedFloat32Array()
	var gb := {}                # Vector2i -> PackedInt32Array (indices de batiments)
	# Les abords de carrefour, RANGES PAR RUE : une rue en compte quatre au
	# plus, la liste en vrac en comptait vingt-quatre a balayer par candidat.
	# DEUX nombres par abord : l'abscisse du carrefour, et LA GARDE a tenir —
	# le plus grand de l'emprise de la rue qui coupe (8,5 m pour la nationale,
	# 4,7 pour une venelle) et de CORNER_FREE. Aujourd'hui c'est toujours
	# CORNER_FREE qui gagne, et c'est bien : le trou du carrefour couvre deja
	# l'emprise de la rue. Le maxf reste parce que le jour ou la nationale
	# s'elargira, c'est l'emprise qui devra gagner — et personne ne relira
	# cette ligne-la ce jour-la.
	var corner := []
	for i in streets.size():
		corner.append(PackedFloat32Array())
	for j in junction_count():
		var su := junction_su(j)
		var ja := junction_a(j)
		var jb := junction_b(j)
		corner[ja].append(su.y)
		corner[ja].append(maxf(_se[jb], CORNER_FREE))
		corner[jb].append(su.x)
		corner[jb].append(maxf(_se[ja], CORNER_FREE))

	var order := [0]
	for pass_kind in ["cross", "rail"]:
		for i in streets.size():
			if streets[i]["kind"] == pass_kind:
				order.append(i)

	for i in order:
		var st: Dictionary = streets[i]
		var a: float = st["a"]
		var b: float = st["b"]
		var setb: float = SETBACK_TR if st["kind"] == "trunk" else SETBACK
		var cor: PackedFloat32Array = corner[i]
		for sgn in [1.0, -1.0]:
			var t := a
			var t_prev := -1.0e9
			var w_prev := 0.0
			while true:
				t += rng.randf_range(BLD_PITCH.x, BLD_PITCH.y)
				# L'ABORD DE CARREFOUR SE SAUTE, IL NE SE SUBIT PAS. Un candidat qui
				# tombe dans la zone n'est pas refuse — il le fut, et le curseur
				# repartait alors pour un entraxe entier : la zone mangeait sa propre
				# longueur ET le reste de l'entraxe en cours a chacun de ses deux
				# bouts. Releve en recompilant le fichier des deux facons, a garde
				# egale : 462 maisons sur les huit villes en refusant, 515 en sautant.
				#
				# ON SAUTE JUSQU'OU LA PLUS ETROITE DES FACADES TIENT, garde comprise :
				# cor[m] + la garde + BLD_W.x / 2. Pas jusqu'a la garde pile — la, le
				# rabot de largeur ci-dessous rendrait une facade de zero, le candidat
				# serait refuse et on aurait rebrule l'entraxe qu'on voulait sauver :
				# 434 maisons au lieu de 515. Pas jusqu'a la demi-largeur MAXI non
				# plus, qui tiendrait la meme promesse pour 442 maisons seulement.
				# Cale la, le rabot rend exactement BLD_W.x au bord de la zone : la
				# maison d'angle est la plus etroite du bourg, et son MUR commence ou
				# le trottoir tourne — c'est ce qu'on voit dans un vrai bourg.
				var jumped := true
				while jumped:
					jumped = false
					var m := 0
					while m < cor.size():
						var g := cor[m + 1] + BLD_W.x * 0.5
						if absf(cor[m] - t) < g:
							t = cor[m] + g
							jumped = true
						m += 2
				if t > b:
					break
				# La largeur est bridee par ce qui reste depuis la facade
				# precedente : c'est la garantie, par construction, que deux
				# voisins de rue ne se traversent pas. Ce n'est PAS ici que la
				# ville perd sa densite, contrairement a ce qu'on a cru : 19
				# candidats refuses sur 705, soit 2,7 %.
				var wmax := minf(BLD_W.y, 2.0 * (t - t_prev - BLD_GAP) - w_prev)
				# LE RABOT DE LARGEUR, et c'est lui qui PORTE la promesse des 12 m.
				# Une facade est retaillee jusqu'a ce qu'elle laisse la garde libre de
				# part et d'autre de chaque carrefour de sa rue : au bord de la zone
				# sautee elle vaut BLD_W.x pile, un metre plus loin elle en gagne deux.
				# Il ne REFUSE personne — zero candidat sur les 705 des huit villes,
				# puisque le saut est cale pour qu'il rende toujours au moins
				# BLD_W.x —, il retaille : la facade moyenne passe de 8,77 a 8,05 m,
				# et le mur le plus proche d'un croisement de 7,59 a 12,73 m.
				var m2 := 0
				while m2 < cor.size():
					wmax = minf(wmax, 2.0 * (absf(cor[m2] - t) - cor[m2 + 1]))
					m2 += 2
				if wmax < BLD_W.x:
					continue
				var w := rng.randf_range(BLD_W.x, wmax)
				var d := rng.randf_range(BLD_D.x, BLD_D.y)
				var h := rng.randf_range(BLD_H.x, BLD_H.y)
				if t - w * 0.5 < a - 2.0 or t + w * 0.5 > b + 2.0:
					continue
				# Pas de test d'abord de carrefour ici : le curseur ne peut plus
				# y etre, il a saute la zone plus haut. C'est le meme invariant,
				# tenu une fois pour toutes au lieu d'etre reverifie sur chaque
				# candidat.
				var clear := true

				var c_su := point(i, t, sgn * (setb + d * 0.5))
				# Le lacet : la facade regarde la rue, plus ou moins quatre
				# degres. Une rangee au cordeau se voit tout de suite comme une
				# rangee posee par un script.
				var yaw := _facing(i, sgn) + deg_to_rad(rng.randf_range(-BLD_YAW, BLD_YAW))
				# L'empreinte n'est calculee que si un test exact la reclame :
				# la plupart des candidats sont ecartes ou acceptes sans que
				# ses quatre coins servent a quoi que ce soit.
				var co := PackedVector2Array()
				# Le rayon du cercle circonscrit, 8,9 m au pire. Il sert de
				# GARDE aux deux tests exacts qui suivent : un test de centre a
				# segment coute une pince et une soustraction, un test
				# d'empreinte a segment coute quatre distances segment-segment
				# et deux tests d'appartenance a un polygone. Sans cette
				# garde, tirer les huit plans coutait 6,7 ms par ville, six
				# fois le budget de l'etape 1 de town.arm.
				var rad := 0.5 * sqrt(w * w + d * d)
				for k in streets.size():
					# Sa PROPRE rue ne se teste pas : la facade est a SETBACK
					# de l'axe par construction, et le lacet de 4 degres ne
					# rapproche le coin que de (w/2) x sin 4 deg = 0,45 m au
					# pire. Il reste 5,55 m sur une rue (garde 4,7) et 9,55 sur
					# le tronc (garde 8,5). C'est le test qui echouait pour TOUS
					# les candidats — et qui n'en a jamais refuse un seul.
					if k == i:
						continue
					# La distance PERPENDICULAIRE a la droite qui porte la rue
					# minore la distance au segment : c'est une garde valable,
					# et elle ne coute ni racine carree ni appel de fonction.
					var perp := absf((c_su.x if _sc[k] != 0 else c_su.y) - _sx[k])
					if perp > rad + _se[k]:
						continue
					if co.is_empty():
						co = _corners(c_su, w, d, yaw)
					if _rect_street_dist(co, k) < _se[k]:
						clear = false
						break
				if not clear:
					continue
				# Deux centres ne peuvent se recouvrir qu'a moins de 17,8 m
				# (deux fois la plus grande demi-diagonale) : les huit cases
				# voisines suffisent, et le test reste local.
				var cell := Vector2i(int(floor(c_su.x / GRID)), int(floor(c_su.y / GRID)))
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var key := Vector2i(cell.x + dx, cell.y + dy)
						if not gb.has(key):
							continue
						for o in gb[key] as PackedInt32Array:
							var oo: int = o * 7
							var rj := 0.5 * sqrt(blds[oo + 2] * blds[oo + 2]
								+ blds[oo + 3] * blds[oo + 3])
							if c_su.distance_squared_to(Vector2(blds[oo], blds[oo + 1])) \
									> (rad + rj) * (rad + rj):
								continue
							if co.is_empty():
								co = _corners(c_su, w, d, yaw)
							# LE COIN D'ILOT, ET CE QU'IL COUTE. C'est le seul
							# endroit ou deux rangees perpendiculaires se
							# disputent le meme carre : a 15 m d'un carrefour, la
							# maison du tronc s'etend en u de 10 a 22 quand celle
							# de la transversale y va de 12 a 18, et elles se
							# traversent toujours — la rangee posee en second perd
							# son angle. 154 candidats sur 705 tombent la. Ce
							# n'est pas rattrapable : on a essaye, du temps de la
							# garde sur les centres, de faire repartir le curseur
							# derriere l'obstacle plutot que de lui faire bruler
							# un entraxe, et ca rendait 69,9 maisons par ville au
							# lieu de 70,3 — le candidat suivant tombait deja
							# au-dela, et ce mecanisme-la ne tient pas a la garde.
							# Un vrai bourg tranche pareil : un carrefour a un
							# seul immeuble d'angle par quart.
							if _obb_hit(co, _corners_of(o)):
								clear = false
								break
						if not clear:
							break
					if not clear:
						break
				if not clear:
					continue

				var bays := clampi(int(w / WIN_BAY), 1, WIN_BAYS_MAX)
				var flrs := clampi(int(h / WIN_FLOOR), 1, WIN_FLOORS_MAX)
				var mask := 0
				for fy in flrs:
					for bx in bays:
						if rng.randf() < WIN_P:
							mask |= 1 << (fy * WIN_BAYS_MAX + bx)

				var idx := blds.size() / 7
				blds.append(c_su.x)
				blds.append(c_su.y)
				blds.append(w)
				blds.append(d)
				blds.append(h)
				blds.append(yaw)
				blds.append(float(mask))
				sl_st.append(i)
				sl_t.append(t)
				sl_side.append(sgn)
				_push(gb, cell, idx)
				t_prev = t
				w_prev = w
	return [sl_st, sl_t, sl_side]


## Les adresses. QUATRE, et jamais sur le tronc : la baie de validation va de
## 0,5 a 5,0 m de l'axe (elle vit chez le taxi, en J4) alors que le trottoir de
## la traversante commence a 5,8 m — une adresse sur le tronc se validerait SUR
## LA CHAUSSEE NATIONALE, a l'endroit precis ou l'on n'a pas le droit de
## s'arreter. Le bourg a des rues pour ca, et c'est la raison d'etre des rues.
##
## Chaque adresse est accrochee a un batiment reellement pose : le porche
## eclaire tombe sur une facade, pas dans un pre.
##
## Le numero se lit comme partout en France : pair d'un cote, impair de
## l'autre, croissant depuis le debut de la rue. Le joueur qui voit un 14 en
## cherchant un 12 sait de quel cote regarder.
func _lay_addrs(rng: RandomNumberGenerator, slots: Array) -> void:
	addrs = []
	var sl_st: PackedInt32Array = slots[0]
	var sl_t: PackedFloat32Array = slots[1]
	var sl_side: PackedFloat32Array = slots[2]

	var pick := PackedInt32Array()
	for k in sl_st.size():
		if streets[sl_st[k]]["kind"] != "trunk":
			pick.append(k)
	if pick.is_empty():
		return

	# Les rues qui portent au moins une porte.
	var have := {}
	for k2 in pick:
		have[sl_st[k2]] = true

	# Le cafe de nuit passe devant. Ce n'est pas de la coquetterie : c'est la
	# SEULE commodite qui fait quelque chose (sleep.drink_boost), et la ville
	# prend 1,73 fois le debit de vigilance de la nationale. Si la ville a un
	# cafe sur la carte, le joueur doit pouvoir le trouver.
	# On DUPLIQUE : MapScript.amenities rend le tableau qui est dans la
	# constante TOWNS, et un erase() dessus retirerait le cafe de la carte pour
	# toute la partie.
	var amen := []
	if MapScript.TOWNS.has(id):
		amen = (MapScript.amenities(id) as Array).duplicate()
	if amen.has("cafe de nuit"):
		amen.erase("cafe de nuit")
		amen.insert(0, "cafe de nuit")

	var used := PackedInt32Array()
	var slot_used := PackedInt32Array()
	var taken := PackedVector2Array()
	var tries := 0
	while addrs.size() < ADDR_N and tries < 600:
		tries += 1
		# Les trois cents premiers essais sont exigeants ; passe ce cap, un
		# bourg trop maigre rend des adresses voisines plutot que trois
		# adresses seulement — une course sans arrivee n'existe pas.
		var strict := tries < 300
		var k: int = pick[rng.randi() % pick.size()]
		var i: int = sl_st[k]
		# Une adresse par rue tant qu'il reste des rues vierges : quatre portes
		# dans la meme ruelle ne feraient pas un bourg.
		if strict and used.size() < have.size() and used.has(i):
			continue
		var su := point(i, sl_t[k], sl_side[k] * walk_mid(i))
		var apart := true
		for p in taken:
			if p.distance_to(su) < ADDR_APART:
				apart = false
				break
		if strict and not apart:
			continue
		if slot_used.has(k):
			continue
		slot_used.append(k)
		var n := 1 + int((sl_t[k] - float(streets[i]["a"])) / 7.0)
		var num := 2 * n if sl_side[k] > 0.0 else 2 * n + 1
		addrs.append({
			"name": "%d %s" % [num, streets[i]["name"]],
			"num": str(num),
			"street": i,
			"t": sl_t[k],
			"side": sl_side[k],
			"amen": amen[addrs.size()] if addrs.size() < mini(2, amen.size()) else "",
		})
		used.append(i)
		taken.append(su)


func _lay_bounds() -> void:
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	for i in streets.size():
		var e := edge_half(i)
		for sgn in [-1.0, 1.0]:
			for t in [float(streets[i]["a"]), float(streets[i]["b"])]:
				var p := point(i, t, sgn * e)
				lo = lo.min(p)
				hi = hi.max(p)
	for k in bld_count():
		var co := _corners_of(k)
		for p2 in co:
			lo = lo.min(p2)
			hi = hi.max(p2)
	bounds = Rect2(lo, hi - lo)
	_rings = int(ceil(maxf(bounds.size.x, bounds.size.y) / GRID)) + 2


# --------------------------------------------------------------------------
# Les outils
# --------------------------------------------------------------------------

func _street(kind: String, s: float, u: float, a: float, b: float,
		half: float, shoulder: float, walk: float, name_: String) -> Dictionary:
	return {"kind": kind, "s": s, "u": u, "a": a, "b": b,
		"half": half, "shoulder": shoulder, "walk": walk, "name": name_}


## Tire un nom et le retire du sac : deux rues d'un meme bourg ne portent
## jamais le meme nom.
func _take(rng: RandomNumberGenerator, pool: Array) -> String:
	if pool.is_empty():
		return "rue Sans-Nom"
	var k := rng.randi() % pool.size()
	var n: String = pool[k]
	pool.remove_at(k)
	return n


## Recopie `streets` a plat. Appele a la fin de _lay_streets, une seule fois.
func _flatten() -> void:
	_sx = PackedFloat32Array()
	_sa = PackedFloat32Array()
	_sb = PackedFloat32Array()
	_sc = PackedByteArray()
	_se = PackedFloat32Array()
	for st in streets:
		var cross: bool = st["kind"] == "cross"
		_sx.append(float(st["s"]) if cross else float(st["u"]))
		_sa.append(float(st["a"]))
		_sb.append(float(st["b"]))
		_sc.append(1 if cross else 0)
		# La garde a tenir face a cette rue : son bord de trottoir, plus
		# KEEP_CLEAR. 8,5 m pour le tronc, 4,7 pour une rue — deux emprises,
		# deux gardes, la ou un seul 4,5 laissait la nationale a decouvert.
		_se.append(float(st["half"]) + float(st["shoulder"]) + float(st["walk"])
			+ KEEP_CLEAR)


## L'angle de la facade qui regarde la rue, mesure de +s vers +u.
func _facing(i: int, sgn: float) -> float:
	if _sc[i] != 0:
		return PI if sgn > 0.0 else 0.0
	return -PI * 0.5 * sgn


## (distance, abscisse) du point `p` a la rue `i`. Les rues sont alignees sur
## les axes du plan : pas de projection, une pince et une soustraction.
func _street_dist(i: int, p: Vector2) -> Vector2:
	if _sc[i] != 0:
		var t := clampf(p.y, _sa[i], _sb[i])
		return Vector2(p.distance_to(Vector2(_sx[i], t)), t)
	var t2 := clampf(p.x, _sa[i], _sb[i])
	return Vector2(p.distance_to(Vector2(t2, _sx[i])), t2)


## L'abscisse du carrefour `j` le long de la rue `s`, ou 1e18 s'il n'y est pas.
func _junction_t(j: int, s: int) -> float:
	var o := j * 4
	if int(junctions[o]) != s and int(junctions[o + 1]) != s:
		return 1.0e18
	return junctions[o + 3] if _sc[s] != 0 else junctions[o + 2]


## La rue que deux carrefours ont en commun, ou -1. Il n'y en a jamais deux :
## deux rues distinctes se croisent en un point et un seul.
func _shared(j1: int, j2: int) -> int:
	var a1 := junction_a(j1)
	var b1 := junction_b(j1)
	var a2 := junction_a(j2)
	var b2 := junction_b(j2)
	if a1 == a2 or a1 == b2:
		return a1
	if b1 == a2 or b1 == b2:
		return b1
	return -1


func _push(dict: Dictionary, key: Vector2i, i: int) -> void:
	if not dict.has(key):
		dict[key] = PackedInt32Array()
	var arr: PackedInt32Array = dict[key]
	arr.append(i)
	dict[key] = arr


## Les quatre coins d'une empreinte, dans l'ordre. `yaw` est la direction de la
## facade : la profondeur la suit, la largeur lui est perpendiculaire.
static func _corners(c: Vector2, w: float, d: float, yaw: float) -> PackedVector2Array:
	var f := Vector2(cos(yaw), sin(yaw))
	var r := Vector2(-f.y, f.x)
	var out := PackedVector2Array()
	out.append(c + f * (d * 0.5) + r * (w * 0.5))
	out.append(c + f * (d * 0.5) - r * (w * 0.5))
	out.append(c - f * (d * 0.5) - r * (w * 0.5))
	out.append(c - f * (d * 0.5) + r * (w * 0.5))
	return out


func _corners_of(k: int) -> PackedVector2Array:
	var o := k * 7
	return _corners(Vector2(blds[o], blds[o + 1]), blds[o + 2], blds[o + 3], blds[o + 5])


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1.0e-9:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


static func _seg_seg_dist(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(p1, p2, q1, q2) != null:
		return 0.0
	return minf(minf(_seg_dist(p1, q1, q2), _seg_dist(p2, q1, q2)),
		minf(_seg_dist(q1, p1, p2), _seg_dist(q2, p1, p2)))


## La distance d'une empreinte a l'AXE d'une rue. Zero si l'axe la traverse —
## c'est le cas qu'on interdit, et c'est celui qu'un test de coins seuls
## laisserait passer avec une distance positive.
func _rect_street_dist(co: PackedVector2Array, i: int) -> float:
	var a := point(i, _sa[i])
	var b := point(i, _sb[i])
	if Geometry2D.is_point_in_polygon(a, co) or Geometry2D.is_point_in_polygon(b, co):
		return 0.0
	var best := 1.0e18
	for k in 4:
		best = minf(best, _seg_seg_dist(a, b, co[k], co[(k + 1) % 4]))
	return best


## Deux rectangles orientes se recouvrent-ils ? Axes separateurs : quatre
## suffisent pour deux quadrilateres convexes.
static func _obb_hit(ca: PackedVector2Array, cb: PackedVector2Array) -> bool:
	for poly in [ca, cb]:
		for k in 2:
			var ax: Vector2 = (poly[k + 1] - poly[k]).orthogonal().normalized()
			var a0 := 1.0e18
			var a1 := -1.0e18
			var b0 := 1.0e18
			var b1 := -1.0e18
			for p in ca:
				var d := p.dot(ax)
				a0 = minf(a0, d)
				a1 = maxf(a1, d)
			for p2 in cb:
				var d2 := p2.dot(ax)
				b0 = minf(b0, d2)
				b1 = maxf(b1, d2)
			if a1 <= b0 or b1 <= a0:
				return false
	return true
