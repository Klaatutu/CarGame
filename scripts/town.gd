extends Node3D
##
## UNE VILLE — trois cent quarante metres de bourg, cousus au ruban.
##
## Ce n'est plus le hameau de trois boites au bord de la route : c'est une
## TRAVERSANTE. Le ruban national entre par un panneau, traverse 260 m de rues,
## et ressort par un second panneau. Pendant ces 340 m dessines (la traversee
## plus PAD de chaque cote), road.gd n'ecrit plus un seul triangle de chaussee :
## c'est la ville qui dessine le tronc, avec SES accotements, SES trottoirs et
## SA peinture, sur les MEMES points que le ruban. Le masque de road.gd s'ouvre
## sur draws_trunk() — la premiere des quatre methodes que road.gd demandait
## depuis le J2 et que ce fichier n'avait pas.
##
## CE QUE ROAD.GD ATTEND D'ICI, ET QUI N'EXISTAIT PAS. Quatre appels, chacun
## derriere un has_method, et les quatre tombaient dans le vide :
##   draws_trunk()   le masque de dessin — il n'a jamais creuse un seul quad
##   contains(p)     l'extinction — un demi-tour dans le bourg l'eteignait
##   street_dist(p)  le juge de course — une rue laterale etait un bas-cote
##   set_dark(on)    le cauchemar — la ville y etait une ville ordinaire
## Plus gps_lines() (le J5 en depend), address_pose() et sleep().
##
## LE PLAN EST AILLEURS, ET C'EST TOUT L'INTERET. town_plan.gd tire les rues,
## les maisons, les mats et les portes en coordonnees curvilignes (s, u) —
## s = metres depuis le panneau, u = decalage lateral — et n'a jamais entendu
## parler de Godot. Ce fichier-ci ne DECIDE de rien : il deplie. C'est ce qui
## fait que le GPS (J5) dessinera exactement les tableaux dont on extrude ici
## les triangles ; la carte n'est pas un schema de la ville, c'est la ville.
##
## UN SEUL MeshInstance3D, SIX SURFACES. Le contre-exemple qu'on evite se chiffre
## sur les releves : 64 maisons, 187 fenetres et 23 mats en noeuds separes font
## 274 objets, soit ~1 100 appels de dessin par image une fois les trois
## retroviseurs comptes (tout est rendu QUATRE fois). Ici, DIX-SEPT objets — les
## six surfaces, les deux panneaux avec leur poteau, leur tole et leur nom, les
## quatre plaques de rue et le numero — pour DIX-HUIT FOIS la surface du hameau
## d'avant, qui en comptait dix-huit (17 MeshInstance3D et un Label3D). On ne
## promet pas une division par dix : on promet le MEME ordre de grandeur pour
## dix-huit fois le bourg, et c'est deja tout ce qu'il fallait.
##
## LES SOMMETS SONT EN COORDONNEES DU MONDE, et le maillage est top_level.
## Ce n'est pas un detail : c'est ce qui rend la couture nulle PAR IDENTITE.
## Les 171 echantillons du tronc sont ceux de road.gd, bit pour bit — les 20
## d'avant le panneau viennent de road.sample_at(), les 150 d'apres de la
## traversee qu'il vient de pre-calculer —, et strip.ribbon() les extrude ici
## avec le meme code, les memes decalages et la meme hauteur que la-bas. Passer
## par le repere local de ce noeud aurait coute un aller-retour de matrice et
## rendu des sommets voisins, pas identiques.
##
## L'ENROULEMENT EST HORAIRE VU DU DESSUS, comme dans strip.gd, et une face a
## l'envers n'est pas plus sombre : elle est PUREMENT ET SIMPLEMENT INVISIBLE.
## Les deux regles qui tiennent tout le fichier, verifiees a la capture et pas
## au raisonnement :
##   - une bande suit sa ligne avec right = direction x UP, et ses decalages
##     vont du plus petit au plus grand (les inverser retourne la bande) ;
##   - une empreinte au sol se parcourt dans le sens d'AIRE SIGNEE NEGATIVE en
##     (x, z) pour que ses MURS regardent dehors ; son TOIT se pose donc dans
##     l'ordre inverse. Les empreintes de town_plan.gd (_corners) sont deja
##     dans ce sens-la, et ce n'est pas une chance : le repere (s, u) et le
##     repere (x, z) ont la meme orientation.
##
## QUATRE IMAGES, ET C'EST LE PLAN, PAS UNE PARADE. arm() est appele depuis
## _append_sample de road.gd, lui-meme appele jusqu'a 150 fois dans une seule
## image par son garde-fou, et la reconstruction du ruban suit dans la meme.
## Les deux couts peuvent tomber ensemble. La ville est armee 234 m devant la
## voiture, soit 11 s a 90 km/h : quatre images coutent quelques millisecondes,
## on a trois cents fois la marge. arm() ne fait donc RIEN qu'aller chercher
## les 171 tetes ; le maillage se batit ensuite, une etape par image, et
## draws_trunk() ne dit oui qu'une fois la sixieme surface versee — un trou de
## quatre images serait pire que la couture qu'il repare.
##
## AUCUN MATERIAU, AUCUN SHADER FABRIQUE A L'ARMEMENT NI PAR IMAGE. Les neuf
## naissent au _ready — les six du maillage, la fenetre morte du cauchemar et
## les deux du panneau —, tous sur le shader unique deja compile (retro.gd), et
## deux d'entre eux ne font que poser l'uniforme `emission` que la ville d'avant
## posait deja. Aucune variante de shader neuve : le depot a
## releve 23 ips sur la premiere image a cache de shaders froid contre 115 a
## chaud : le milieu d'un bourg est le pire moment possible pour compiler quoi
## que ce soit.
##
## PAS D'OMBRES. cast_shadow OFF sur tout ce qui est ici, et les trois lampes
## ont shadow_enabled = false : il ne reste que DEUX ombres dans tout le jeu,
## les phares. Les trois lampes posent aussi light_volumetric_fog_energy a
## 0,15 — la ville d'avant etait le SEUL endroit du depot a laisser le defaut
## de 1,0, et seize lampes a energie volumetrique pleine seraient le seul poste
## capable de couter des millisecondes.
##
## LE COMPTE REEL. Ce fichier se pese lui-meme : des qu'un banc tourne, il
## imprime ce que la ville a coute, surface par surface. Les chiffres ci-dessous
## sont ces releves, les HUIT bourgs batis sur le meme ruban — pas le budget du
## plan, qui datait d'un autre generateur. Corbeny, celui que maptest traverse :
##   1 asphalte     713 sommets    852 triangles
##   2 accotement   636             616
##   3 trottoir    1036             960
##   4 peinture     684             680
##   5 bati        2040            1580   dont le clocher : 392 / 612
##   6 emissif      988             682   dont son cadran :  112 / 148
##   TOTAL        6 097           5 370
## Les huit, du plus leger au plus lourd : Les Essarts 5 525 / 4 544,
## La Fresnaie 5 635 / 4 624, Saint-Elme 5 733 / 4 786, Malassis 5 809 / 4 844,
## Peyrelade 5 929 / 5 160, Vieux-Bourg 6 009 / 5 088, Corbeny 6 097 / 5 370,
## BRUMAIRE 6 305 / 5 066 — moyenne 5 880 / 4 935. Les seuils du jalon sont a
## 8 000 et 6 500 : il reste 27 % de marge sur le pire compte de sommets
## (Brumaire) et 21 % sur le pire compte de triangles (Corbeny).
##
## LE BOURG SEUL, SANS SON REPERE, faisait 5 189 a 5 825 sommets et 4 248 a
## 4 762 triangles — moyenne 5 489 / 4 509. C'est sur ces chiffres-la que se
## lisent les deux paragraphes suivants, qui comparent le bourg au budget du
## plan ; le repere, lui, se lit plus bas.
##
## CE QUE LE PLAN AVAIT JUSTE, ET CE QU'IL AVAIT FAUX. Il annoncait 5 610 a
## 5 780 sommets et 4 700 a 4 790 triangles pour le bourg moyen : le total tombe
## 2 % SOUS sa borne basse. Surface par surface, en revanche :
##  - la 4 (peinture) tombe au sommet pres — 684 / 680, exactement le chiffre du
##    plan. C'est la seule qui ne depende que du tronc, et le tronc n'a pas
##    bouge ;
##  - la 2 (accotement) fait 636 a 648 la ou le plan disait 684 : il ne coupait
##    pas l'accotement aux transversales, et une rue qui debouche sur la
##    nationale y coupe l'accotement et le trottoir ;
##  - les 1 et 3 etaient chiffrees sur 880 m de rue et huit carrefours quand
##    Corbeny en porte 1 090 et douze ; elles sortent pourtant SOUS l'estimation,
##    parce qu'une transversale est une droite du monde et se pose en deux
##    points, pas en cinquante ;
##  - le pire bourg n'est pas celui que le plan designait. Il pariait sur
##    Malassis (70 maisons, 28 mats) : c'est Brumaire, et par la surface 6 —
##    225 fenetres allumees contre 177.
##
## LES FENETRES SONT COMPTEES, ET C'EST NEUF. Le plan en faisait une fourchette
## (172 a 214 par bourg) faute de banc qui les compte ; ce fichier les compte.
## 159 (Corbeny), 188, 201, 177, 214, 175, 154, 225 — 1 493 sur les huit, 186,6
## par bourg. La fourchette du plan tient EN MOYENNE et rate deux bourgs sur
## huit : Peyrelade avec 154 et Brumaire avec 225.
##
## LE REPERE, ET CE QU'IL FAUT POUR QU'UN BOURG SOIT UN LIEU. Huit modeles
## batis sous Blender (assets/blender/build_landmarks.py) entrent ici, un par
## ville : le clocher de Corbeny, le totem de la station de Saint-Elme, le
## chateau d'eau de La Fresnaie, le silo de Malassis, la porte fortifiee de
## Vieux-Bourg, la cheminee des Essarts, la halle de Peyrelade, le pont du
## chemin de fer de Brumaire. Chacun dit le METIER du bourg et pas son decor.
##
## ILS N'ENTRENT PAS COMME DES NOEUDS, ILS ENTRENT COMME DES TRIANGLES. Leurs
## sommets sont verses dans les surfaces qui existent DEJA : le corps dans la
## 5 avec les maisons, tout noeud dont le nom finit par _Lit dans la 6 avec
## les fenetres. C'est le seul contrat entre Blender et Godot, et il est ecrit
## en tete de build_landmarks.py. Un repere devenu MeshInstance3D couterait
## son propre appel de dessin, QUATRE fois par image avec les retroviseurs ;
## cousu, il en coute ZERO — pas un noeud, pas un materiau, pas une variante
## de shader : il prend le materiau retro deja compile de la surface qui
## l'accueille. Les DIX-SEPT objets dessinables du bourg sont toujours
## dix-sept, avec ou sans lui.
##
## CE QU'IL PESE, releve sur les huit : chateau d'eau 264 sommets, silo 276,
## totem 336, cheminee 336, halle 456, porte 480, pont 480, clocher 504 —
## 3 132 pour les huit, de 4,7 a 8,3 % du bourg qui le porte. Les comptes
## tombent au sommet pres sur ceux du .glb livre, parce que ce sont les memes :
## on lit le fichier, on transforme, on ajoute.
##
## ILS SE LISENT AU _ready ET NULLE PART AILLEURS, par GLTFDocument et pas par
## load() : sept des huit .glb n'ont pas de fichier .import, que seul un
## passage dans l'EDITEUR ecrirait, et l'editeur n'est jamais ouvert quand un
## banc tourne. CE QUE CA COUTE, remesure ici — douze lancements de plantest a
## la file, dans l'ordre du releve : 194,2 / 157,2 / 206,9 / 153,2 / 230,4 /
## 180,5 / 140,5 / 133,6 / 223,2 / 91,8 / 109,0 / 120,9 ms pour les huit,
## mediane 155. D'autres lancements du meme jour ont donne 69,0 et 232,9.
##
## DEUX CHOSES A EN RETENIR, ET PAS UNE TROISIEME. La premiere : la fourchette
## qui tenait ici — « 69 a 168 ms pour les huit sur sept lancements » — est
## fausse par le haut, et pas d'un cheveu : CINQ des douze lancements la
## depassent. La seconde : sur le MEME fichier et la meme machine, le pire
## lancement fait plus de TROIS FOIS le meilleur — et la machine n'etait pas au
## repos, un autre Godot et un Blender tournaient a cote pendant une partie de
## la serie. Une fourchette etroite ne veut donc rien dire sur ce chiffre-la ;
## ce qui compte est l'ordre de grandeur : un dixieme a un quart de seconde,
## UNE FOIS, au demarrage. A l'armement ce serait une milliseconde par bourg au
## milieu d'une image ou road.gd peut poser 150 echantillons.
##
## OU IL SE POSE : IL FERME LA PERSPECTIVE D'UNE RUE. On essaie les deux bouts
## de chaque rue du bourg — le tronc excepte, il n'a pas de bout, il traverse —
## et on garde celui que la route voit le PLUS TOT ; a trois metres pres, c'est
## le ciel qui departage (voir _lm_seat et _lm_sky). Releve sur les huit : 44 a
## 50 m du panneau d'entree, 79 a 87 m du premier metre que la ville dessine,
## 17,5 a 24,0 degres hors de l'axe de la route — dans le pare-brise, dont la
## demi-ouverture horizontale vaut 40 degres. Le degagement, mesure au mur et
## au bord de trottoir le plus proche, va de 2,80 a 20,23 m : pas un repere au
## milieu d'une rue, pas un repere dans une maison, et le banc l'imprime.
##

const Retro := preload("res://scripts/retro.gd")
## La geometrie de ruban, partagee avec road.gd. Les MEMES fonctions
## statiques : une rue de bourg est le meme ruban qu'une nationale, et si les
## deux etaient ecrites deux fois elles finiraient par ne plus dire tout a fait
## la meme chose — un centimetre a la couture, c'est un trait de brouillard en
## travers de la chaussee a deux metres des phares.
const Strip := preload("res://scripts/strip.gd")
const TownPlan := preload("res://scripts/town_plan.gd")

const STEP := TownPlan.STEP
const PAD := TownPlan.PAD
const CROSS := TownPlan.CROSS

## Les hauteurs. Tout est plat — velocity.y est remis a zero a chaque tick de
## car.gd et floor_max_angle vaut 45 degres : un vrai trottoir de 12 cm serait
## un MUR qui arreterait net une voiture lancee. Le trottoir est donc une
## DIFFERENCE DE COULEUR, et ces dix millimetres ne servent qu'a ranger les
## couches pour le z-buffer.
const Y_SHOULDER := 0.0     # = RoadScript.Y_SHOULDER
const Y_ROAD := 0.02        # = RoadScript.Y_ROAD
const Y_PAINT := 0.026      # = RoadScript.Y_PAINT
const Y_WALK := 0.03

## La chaussee du tronc, decoupee comme celle de road.gd : ce sont les memes
## triangles de part et d'autre de la couture, pas des triangles qui se
## ressemblent.
const ROAD_COLS := 2
const SHOULDER_COLS := 1
const LINE_INSET := 0.45    # = RoadScript.LINE_INSET
const LINE_HALF := 0.075    # = RoadScript.LINE_HALF

## TROIS lumieres, contre une seule dans la ville d'avant, et elles SE
## DEPLACENT : une lampe reassignee suit la voiture au lieu de rester allumee
## derriere elle. Portee 14 m, energie 1,4 — celles de la ville d'avant, qui
## marchaient.
const LIGHTS := 3
const LIGHT_RANGE := 14.0
const LIGHT_ENERGY := 1.4
## L'attenuation, et c'est le seul chiffre de lampe qui bouge. La ville d'avant
## posait 1,6 : Godot 4 attenue en distance^-decay, donc a 5 m sous la tete il
## restait 1,4 / 5^1,6 = 0,10 d'energie, sur un asphalte a 0,085 d'albedo — un
## reverbere qui n'eclaire pas le sol, releve a la capture. A 0,9 il en reste
## 0,33, et la flaque orange existe. Les phares de la voiture sont a 0,85
## (car.gd) et le halo de la police a 1,2 : on est dans la fourchette du depot,
## pas au-dela.
const LIGHT_ATTEN := 0.9
## Le seul reglage neuf, et c'est une correction : la ville d'avant etait le
## SEUL endroit du depot a laisser le defaut de 1,0 (car.gd pose 0,12, 0,16 et
## 0,10, dome_light.gd 0,0, police_car.gd deux fois).
const LIGHT_FOG := 0.15
const RELIGHT_EVERY := 0.25 # 4 Hz : ni par image, ni assez lentement pour se voir
const RELIGHT_DROP := 70.0  # m : au-dela, ET derriere, la lampe est rendue
## On ne rallume JAMAIS a moins de ca : a 60 m, le brouillard a 0,030 ne laisse
## passer que 16 % — un allumage y est invisible, et c'est exactement ce qu'on
## veut. Une lampe qui s'allume sous le nez du joueur est le pop le plus voyant
## qu'un decor puisse faire.
const RELIGHT_MIN := 60.0

const MAST_R := 0.085       # rayon du mat, hexagonal
const MAST_H := 5.2
const HEAD_OUT := 0.55      # deport de la tete vers la chaussee
const HEAD_W := 0.55
const HEAD_H := 0.20
const WIN_W := 0.62
const WIN_H := 0.82
const WIN_OUT := 0.02       # la fenetre est POSEE sur la facade, pas dedans
const PLATE_Y := 2.2        # hauteur d'une plaque de rue, sur un mat
const PORCH_W := 1.05
const PORCH_H := 2.10
## Le panneau, a droite. SUR LE TROTTOIR (5,8 a 8,0 m) et plus sur l'accotement
## comme dans la ville d'avant, qui n'avait pas de trottoir : a 5,2 m il se
## plantait au milieu de la zone ou le client attend et ou le banc gare la
## voiture (x = 4,6), une caisse de 1,7 m de large en travers du poteau.
const SIGN_OFF := 7.0

## De combien contains() deborde l'enveloppe du plan. Il ne sert qu'a une
## chose : interdire d'eteindre une ville dans laquelle on a fait demi-tour.
## Large, donc — le pop le plus voyant du jeu est deja paye une fois.
const INSIDE_MARGIN := 12.0

## LE REPERE DE CHAQUE BOURG. La table est ECRITE, comme la carte de map.gd
## et pour la meme raison : un repere tire au sort ne se retient pas. Une
## ville qui n'est pas sur la carte — les bancs en arment — en pioche un sur
## son nom, elle a droit a une silhouette, pas a un quartier reserve.
const LM_MODEL := {
	"Corbeny": "clocher",
	"Saint-Elme": "totem",
	"La Fresnaie": "chateau_eau",
	"Malassis": "silo",
	"Vieux-Bourg": "porte",
	"Les Essarts": "cheminee",
	"Peyrelade": "halle",
	"Brumaire": "pont",
}
const LM_PATH := "res://assets/models/landmark_%s.glb"

## LE PARVIS : ce que le repere laisse entre son socle et le bout de la rue
## qu'il ferme. Sept metres, et ce n'est pas un chiffre rond — le bout d'une
## parallele EST un carrefour, dont l'emprise vaut 4,2 m. Il reste donc 2,8 m
## de trottoir devant le socle : ni un porche colle a la chaussee, ni un
## monument perdu dans un champ.
const LM_CLEAR := 7.0
## Ce qu'il laisse a un mur ou a un bord de trottoir. Deux metres : de quoi
## passer a pied, et de quoi qu'aucune arete ne se touche quand le lacet de
## quatre degres des facades joue contre nous.
const LM_KEEP := 2.0
## ET JAMAIS PLUS LOIN QUE CA DU PANNEAU D'ENTREE. C'est la seule contrainte
## qui ne vienne pas du plan mais du BROUILLARD : a 0,030 de densite il ne
## repasse que 22 % a 50 m, 16 % a 60, 7 % a 90. Un repere qu'on ne voit qu'a
## l'interieur du bourg n'annonce rien ; il doit se lever devant le
## conducteur AVANT le panneau, et 50 m du panneau, c'est 90 m du premier
## metre que la ville dessine. Le meme raisonnement, au meme chiffre, tient
## deja RELIGHT_MIN plus haut.
const LM_REACH := 50.0
## Le rayon d'une maison, au pire : la demi-diagonale d'une empreinte de
## 13 x 12 m (TownPlan.BLD_W.y et BLD_D.y). Il ne sert qu'a ecarter d'un
## test de cercle les soixante maisons qui ne peuvent pas gener, avant de
## payer la separation d'axes sur les trois qui restent.
const LM_BLD_R := 8.85
## L'oeil du conducteur au-dessus de la route : la hauteur des optiques et
## du regard dans la Civic. C'est de la que se juge ce que les toits cachent.
const EYE_H := 1.45
## A combien de metres pres deux bouts de rue sont « aussi proches ». Trois :
## la largeur d'une voie de bourg, et bien moins que ce que le brouillard
## sait distinguer (a 45 m, trois metres valent 4 % de transmission).
const LM_TIE := 3.0

var town_name := ""

## Le plan (memoise par town_plan.gd, jamais libere) et la ligne mediane du
## tronc en coordonnees du monde : 171 points, et le vecteur droite de chacun.
## Ce sont ceux de road.gd, pas des copies calculees.
var _plan
var _c_pos := PackedVector3Array()
var _c_right := PackedVector3Array()

var _mesh := ArrayMesh.new()
var _mi: MeshInstance3D
## Les tampons de geometrie, membres et pas locaux : une surface s'empile en
## plusieurs appels a strip.ribbon avant d'etre versee d'un coup.
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _f := PackedInt32Array()
## Les deux tampons de ligne, pour la meme raison.
var _lp := PackedVector3Array()
var _lr := PackedVector3Array()

var _mat_asphalt: ShaderMaterial
var _mat_shoulder: ShaderMaterial
var _mat_walk: ShaderMaterial
var _mat_paint: ShaderMaterial
var _mat_house: ShaderMaterial
var _mat_glow: ShaderMaterial
## La meme fenetre, emission eteinte : le cauchemar. Fabriquee au _ready comme
## les six autres — set_dark() ne fait qu'echanger deux references.
var _mat_glow_dark: ShaderMaterial
var _mat_metal: ShaderMaterial
var _mat_pole: ShaderMaterial

## L'index de la surface emissive dans le maillage. Il se RELEVE au lieu de
## s'ecrire : strip.commit ne verse pas une surface vide (Godot la refuse), et
## un bourg sans une seule fenetre allumee decalerait toutes les suivantes.
var _surf_glow := -1

## L'etape de construction : -1 rien a faire, 0..3 l'etape a venir.
var _step := -1
## L'image ou arm() a ete appele. Les quatre etapes tombent APRES elle : le
## _process de ce noeud passe juste apres celui de road.gd dans la meme image,
## et l'etape 1 y retomberait sur l'armement et sur la reconstruction du ruban.
var _arm_frame := -1
## Le maillage est-il acheve ? C'est la reponse de draws_trunk(), et donc le
## masque de road.gd.
var _built := false
var _dark := false

var _sign_in: Node3D
var _sign_out: Node3D
var _plates: Array[Label3D] = []
var _number: Label3D
## L'adresse dont le numero brule (-1 : aucune). Une seule par visite : c'est
## celle de la course, et une ville ou tous les numeros brillent ne se cherche
## pas.
var _addr_k := -1
var _lights: Array[OmniLight3D] = []
## Le mat que porte chaque lampe (-1 : aucune). C'est ce qui interdit a deux
## lampes de se poser sur le meme reverbere.
var _light_mast := PackedInt32Array()
var _mast_pos := PackedVector3Array()
var _relight_t := 0.0

## Les traits que le GPS dessinera : des COUPLES de points en metres du monde,
## dans le plan (x, z). Le meme tableau que celui dont on extrude les rues.
var _gps := PackedVector2Array()

## Le bourg dit ce qu'il coute des qu'un banc tourne. Une ville muette en
## partie normale, un releve chiffre sous chaque banc : les seuils du jalon se
## posent sur des sommets comptes, pas sur un budget de plan.
var _loud := false

## LES HUIT REPERES, lus une bonne fois et gardes en SOMMETS. Huit cases par
## modele, et pas un Dictionary de plus : c'est lu dans la boucle qui verse
## les triangles.
##   0 1 2  sommets, normales, indices du CORPS       -> surface 5
##   3 4 5  sommets, normales, indices de CE QUI LUIT -> surface 6
##   6      la demi-emprise (x, z) du modele, en metres
##   7      sa hauteur
var _lm := {}
## Ou se pose le repere de chaque bourg, EN COORDONNEES DU PLAN et memoise :
## (s, u) et le cap (unitaire) sous lequel il regarde sa rue. Il ne depend
## que du plan, jamais du ruban — deux visites du meme bourg y retrouvent le
## meme clocher a la meme place, alors que le maillage, lui, se refait.
## Un cap nul est la reponse « aucune place tenable », et il ne peut pas se
## confondre avec un site : un cap est toujours un axe du plan.
var _lm_site := {}
## Le modele du bourg arme ("" : aucun) et sa pose dans le monde.
var _lm_key := ""
var _lm_pose := Transform3D()


func _ready() -> void:
	_loud = not OS.get_cmdline_user_args().is_empty()

	# LES SIX MATERIAUX DU MAILLAGE, plus les deux du panneau. Trois d'entre
	# eux sont ceux de road.gd, aux memes chiffres : de part et d'autre de la
	# couture, la chaussee, l'accotement et la peinture ne doivent pas
	# seulement se toucher, ils doivent avoir la MEME couleur — sinon la ville
	# se voit comme un rectangle plus clair a 200 m dans les phares.
	_mat_asphalt = Retro.mat(Color(0.085, 0.086, 0.094), 0.55, 0.10)
	_mat_shoulder = Retro.mat(Color(0.060, 0.058, 0.052), 0.94)
	_mat_paint = Retro.mat(Color(0.58, 0.56, 0.50), 0.70)
	# Le trottoir se LIT : 0,130 contre 0,085 d'asphalte et 0,060
	# d'accotement, soit 0,045 d'ecart quand le tramage avance par pas de
	# 8/255 = 0,031. Un ecart plus fin serait mange par le tramage et le
	# trottoir n'existerait que dans ce commentaire.
	_mat_walk = Retro.mat(Color(0.130, 0.128, 0.120), 0.90)
	_mat_house = Retro.mat(Color(0.030, 0.030, 0.034), 0.95)
	# La fenetre et la tete de lampadaire : EXACTEMENT le materiau de la ville
	# d'avant. Aucune variante de shader neuve a compiler — c'est le poste le
	# plus important du budget, et il vaut zero.
	_mat_glow = Retro.mat(Color(0.09, 0.075, 0.045), 0.6)
	_mat_glow.set_shader_parameter("emission", Color(0.55, 0.38, 0.16))
	_mat_glow_dark = Retro.mat(Color(0.045, 0.042, 0.040), 0.8)
	_mat_metal = Retro.mat(Color(0.10, 0.11, 0.13), 0.5)
	_mat_pole = Retro.mat(Color(0.055, 0.055, 0.06), 0.9)

	# LE MAILLAGE EST top_level : ses sommets sont en coordonnees du monde,
	# comme ceux du ruban de road.gd. Le noeud-ville, lui, garde la transform
	# du panneau d'entree — taxi.gd y lit la zone d'arret en repere ville
	# (x a droite, z devant), et main.gd y gare la voiture au banc.
	_mi = MeshInstance3D.new()
	_mi.name = "Surface"
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.set_as_top_level(true)
	_mi.transform = Transform3D()
	_mi.visible = false
	add_child(_mi)

	_sign_in = make_sign(_mat_metal, _mat_pole)
	_sign_in.name = "SignIn"
	_sign_in.set_as_top_level(true)
	_sign_in.visible = false
	add_child(_sign_in)

	_sign_out = make_sign(_mat_metal, _mat_pole)
	_sign_out.name = "SignOut"
	_sign_out.set_as_top_level(true)
	_sign_out.visible = false
	add_child(_sign_out)

	# Les plaques de rue : QUATRE au plus, et seulement sur les rues qui
	# portent une adresse. Cinquante enseignes de commerce, ce serait cinquante
	# appels de dessin par vue, donc deux cents.
	for i in TownPlan.ADDR_N:
		var pl := Label3D.new()
		pl.name = "Plate%d" % i
		pl.font_size = 40
		pl.pixel_size = 0.005
		pl.modulate = Color(0.74, 0.76, 0.72)
		pl.outline_size = 0
		pl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pl.set_as_top_level(true)
		pl.visible = false
		add_child(pl)
		_plates.append(pl)

	# Le numero de l'adresse visee, sous le porche. Un seul : c'est celui de la
	# course en cours, et une ville ou tous les numeros brillent ne se cherche
	# pas.
	_number = Label3D.new()
	_number.name = "Number"
	_number.font_size = 64
	_number.pixel_size = 0.006
	_number.modulate = Color(0.92, 0.80, 0.55)
	_number.outline_size = 0
	_number.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_number.set_as_top_level(true)
	_number.visible = false
	add_child(_number)

	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.name = "Lamp%d" % i
		l.light_color = Color(1.0, 0.62, 0.22)
		l.light_energy = LIGHT_ENERGY
		l.omni_range = LIGHT_RANGE
		l.omni_attenuation = LIGHT_ATTEN
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = LIGHT_FOG
		l.set_as_top_level(true)
		l.visible = false
		add_child(l)
		_lights.append(l)
	_light_mast.resize(LIGHTS)
	_light_mast.fill(-1)

	# LES REPERES SE LISENT ICI ET NULLE PART AILLEURS. Ouvrir un .glb coute
	# une milliseconde, et l'armement tombe dans une image ou road.gd peut
	# deja poser 150 echantillons et re-trianguler tout son ruban.
	_load_landmarks()

	visible = false


# --------------------------------------------------------------------------
# Ce que road.gd appelle
# --------------------------------------------------------------------------

## Pose la ville. `at` est la transform du ruban a l'echantillon du panneau
## d'entree (X = droite de la route, -Z = sens de la marche).
##
## ON NE BATIT RIEN ICI. On range le plan et les 171 tetes du tronc, et on
## rend la main : le maillage se fait en quatre images, dans _process. Voir
## l'en-tete du fichier — arm() est appele depuis _append_sample, qui peut
## tourner 150 fois dans la meme image.
func arm(at: Transform3D, name_: String) -> void:
	global_transform = at
	town_name = name_
	_plan = TownPlan.of(name_)
	# Une recherche dans une table, rien de plus : le SITE du repere se
	# cherche a l'etape 3, avec le reste du bati.
	_lm_key = _lm_of(name_)
	_dark = false
	_built = false
	_surf_glow = -1
	_mesh.clear_surfaces()
	_mi.visible = false
	_sign_in.visible = false
	_sign_out.visible = false
	_number.visible = false
	_addr_k = -1
	for pl in _plates:
		pl.visible = false
	for l in _lights:
		l.visible = false
	_light_mast.fill(-1)
	_mast_pos.clear()
	_gps.clear()
	_gather(at)
	_step = 0
	_arm_frame = Engine.get_process_frames()
	visible = true


## La ville se range : le maillage vide, le noeud eteint, la ligne mediane
## oubliee. C'est road.gd qui decide QUAND — sorti par le bout ET plus dedans,
## contains() en repond — et c'est lui qui efface ses propres bornes.
##
## Ce qu'on ne libere PAS : le plan. Les huit sont memoises et ne meurent
## jamais, parce que la ville d'a cote se rearme trois fois par nuit et qu'une
## adresse qui aurait bouge entre deux visites serait une course perdue sans
## que rien ne le dise.
func sleep() -> void:
	visible = false
	_mi.visible = false
	_mesh.clear_surfaces()
	_built = false
	_step = -1
	_surf_glow = -1
	_c_pos.clear()
	_c_right.clear()
	_mast_pos.clear()
	_gps.clear()
	_lm_key = ""
	_light_mast.fill(-1)
	for l in _lights:
		l.visible = false


## LE MASQUE DE road.gd TIENT A CETTE LIGNE. Tant qu'elle rend faux, le ruban
## national est trace d'un bout a l'autre du bourg — c'est ce qui s'est passe
## a chaque reconstruction depuis que le J2 existe, parce que cette methode
## n'existait pas. Elle ne dit oui qu'une fois les six surfaces versees : un
## trou de quatre images serait pire que la couture.
func draws_trunk() -> bool:
	return _built and visible


## La voiture est-elle DANS le bourg ? road.gd s'en sert pour ne pas eteindre
## une ville dans laquelle on a fait demi-tour — l'enveloppe du plan, elargie,
## et pas un produit scalaire avec le cap de la voiture : nez au nord et ville
## a l'ouest, celui-la la disait depassee.
func contains(p: Vector3) -> bool:
	if _plan == null or _c_pos.is_empty():
		return false
	return (_plan.bounds as Rect2).grow(INSIDE_MARGIN).has_point(_su_of(p))


## La distance de `p` a l'axe de chaussee le plus proche du bourg. C'est ce qui
## manquait au juge de course : sans elle, off_road_dist ne rendait que la
## nationale, et la premiere rue laterale saturait la note d'inconfort en UN
## echantillon, sans une erreur de compilation.
##
## Le plan repond dans SON repere, par sa grille de 20 m ; tout le travail est
## de lui porter le point. Le balayage des 171 echantillons coute ce que coute
## deja _closest_dist chez road.gd — c'est la meme question, posee a la
## meme densite.
func street_dist(p: Vector3) -> float:
	if _plan == null or _c_pos.is_empty():
		return 1.0e18
	return float((_plan.nearest(_su_of(p)) as Dictionary)["dist"])


## Les rues en metres du MONDE, par couples de points : le GPS y lit ses
## traits. Le meme tableau que celui dont on extrude les triangles, donc une
## carte qui ne peut pas mentir sur la ville.
func gps_lines() -> PackedVector2Array:
	return _gps


## Le repere d'une adresse, tel que le taxi le lira : origine sur l'AXE de la
## rue, -Z le long de la rue, +X vers le trottoir de l'adresse. La baie de
## validation (16 x 4,5 m) vit chez le taxi, pas ici — c'est lui qui juge un
## arret, pas la ville qui range des nombres.
func address_pose(k: int) -> Transform3D:
	if _plan == null or k < 0 or k >= (_plan.addrs as Array).size():
		return Transform3D()
	var a: Dictionary = (_plan.addrs as Array)[k]
	var i: int = a["street"]
	var t: float = a["t"]
	var side: float = a["side"]
	var su: Vector2 = _plan.point(i, t)
	var o := _world(su.x, su.y)
	# Le cote, en vrai : deux points du plan, un metre de trottoir d'ecart,
	# deplies dans le monde. Deriver ce vecteur du repere de la ville
	# marcherait au panneau et se tromperait de 17 degres a la sortie, ou la
	# traversante a tourne.
	var su2: Vector2 = _plan.point(i, t, side)
	var sx := (_world(su2.x, su2.y) - o).normalized()
	return Transform3D(Basis(sx, Vector3.UP, -Vector3.UP.cross(sx)), o)


func address_count() -> int:
	return 0 if _plan == null else (_plan.addrs as Array).size()


func address_name(k: int) -> String:
	if _plan == null or k < 0 or k >= (_plan.addrs as Array).size():
		return ""
	return String(((_plan.addrs as Array)[k] as Dictionary)["name"])


## Allume le numero de l'adresse visee, et lui seul. Le J4 l'appellera avec
## celle de la course ; d'ici la, arm() arme la premiere — une porte eclairee
## dans un bourg endormi, c'est le genre de detail qu'on ne remarque que
## lorsqu'il manque.
func set_address(k: int) -> void:
	if _plan == null or not _built:
		return
	var addrs: Array = _plan.addrs
	_addr_k = k if k >= 0 and k < addrs.size() else -1
	if _addr_k < 0:
		_number.visible = false
		return
	var fa := _addr_face(k)
	if fa.is_empty():
		_addr_k = -1
		_number.visible = false
		return
	var face: Vector3 = fa[2]
	_number.text = String((addrs[k] as Dictionary)["num"])
	_number.global_position = (fa[0] as Vector3) + face * 0.06 \
		+ Vector3(0.0, PORCH_H + 0.34, 0.0)
	_number.global_basis = Basis(Vector3.UP.cross(face), Vector3.UP, face)
	_number.visible = not _dark


## LE CAUCHEMAR : lumieres eteintes, fenetres mortes, panneaux ternes. Une
## ville qu'on connait, traversee dans le noir absolu, est une image que rien
## d'autre ne donne — et c'est le quatrieme appel que road.gd faisait dans le
## vide depuis le J2.
##
## On ECHANGE deux references de materiau, on n'en fabrique pas : les deux
## sont nes au _ready. Fabriquer un ShaderMaterial au moment ou le portail du
## cauchemar s'ouvre, c'est une compilation de shader au pire endroit du jeu.
func set_dark(on: bool) -> void:
	_dark = on
	if _surf_glow >= 0:
		_mesh.surface_set_material(_surf_glow, _mat_glow_dark if on else _mat_glow)
	for li in LIGHTS:
		_lights[li].visible = (not on) and _light_mast[li] >= 0
	var tint := Color(0.30, 0.31, 0.29) if on else Color(0.72, 0.74, 0.70)
	for s in [_sign_in, _sign_out]:
		if s != null:
			(s.get_node("Name") as Label3D).modulate = tint
	for pl in _plates:
		pl.modulate = tint
	# Le numero se rallume avec le reste : sortir du cauchemar sans lui laisserait
	# la course en cours sans son adresse, et personne ne verrait pourquoi.
	_number.visible = (not on) and _addr_k >= 0


# --------------------------------------------------------------------------
# La construction, une etape par image
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _step >= 0:
		# Le _process de ce noeud suit celui de road.gd DANS LA MEME IMAGE
		# (l'arbre descend des parents vers les enfants) : sans cette ligne, la
		# premiere etape retomberait sur l'image de l'armement, celle-la meme
		# qui peut engendrer 150 echantillons et reconstruire le ruban.
		if Engine.get_process_frames() != _arm_frame:
			match _step:
				0: _build_roads()
				1: _build_walks()
				2: _build_town()
				3: _build_glow()
			_step += 1
			if _step > 3:
				_step = -1
		return
	if _built:
		_relight(delta)



## Etape 1 — les chaussees. Le tronc d'abord, avec les MEMES points et le meme
## code que road.gd ; puis les rues.
##
## AUCUN PAVE DE CARREFOUR, et le plan en promettait huit. Un pave est un
## rectangle d'asphalte pose la ou deux chaussees se croisent — c'est-a-dire
## exactement la ou l'une des deux passe deja. Coplanaire, meme materiau, meme
## hauteur : ce n'est pas un carrefour plus epais, c'est du z-fighting en
## travers des phares. On tranche autrement, et c'est la regle de tout ce
## fichier : A CHAQUE CROISEMENT, UNE SEULE DES DEUX RUES PASSE. Celle qui cede
## est COUPEE a l'emprise de celle qui garde — ni trou, ni recouvrement, et le
## carrefour se dessine tout seul.
##
## MAIS LA PRIORITE SE DONNE PAR SURFACE, ET ELLE S'INVERSE D'UNE SURFACE A
## L'AUTRE. Ce paragraphe a longtemps dit « le tronc passe sous les
## transversales » tout court : c'est vrai de l'accotement et du trottoir, et
## c'est faux de la chaussee — celle que cette fonction pose.
##
## SUR LA CHAUSSEE — ici, etape 1 —, LE TRONC GARDE. Sa bande est posee SANS
## COUPE, en un seul appel sur les 171 echantillons (_band, cut = false), et
## c'est la transversale qui cede : _cross_band l'arrete a plus ou moins
## TRUNK_HALF, 3,4 m, le bord meme de la chaussee nationale. La parallele, elle,
## cede aux transversales (_rail_band) et ne rencontre jamais le tronc — elle
## vit a 26 m de son axe au plus pres (RAIL_U).
##
## SUR L'ACCOTEMENT ET LE TROTTOIR — etape 2, _build_walks —, LE TRONC CEDE.
## C'est la, et la seulement, que la vieille phrase devient vraie : ses bandes
## sont coupees sur l'emprise entiere de chaque transversale, plus ou moins
## edge_half, soit 2,6 + 1,6 = 4,2 m de part et d'autre, donc un trou de 8,4 m.
## La transversale le rebouche au metre pres avec sa chaussee (5,2 m) et ses
## deux trottoirs (2 x 1,6 m) — 8,4 m —, et ses bandes partent de TRUNK_HALF
## pile, sur le segment de bord que le tronc vient de laisser.
##
## LA SECONDE MOITIE DE LA PHRASE, ELLE, TIENT PARTOUT : les transversales
## passent sur les paralleles, sur la chaussee comme sur le trottoir.
func _build_roads() -> void:
	_reset()
	# La chaussee du tronc : un seul appel sur les 171 echantillons, les memes
	# decalages, la meme hauteur, le meme nombre de colonnes que road.gd. C'est
	# ici que la couture se joue, et elle ne se calcule pas : c'est le meme
	# point, extrude par le meme code.
	_band(-TownPlan.TRUNK_HALF, TownPlan.TRUNK_HALF, Y_ROAD, ROAD_COLS, false)
	for i in (_plan.streets as Array).size():
		var st: Dictionary = _plan.streets[i]
		if st["kind"] == "trunk":
			continue
		var h: float = st["half"]
		if st["kind"] == "cross":
			_cross_band(i, -h, h, Y_ROAD)
		else:
			_rail_band(i, -h, h, Y_ROAD)
	_commit(_mat_asphalt)


## Etape 2 — accotements, trottoirs, peinture.
##
## L'accotement et le trottoir du tronc sont COUPES a chaque transversale : une
## rue qui debouche sur la nationale n'a pas un trottoir en travers de sa
## bouche. La coupe vaut l'emprise entiere de la transversale (4,2 m de part et
## d'autre de son axe), et c'est exactement ce que ses propres bandes
## rebouchent — sa chaussee sur 2,6 m, ses trottoirs sur les 1,6 qui suivent.
## Les deux bouts tombent au metre pres sur la meme abscisse : rien ne se
## recouvre, rien ne manque.
##
## La peinture, elle, n'est pas coupee : les lignes de rive sont a 2,95 m de
## l'axe, dans la chaussee, et une rive interrompue a chaque venelle ferait
## clignoter la route. Aucun pointille central en revanche — une traversante
## n'a pas de bande axiale, et un pointille survivant flotterait tout seul
## entre deux trottoirs.
func _build_walks() -> void:
	var e := TownPlan.TRUNK_HALF + TownPlan.SHOULDER
	_reset()
	_band(-e, -TownPlan.TRUNK_HALF, Y_SHOULDER, SHOULDER_COLS, true)
	_band(TownPlan.TRUNK_HALF, e, Y_SHOULDER, SHOULDER_COLS, true)
	_commit(_mat_shoulder)

	_reset()
	var w := e + TownPlan.WALK_TRUNK
	_band(-w, -e, Y_WALK, SHOULDER_COLS, true)
	_band(e, w, Y_WALK, SHOULDER_COLS, true)
	for i in (_plan.streets as Array).size():
		var st: Dictionary = _plan.streets[i]
		if st["kind"] == "trunk":
			continue
		var h: float = st["half"]
		var k: float = h + float(st["walk"])
		if st["kind"] == "cross":
			_cross_band(i, h, k, Y_WALK)
			_cross_band(i, -k, -h, Y_WALK)
		else:
			_rail_band(i, h, k, Y_WALK)
			_rail_band(i, -k, -h, Y_WALK)
	_commit(_mat_walk)

	_reset()
	var p := TownPlan.TRUNK_HALF - LINE_INSET
	_band(-p - LINE_HALF, -p + LINE_HALF, Y_PAINT, 1, false)
	_band(p - LINE_HALF, p + LINE_HALF, Y_PAINT, 1, false)
	_commit(_mat_paint)


## Etape 3 — le bati : les maisons et les mats. C'est l'etape la plus chere du
## fichier, et la seule dont le cout depend du tirage : de 60 maisons (Peyrelade)
## a 70 (Malassis).
##
## Une maison est une boite a CINQ faces — quatre murs et un toit plat, pas de
## dessous : on ne verra jamais le dessous d'une maison, et le plancher aurait
## coute 20 % de la surface 5 pour rien.
func _build_town() -> void:
	_reset()
	for k in _plan.bld_count():
		_building(k)
	for k in _plan.lamp_count():
		_mast(k)
	# Le repere se pose ici, APRES les maisons : sa place se cherche contre
	# elles, et son corps part dans la meme surface qu'elles.
	_landmark_pose()
	_landmark(0)
	_plates_and_signs()
	_commit(_mat_house)


## Etape 4 — l'emissif, et la ville s'allume.
##
## C'est LA surface qui fait le bourg. Le brouillard a 0,030 ne laisse passer
## que 5 % a 100 m : les soixante-quatre boites d'albedo 0,030 ne rendent rien
## au-dela de la portee des phares, et ce qu'on voit d'une ville de nuit, ce
## sont ses fenetres allumees et ses tetes de lampadaire. Elles ne coutent ni
## une lumiere ni un appel de dessin — ce sont des quads dans une surface deja
## emise.
func _build_glow() -> void:
	_reset()
	for k in _plan.bld_count():
		_windows(k)
	for k in _plan.lamp_count():
		_head(k)
	for k in (_plan.addrs as Array).size():
		_porch(k)
	# Ce qui luit du repere : le cadran, la couronne, le fanal. Meme surface,
	# meme materiau, donc meme couleur que les fenetres — un feu rouge de
	# balisage sortirait orange, et c'est pour ca que les huit se distinguent
	# par la FORME et la HAUTEUR de leur lumiere, jamais par sa teinte.
	_landmark(3)
	_surf_glow = _mesh.get_surface_count()
	_commit(_mat_glow)
	if _mesh.get_surface_count() == _surf_glow:
		_surf_glow = -1        # aucune fenetre allumee : rien n'a ete verse

	_build_gps()
	_mi.visible = true
	_built = true
	_place_lights()
	set_address(0)
	if _loud:
		_print_cost()


# --------------------------------------------------------------------------
# Le tronc : les 171 tetes de road.gd, telles quelles
# --------------------------------------------------------------------------

## Va chercher la ligne mediane que la ville doit dessiner. Elle est en DEUX
## morceaux, et c'est structurel :
##  - les 20 echantillons d'avant le panneau (PAD) sont NES : road.sample_at()
##    les rend, et ce sont ceux du ruban vivant, bit pour bit ;
##  - les 150 d'apres ne le sont pas encore — la tete de fenetre EST le
##    panneau. road.gd vient de les simuler (_simulate_town_path) pour cette
##    raison exacte : la ville a besoin de sa ligne ENTIERE au moment ou elle
##    se batit, et _append_sample les reposera ensuite tels quels au lieu de
##    tirer au sort. On lit donc son tableau.
##
## OUI, C'EST UN MEMBRE PRIVE, et il n'y a pas d'autre porte. arm() ne recoit
## qu'une transform et un nom ; rejouer la simulation ici demanderait la
## courbure sous le panneau, que rien ne rend et qu'aucune geometrie passee ne
## permet de retrouver — le lissage d'approche l'a menee a ~1e-7, ce qui n'est
## pas zero. Un chemin rejoue « pareil » et un chemin REPOSE, ce sont deux
## rubans qui divergent, et la couture est faite pour ne pas dependre de ca.
##
## Le filet, si la fenetre ne rend rien : on prolonge tout droit depuis le
## panneau. Ca n'arrive que dans une image ou road.gd vient d'echanger ses
## rubans a une fourche et n'a pas encore rempli sa fenetre — jamais en
## navigation normale, ou le Y est tenu 33 echantillons au-dela du bourg.
func _gather(at: Transform3D) -> void:
	_c_pos.clear()
	_c_right.clear()
	var road := get_parent()
	var g0: int = (road.town_span() as Vector2i).x
	var fwd0 := -at.basis.z

	for k in PAD:
		var tr: Transform3D = road.sample_at(g0 + k)
		if tr.origin == Vector3.ZERO:
			_c_pos.append(at.origin - fwd0 * float(PAD - k) * STEP)
			_c_right.append(at.basis.x)
		else:
			_c_pos.append(tr.origin)
			_c_right.append(tr.basis.x)
	_c_pos.append(at.origin)
	_c_right.append(at.basis.x)

	var heads: Array = road._town_heads
	var h := at
	for k in CROSS + PAD:
		if k < heads.size():
			h = heads[k]
		else:
			h.origin += -h.basis.z * STEP
		_c_pos.append(h.origin)
		# La MEME expression que road.gd, pas le vecteur X de la base : les
		# deux valent la meme chose au bit pres seulement si on les calcule
		# pareil, et c'est de ce vecteur que sortent les bords de chaussee.
		_c_right.append((-h.basis.z).cross(Vector3.UP).normalized())


## Le point du monde a la coordonnee curviligne (s, u). Sur un echantillon
## (s multiple de STEP) il rend EXACTEMENT pos + right * u — le calcul de
## strip.ribbon, aux memes bits : c'est ce qui permet a une bande coupee de se
## raccorder a une bande entiere sans un cheveu d'ecart. Entre deux, il
## interpole ; au-dela des bouts, il prolonge le dernier segment.
func _world(s: float, u: float) -> Vector3:
	var f := s / STEP + float(PAD)
	var i := clampi(int(floor(f)), 0, _c_pos.size() - 2)
	var w := f - float(i)
	return _c_pos[i] + (_c_pos[i + 1] - _c_pos[i]) * w \
		+ (_c_right[i] + (_c_right[i + 1] - _c_right[i]) * w) * u


func _right_at(s: float) -> Vector3:
	var f := s / STEP + float(PAD)
	var i := clampi(int(floor(f)), 0, _c_pos.size() - 2)
	var w := f - float(i)
	return _c_right[i] + (_c_right[i + 1] - _c_right[i]) * w


## Le point du monde ramene en coordonnees du plan. L'echantillon le plus
## proche, puis deux produits scalaires : c'est le meme balayage que
## _closest_dist chez road.gd, sur la meme densite de points.
func _su_of(p: Vector3) -> Vector2:
	var best := 1.0e18
	var bk := 0
	for k in _c_pos.size():
		var q := _c_pos[k]
		var d := Vector2(p.x - q.x, p.z - q.z).length_squared()
		if d < best:
			best = d
			bk = k
	var r := _c_right[bk]
	var dp := p - _c_pos[bk]
	return Vector2(float(bk - PAD) * STEP + dp.dot(Vector3.UP.cross(r)), dp.dot(r))


# --------------------------------------------------------------------------
# Les bandes
# --------------------------------------------------------------------------

## Une bande le long du TRONC, de u0 a u1. `cut` la coupe a chaque
## transversale, sur l'emprise entiere de celle-ci.
##
## Sans coupe, c'est UN SEUL appel a strip.ribbon sur les 171 echantillons du
## ruban : la chaussee et la peinture du tronc sont, au bit pres, celles que
## road.gd aurait ecrites.
func _band(u0: float, u1: float, y: float, cols: int, cut: bool) -> void:
	var s0 := -float(PAD) * STEP
	var s1 := float(CROSS + PAD) * STEP
	if not cut:
		_line(s0, s1, 1)
		Strip.ribbon(_v, _n, _f, _lp, _lr, u0, u1, y, cols)
		return
	var a := s0
	for i in (_plan.streets as Array).size():
		var st: Dictionary = _plan.streets[i]
		if st["kind"] != "cross":
			continue
		var g: float = _plan.edge_half(i)
		var s: float = st["s"]
		_seg(a, s - g, u0, u1, y, cols, 1)
		a = s + g
	_seg(a, s1, u0, u1, y, cols, 1)


## Une bande d'une PARALLELE : elle suit le tronc a u constant, et cede a
## chaque transversale. Ses deux bouts tombent sur la premiere et la derniere
## d'entre elles, donc les coupes d'extremite la rognent d'elles-memes.
##
## Un point sur deux (4 m) : a la courbure plafonnee de la traversante, la
## fleche d'une corde de 4 m vaut trois millimetres. Un point tous les deux
## metres aurait double la surface 3 pour ca.
func _rail_band(i: int, o0: float, o1: float, y: float) -> void:
	var u: float = _plan.streets[i]["u"]
	var a: float = _plan.streets[i]["a"]
	var b: float = _plan.streets[i]["b"]
	var at := a
	for j in (_plan.streets as Array).size():
		var st: Dictionary = _plan.streets[j]
		if st["kind"] != "cross":
			continue
		var g: float = _plan.edge_half(j)
		var s: float = st["s"]
		if s < a - g or s > b + g:
			continue
		_seg(at, s - g, u + o0, u + o1, y, 1, 2)
		at = s + g
	_seg(at, b, u + o0, u + o1, y, 1, 2)


## Une bande d'une TRANSVERSALE. Dans le plan c'est une perpendiculaire au
## tronc ; dans le monde c'est une DROITE, parce que le repere curviligne pose
## tout un carrefour sur le meme echantillon de route. Deux points suffisent
## donc, et deux points sont EXACTS — c'est la seule geometrie du bourg qui ne
## paie pas la courbure.
##
## Elle est coupee sur la chaussee du tronc, et sur elle seule : sa bouche
## couvre l'accotement et le trottoir de la nationale, que _band vient de
## trouer sur exactement la meme largeur.
func _cross_band(i: int, o0: float, o1: float, y: float) -> void:
	var s: float = _plan.streets[i]["s"]
	var a: float = _plan.streets[i]["a"]
	var b: float = _plan.streets[i]["b"]
	_cross_seg(s, a, -TownPlan.TRUNK_HALF, o0, o1, y)
	_cross_seg(s, TownPlan.TRUNK_HALF, b, o0, o1, y)


func _cross_seg(s: float, u_a: float, u_b: float, o0: float, o1: float, y: float) -> void:
	if u_b - u_a < 0.5:
		return
	var p := _world(s, 0.0)
	var r := _right_at(s)
	# La rue file vers +u : sa direction est le vecteur DROITE du tronc, donc
	# son propre vecteur droite vaut direction x UP, soit l'arriere du tronc.
	# C'est la regle d'enroulement de strip.gd, et s'en ecarter d'un signe rend
	# la rue invisible.
	var q := -Vector3.UP.cross(r)
	_lp.clear()
	_lr.clear()
	_lp.append(p + r * u_a)
	_lr.append(q)
	_lp.append(p + r * u_b)
	_lr.append(q)
	Strip.ribbon(_v, _n, _f, _lp, _lr, o0, o1, y, 1)


func _seg(s_a: float, s_b: float, u0: float, u1: float, y: float,
		cols: int, stride: int) -> void:
	if s_b - s_a < 0.5:
		return
	_line(s_a, s_b, stride)
	if _lp.size() < 2:
		return
	Strip.ribbon(_v, _n, _f, _lp, _lr, u0, u1, y, cols)


## La ligne mediane du tronc entre deux abscisses, dans _lp / _lr. Les
## echantillons du ruban sont repris TELS QUELS — c'est ce qui rend une bande
## entiere identique a celle de road.gd — et seuls les bouts qui tombent entre
## deux echantillons sont interpoles.
func _line(s_a: float, s_b: float, stride: int) -> void:
	_lp.clear()
	_lr.clear()
	var ka := int(ceil(s_a / STEP + float(PAD) - 0.001))
	var kb := int(floor(s_b / STEP + float(PAD) + 0.001))
	ka = clampi(ka, 0, _c_pos.size() - 1)
	kb = clampi(kb, 0, _c_pos.size() - 1)
	if float(ka - PAD) * STEP > s_a + 0.001:
		_lp.append(_world(s_a, 0.0))
		_lr.append(_right_at(s_a))
	if ka <= kb:
		var k := ka
		while k < kb:
			_lp.append(_c_pos[k])
			_lr.append(_c_right[k])
			k += stride
		# Le dernier echantillon est TOUJOURS pose, quel que soit le pas :
		# le sauter raccourcirait la bande de quatre metres, et ces quatre
		# metres-la sont la couture avec ce qui suit.
		_lp.append(_c_pos[kb])
		_lr.append(_c_right[kb])
	if float(kb - PAD) * STEP < s_b - 0.001:
		_lp.append(_world(s_b, 0.0))
		_lr.append(_right_at(s_b))


# --------------------------------------------------------------------------
# Le bati
# --------------------------------------------------------------------------

## Une maison : quatre murs et un toit, sur l'empreinte que le plan a posee.
##
## L'empreinte arrive dans le sens qui va : celui ou (arete x UP) regarde
## DEHORS a chaque cote, donc celui ou les murs sont a l'endroit. Le toit se
## pose dans l'ordre INVERSE — un volume ferme se parcourt en sens contraire
## selon qu'on le regarde du dessus ou du dehors, et c'est la faute que le
## depot a deja payee deux fois.
func _building(k: int) -> void:
	var o := k * 7
	var h: float = _plan.blds[o + 4]
	var co: PackedVector2Array = TownPlan._corners(
		Vector2(_plan.blds[o], _plan.blds[o + 1]),
		_plan.blds[o + 2], _plan.blds[o + 3], _plan.blds[o + 5])
	var p := PackedVector3Array()
	for c in co:
		p.append(_world(c.x, c.y))
	for i in 4:
		_wall(p[i], p[(i + 1) % 4], h)
	var up := Vector3(0.0, h, 0.0)
	_quad(p[3] + up, p[2] + up, p[1] + up, p[0] + up, Vector3.UP)


## Un mur, de A a B, de hauteur h. L'exterieur est du cote (B - A) x UP :
## quatre sommets, deux triangles, une normale plate.
func _wall(a: Vector3, b: Vector3, h: float) -> void:
	var nrm := (b - a).cross(Vector3.UP).normalized()
	var up := Vector3(0.0, h, 0.0)
	_quad(a, a + up, b + up, b, nrm)


## Un quadrilatere plan, quatre sommets dans l'ordre, deux triangles. Le meme
## enroulement que strip.gd : (0, 1, 2) puis (0, 2, 3).
func _quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3) -> void:
	var base := _v.size()
	_v.append(p0)
	_v.append(p1)
	_v.append(p2)
	_v.append(p3)
	for i in 4:
		_n.append(nrm)
	_f.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Le meme, VISIBLE DES DEUX COTES : les memes quatre sommets, les deux
## enroulements. C'est pour les tetes de lampadaire, qu'on croise dans les deux
## sens — une tete visible d'un seul cote s'eteindrait dans le retroviseur.
func _quad2(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3) -> void:
	var base := _v.size()
	_quad(p0, p1, p2, p3, nrm)
	_f.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


## Un mat hexagonal : douze sommets, douze triangles, aucun couvercle. Six cotes
## suffisent a 0,17 m de diametre — road.gd fait deja tourner ses troncs a 6 et
## ses poteaux a 6.
##
## LE LAMPADAIRE N'EST PLUS UN NOEUD. La ville d'avant en posait quatre, chacun
## un Node3D avec son CylinderMesh et sa BoxMesh — et ce CylinderMesh n'avait
## jamais touche radial_segments, donc il tournait au defaut de Godot :
## SOIXANTE-QUATRE segments pour un poteau de 5 cm de rayon vu dans le
## brouillard, soit plus de sommets qu'une maison entiere, quatre fois. Ici les
## vingt-trois mats sont douze sommets chacun dans une surface deja emise, et
## ils ne coutent pas un appel de dessin de plus. Le meme defaut vivait dans
## make_sign, qui reste un noeud lui : il y est corrige a 8.
func _mast(k: int) -> void:
	var i := int(_plan.lamps[k * 3])
	var t: float = _plan.lamps[k * 3 + 1]
	var side: float = _plan.lamps[k * 3 + 2]
	var su: Vector2 = _plan.point(i, t, side * _plan.walk_mid(i))
	var foot := _world(su.x, su.y)
	var b0 := _v.size()
	for pass_ in 2:
		var up := Vector3(0.0, MAST_H if pass_ == 1 else 0.0, 0.0)
		for j in 6:
			# Le sens HORAIRE vu du dessus (angle decroissant) : c'est lui qui
			# met les six faces a l'endroit, par la meme regle que les murs.
			var ang := -TAU * float(j) / 6.0
			var off := Vector3(cos(ang) * MAST_R, 0.0, sin(ang) * MAST_R)
			_v.append(foot + off + up)
			_n.append(off.normalized())
	for j in 6:
		var j2 := (j + 1) % 6
		_f.append_array([b0 + j, b0 + 6 + j, b0 + 6 + j2,
			b0 + j, b0 + 6 + j2, b0 + j2])
	_mast_pos.append(foot + Vector3(0.0, MAST_H - 0.2, 0.0)
		+ _toward_axis(i, t, side) * HEAD_OUT)


## Le vecteur qui, depuis un point decale de `side` sur la rue `i`, pointe vers
## SON AXE. Il sert deux fois : la tete d'un reverbere deborde par la (un
## lampadaire eclaire la chaussee, pas le mur derriere lui) et une plaque de rue
## se lit par la.
##
## Il se PREND A SON ABSCISSE, jamais au panneau : d'un bout a l'autre du bourg
## la traversante tourne de dix-sept degres, et une plaque orientee a l'entree
## serait de travers a la sortie.
func _toward_axis(i: int, t: float, side: float) -> Vector3:
	var a: Vector2 = _plan.point(i, t, side)
	var b: Vector2 = _plan.point(i, t)
	return (_world(b.x, b.y) - _world(a.x, a.y)).normalized()


## La tete de lampadaire : DEUX quads croises, visibles des deux cotes, dans la
## surface emissive. Vingt tetes orange dans le brouillard, c'est ce qui fait
## une ville de nuit ; trois d'entre elles seulement portent une vraie
## OmniLight, et le joueur ne peut pas dire lesquelles.
##
## Croises, parce qu'un seul quad s'efface a quatre-vingt-dix degres : on
## traverse le bourg par le tronc et on tourne dans les rues, donc on les voit
## sous tous les angles.
func _head(k: int) -> void:
	if k >= _mast_pos.size():
		return
	var c := _mast_pos[k]
	var i := int(_plan.lamps[k * 3])
	var t: float = _plan.lamps[k * 3 + 1]
	var out := _toward_axis(i, t, _plan.lamps[k * 3 + 2])
	var along := Vector3.UP.cross(out)
	var up := Vector3(0.0, HEAD_H, 0.0)
	for d: Vector3 in [along, out]:
		var a := c - d * (HEAD_W * 0.5) - up * 0.5
		var b := c + d * (HEAD_W * 0.5) - up * 0.5
		_quad2(a, a + up, b + up, b, d.cross(Vector3.UP).normalized())


## Les fenetres allumees d'une maison, sur la SEULE face qui regarde la rue —
## celle qui va du coin 0 au coin 1 de l'empreinte. Un masque de 24 bits, bit
## (etage x 8 + travee), tire par le plan.
##
## Posees deux centimetres DEVANT le mur et pas dedans : une fenetre coplanaire
## a sa facade clignote avec elle des que la voiture bouge.
func _windows(k: int) -> void:
	var o := k * 7
	var mask := int(_plan.blds[o + 6])
	if mask == 0:
		return
	var w: float = _plan.blds[o + 2]
	var h: float = _plan.blds[o + 4]
	var co: PackedVector2Array = TownPlan._corners(
		Vector2(_plan.blds[o], _plan.blds[o + 1]), w, _plan.blds[o + 3], _plan.blds[o + 5])
	var a := _world(co[0].x, co[0].y)
	var b := _world(co[1].x, co[1].y)
	var wide := a.distance_to(b)
	if wide < 0.01:
		return
	var dir := (b - a) / wide
	var nrm := dir.cross(Vector3.UP).normalized()
	var bays := clampi(int(w / TownPlan.WIN_BAY), 1, TownPlan.WIN_BAYS_MAX)
	var flrs := clampi(int(h / TownPlan.WIN_FLOOR), 1, TownPlan.WIN_FLOORS_MAX)
	for fy in flrs:
		for bx in bays:
			if mask & (1 << (fy * TownPlan.WIN_BAYS_MAX + bx)) == 0:
				continue
			var c := a + dir * (wide * (float(bx) + 0.5) / float(bays)) \
				+ nrm * WIN_OUT \
				+ Vector3(0.0, float(fy) * TownPlan.WIN_FLOOR + 1.35 - WIN_H * 0.5, 0.0)
			_wall(c - dir * (WIN_W * 0.5), c + dir * (WIN_W * 0.5), WIN_H)


## Le porche : trois quads emissifs sur la facade de l'adresse — la porte et
## ses deux jambages. C'est ce qu'on cherche dans les phares avant de l'avoir
## atteint, et c'est la raison d'etre de la surface 6.
##
## Les QUATRE adresses du bourg l'ont, pas seulement celle de la course : une
## seule porte eclairee dans une ville entiere serait un panneau, pas une
## ville. Ce qui distingue celle qu'on cherche, c'est son NUMERO (set_address).
func _porch(k: int) -> void:
	var fa := _addr_face(k)
	if fa.is_empty():
		return
	var c: Vector3 = fa[0] + (fa[2] as Vector3) * WIN_OUT
	var dir: Vector3 = fa[1]
	_wall(c - dir * (PORCH_W * 0.5), c + dir * (PORCH_W * 0.5), PORCH_H)
	for s: float in [-1.0, 1.0]:
		var j := c + dir * (s * (PORCH_W * 0.5 + 0.16))
		_wall(j - dir * 0.06, j + dir * 0.06, PORCH_H + 0.30)


## Le MUR de l'adresse : milieu de la facade du batiment auquel elle est
## accrochee, sa direction et sa normale. On ne pose pas le porche sur le plan
## de retrait nominal — le lacet de quatre degres que le plan donne aux
## facades y ferait flotter la porte jusqu'a 28 cm devant le mur, ou l'y
## enfoncerait. On la pose sur le mur qui existe.
##
## Le batiment se retrouve par sa distance au point de facade de l'adresse : le
## sien a son centre a une demi-profondeur de la (5 m au plus), le voisin le
## plus proche a plus de dix.
func _addr_face(k: int) -> Array:
	var a: Dictionary = (_plan.addrs as Array)[k]
	var i: int = a["street"]
	var setb: float = TownPlan.SETBACK_TR if _plan.streets[i]["kind"] == "trunk" \
		else TownPlan.SETBACK
	var aim: Vector2 = _plan.point(i, float(a["t"]), float(a["side"]) * setb)
	var best := -1
	var bd := 1.0e18
	var n := int(_plan.bld_count())
	for b in n:
		var o: int = b * 7
		var d := aim.distance_squared_to(Vector2(_plan.blds[o], _plan.blds[o + 1]))
		if d < bd:
			bd = d
			best = b
	if best < 0:
		return []
	var o2 := best * 7
	var co: PackedVector2Array = TownPlan._corners(
		Vector2(_plan.blds[o2], _plan.blds[o2 + 1]),
		_plan.blds[o2 + 2], _plan.blds[o2 + 3], _plan.blds[o2 + 5])
	var p0 := _world(co[0].x, co[0].y)
	var p1 := _world(co[1].x, co[1].y)
	var dir := (p1 - p0).normalized()
	return [(p0 + p1) * 0.5, dir, dir.cross(Vector3.UP).normalized(), _plan.blds[o2 + 4]]


# --------------------------------------------------------------------------
# Le repere
# --------------------------------------------------------------------------

## Les huit modeles, lus au _ready.
##
## ON OUVRE LE .glb NOUS-MEMES, par GLTFDocument, et pas par load(). Sept des
## huit n'ont pas de fichier .import — Godot l'ecrit a la premiere ouverture de
## l'EDITEUR, et l'editeur n'est jamais ouvert quand un banc tourne. Un repere
## qui manque parce qu'un fichier de cache n'a pas ete ecrit serait le genre de
## panne qu'on ne comprend pas ; ici il n'y a rien a importer, on lit le
## fichier livre.
##
## Ce qu'on garde de la scene : des sommets, des normales et des indices. La
## scene elle-meme est LIBEREE dans la foulee — ses MeshInstance3D et ses
## materiaux glTF n'ont plus rien a faire dans un jeu ou tout passe par le
## shader de tramage.
func _load_landmarks() -> void:
	var t0 := Time.get_ticks_usec()
	var v := 0
	var t := 0
	for key: String in LM_MODEL.values():
		if _lm.has(key):
			continue
		var d := _read_glb(LM_PATH % key)
		if d.is_empty():
			continue
		_lm[key] = d
		v += (d[0] as PackedVector3Array).size() + (d[3] as PackedVector3Array).size()
		t += ((d[2] as PackedInt32Array).size() + (d[5] as PackedInt32Array).size()) / 3
	if _loud:
		print("  [reperes] %d modeles lus en %.1f ms au _ready, %d sommets et %d triangles en reserve" % [
			_lm.size(), float(Time.get_ticks_usec() - t0) / 1000.0, v, t])
		_audit_landmarks()


## LES HUIT PLACES, CHERCHEES ET CHIFFREES DES QU'UN BANC TOURNE. Un banc
## n'arme jamais que deux ou trois bourgs : sans cette ligne, la place du
## repere des cinq autres ne serait verifiee par personne. On la cherche donc
## pour les huit villes de la carte, au _ready, et on imprime ce qu'on trouve
## — le degagement (« pas au milieu d'une rue, pas dans une maison ») et la
## distance au panneau (« il se voit depuis la route avant le panneau »).
## Le site trouve est celui-la meme que le bourg utilisera : il est memoise
## par nom, et le plan qui l'a produit l'est aussi.
func _audit_landmarks() -> void:
	var cost := 0
	for id: String in TownPlan.MapScript.towns():
		var key := _lm_of(id)
		if not _lm.has(key):
			print("  [repere] %s — AUCUN MODELE (%s)" % [id, key])
			continue
		var plan = TownPlan.of(id)
		var t0 := Time.get_ticks_usec()
		var site: Vector4 = _lm_seat(plan, key, id)
		cost += Time.get_ticks_usec() - t0
		if site.z == 0.0 and site.w == 0.0:
			print("  [repere] %s — AUCUNE PLACE TENABLE pour %s" % [id, key])
			continue
		var half: Vector2 = (_lm[key] as Array)[6]
		var box := half if absf(site.w) > 0.5 else Vector2(half.y, half.x)
		var seat := Vector2(site.x, site.y)
		var sky := _lm_sky(plan, seat, float((_lm[key] as Array)[7]))
		print("  [repere] %-12s %-11s (s %6.1f, u %6.1f) emprise %4.1f x %4.1f m, haut %5.2f m ; degagement %5.2f m ; %3.0f m du panneau, %3.0f m du premier metre dessine, %4.1f deg hors de l'axe ; VU DE LA ROUTE sur %3.0f %% de l'approche, %4.1f m au-dessus des toits" % [
			id, key, seat.x, seat.y, box.x * 2.0, box.y * 2.0, float((_lm[key] as Array)[7]),
			_lm_room(plan, seat, box), seat.length(),
			seat.distance_to(Vector2(-float(PAD) * STEP, 0.0)),
			rad_to_deg(atan2(absf(seat.y), seat.x + float(PAD) * STEP)),
			sky.x * 100.0, sky.y])
	# CE QUE LA RECHERCHE COUTE, et ou elle tombe. En partie normale ces huit
	# sites ne sont pas cherches ici (l'audit ne tourne que sous banc) : le
	# premier armement d'un bourg en paie UN, a l'etape 3, avec le bati. Le
	# jalon demande moins de 4,0 ms par etape.
	print("  [reperes] les huit sites cherches en %.2f ms — %.2f ms par bourg, et c'est ce que paie l'etape 3 au premier armement (le jalon demande moins de 4,0)" % [
		float(cost) / 1000.0, float(cost) / 8000.0])


## Un modele, en huit cases (voir _lm). Rend un tableau VIDE si le fichier
## manque ou ne porte pas un triangle : le bourg se batira alors sans repere,
## et le releve du banc le dira.
func _read_glb(path: String) -> Array:
	var bv := PackedVector3Array()
	var bn := PackedVector3Array()
	var bf := PackedInt32Array()
	var gv := PackedVector3Array()
	var gn := PackedVector3Array()
	var gf := PackedInt32Array()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) == OK:
		var root := doc.generate_scene(st)
		if root != null:
			_read_node(root, (root as Node3D).transform, bv, bn, bf, gv, gn, gf)
			root.free()
	if bf.is_empty() and gf.is_empty():
		return []
	# L'emprise, mesuree et pas lue dans un tableau : le contrat de Blender dit
	# base a z = 0 et centre en (0, 0) — c'est verifie la-bas, ca se remesure
	# ici, et c'est ce nombre-la qui decide ou le repere tient.
	var lo := Vector3(1.0e18, 1.0e18, 1.0e18)
	var hi := -lo
	for p in bv:
		lo = lo.min(p)
		hi = hi.max(p)
	for p in gv:
		lo = lo.min(p)
		hi = hi.max(p)
	return [bv, bn, bf, gv, gn, gf,
		Vector2(maxf(-lo.x, hi.x), maxf(-lo.z, hi.z)), hi.y]


## Descend l'arbre de la scene glTF et verse chaque maillage dans le bon
## tampon. LE NOM DU NOEUD DECIDE : il finit par _Lit, ce qu'il porte luit et
## part dans la surface 6 ; sinon c'est de la pierre et ca part dans la 5.
##
## La transform se cumule A LA MAIN : les noeuds ne sont pas dans l'arbre du
## jeu, et global_transform y rend l'identite en criant.
func _read_node(n: Node, xf: Transform3D,
		bv: PackedVector3Array, bn: PackedVector3Array, bf: PackedInt32Array,
		gv: PackedVector3Array, gn: PackedVector3Array, gf: PackedInt32Array) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		var lit := mi.name.ends_with("_Lit")
		for k in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(k)
			if lit:
				_pour(a, xf, gv, gn, gf)
			else:
				_pour(a, xf, bv, bn, bf)
	for c in n.get_children():
		var c3 := c as Node3D
		_read_node(c, xf if c3 == null else xf * c3.transform, bv, bn, bf, gv, gn, gf)


## Une surface de maillage, transformee et empilee. L'ENROULEMENT NE SE TOUCHE
## PAS : ces tableaux sortent de l'importeur glTF de Godot, ils sont donc deja
## dans le sens ou Godot voit une face avant. La pose, elle, a un determinant
## de +1 (une rotation autour de UP), et ne le retourne pas.
##
## La normale suit la BASE et rien d'autre : les huit modeles ne portent aucune
## echelle de noeud (mesure sur les huit .glb), la base est donc une rotation
## pure et une normale unitaire le reste.
static func _pour(a: Array, xf: Transform3D, v: PackedVector3Array,
		n: PackedVector3Array, f: PackedInt32Array) -> void:
	var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var pf: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var base := v.size()
	var b := xf.basis
	for i in pv.size():
		v.append(xf * pv[i])
		n.append(b * pn[i])
	for k in pf.size():
		f.append(base + pf[k])


## Le modele d'un bourg. Hors carte, on en pioche un sur le nom : c'est stable
## d'une partie a l'autre, et un bourg de banc a droit a une silhouette.
func _lm_of(name_: String) -> String:
	if LM_MODEL.has(name_):
		return String(LM_MODEL[name_])
	var keys: Array = LM_MODEL.values()
	return String(keys[absi(hash(name_)) % keys.size()])


## Pose le repere dans le MONDE, a l'etape 3, une fois les maisons connues.
##
## L'ORIENTATION DU MODELE EST MESUREE, PAS DEDUITE. Ce que les huit .glb
## rendent une fois relus dans Godot, releve sur les huit : Y EN HAUT (le glTF
## est deja Y-up, l'importeur ne retourne rien), BASE A y = 0 au millimetre,
## centre en (x, z) = (0, 0), et la face avant — celle qui porte le cadran, la
## lanterne, le panneau — regarde +Z. C'est la consequence de la convention de
## Blender (Z en haut, avant vers -Y) que le glTF transpose en (x, z, -y), et
## c'est verifie au chiffre : le cadran du clocher sort a z = +1,70 a +1,85 m,
## et l'emprise entiere tient dans y = 0 a 21,96 m. La pose ci-dessous envoie
## donc +Z sur le cap, et rien d'autre n'a a etre retourne.
##
## Le cap se DEPLIE : deux points du plan a un metre l'un de l'autre, portes
## dans le monde par _world. Le prendre dans le repere du panneau tomberait
## juste a l'entree et de dix-sept degres a cote a la sortie, ou la
## traversante a tourne — c'est deja la lecon de _toward_axis.
func _landmark_pose() -> void:
	if _lm_key == "" or not _lm.has(_lm_key):
		_lm_key = ""
		return
	var site: Vector4 = _lm_seat(_plan, _lm_key, town_name)
	if site.z == 0.0 and site.w == 0.0:
		_lm_key = ""
		return
	var o := _world(site.x, site.y)
	var f := (_world(site.x + site.z, site.y + site.w) - o).normalized()
	_lm_pose = Transform3D(Basis(Vector3.UP.cross(f), Vector3.UP, f), o)


## Verse le repere dans la surface en cours. `o` vaut 0 pour le corps (avec les
## maisons) et 3 pour ce qui luit (avec les fenetres) — les memes tampons, le
## meme _commit, le meme materiau : le repere n'existe pas separement.
func _landmark(o: int) -> void:
	if _lm_key == "" or not _lm.has(_lm_key):
		return
	var d: Array = _lm[_lm_key]
	var vs: PackedVector3Array = d[o]
	var ns: PackedVector3Array = d[o + 1]
	var fs: PackedInt32Array = d[o + 2]
	if fs.is_empty():
		return
	var base := _v.size()
	var b := _lm_pose.basis
	for i in vs.size():
		_v.append(_lm_pose * vs[i])
		_n.append(b * ns[i])
	for k in fs.size():
		_f.append(base + fs[k])


## OU SE POSE LE REPERE, et ce n'est ni au hasard ni a la main.
##
## LA REGLE : IL FERME LA PERSPECTIVE D'UNE RUE. On essaie les DEUX bouts de
## chaque rue du bourg sauf le tronc (qui n'en a pas : il traverse), on garde
## celui que le conducteur voit le PLUS TOT — le plus proche du premier metre
## que la ville dessine, PAD echantillons avant le panneau — et on refuse tout
## ce qui n'a pas LM_KEEP de degagement. Le tronc est ecarte pour une raison de
## plus : un repere au bout du tronc serait AU MILIEU de la nationale.
##
## PUIS ON LE RAMENE, s'il le faut, sur l'axe de sa rue et jamais ailleurs
## (voir _lm_pull) : il ne quitte donc pas la perspective qu'il ferme, on le
## voit toujours au bout de la rue, simplement de plus loin.
##
## ET A TROIS METRES PRES, C'EST LE CIEL QUI TRANCHE. Les deux paralleles d'un
## bourg finissent sur la MEME transversale : leurs deux bouts sont a la meme
## distance de l'entree, au metre pres, et rien ne les departagerait que
## l'ordre du tirage. On mesure alors, sur les seuls candidats a egalite, ce
## que les toits laissent voir de chacun depuis la route (_lm_sky) — et c'est
## ce qui met le totem de Saint-Elme du bon cote.
##
## Le site est memoise par nom de ville : il ne depend que du plan, qui est lui
## meme memoise, et la place d'un clocher ne se retire pas d'une visite a
## l'autre. Releve : 0,80 ms par bourg, paye a l'etape 3 du premier armement et
## jamais plus.
func _lm_seat(plan, key: String, id: String) -> Vector4:
	if _lm_site.has(id):
		return _lm_site[id]
	var half: Vector2 = (_lm[key] as Array)[6]
	var top: float = (_lm[key] as Array)[7]
	var eye := Vector2(-float(PAD) * STEP, 0.0)
	# Les places tenables, et la distance de chacune au premier metre dessine.
	# On les garde toutes : le ciel se mesure APRES, et seulement sur celles qui
	# se disputent la premiere place. Le mesurer sur les douze couterait treize
	# lignes de vue par candidat pour departager deux d'entre eux.
	var seats: Array[Vector4] = []
	var dists := PackedFloat32Array()
	var bd := 1.0e18
	for i in (plan.streets as Array).size():
		var st: Dictionary = plan.streets[i]
		if st["kind"] == "trunk":
			continue
		var cross: bool = st["kind"] == "cross"
		for e in 2:
			var sgn := 1.0 if e == 1 else -1.0
			var end_: float = float(st["b"]) if e == 1 else float(st["a"])
			# L'emprise du modele dans le plan. Sa PROFONDEUR (z) suit le cap,
			# sa LARGEUR (x) lui est perpendiculaire : c'est la face large du
			# repere qui regarde la rue, et c'est elle qu'on veut lire.
			var box := Vector2(half.x, half.y) if cross else Vector2(half.y, half.x)
			var seat := Vector2(float(st["s"]), end_ + sgn * (LM_CLEAR + half.y))
			var cap := Vector2(0.0, -sgn)
			if not cross:
				seat = Vector2(end_ + sgn * (LM_CLEAR + half.y), float(st["u"]))
				cap = Vector2(-sgn, 0.0)
			if _lm_room(plan, seat, box) < LM_KEEP:
				continue
			seat = _lm_pull(plan, seat, -cap, box)
			var d := seat.distance_to(eye)
			seats.append(Vector4(seat.x, seat.y, cap.x, cap.y))
			dists.append(d)
			bd = minf(bd, d)
	# LE PLUS TOT VU GAGNE, et a LM_TIE pres deux bouts de rue sont a la meme
	# distance : c'est alors le CIEL qui tranche. Ce n'est pas une subtilite
	# gratuite — les deux paralleles d'un bourg finissent sur la MEME
	# transversale, donc au metre pres a la meme distance de l'entree : sans
	# cette ligne, le cote se choisirait dans l'ordre du tirage. A Saint-Elme,
	# le cote nord ne montre RIEN du totem sur les treize points de vue de
	# l'approche ; le cote sud le montre sur deux.
	var best := Vector4.ZERO
	var bs := -1.0
	var bdd := 1.0e18
	for k in seats.size():
		if dists[k] > bd + LM_TIE:
			continue
		var sky: float = _lm_sky(plan, Vector2(seats[k].x, seats[k].y), top).x
		if sky > bs or (sky == bs and dists[k] < bdd):
			bs = sky
			bdd = dists[k]
			best = seats[k]
	_lm_site[id] = best
	return best


## Ramene le repere vers le panneau, sur l'axe de sa rue, et sans quitter la
## perspective qu'il ferme : le bout d'une parallele tombe sur la premiere
## transversale, qui peut etre a 94 m du panneau (Saint-Elme) — le brouillard
## n'en rendrait rien avant qu'on soit dedans.
##
## LE POINT SE RESOUT, IL NE SE CHERCHE PAS. Ou l'axe coupe-t-il le cercle de
## LM_REACH autour du panneau ? Une equation du second degre en une ligne, la
## ou la premiere version avancait de metre en metre et payait cent tests de
## degagement par candidat : les huit sites coutaient 15,6 ms, ils en coutent
## 1,2. On ne verifie la place qu'a l'arrivee — le repere ne GLISSE pas, il se
## POSE, et ce qui compte est l'endroit ou il finit. S'il est pris, on revient
## vers le bout de la rue deux metres a la fois : une facade fait six metres au
## moins (TownPlan.BLD_W), aucun pas ne peut l'enjamber.
func _lm_pull(plan, p: Vector2, dir: Vector2, box: Vector2) -> Vector2:
	if p.length() <= LM_REACH:
		return p
	var b := p.dot(dir)
	var disc := b * b - p.length_squared() + LM_REACH * LM_REACH
	if disc < 0.0 or b >= 0.0:
		return p        # cet axe ne s'approche jamais assez du panneau
	var t := -b - sqrt(disc)
	while t > 0.0:
		var q := p + dir * t
		if _lm_room(plan, q, box) >= LM_KEEP:
			return q
		t -= 2.0
	return p


## DE COMBIEN LE REPERE RESPIRE, a la place `p` et pour l'emprise `box` : la
## plus petite distance a une emprise de rue ou a un mur, dans le plan. C'est
## le seul juge de « pas au milieu d'une rue, pas dans une maison » — et il
## rend un NOMBRE, que le banc imprime au lieu de le supposer.
func _lm_room(plan, p: Vector2, box: Vector2) -> float:
	var room := 1.0e18
	for i in (plan.streets as Array).size():
		var st: Dictionary = plan.streets[i]
		var d: float
		if st["kind"] == "cross":
			d = _box_seg(p, box, Vector2(st["s"], st["a"]), Vector2(st["s"], st["b"]))
		else:
			d = _box_seg(p, box, Vector2(st["a"], st["u"]), Vector2(st["b"], st["u"]))
		room = minf(room, d - plan.edge_half(i))
	# Le filtre au cercle d'abord, et AU CARRE : sur soixante-huit maisons,
	# trois au plus passent, et la separation d'axes ne se paie que sur
	# celles-la.
	var reach := box.length() + LM_BLD_R + LM_KEEP
	var reach2 := reach * reach
	var nb := int(plan.bld_count())
	for k in nb:
		var o := k * 7
		var c := Vector2(plan.blds[o], plan.blds[o + 1])
		if c.distance_squared_to(p) > reach2:
			continue
		room = minf(room, _box_poly(p, box, TownPlan._corners(c,
			plan.blds[o + 2], plan.blds[o + 3], plan.blds[o + 5])))
	return room


## CE QUE LA ROUTE EN VOIT, mesure et pas suppose.
##
## Le bourg range ses maisons a dix metres de l'axe de la nationale et leur
## donne jusqu'a 9,4 m de haut ; le repere, lui, est au-dela, a vingt-six ou
## trente. La ligne de vue qui part de l'oeil du conducteur (1,45 m, la hauteur
## de la Civic) et qui passe le bord de ce rang de toits ne remonte que d'un
## facteur u_toit / u_repere : ce n'est pas la distance qui decide, c'est le
## RAPPORT DES DEUX DECALAGES, et il ne change pas quand on avance. Un repere
## plus haut que 1,45 + (9,4 - 1,45) x u_repere / 10 passe au-dessus de tout ;
## en dessous, il ne se montre que dans les trous du rang.
##
## On mesure donc, et on ne raisonne pas : treize points de vue le long de
## l'approche, de 120 m avant le panneau jusqu'au panneau, et pour chacun la
## hauteur que les toits mangent au droit du repere. Rend (part des points d'ou
## il depasse, hauteur moyenne qui depasse).
##
## CE QUE LE RELEVE DIT, ET QU'IL FAUT LIRE EN FACE : les quatre reperes de
## plus de 18 m (clocher, cheminee, silo, chateau d'eau) depassent les toits
## depuis LES TREIZE points de vue, de 6,6 a 9,4 m. Les quatre autres — porte
## 14,8 m, halle 13,4, totem 12,6, pont 12,05 — ne depassent que de 15 a 46 %
## des points : ils se montrent dans les TROUS du rang de maisons, pas
## au-dessus. Ce n'est pas la place qui est mauvaise, c'est l'arithmetique
## ci-dessus, et elle ne se corrige ni en les rapprochant (le rapport des
## decalages ne bouge pas) ni en les eloignant (il empire). Elle se corrigerait
## en les faisant plus hauts, et ce n'est pas ce fichier qui les modele.
func _lm_sky(plan, seat: Vector2, top: float) -> Vector2:
	var seen := 0
	var n := 0
	var over := 0.0
	var nb := int(plan.bld_count())
	var e := Vector2(-120.0, 0.0)
	while e.x <= 0.1:
		n += 1
		var d := seat - e
		var l2 := d.length_squared()
		var eaten := 0.0
		for k in nb:
			var o := k * 7
			var c := Vector2(plan.blds[o], plan.blds[o + 1])
			var t := (c - e).dot(d) / l2
			if t <= 0.05 or t >= 1.0:
				continue
			# La maison coupe-t-elle la ligne ? Son cercle circonscrit, donc un
			# peu large : on prefere annoncer un toit de trop qu'un toit de
			# moins.
			var r := 0.5 * sqrt(plan.blds[o + 2] * plan.blds[o + 2]
				+ plan.blds[o + 3] * plan.blds[o + 3])
			if (e + d * t).distance_to(c) > r:
				continue
			eaten = maxf(eaten, EYE_H + (float(plan.blds[o + 4]) - EYE_H) / t)
		if top > eaten:
			seen += 1
			over += top - eaten
		e.x += 10.0
	return Vector2(float(seen) / float(n), over / float(n))


## La distance d'un rectangle droit a un segment DROIT LUI AUSSI. Toute rue du
## plan est parallele ou perpendiculaire au tronc — c'est la garantie du repere
## curviligne (town_plan.gd) —, les deux sont donc alignes sur les memes axes
## et la distance s'ecrit sans un seul produit scalaire.
static func _box_seg(p: Vector2, box: Vector2, a: Vector2, b: Vector2) -> float:
	var dx := maxf(maxf(minf(a.x, b.x) - (p.x + box.x),
		(p.x - box.x) - maxf(a.x, b.x)), 0.0)
	var dy := maxf(maxf(minf(a.y, b.y) - (p.y + box.y),
		(p.y - box.y) - maxf(a.y, b.y)), 0.0)
	return sqrt(dx * dx + dy * dy)


## La separation d'un rectangle droit et d'une empreinte de maison, par les
## axes separateurs : le plus grand vide trouve sur les quatre normales des
## deux formes, zero si elles se traversent. C'est une MINORATION de la vraie
## distance — elle ne peut donc pas declarer libre une place qui ne l'est pas,
## et c'est le seul sens dans lequel se tromper coute cher.
static func _box_poly(p: Vector2, box: Vector2, co: PackedVector2Array) -> float:
	var gap := 0.0
	for ax: Vector2 in [Vector2(1.0, 0.0), Vector2(0.0, 1.0),
			(co[1] - co[0]).normalized(), (co[3] - co[0]).normalized()]:
		var c := p.dot(ax)
		var r := absf(ax.x) * box.x + absf(ax.y) * box.y
		var lo := 1.0e18
		var hi := -1.0e18
		for q in co:
			var t := q.dot(ax)
			lo = minf(lo, t)
			hi = maxf(hi, t)
		gap = maxf(gap, maxf(lo - (c + r), (c - r) - hi))
	return gap


# --------------------------------------------------------------------------
# Les mots dans le monde
# --------------------------------------------------------------------------

## Les deux panneaux et les plaques de rue — SEPT Label3D, pas un de plus. Une
## enseigne de commerce par facade, ce serait soixante Label3D, donc deux cent
## quarante appels de dessin sur les quatre vues, pour des mots qu'on ne lit
## pas. Les plaques se boulonnent sur les MATS, comme dans un vrai bourg : pas
## un poteau de plus a payer, et elles tombent la ou l'on regarde quand on
## cherche son chemin.
func _plates_and_signs() -> void:
	_sign_in.global_transform = _sign_pose(0.0)
	(_sign_in.get_node("Name") as Label3D).text = town_name.to_upper()
	_sign_in.visible = true
	_sign_out.global_transform = _sign_pose(float(CROSS) * STEP)
	(_sign_out.get_node("Name") as Label3D).text = town_name.to_upper()
	_sign_out.visible = true

	var done := {}
	var n := 0
	for k in (_plan.addrs as Array).size():
		if n >= _plates.size():
			break
		var i: int = ((_plan.addrs as Array)[k] as Dictionary)["street"]
		if done.has(i):
			continue
		done[i] = true
		var m := _plate_mast(i)
		if m < 0:
			continue
		var pl := _plates[n]
		n += 1
		# Face a la chaussee de SA rue : la plaque se lit en arrivant dedans,
		# pas en la depassant.
		var t: float = _plan.lamps[m * 3 + 1]
		var side: float = _plan.lamps[m * 3 + 2]
		var face := _toward_axis(i, t, side)
		var su: Vector2 = _plan.point(i, t, side * _plan.walk_mid(i))
		pl.text = String(_plan.streets[i]["name"])
		pl.global_position = _world(su.x, su.y) + Vector3(0.0, PLATE_Y, 0.0) \
			+ face * (MAST_R + 0.04)
		pl.global_basis = Basis(Vector3.UP.cross(face), Vector3.UP, face)
		pl.visible = true


## Le mat de plus petite abscisse absolue sur cette rue. Pour une transversale,
## c'est celui qui touche le tronc — la plaque se lit du volant, en passant.
## Pour une parallele, qui ne rencontre jamais le tronc, c'est celui de son
## premier carrefour, par ou l'on y entre.
func _plate_mast(i: int) -> int:
	var best := -1
	var bd := 1.0e18
	for k in mini(_plan.lamp_count(), _mast_pos.size()):
		if int(_plan.lamps[k * 3]) != i:
			continue
		var d: float = absf(_plan.lamps[k * 3 + 1])
		if d < bd:
			bd = d
			best = k
	return best


## Le panneau, a droite de la route, au-dela du trottoir, sa tole face au
## conducteur qui arrive. C'est la meme tole et la meme peinture que les
## panneaux de Y (road.gd les rebatit chez lui) : un bourg et une bifurcation
## se signalent du meme metal.
func _sign_pose(s: float) -> Transform3D:
	var r := _right_at(s)
	return Transform3D(Basis(r, Vector3.UP, -Vector3.UP.cross(r)), _world(s, SIGN_OFF))


# --------------------------------------------------------------------------
# Les trois lumieres
# --------------------------------------------------------------------------

func _place_lights() -> void:
	_light_mast.fill(-1)
	for li in LIGHTS:
		_take_mast(li)


## Les lampes SUIVENT. Une lampe dont le mat est passe a plus de 70 m DERRIERE
## est rendue, et se repose sur un mat a plus de 60 m — jamais plus pres, parce
## qu'a 60 m le brouillard a 0,030 ne laisse passer que 16 % et qu'un allumage
## y est invisible. Trois lampes pour vingt-trois mats : le joueur en croise
## trois allumees d'un bout a l'autre du bourg et ne voit jamais laquelle a
## bouge.
func _relight(delta: float) -> void:
	_relight_t += delta
	if _relight_t < RELIGHT_EVERY:
		return
	_relight_t = 0.0
	var car := _car()
	if car == null:
		return
	var cp: Vector3 = car.global_position
	var fwd: Vector3 = -car.global_transform.basis.z
	for li in LIGHTS:
		var m := _light_mast[li]
		if m >= 0:
			var d := _mast_pos[m] - cp
			if d.length() <= RELIGHT_DROP or d.dot(fwd) > 0.0:
				continue
		_light_mast[li] = -1
		_take_mast(li)


## Donne a la lampe `li` le mat libre le plus proche au-dela de RELIGHT_MIN.
## Le plus proche et pas le premier venu : c'est celui qu'on va croiser.
func _take_mast(li: int) -> void:
	var car := _car()
	var cp := global_position if car == null else car.global_position
	var best := -1
	var bd := 1.0e18
	for k in _mast_pos.size():
		if _light_mast.has(k):
			continue
		var d := _mast_pos[k].distance_to(cp)
		if d < RELIGHT_MIN or d >= bd:
			continue
		bd = d
		best = k
	_light_mast[li] = best
	_lights[li].visible = best >= 0 and not _dark
	if best >= 0:
		_lights[li].global_position = _mast_pos[best]


func _car() -> Node3D:
	var road := get_parent()
	if road == null:
		return null
	var t: Node3D = road.target
	return t if t != null and is_instance_valid(t) else null


# --------------------------------------------------------------------------
# Le GPS, et le compte
# --------------------------------------------------------------------------

## Les traits de la carte : des couples de points, en metres du monde. Le tronc
## et les paralleles suivent la courbure (un point tous les 8 m, la fleche y
## vaut un centimetre) ; une transversale est une droite et n'a besoin que de
## ses deux bouts.
func _build_gps() -> void:
	_gps.clear()
	for i in (_plan.streets as Array).size():
		var st: Dictionary = _plan.streets[i]
		var a: float = st["a"]
		var b: float = st["b"]
		if st["kind"] == "cross":
			var s: float = st["s"]
			_gps.append(_flat(_world(s, a)))
			_gps.append(_flat(_world(s, b)))
			continue
		var u: float = st["u"]
		var t := a
		while t < b:
			var t2 := minf(t + 8.0, b)
			_gps.append(_flat(_world(t, u)))
			_gps.append(_flat(_world(t2, u)))
			t = t2


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## LA VILLE DIT CE QU'ELLE COUTE, des qu'un banc tourne — silencieuse en partie
## normale. Les seuils du jalon (8 000 sommets, 6 500 triangles) ne valent que
## s'ils se comparent a des sommets COMPTES : le budget du plan a ete refait
## trois fois et s'est trompe de surface a chaque passe. Une ligne par ville
## armee, dans le journal de chaque banc, et le chiffre est sous les yeux de
## celui qui le lit.
func _print_cost() -> void:
	var names := ["asphalte", "accotement", "trottoir", "peinture", "bati", "emissif"]
	var vt := 0
	var tt := 0
	var line := ""
	for s in _mesh.get_surface_count():
		var av := _mesh.surface_get_arrays(s)
		var nv: int = (av[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var nt: int = (av[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		vt += nv
		tt += nt
		line += "%s %d/%d, " % [names[s] if s < names.size() else str(s), nv, nt]
	# Les fenetres allumees, COMPTEES et non deduites : c'est le seul chiffre de
	# la surface 6 que le plan n'a jamais pu mesurer, et il en faisait une
	# fourchette de 172 a 214 par bourg.
	var wins := 0
	var nb := int(_plan.bld_count())
	for k in nb:
		var m := int(_plan.blds[k * 7 + 6])
		while m != 0:
			wins += m & 1
			m >>= 1
	print("  [ville] %s — %d surface(s), %d sommets, %d triangles (%s%d maisons, %d mats, %d fenetres, %d portes)" % [
		town_name, _mesh.get_surface_count(), vt, tt, line,
		nb, _plan.lamp_count(), wins, (_plan.addrs as Array).size()])
	_print_landmark(vt)


## CE QUE LE REPERE COUTE ET OU IL EST, en clair sous chaque banc. Les deux
## chiffres qui comptent sont le degagement (il repond a « pas au milieu
## d'une rue, pas dans une maison ») et la distance au panneau (elle repond a
## « il se voit depuis la route avant le panneau »). Les sommets sont deja
## DANS le total de la ligne du dessus : c'est tout l'interet.
func _print_landmark(total: int) -> void:
	if _lm_key == "" or not _lm.has(_lm_key):
		print("  [repere] %s — AUCUN (modele absent ou aucune place tenable)" % town_name)
		return
	var d: Array = _lm[_lm_key]
	var site: Vector4 = _lm_site[town_name]
	var seat := Vector2(site.x, site.y)
	var box: Vector2 = d[6]
	if absf(site.w) < 0.5:
		box = Vector2(box.y, box.x)
	var nv: int = (d[0] as PackedVector3Array).size() + (d[3] as PackedVector3Array).size()
	var nt: int = ((d[2] as PackedInt32Array).size() + (d[5] as PackedInt32Array).size()) / 3
	print("  [repere] %s — %s a (s %.1f, u %.1f) haut de %.1f m, cap (%.0f, %.0f) : %d sommets et %d triangles DANS les surfaces 5 et 6, soit %.1f %% du bourg ; degagement %.2f m ; %.0f m du panneau, %.0f m du premier metre dessine" % [
		town_name, _lm_key, seat.x, seat.y, float(d[7]), site.z, site.w, nv, nt,
		100.0 * float(nv) / maxf(float(total), 1.0), _lm_room(_plan, seat, box),
		seat.length(), seat.distance_to(Vector2(-float(PAD) * STEP, 0.0))])


func _reset() -> void:
	_v.clear()
	_n.clear()
	_f.clear()


func _commit(mat: Material) -> void:
	Strip.commit(_v, _n, _f, mat, _mesh)


# --------------------------------------------------------------------------
# Le panneau
# --------------------------------------------------------------------------

## Un panneau au nom d'une ville : poteau, tole, texte. Reste une fabrique
## publique et statique — les deux panneaux du bourg s'en servent, et rien
## n'empeche la signalisation d'un Y d'y venir.
##
## radial_segments a 8, et c'est une correction : ce CylinderMesh n'y avait
## jamais touche, donc il tournait au defaut de Godot — SOIXANTE-QUATRE
## segments pour un poteau de 5 cm de rayon vu dans le brouillard, quand
## road.gd fait deja tourner ses troncs a 6.
static func make_sign(mat_metal: Material, mat_pole: Material) -> Node3D:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.045
	pcyl.bottom_radius = 0.055
	pcyl.height = 2.4
	pcyl.radial_segments = 8
	pole.mesh = pcyl
	pole.material_override = mat_pole
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position = Vector3(0.0, 1.2, 0.0)
	root.add_child(pole)

	var plate := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(2.1, 0.62, 0.04)
	plate.mesh = pbox
	plate.material_override = mat_metal
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.position = Vector3(0.0, 2.15, 0.0)
	root.add_child(plate)

	var label := Label3D.new()
	label.name = "Name"
	label.text = "?"
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(0.72, 0.74, 0.70)
	label.outline_size = 0
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = Vector3(0.0, 2.15, 0.035)
	root.add_child(label)
	return root
