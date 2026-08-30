# LE PLAN — LA TRAVERSANTE

*Une ville qu'on traverse, une carte qui est la ville.*
**Les references de ligne de ce document sont perimees et le resteront** — `road.gd`, `town.gd` et `main.gd` ont ete reecrits depuis qu'elles ont ete posees. La regle adoptee en §3 vaut pour tout le document : **on cite une FONCTION ou une CONSTANTE, jamais une ligne.** Les endroits ou le dossier de reconnaissance ou un juge se trompait restent signales par **[verifie]**.

**Ce plan a ete recale TROIS FOIS sur le code qui l'a suivi, et cette troisieme fois est la premiere ou le monde est en AVANCE sur le document.** Le J0, le J1, le J2 et le J3 sont ecrits et tournent : `scripts/strip.gd`, `scripts/town_plan.gd` et `scripts/town.gd` existent, la ville se batit, le masque creuse son trou, et `villetest` imprime **11/11**. Les deux recalages precedents corrigeaient des chiffres que le plan avait devines ; celui-ci corrige quatre **decisions** que le code a prises autrement — et mieux — que ce qui etait ecrit ici, et que le J3 a livrees sans que ce document les porte.

> **LES QUATRE ECARTS DU J3.** Chacun est documente a son point d'emploi dans `town.gd` ou dans `main.gd`, et aucun ne l'etait ici avant cette version.
> 1. **Aucun pave de carrefour.** Le plan en promettait huit, et son invariant `TOUT EST A L'ENDROIT` disait « sur les 8 paves de carrefour ». `town.gd` n'en pose **aucun**, et son argument est meilleur que la promesse. L'invariant livre, lui, couvre **tous** les triangles du bourg. §4.6, §6.
> 2. **Les appels de dessin ne se mesurent pas la ou le plan le demandait.** Il demandait « nationale nue, puis centre de la ville » ; le banc fait un A/B sur la seule visibilite du bourg. La mesure du plan aurait rendu une **baisse de mille appels**, et elle n'aurait pas mesure la ville. §6.
> 3. **Le demi-tour tient AU CARREFOUR**, et pas n'importe ou dans la ville. Le banc le fait sur un croisement, et son propre temoin dit ce qu'il en coute soixante metres plus loin. §6.
> 4. **Le cout de la ville est mesure, et l'instrument est trop grossier pour le seuil qu'on lui donne.** Le chiffre est bon, la ligne est fragile. §6, §7.

Le premier recalage a refait la densite, les rues, les carrefours, les fenetres, les mats et le budget de sommets sur des releves. **Le meme lot de corrections qui l'a produit a resserre l'abord de carrefour dans `town_plan.gd`, et fait bouger tous ces chiffres une seconde fois** : 562 batiments sont devenus **515**, le plafond geometrique 91 est devenu **77**, la surface 5 a encore maigri. Le recalage precedent avait relance `plantest` une fois (il est deterministe) et `rubantest` dix fois. **Cette version-ci a relance `plantest` une fois et `villetest` DIX FOIS**, pour la meme raison et une de plus : la courbure du ruban est retiree a chaque lancement, un vert unique ne prouve rien — et dix lancements ont aussi attrape un `.glb` qui changeait sous le banc (annexe B.4).

**Et deux fautes de fond, qui ne sont pas des chiffres :**
1. **La decision 4 etait fausse.** La traversee **armait** la monotonie de `sleep.gd` au lieu de l'eviter — mesure sur dix lancements : neuf silences du volant au-dessus des 10 s de `mono_after`, un de 21,1 s sur 21,1. Et elle ne pouvait pas faire autrement : **aucune courbure TENUE ne franchit le seuil de monotonie dans une ville**, c'est une inegalite, pas un reglage. `road.gd` y a repondu pendant la redaction, non pas en montant le plafond de courbure — la sortie que le plan proposait, et qui n'existe pas — mais en **alternant le sens** : un slalom. §1, §3.2.
2. **Le masque de dessin n'avait jamais tourne** — et il tourne depuis le J3. `road.gd` le conditionnait a une methode `draws_trunk()` que `town.gd` n'avait pas, et trois autres appels a la ville tombaient dans le meme vide. Les quatre existent, et `LE MASQUE EST OUVERT` les mesure : **0 triangle du ruban national dans la fenetre du bourg, contre 2 262 a 3 076 des qu'on referme le masque a la main sur la meme image**. La couture n'est plus une intention — §3.3.

La liste complete est en **annexe B**, qui distingue ce que le plan d'origine disait de faux (B.1), ce que **son premier recalage** disait de faux (B.2), les affirmations de fond qui n'etaient pas des chiffres (B.3) et, **neuve, ce que le J3 a dementi en le livrant (B.4)**. B.2 montrait qu'une correction faite sur des releves peut vieillir en une journee si le code bouge sous elle ; **B.4 montre l'inverse et c'est plus rare : un code qui a eu raison contre son plan, quatre fois, sans que le plan soit bete.** Quand le code et le plan se contredisent, **c'est le code qui a raison** : le plan n'est pas un contrat, c'est une carte, et une carte qui ment est pire que pas de carte.

---

## 1. LA DECISION, en cinq lignes

1. Une rue est **le meme ruban** que la nationale : `_strip_of` (road.gd:403-419) sait deja suivre une ligne quelconque, on l'extrait en fonction statique et une ville s'en sert.
2. Une ville est **un PLAN** (donnee pure, RefCounted, graine derivee du nom) plus **un maillage** (un seul `MeshInstance3D`, 6 surfaces) ; le plan existe avant le monde, le maillage n'existe qu'a la visite.
3. Le ruban de road.gd **ne se fige pas et ne se coupe pas** : `_pos` garde tous ses echantillons a travers la ville — seul le **dessin** est masque sur la traversee, et la ville dessine sa propre traversante **a partir des memes points**. Ecart de couture nul par identite, pas par arithmetique.
4. La traversante **suit la route** — courbure **bornee** pour que le quadrillage curviligne ne cisaille pas, et **alternee** pour que le volant travaille. Ce sont deux exigences differentes ; le plan n'en voyait qu'une, et se trompait sur l'autre.
5. Le GPS dessine **exactement les tableaux** dont on a extrude les triangles. La carte n'est pas un schema de la ville : c'est la ville.

> **LA DECISION 4 DISAIT AUTRE CHOSE, ET C'ETAIT FAUX.** Elle disait : « pas de 380 m de ligne droite, donc **pas de declenchement de la monotonie** de `sleep.gd` (mono_after 10 s, mono_factor 1.6 — sleep.gd:41 et 43) ». C'etait un des cinq arguments qui portent l'architecture, et `rubantest` l'a renverse.
>
> **Dix lancements, le meme banc, la courbure retiree a chaque fois** (`_rng.randomize()`, road.gd) — `LE VOLANT TRAVAILLE EN VILLE`, le plus long silence du volant sur une traversee conduite au volant a 12,5 m/s. **Ceci est l'etat D'AVANT la correction** ; ce qu'elle a donne est plus bas et en §3.2 :
>
> | Lancement | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
> |---|---|---|---|---|---|---|---|---|---|---|
> | silence maxi (s) | 17,5 | **7,7** | 16,9 | **21,1** | 16,8 | 12,6 | 17,1 | 11,7 | 11,3 | 16,0 |
> | volant maxi, `abs(steer)` | 0,054 | 0,071 | 0,059 | **0,034** | 0,073 | 0,065 | 0,061 | 0,070 | 0,059 | 0,053 |
> | cap tourne (deg) | 5,3 | 11,3 | 10,5 | 8,5 | 5,5 | 8,7 | 10,4 | 11,4 | 10,5 | 5,8 |
> | verdict | rouge | **vert** | rouge | rouge | rouge | rouge | rouge | rouge | rouge | rouge |
>
> La traversee dure 21,0 s. `sleep.gd:142-143` arme `mono_factor` a **10 s** de vitesse etale et de volant sous 0,04 (`sleep.gd:163`). **Neuf lancements sur dix laissent le volant silencieux plus de 10 s pendant la traversee** ; un (le 4) le laisse silencieux **21,1 s sur 21,1**, et n'atteint jamais 0,04 de toute la ville. **La traversee armait la monotonie**, elle ne la desarmait pas — l'exact contraire de ce que la decision 4 annoncait.
>
> **Ce n'est pas un reglage rate, c'est une inegalite**, et c'est ce qui rend la faute interessante. Pour tenir une courbure `k` a la vitesse `v` il faut `steer = v · k / (steer_rate · grip · stability)` ; a 12,5 m/s cela vaut `13,5 · k`. Et `k` est plafonne par le cisaillement, pas par le gout : la compression a 60 m de l'axe vaut `60 · k`, donc les 12 % que `LA TRAVERSEE NE SE REPLIE PAS` autorise plafonnent `k` a **0,0020** — soit **0,027 de volant, pour un seuil de 0,04**. **Aucune courbure TENUE ne franchira jamais le seuil de monotonie dans une ville.** Monter `TOWN_CURVE` ne pouvait donc pas marcher, et le plan proposait exactement ca.
>
> **CE QUI FRANCHIT 0,04, C'EST LE CHANGEMENT DE SENS.** Le volant ne travaille pas a tenir une courbe, il travaille a en **quitter** une. C'est la correction que `road.gd` a recue pendant la redaction de cette version : l'ancienne consigne **errait** — `randfn(0 ; 0,0010)`, une consigne neuve tous les 14 a 40 echantillons, 68 % du temps sous 0,0010, une portion plate allant jusqu'a 194 m d'affilee : *une ligne droite deguisee*. La nouvelle **alterne de bord a chaque tirage** et vise le plafond au lieu de le fuir (`TOWN_WEAVE`, `TOWN_WEAVE_FLOOR = 0,80`, `TOWN_SETTLE = 0,26`, dans `_simulate_town_path()`).
>
> Et le bourg y gagne au lieu d'y perdre, ce qui est le plus joli du raisonnement : une courbure de **meme signe** tenue sur 260 m bombe l'axe de `0,0015 × 260² / 2 =` **51 m** — la ville partirait de travers ; le slalom, lui, la garde dans un couloir de quelques dizaines de centimetres. **Le quadrillage est plus droit qu'avant dans son ensemble ; c'est localement, d'un bord a l'autre, qu'il travaille.**
>
> **Ce que la decision 4 achete, une fois corrigee :** un plafond `TOWN_CURVE` qui empeche le cisaillement (compression relevee **3,9 % a 9,0 %** pour un seuil de 12 %), **plus** une alternance qui rend le volant necessaire. Le plafond seul ne suffisait pas, et le plan croyait qu'il suffisait. *(Ce que le slalom donne au banc, releve au moment ou ces lignes sont ecrites, est en **§3.2** — et `road.gd` etait encore en cours de reglage : c'est `LE VOLANT TRAVAILLE EN VILLE`, seuil 8,0 s, qu'il faut relancer dix fois plutot que me croire.)*

**Pourquoi celle-la et pas une autre.** Le monde ne peut pas etre pre-pose (un atlas oblige a re-deriver les huit ancres, les caps de porte, les longueurs d'aretes de map.gd:40-51, et casse `maptest` au dixieme de metre et `faretest` au centime). Le ruban ne peut pas non plus etre gele (le geler casse `_rail`, main.gd:4975-4984, appele huit fois par `maptest` et `faretest`, et laisse `_place_props` sans site d'appel). La seule greffe qui ne touche a aucun contrat existant est celle-ci : **le ruban continue, la ville lui emprunte sa ligne, et on eteint le dessin la ou les deux se recouvrent.**

---

## 2. LES FICHIERS

### Nouveaux

| Fichier | Role en une ligne |
|---|---|
| `scripts/strip.gd` | La geometrie de ruban, sortie de road.gd en fonctions **statiques** : road et town y puisent le meme code. |
| `scripts/town_plan.gd` | Le PLAN d'une ville : donnee pure, en coordonnees curvilignes, a graine fixe. Aucun Node, aucun Mesh. |
| `scripts/gps_map.gd` | L'ecran GPS : un `Control` autonome qui remplace la classe interne `GpsMap` de phone_apps.gd:61-92. |

#### `scripts/strip.gd` (RefCounted, ~90 lignes)

```gdscript
## Un ruban de triangles le long d'une polyligne. Enroulement HORAIRE vu du
## dessus : Godot prend les faces horaires pour les faces avant, sinon la
## surface est purement et simplement invisible (le depot l'a paye deux fois).
class_name StripBuilder      # non : pas de class_name dans ce depot -> preload

static func ribbon(v: PackedVector3Array, n: PackedVector3Array,
        f: PackedInt32Array,
        pos: PackedVector3Array, right: PackedVector3Array,
        off_a: float, off_b: float, y: float, cols: int,
        skip_from := -1, skip_to := -1) -> void

static func quads(v, n, f, corners: PackedVector3Array, y: float) -> void
static func commit(v, n, f, mat: Material, mesh: ArrayMesh) -> void
```

`ribbon()` est **mot pour mot** le corps de road.gd:403-419, plus deux lignes :
`if i >= skip_from and i < skip_to: continue` dans la boucle d'indices (les **sommets** restent emis, seuls les **quads** sautent : aucune renumerotation).
road.gd:397-419 et road.gd:441-451 deviennent des appels a `strip.gd`. Le comportement du brin mort (road.gd:358-373) est inchange : il passe `skip_from = -1`.

#### `scripts/town_plan.gd` (RefCounted, ~240 lignes)

Le plan vit en **coordonnees curvilignes** `(s, u)` : `s` = metres le long de la traversante depuis le panneau (positif vers l'avant), `u` = decalage lateral (positif a droite). C'est ce qui permet a la traversante de **courber** sans que le quadrillage se cisaille.

```gdscript
const CROSS      := 130     # echantillons de traversee = 260 m, panneau -> sortie
const PAD        := 20      # echantillons dessines avant/apres = 40 m
const TRUNK_HALF := 3.4     # = RoadScript.ROAD_HALF, la couture l'exige
const SHOULDER   := 2.4     # = RoadScript.SHOULDER
const WALK_TRUNK := 2.2     # trottoir en plus, de 5.8 a 8.0 m
const STREET_HALF:= 2.6     # 5,2 m de chaussee : deux voitures se croisent au pas
const WALK       := 1.6     # trottoir de rue
const SETBACK    := 6.0     # facade / axe de rue  (3,4 m de trottoir libre)
const SETBACK_TR := 10.0    # facade / axe de la traversante
const CORNER_FREE:= 12.0    # aucun batiment a moins de ca d'un carrefour
const LAMP_EVERY := 30.0    # m de rue entre deux lampadaires
const BLD_PITCH  := Vector2(9.0, 14.0)    # entraxe des facades
const BLD_W      := Vector2(6.0, 13.0)
const BLD_D      := Vector2(8.0, 12.0)
const BLD_H      := Vector2(4.6, 9.4)
const WIN_P      := 0.30    # une travee-etage sur trois est allumee
const BAY_LEN    := 16.0    # baie d'adresse : 16 x 4,5 m le long du trottoir
const BAY_X      := Vector2(0.5, 5.0)

var id: String
var streets: Array            # {kind:"trunk"/"cross"/"rail", s:float, u:float,
                              #  a:float, b:float, half:float, walk:float, name:String}
var junctions: Array          # {street_a:int, street_b:int, s:float, u:float}
var lamps  := PackedFloat32Array()   # triplets (street, t, side)
var blds   := PackedFloat32Array()   # 7-uplets (s, u, w, d, h, yaw, wins)
var addrs  : Array            # {name:String, street:int, t:float, side:float, amen:String}
var bounds : Rect2            # en (s, u)

static func of(id: String) -> RefCounted        # memoise, 8 villes, jamais liberees
func nearest(su: Vector2) -> Dictionary          # {street, dist, t} — grille de 20 m
func route(su_from: Vector2, su_to: Vector2) -> PackedInt32Array   # Dijkstra, <= 12 noeuds
func cross_len() -> float                        # = CROSS * STEP
```

Graine : `map.gd` gagne `"seed"` par ville (`TOWNS["Corbeny"]["seed"] = 40213`) et `static func seed_of(id) -> int`. Une ville laide se re-tire en changeant un entier ; deux parties ont **la meme** Corbeny.

#### `scripts/gps_map.gd` (Control, ~280 lignes)

```gdscript
var zoom := 1                     # 0..2
const ZOOM_M := [220.0, 90.0, 35.0]     # metres sur les 196 px de large
var north_up := false             # bascule au tap sur la carte
func set_town(town) -> void       # (re)construit le maillage de rues, en metres
func zoom_step(dir: int) -> bool  # false en butee -> phone_apps tourne la page
func _draw() -> void
func _gui_input(e: InputEvent) -> void
```

### Modifies

| Fichier | Ce qu'on y touche |
|---|---|
| `scripts/road.gd` | tangente d'avance, masque de dessin, courbure bornee en ville, chemin pre-calcule de la traversee, `town_left`, `off_road_dist`, `in_town`, `trail`, `_place_props` filtre par categorie, `suspend_town`. |
| `scripts/town.gd` | reecrit : le maillage a 6 surfaces depuis le plan, 3 lumieres mobiles, panneaux, plaques, adresses. `make_sign` (town.gd:116-147) reste **tel quel**. |
| `scripts/map.gd` | + `"seed"` par ville, + `seed_of()`, + un index d'adjacence statique `_ADJ` (`neighbors()` passe de O(aretes) a O(1) : `path()` est appele **huit fois par offre**, taxi.gd:205). |
| `scripts/taxi.gd` | `off_road_dist` publique, seuils contextuels, grace de calage, adresses a la place de la boite `ZONE_*`. |
| `scripts/main.gd` | navigation (le Y repousse, la programmation depuis `nav["start_g"]`), garde du cauchemar, cinq bancs neufs. |
| `scripts/phone.gd` | `_apps.tick(delta)` dans la branche `viewing` (phone.gd:212-215). |
| `scripts/phone_apps.gd` | la classe interne `GpsMap` s'en va, `clip_contents`, `scroll()` zoome sur la page gps, `tick()`. |
| `scripts/sleep.gd` | une entree `"cafe"` dans `drink_boost` (sleep.gd:235-245). |
| `README.md` | une section "La traversante", dans le ton. |

---

## 3. LE RACCORD AU RUBAN

> **LES NUMEROS DE LIGNE DE CETTE SECTION SONT PERIMES, ET C'EST STRUCTUREL.** Le titre disait « numeros de ligne d'aujourd'hui » : ils l'etaient le jour ou la section a ete ecrite, **avant** que le J2 ne soit livre. Depuis, `scripts/road.gd` a gagne `strip.gd`, le chemin pre-calcule, le masque, la trace et le slalom — le fichier a grossi de plusieurs centaines de lignes, et il a bouge **trois fois pendant la redaction de cette version-ci**. Toutes les references `road.gd:NNN` ci-dessous sont a lire comme des **reperes de l'intention d'origine**, pas comme des adresses.
>
> C'est la troisieme fois que ce document se fait prendre par ses propres numeros de ligne (annexe B). La regle qu'on en tire, et qu'on applique a partir d'ici : **on cite une FONCTION ou une CONSTANTE, jamais une ligne, sauf a dater la citation.** Un `grep` sur un nom de symbole survit a une refonte ; un numero de ligne ne survit pas a une insertion.

### 3.1 La tangente d'avance — `_append_sample()`

Aujourd'hui :
```gdscript
196:  var forward := -target.global_transform.basis.z
200:      if (target.global_position - _pos[0]).dot(forward) < BEHIND * STEP:
```
Le test projette sur le **nez de la voiture** : rouler 100 m en travers fait defiler des echantillons de route sans avoir avance dessus. Le plan chiffrait la casse a `(100−24)/2 =` **38 echantillons** ; `rubantest` la mesure, sur exactement ce trajet, a **261** — sept fois plus, parce que le calcul supposait un ruban immobile alors que chaque echantillon avale fait avancer la tete de fenetre et re-projette le suivant. On projette sur la **tangente du ruban** :
```gdscript
var tang := _pos[1] - _pos[0]; tang.y = 0.0; tang = tang.normalized()
```
`forward` (le nez de la voiture) reste utilise tel quel pour l'extinction de la police (road.gd:212) et de la ville (road.gd:238) — deux usages differents, deux vecteurs differents. Consequence en cascade, gratuite : `nav_progress()` (main.gd:4084-4091) redevient juste **sans etre touchee**, et une rue laterale ne fait plus rien defiler.

### 3.2 Le chemin pre-calcule de la traversee — `_simulate_town_path()`

C'est le point de greffe unique. Aujourd'hui :
```gdscript
313:  if _town_g >= 0 and g == _town_g and town != null:
314:      var r := _right[_pos.size() - 1]
315:      town.arm(Transform3D(Basis(r, Vector3.UP, -Vector3.UP.cross(r)),
316:          _pos[_pos.size() - 1]), _town_id)
```
Probleme : la ville a besoin de la ligne mediane **jusqu'a g_in + CROSS + PAD**, et ces echantillons n'existent pas encore (la tete de fenetre EST `g_in`). Reponse : a l'armement, on **simule** la suite depuis `_head` et `_curve`, avec un RNG seme par `(nom de ville, g_in)`, et on la **range** ; `_append_sample` la **consomme** ensuite au lieu de tirer au sort.

```gdscript
# a l'armement (road.gd:313), avant town.arm :
_town_in  = g - PAD_S            # PAD_S = TownPlan.PAD  = 20
_town_out = g + TownPlan.CROSS   # 130
_town_heads = _simulate_town_path(g)     # CROSS + PAD transforms, courbure bornee
# dans _append_sample, tout en haut, a la place de _advance_curve() :
if not _town_heads.is_empty() and g > _town_in and g <= _town_out + PAD_S:
    _head  = _town_heads.pop_front()     # identite exacte avec ce que la ville a bati
    _curve = _town_curve_at(g)
else:
    _advance_curve()
```
`_simulate_town_path` reproduit **exactement** road.gd:318-321 (`_head.origin += forward * STEP` puis `rotated_local(UP, _curve * STEP)`) avec une courbure bornee :
```gdscript
const TOWN_CURVE := 0.0015      # rad/m -> rayon >= 667 m
```
Pourquoi 0.0015 et pas 0 : a 60 m de l'axe, un rayon de 667 m comprime le cote interieur de 9 % — invisible ; a `MAX_CURVE = 0.009` (rayon 111 m) il le comprimerait de 54 %, le quadrillage se replierait sur lui-meme. **C'est la seule chose que le PLAFOND achete**, et le plan lui en attribuait une seconde qu'il ne pouvait pas rendre.

> **CE QUE CE PARAGRAPHE PROMETTAIT EN PLUS, ET QUI ETAIT FAUX.** Il ajoutait : « zero dur donnerait 342 m de regle plate, plus les 150 echantillons droits que le Y impose deja : ~610 m de rectitude, soit largement de quoi armer `mono_after` et `mono_factor` huit fois par nuit » — sous-entendu : **0,0015 l'evite**. Non : avec 0,0015, **la traversee armait la monotonie** (§1 : dix lancements, neuf silences du volant au-dessus des 10 s de `mono_after`, un de 21,1 s sur 21,1, **1 vert sur 10**).
>
> **L'inegalite qui ferme la porte, et qu'il faut poser une fois pour toutes.** Le volant qu'il faut pour TENIR une courbure `k` a 12,5 m/s vaut `13,5 · k`. La compression a 60 m de l'axe vaut `60 · k`, donc le seuil de 12 % de `LA TRAVERSEE NE SE REPLIE PAS` plafonne `k` a **0,0020**, soit **0,027 de volant** contre les **0,04** de `sleep.gd`. **Le regime permanent ne franchira jamais le seuil de monotonie dans une ville, a aucune valeur de `TOWN_CURVE`.** Ce n'est pas un reglage : c'est une inegalite. Monter le plafond etait la seule sortie que le plan envisageait, et elle n'existe pas.
>
> **Ce qui franchit 0,04, c'est le CHANGEMENT DE SENS** — et c'est la correction que `road.gd` a recue. L'ancienne consigne **errait** (`randfn(0 ; 0,0010)`, une consigne neuve tous les 14 a 40 echantillons) : 68 % du temps sous 0,0010, le clamp n'attrapant que 13 % des tirages, et une portion plate allant jusqu'a **194 m d'affilee**. La nouvelle **slalome** : la consigne alterne de bord a chaque tirage et vise `TOWN_CURVE × [0,80 ; 1,0]`, lissee a `TOWN_SETTLE = 0,26` — le hasard ne decide plus du **sens**, seulement de la duree et de la force du bord.
>
> **Ce que le slalom change, releve au banc** *(les deux colonnes sont des `rubantest` du meme jour, sur les 151 echantillons dessines)* :
>
> | | Consigne qui erre *(avant)* | Slalom *(apres)* |
> |---|---|---|
> | portion la plus plate | **28 a 178 m** | **6 m** |
> | cap tourne sur la traversee | 5,3 a 11,4 deg | **14,7 a 18,2 deg** |
> | courbure maxi | 0,00067 a 0,00143 | **0,00146 a 0,00154** (le slalom vit **au** plafond) |
> | compression a 60 m *(seuil 12 %)* | 3,9 a 8,6 % | **8,8 a 9,0 %** |
> | volant maxi *(seuil 0,04)* | 0,034 a 0,073 | **0,055 a 0,084** |
> | silence maxi *(seuil 8,0 s)* | **7,7 a 21,1 s** | **3,9 a 10,6 s** |
> | `LE VOLANT TRAVAILLE EN VILLE` | **1 vert / 10** | **vert dans la plupart des lancements releves** — avec un rouge apres chaque changement de `TOWN_WEAVE` |
>
> **Et le bourg y gagne**, ce qui n'etait pas acquis : une courbure de **meme signe** tenue sur 260 m bombe l'axe de `0,0015 × 260² / 2 =` **51 m** — la ville partirait de travers —, quand le slalom la garde dans un couloir de quelques dizaines de centimetres. Le quadrillage est **plus droit qu'avant dans son ensemble** ; c'est localement, d'un bord a l'autre, qu'il travaille. La compression, elle, est montee de 8,6 a 9,0 % : on a depense la marge qui restait sous les 12 %, et il n'en reste plus beaucoup.
>
> **AVERTISSEMENT DE DATE — et il est le vrai contenu de ce paragraphe.** `scripts/road.gd` etait **en cours de reglage** pendant la redaction de cette section : le fichier a change quatre fois, et `TOWN_WEAVE`, la demi-periode du slalom, deux fois sous les mesures ci-dessus (24-42 puis 16-26 echantillons) — le commentaire du fichier en annoncait encore une troisieme (9-15) qu'aucune constante ne portait. Les six premieres lignes du tableau sont stables d'un reglage a l'autre ; **la derniere ne l'est pas** : un silence de 10,6 s, donc un rouge, a ete releve apres un des changements.
> **Ne recopiez pas la derniere ligne. Relancez `rubantest` dix fois et comptez.** C'est exactement la faute que l'annexe B.2 raconte, et elle etait en train de se rejouer sur ce paragraphe pendant qu'il s'ecrivait — la seule difference est qu'on la voit venir cette fois, et qu'on l'ecrit au lieu de la subir.
>
> **Ce qui reste vrai quoi qu'il arrive au reglage**, et c'est le vrai enseignement : la ville **ne peut pas** desarmer la monotonie par la courbure qu'elle **tient** ; elle ne peut le faire que par celle qu'elle **quitte**. Et le remede de fond est ailleurs, la ou le plan l'ecrivait deja sans savoir qu'il en aurait besoin : **le cafe de nuit (§4.5)**. La ville prend de la vigilance — par la lenteur *et* par la monotonie —, le cafe en rend.

La regle de courbure existante road.gd:280-284 (`absi(g - _town_g) < 20`, lissage a 0.4) est **conservee pour l'approche** et complete par une regle dure sur la traversee, **calee sur `_town_out`, pas sur `_town_g`** — parce que road.gd:233-235 rend `_town_g = -1` des l'emission de `town_reached`, bien avant la fin de la traversee.

### 3.3 Le masque de dessin — `_rebuild()`, `strip.ribbon()`, `_dashes()`

`_rebuild()` calcule une fois par reconstruction :
```gdscript
var sf := -1 ; var st := -1
if _town_ready and _town_in >= 0:
    sf = maxi(_town_in  - _index0, 0)
    st = mini(_town_out + PAD_S - _index0, _pos.size())
```
et le passe a `strip.ribbon(...)` et `_dashes()`. Le quad `(sf-1 -> sf)` est emis, le quad `(sf -> sf+1)` ne l'est pas : la couture tombe **sur le sommet** `_pos[_town_in]`, qui est aussi le premier sommet de la traversante de la ville. Ecart nul par identite.

`_town_ready` n'est vrai qu'une fois le maillage de la ville **acheve** (construction etalee sur quatre images, §4.6) : jamais de trou de quatre images.

> **CE MASQUE A TOURNE AU J3, ET IL SE MESURE MAINTENANT SUR DES TRIANGLES.** Tant que le J2 etait seul, il n'avait creuse **ni une image, ni un quad** : `_rebuild()` conditionne le trou a `town.draws_trunk()`, et `scripts/town.gd` n'avait pas cette methode. Le code n'a pas bouge ; c'est la ville qui repond.
>
> ```gdscript
> _town_ready = _town_in >= 0 and town != null and town.visible \
>     and town.has_method("draws_trunk") and town.draws_trunk()
> ```
>
> **Les quatre appels que road.gd faisait dans le vide sont branches**, et c'est ce que le J3 a livre avant le maillage, avant les lumieres, avant les captures. `draws_trunk()` ne dit oui qu'une fois les **six** surfaces versees (`_built and visible`) : un trou de quatre images serait pire que la couture qu'il repare.
>
> | Ou dans road.gd | Ce qu'il demande | Ce que town.gd repond aujourd'hui | Ce qui le mesure |
> |---|---|---|---|
> | `_rebuild()` | `draws_trunk()` | `_built and visible` | `LE MASQUE EST OUVERT` |
> | `_town_contains()` | `contains(p)` | l'enveloppe `bounds` du plan, elargie, lue en (s, u) | `LE DEMI-TOUR TIENT`, `LA VILLE NE S'ETEINT PAS DEDANS` |
> | `off_road_dist()` | `street_dist(p)` | `plan.nearest()`, le point porte dans le repere du bourg | `LE DEMI-TOUR TIENT` et son temoin |
> | `suspend_town()` | `set_dark(true)` | materiau emissif echange, lampes eteintes, panneaux ternes | **rien encore** — §3.10 |
>
> *(Les quatre sont designees par leur **fonction**, pas par leur ligne : c'est la regle adoptee en tete de cette section, et elle a survecu a la refonte de `town.gd`.)*
>
> **Ce que `LE MASQUE EST OUVERT` releve** : **0 triangle** du ruban national dans la fenetre que le bourg dessine, sur les quatre villes que le banc ouvre — et **2 262 a 3 076** dans la MEME fenetre, a la MEME image, des que `road._town_in` est ramene a −1 a la main. Meme ruban, meme fenetre, meme code de comptage : c'est exactement ce que le masque supprime.
>
> **Et la couture est passee de la donnee au DESSIN.** `LA COUTURE EST NETTE` (rubantest, 0,0000 m dix fois sur dix) compare les 150 transforms pre-calculees a l'armement a celles que `_append_sample` repose ensuite : une identite de **donnee**, vraie, et qui ne regarde **aucun triangle**. `villetest` compare desormais **le dernier sommet d'asphalte que road.gd emet avant le trou au premier que la ville pose** : **0,000000 m** sur 12 sommets, pour un seuil de 0,001. Son temoin dit que la mesure n'est pas une constante — decaler de 5 cm le seul echantillon `_pos[_town_in]` et re-trianguler la fait monter a **0,0498 m**, et la remettre la ramene a zero.

### 3.4 La propriete des bornes — **PAS dans `program_town` (road.gd:573-577)**

C'est la faute qui aurait tue la moitie de la carte. `main.gd:4045-4051` appelle `road.program_town(...)` pour la ville **SUIVANTE** au moment exact ou le panneau de la ville courante est franchi **[verifie : main.gd:4046-4051, branche `outs.size() == 1`, qui concerne Saint-Elme, Vieux-Bourg, Les Essarts et Brumaire — les quatre villes de degre 2]**. Un jeu unique de champs pose par `program_town` sauterait donc de ~475 echantillons a l'echantillon 0 des 130 de la traversee : le ruban national se re-triangulerait en travers de la ville, coplanaire avec ses rues au meme `Y_ROAD = 0.02`.

Donc : `_town_in` / `_town_out` / `_town_heads` sont poses **a l'armement** (road.gd:313) et effaces **la ou road.gd:238-239 appelle `town.sleep()`**. `program_town` ne touche que `_town_g` et `_town_id`, exactement comme aujourd'hui. C'est correct parce que `_rebuild()` re-triangule **toute** la fenetre a chaque avance : au moment de l'armement, `_town_in` est a l'index local 129, soit 258 m devant la voiture — jamais vu non masque.

### 3.5 L'extinction — **road.gd:237-239**

Aujourd'hui : produit scalaire avec le cap **de la voiture**, seuil 130 m. Ca n'a plus de sens des qu'on tourne dans une rue. Remplace par :
```gdscript
if town.visible and head_index() > _town_out + 65 and not town.contains(target.global_position):
    town.sleep() ; _town_in = -1 ; _town_out = -1 ; town_left.emit(town.town_name)
```
Les deux conditions : la premiere dit qu'on est sorti par le bout (130 m apres la sortie), la seconde interdit d'eteindre une ville dans laquelle on a fait demi-tour. C'est le piege deja paye et documente a road.gd:565-572 (« le pop le plus voyant du jeu »).

**Arme au J3, et mesure.** La seconde condition passe par `_town_contains()`, qui delegue a `town.contains()` : l'enveloppe `bounds` du plan, elargie, lue en coordonnees curvilignes — et pas un produit scalaire avec le cap de la voiture, qui disait la ville depassee des qu'on roulait nez au nord et ville a l'ouest. `villetest` la prend au mot : sur le demi-tour et le retour au panneau, **`contains()` a repondu vrai a CHACUNE des images**, et `LA VILLE NE S'ETEINT PAS DEDANS` compte **0 image eteinte** sur la traversee, le demi-tour et le retour. On peut faire demi-tour dans un bourg sans l'effacer.

### 3.6 `_place_props` — filtrer par CATEGORIE, jamais sortir de la fonction — **road.gd:457-531**

Un `return` en tete eteindrait le **portail du cauchemar** (road.gd:525-529, le dernier bloc de la fonction), c'est-a-dire la seule sortie du cauchemar. On pose donc :
```gdscript
var quiet := _town_in >= 0 and g >= _town_in - 20 and g <= _town_out + PAD_S + 20
```
et on garde `quiet` en tete des blocs **arbres** (road.gd:458-470), **poteaux** (472-482), **police** (485-495), **geant** (498-508), **etrangleur** (511-520). Le bloc **portail** (525-529) n'est jamais filtre.

Corrige au passage un defaut existant : les arbres tombent entre 6.4 et 20.4 m de l'axe (road.gd:462) et les maisons de town.gd sont a x = -11 a -13.5 sur 7 a 10 m de large (town.gd:88-111) — **les arbres poussent deja dans les maisons**, le brouillard le cache.

### 3.7 L'API publique neuve de road.gd

```gdscript
signal town_left(id: String)
func in_town() -> bool                       # _town_in >= 0 and head_index() <= _town_out
func town_span() -> Vector2i                 # (_town_in, _town_out), (-1,-1) si aucune
func town_exit_g() -> int                    # _town_out, -1 si aucune
func off_road_dist(p: Vector3) -> float      # min(_closest_dist(_pos,p), town.street_dist(p))
func trail() -> PackedVector2Array           # la ligne mediane deja passee, un point sur 4
func suspend_town() -> void                  # le cauchemar : annule la ville PROMISE
```
`off_road_dist` remplace l'acces aux membres prives depuis taxi.gd:409 (`road._closest_dist(road._pos, ...)`), que GDScript ne signalerait jamais s'il cassait. **Les deux moities sont faites.** Le J2 avait branche la porte : `LE JUGE NE LIT PLUS LES PRIVES` est vert dix fois sur dix, `grep "road\._"` sur taxi.gd ne rend rien. Le J3 a mis les rues derriere : `town.street_dist()` existe et porte le point dans le repere du bourg pour le poser a la grille de 20 m du plan. La mesure n'est plus une constante, et le temoin de `LE DEMI-TOUR TIENT` le montre sur deux points distants de 7,8 m : **9,00 m a 9 m de l'axe du tronc entre deux transversales, 1,20 m pour le meme point ramene sur la voie**. Voir §4.9 — ce qui reste au J4, c'est le juge de course lui-meme, pas la distance qu'il lit.

`trail()` : avant `_pos.remove_at(0)`, on pousse `Vector2(_pos[0].x, _pos[0].z)` un echantillon sur `TRAIL_EVERY = 4` (un point tous les 8 m) dans un tampon circulaire `TRAIL_MAX = 4096`. **« Un sur quatre » se COMPTE, il ne se lit pas dans `_index0`** — le plan ne le disait pas, et c'est ce qui a coute la ligne `LA TRACE SE RECOUD AU Y` : `_swap_to_branch` repose `_index0` sur `_fork_g + 1 + start`, l'index global continue, et le saut enjambait le multiple de 4 une fois sur deux. Un compteur d'echantillons **pousses** ne connait pas les index et ne peut pas les rater (§6, J2). 8 octets par point = 1 Ko/km ; une nuit entiere (~29 km) = 32 Ko. **C'est la ligne mediane deja parcourue, pas la trajectoire de la voiture** — a nommer ainsi dans le commentaire et dans le README, et a ne pas dessiner comme une trace de pneus.

### 3.8 La navigation — **main.gd:4031-4082**

- `_on_town_reached` (4037-4062) : inchange dans son principe. **Une correction** : dans la branche a deux sorties (4056-4062), le Y passe de `road.head_index() + 120/STEP` a
  ```gdscript
  road.program_fork(nav["start_g"] + TownPlan.CROSS + TownPlan.PAD + 60, outs[0], outs[1], main_side)
  ```
  soit panneau + 210 echantillons = **420 m**, c'est-a-dire 120 m apres la sortie de ville. On **n'utilise pas `_town_g`** : road.gd:234-235 le remet a -1 **avant** d'emettre `town_reached`. `nav["start_g"]` est pose deux lignes plus haut (4060) et vaut l'index du panneau.
  Marge verifiee : le panneau du Y nait `FORK_SIGN_AT = 45` echantillons avant, soit panneau + 165 ; la fin du masque est a panneau + 150. **15 echantillons = 30 m de marge** — le banc l'imprime.
- `_on_fork_committed` (4065-4072) : aujourd'hui `road.head_index() + (edge_length - 120)`. Le verdict tombe ~26 echantillons apres la fourche (`FORK_TO`, road.gd:29), donc la derive metrique par bifurcation vaut deja +26 m et passerait a +52 m avec le Y repousse. On la **supprime** :
  ```gdscript
  var g := nav["start_g"] + int(MapScript.edge_length(nav["at"], id) / RoadScript.STEP)
  road.program_town(maxi(g, road.head_index() + 20), id)
  ```
  Zero derive, et c'est la meme expression que la branche a une sortie. `nav["start_g"]` doit survivre a `_swap_to_branch` (road.gd:641 remet `_index0 = _fork_g + 1 + start`) : c'est le cas, la metrique continue a un pas pres.

  > **RELEVE — ce que la derive coute aujourd'hui, avant la correction.** La proposition ci-dessus n'est pas faite ; elle a ete ecrite en estimant la derive a +26 m par bifurcation, +52 m avec le Y repousse. **La mesure est bien pire, et le document doit en porter la trace :**
  >
  > | Arete | Annonce par `map.gd` | Roule panneau a panneau | Derive |
  > |---|---|---|---|
  > | Corbeny > Malassis (map.gd:50) | 1 100 m | **1 414 m** | **+314 m** |
  > | Malassis > Peyrelade (map.gd:54) | 1 350 m | **1 622 m** | **+272 m** |
  >
  > Soit **+29 % et +20 %** — d'un cinquieme a pres d'un tiers d'arete de rab, offert par le calcul, sur des longueurs que `faretest` facture au centime et que le GPS annonce en toutes lettres (« Vers Corbeny — 1 048 m »). L'estimation a +52 m se trompait d'un facteur six.
  >
  > Pourquoi c'est plus que +52 : la derive ne vient pas seulement des ~26 echantillons qui separent la fourche de son verdict (`FORK_TO`, road.gd:29). `_on_fork_committed` (main.gd:4067-4073) reprogramme la ville a `road.head_index() + (edge_length − FORK_AFTER_TOWN_M)`, ou `head_index()` est deja au verdict — **et `FORK_AFTER_TOWN_M = 120,0` (main.gd:4030-4031) est un nombre de METRES compte depuis le panneau, pas depuis le point ou l'on a reellement bifurque.** Chaque terme approxime dans le meme sens, et l'erreur ne se compense jamais : elle s'additionne a chaque Y.
  >
  > **Ce que le banc mesure aujourd'hui, et ce qui manque.** `maptest` imprime `LA VILLE TOMBE JUSTE : Corbeny apres 952 m, la carte dit 950` — **+2 m, mais sur la PREMIERE arete, celle qui n'a pas de Y**. C'est exactement l'angle mort qui a laisse passer les +314 m. D'ou l'invariant `LA METRIQUE NE DERIVE PLUS` du J4, qui exige **trois aretes consecutives dont deux avec Y**.
  >
  > *(Ce releve est ecrit ici pour memoire du prix paye.)*
  >
  > **ET LA CORRECTION EST FAITE — dans `main.gd`, avant le J3, et pas dans ce plan.** `_on_fork_committed` calcule desormais `nav["start_g"] + edge_length / STEP`, exactement la proposition ci-dessus, et son commentaire porte le releve de l'ancienne formule remise sur une copie jetable : **Corbeny > Malassis 1 100 annonces / 1 402 roules (+302 m)**, **Malassis > Peyrelade 1 350 / 1 624 (+274 m)** — les memes ordres de grandeur que les +314 et +272 releves ici, la granularite de l'image bougeant le premier chiffre d'une douzaine de metres. Apres correction, prise **par le brin mort**, la derive tient entre **+0 et +8 m sur onze lancements**. `maptest` porte la ligne `LA METRIQUE NE DERIVE PLUS` (seuil 30 m), que ce plan rangeait au J4 : **elle est livree en avance.**
  >
  > **Ce qui n'est PAS fait, en revanche, c'est le Y repousse.** `_on_town_reached` demande toujours la fourche a `head_index() + FORK_AFTER_TOWN_M / STEP` = panneau + 120 m, et non a `nav["start_g"] + CROSS + PAD + 60` = panneau + 420 m. La demande est d'ailleurs **morte, toujours** : `program_fork` la plafonne au premier echantillon a naitre plus les 90 m du panneau du Y — releve au banc, **demande 551, obtenu 674**, soit ~366 m devant la voiture au lieu des 120 demandes. Le Y ne tombe donc pas ou le plan le voulait, et il n'y tombe pas non plus ou `main.gd` le demande : il tombe ou road.gd peut encore le poser. `LE Y TOMBE APRES LA SORTIE` (J4) reste a ecrire, et **la seule position vraie se lit dans `road.fork_index()`**, jamais dans la demande.
- **Le contrat metrique est inchange** : une arete se mesure **de panneau a panneau**, la traversee de 260 m est **dedans**. Sur l'arete la plus courte (950 m = 475 echantillons), il reste 325 echantillons = 650 m de nationale entre la sortie d'une ville et le panneau de la suivante. Corollaire heureux : `MapScript.path_length` (taxi.gd:212-213) facture deja la traversee — **le bareme n'a pas a bouger**, seuls les detours vers une adresse (≤ 240 m aller-retour) ne sont pas factures.

### 3.9 Deux villes ne coexistent jamais

Pool d'un exemplaire (road.gd:754-756), conserve : taxi.gd:281, 294 et 299 testent `road.town` **au singulier**, par identite de nom. La suivante s'arme a `panneau_A + 475` (arete la plus courte) quand la voiture est a `475 - 138 = 337`. La ville A est eteinte a `head_index() > 150 + 65 = 215`. Marge = **122 echantillons = 244 m** derriere la voiture. Le banc l'imprime et echoue sous 100 m.

### 3.10 Le cauchemar

Rien dans `_enter_nightmare` (main.gd:4110-4155) n'arrete la navigation aujourd'hui. On ajoute :
- dans `_enter_nightmare` : `road.suspend_town()` — si une ville est **promise** (`_town_g >= 0`), elle est annulee ; si une ville est **armee**, on la garde et on appelle `town.set_dark(true)` (lumieres eteintes, fenetres noires, panneaux ternes). Une ville qu'on connait, traversee dans le noir absolu, est une image que rien d'autre ne donne. **`set_dark()` existe depuis le J3 et fait quelque chose** : elle **echange** deux references de materiau nees au `_ready` (jamais de `ShaderMaterial` fabrique au moment ou le portail du cauchemar s'ouvre — ce serait une compilation de shader au pire endroit du jeu), eteint les trois lampes, ternit les deux panneaux et les plaques, et cache le numero d'adresse. **Mais rien ne le mesure, et c'est le seul des quatre appels du §3.3 dans ce cas** : `villetest` n'a pas de ligne pour la ville du cauchemar, et la capture `90` du banc livre n'est pas `90_ville_cauchemar.png` — c'est **`90_ville_repere.png`**, le clocher de Corbeny. La teinte du cauchemar est du code ecrit, execute, et **non verifie**.
- dans main : `_on_town_reached` et `_on_fork_committed` ne programment rien tant que `world_mode == "nightmare"`.
- dans `_exit_nightmare` (4157-4189) : `_nav_resume()`, qui reprogramme la ville visee a `road.head_index() + int(edge_length * (1 - nav_progress()) / STEP)`.
- Invariant ajoute a `sleeptest` : apres un aller-retour dans le cauchemar, la ville suivante tombe encore a 30 m pres.

---

## 4. LA VILLE

### 4.1 Etendue, en metres

| | |
|---|---|
| Traversee, panneau a panneau de sortie | **260 m** (`CROSS = 130` echantillons) |
| Tronc dessine par la ville | **342 m** (`PAD = 20` echantillons de part et d'autre) |
| Largeur totale de l'emprise | **111,8 m** en moyenne, de **98** a **122** — etendue relevee 340 × 112 m *(releve)* |
| Emprise du tronc en ville | 16,0 m (6,8 de chaussee + 2×2,4 d'accotement + 2×2,2 de trottoir) |
| Emprise d'une rue | 8,4 m (5,2 de chaussee + 2×1,6 de trottoir) |
| Duree de traversee | 21 s a 45 km/h, 10 s a 90 km/h |
| Longueur de rue cumulee | **921 m** en moyenne, de **760** (Les Essarts) a **1 090** (Corbeny) *(releve)* |

**Les deux dernieres lignes sont des RELEVES, pas des estimations** — `plantest` les imprime pour les huit bourgs, une ligne chacun (`etendue 340 x 110 m`, `872 m de rue cumules`, …). Les moyennes sont celles des huit, relancees pour cette version : largeurs 110, 122, 120, 114, 98, 108, 108, 114 → 894 / 8 = **111,75 m** ; rue cumulee 872 + 1 090 + 864 + 918 + 892 + 760 + 1 040 + 936 = 7 372 m → **921,5 m**. Le plan annoncait « ±75 m de l'axe » et « ~880 m (tronc 342 + 4 transversales + 1 parallele) » : la premiere valeur etait une reservation, pas une mesure — l'enveloppe reelle est plus etroite parce que les bras de transversale sont tires dans [34, 62] m et non a 75 ; la seconde etait juste pour une ville a quatre transversales et une parallele, et le tirage en donne de trois a quatre et une a deux (§4.2).

*(Le premier recalage de ce document avait ecrit **112,1 m** sur trois largeurs de plus un metre — 111, 123, 121 la ou le banc imprime aujourd'hui 110, 122, 120. Deux dixiemes de metre sur une moyenne, ca n'a aucune consequence ; c'est cite ici parce que **le meme lot de corrections a change les batiments de 562 a 515**, et que cette ligne-la, elle, a des consequences partout. Voir annexe B.2.)*

La ville d'aujourd'hui fait 26 m sur 80 (town.gd:64-111), soit 2 080 m². La neuve en fait 340 × 111,75 = 37 995 : **18 fois la surface**. Elle mange 36 % de l'arete la plus courte — 342 m dessines sur les 950 m de Saint-Elme > Corbeny (map.gd:48) — chiffre a surveiller au banc, pas a esperer.

### 4.2 Le plan des rues — ECRIT A LA MAIN dans la forme, TIRE dans le detail

**Ce qui est ecrit a la main** (dans `town_plan.gd`, en dur) : la FORME est une echelle — un tronc, des transversales, une ou deux paralleles. C'est ce qu'est un bourg francais, et c'est ce qui fait qu'on peut faire le tour du pate.

**Ce qui est tire** (RNG seme par `map.seed_of(id)`, donc identique a chaque partie et a chaque banc) :
- **Transversales** : **3 a 4** (`CROSS_N`, town_plan.gd:156), perpendiculaires au tronc en coordonnees curvilignes, a `s` tires dans [40, 220] m, espacees d'au moins 48 m. Chacune s'etend de `u = -A` a `u = +B`, A et B tires dans [34, 62] m, arrondis a 2 m.
  Le plan annoncait « 3 a 5 » ; **l'arithmetique dit non**, et town_plan.gd:179-188 pose le calcul : cinq transversales espacees d'au moins 48 m demandent 4 × 48 = **192 m**, et la plage [40, 220] n'en offre que **180**. On garde la plage et l'espacement — ce sont eux qui font l'ilot : 48 m moins deux fois les **15 m** que le curseur saute a chaque carrefour (§4.3) laissent **18 m** de facade, de quoi poser une maison, deux quand l'entraxe tire court (9 m au plus court, et 15 + 9 = 24 tient encore) — et on plafonne le compte a quatre. *(Le premier recalage ecrivait ici « deux fois les 12 m d'abord de carrefour laissant 24 m » : c'etait la garde d'avant le resserrement, et l'ilot a maigri de 6 m sans que ce paragraphe le dise.)*
- **Paralleles** : **1 a 2** (`RAIL_N`, town_plan.gd:165), a `u = ±[26, 44]` m, de la premiere a la derniere transversale. C'est ce qui **ferme** les ilots et rend le tour du bloc possible.
  Le plan annoncait « 0 a 2 » ; **zero est interdit** (town_plan.gd:193-198) : sans parallele le graphe est un peigne, nombre cyclomatique nul, aucun tour du pate possible, et le bourg n'est plus qu'un couloir. C'est la seule rue qui donne une seconde chance quand on a rate la bonne — et `plantest` mesure « cycles mini 2 », pour un seuil de 1.
- Noms de rue tires dans une liste ecrite a la main (`rue des Tanneurs`, `quai de la Vanne`, `ruelle du Four`, …).

**Toutes les rues sont perpendiculaires ou paralleles au tronc en coordonnees curvilignes.** Consequence : un carrefour est un **rectangle** `2×half_a × 2×half_b`, pas un eventail. Pas de calcul d'angle, pas de `1/|sin|`, ~15 lignes au lieu de 35, et l'enroulement se verifie a l'oeil. La courbure du tronc (bornee a 0.0015 rad/m) est absorbee par le mapping curviligne : les ilots deviennent legerement trapezoidaux, ce qui est plus organique, pas moins.

**Nombre de rues** : 1 tronc + 3 a 4 transversales + 1 a 2 paralleles = **5 a 7**. Releve `plantest` sur les huit bourgs : 6, 7, 6, 6, 6, 5, 7, 6 — soit 49 rues, 6,1 par bourg. Le plan n'annoncait pas ce compte ; il l'annonce maintenant, parce que c'est lui qui dimensionne les surfaces 1 et 3 (§4.6).

**Carrefours** : chaque transversale coupe le tronc et chaque parallele, donc `n_transversales × (1 + n_paralleles)`, de **6** (3 × 2) a **12** (4 × 3). Le plan annoncait **8** « pour une ville type » : c'est le cas d'une ville a quatre transversales et une parallele, et c'est le plus rare. Releve : 9, 12, 8, 8, 9, 6, 12, 9 — **73 carrefours sur les huit bourgs, 9,1 par bourg**. C'est ce 9,1, et non 8, qui sert au calcul de densite ci-dessous.

### 4.3 Ilots et batiments — PROCEDURAL, deterministe

Le long de chaque troncon, des deux cotes, tous les 9 a 14 m ; facade a `SETBACK = 6,0 m` de l'axe de rue (`SETBACK_TR = 10,0 m` du tronc) ; largeur 6 a 13 m ; profondeur 8 a 12 m ; hauteur 4,6 a 9,4 m ; lacet ±4°.

**L'abord de carrefour : le generateur s'est resserre, et ce paragraphe a du etre reecrit.** Le plan promettait « aucun batiment a moins de 12 m d'un carrefour ». La version precedente de ce document repondait : vrai des **centres** (15,62 m au plus juste), faux des **empreintes** (7,59 m, 120 couples sur 5 102 sous les 12 m) — et elle finissait sur cet avertissement, mot pour mot : *« Si le generateur se resserre plus tard, c'est ce paragraphe qu'il faut reecrire. »* **Il s'est resserre. Le voici reecrit.**

Le curseur de pose ne saute plus a `CORNER_FREE` pile : il saute a **`CORNER_FREE` plus la demi-largeur de la plus etroite des facades**, soit `12,0 + 6,0/2 =` **15,0 m**, et le **rabot de largeur** retaille les plus larges jusqu'a ce qu'elles laissent la garde libre de part et d'autre de chaque carrefour de leur rue (town_plan.gd:79-104 pour le raisonnement, l. 908-935 pour le saut, l. 942-951 pour le rabot). Le saut est cale **exactement** la ou le rabot rend `BLD_W.x` et pas zero : un metre plus tot, le candidat serait refuse et l'entraxe rebrule.

**Ce que ca change, releve en recompilant le fichier des cinq facons** (consigne dans town_plan.gd:93-104 — *maisons sur les huit villes, mur le plus proche d'un carrefour, couples mur/carrefour sous les 12 m*) :

| Regle d'abord de carrefour | Maisons | Mur le plus proche | Fautes |
|---|---|---|---|
| saut sur le CENTRE *(l'etat d'avant, celui que ce plan decrivait)* | 562 | **7,59 m** | **120** |
| refus pur, garde sur le centre | 512 | 8,40 m | 55 |
| refus pur, garde sur l'empreinte | 462 | 13,04 m | 0 |
| **SAUT sur l'empreinte — ce que le code fait** | **515** | **12,73 m** | **0** |
| saut de 12 + la demi-largeur MAXI | 442 | 13,49 m | 0 |

Donc, aujourd'hui : **aucune EMPREINTE de batiment a moins de 12 m du centre d'un carrefour** — 12,73 m au plus juste, **zero couple sur 4 691** —, **et** aucune empreinte dans l'emprise d'une rue. La promesse d'origine est tenue, et elle l'est **sur le bon objet** : c'est un mur qui borde le croisement, pas le milieu d'une maison. Le trou dans les phares est reel et il vaut 12,7 m.

Ce qui garantit le second point est inchange : la largeur est rabotee par `wmax = min(wmax, 2 × (|abscisse du carrefour − t| − garde))` ou la garde vaut `edge_half(rue) + KEEP_CLEAR` — 8,5 m contre le tronc, 4,7 contre une rue (town_plan.gd:106-117, 942-951). `plantest`, relance pour cette version : **515 batiments, 3 153 couples mur/rue, 0 empietement ; marge du mur au bord de trottoir, tronc +0,896 m, transversale +1,456, parallele +0,541 ; pire cas +0,541 m sur Malassis, rail.**

**Le prix, et il est ecrit :** 47 maisons sur 562, soit 5,9 par bourg. La ligne retenue est **la seule des cinq** qui rende a la fois le trou promis **et** plus de maisons que le refus pur (515 contre 512).

> *(Etat du generateur au moment ou CETTE ligne est ecrite. `town_plan.gd` connait maintenant **trois** gardes d'abord de carrefour : le saut du curseur sur l'empreinte (l. 908-935), le rabot de largeur (l. 942-951) et le bridage par l'entraxe precedent (l. 938-941, 19 refus sur 705). **Le 12,73 m et les 4 691 couples ne sortent d'AUCUN banc** : ils sont consignes dans les commentaires de `town_plan.gd`, mesures en recompilant le fichier. `plantest` compare les murs aux **rues**, jamais aux **centres de carrefour** — c'est exactement l'angle mort qui a laisse vivre le 7,59 m. Une ligne `AUCUN MUR DANS UN CARREFOUR` dans `plantest` couterait dix lignes et fermerait le trou pour de bon ; tant qu'elle n'existe pas, ce tableau est a re-mesurer avant d'en resservir un chiffre.)*

**LE COMPTE, ET POURQUOI CE N'EST PAS 120.** Le plan ecrivait : `880 m × 2 cotes / 11,5 m` moins les abords de carrefour ≈ 120. **Les deux premiers termes donnent 153 ; le troisieme n'a jamais ete soustrait.** On le pose, terme par terme, sur les releves :

| | |
|---|---|
| Rue cumulee par bourg *(`plantest`)* | 7 372 / 8 = **921,5 m** |
| Lineaire de facade, deux cotes | 921,5 × 2 = **1 843 m** |
| Ce que le curseur saute vraiment, de part et d'autre | `CORNER_FREE + BLD_W.x / 2` = 12,0 + 3,0 = **15,0 m** |
| Abords de carrefour : 15 m de part et d'autre de 9,125 carrefours, sur les **deux** rues de chacun et les **deux** trottoirs de chaque rue | naivement 4 × 15 × 9,125 = 548 m de rue, soit 1 095 m de facade, **59 %** |
| Ce que la mesure en retire vraiment, unions faites | **52 %** — moins que le produit, parce que deux carrefours voisins partagent leur zone et qu'une zone qui deborde du bout d'une rue ne coute rien |
| Lineaire utile | 1 843 × 0,48 = **885 m** |
| Entraxe median `BLD_PITCH` | **11,5 m** |
| **Plafond geometrique** | 885 / 11,5 = **77 emplacements** |

**Ce plafond vaut 77, pas 120, et pas 91 non plus** — et pour tenir 120 il faudrait un entraxe de 885 / 120 = 7,4 m, donc une facade moyenne de 5,9 m quand `BLD_W` en promet 6 a 13. Le plan se contredisait lui-meme, et le premier recalage n'a corrige la contradiction qu'a moitie : il a soustrait **12 m** d'abord de carrefour quand le code en saute **15**. Le calcul complet est pose une fois pour toutes dans town_plan.gd:121-137, a cote de la constante qu'il justifie.

Sous ce plafond, le coin d'ilot prend encore sa part : deux rangees perpendiculaires se disputent le meme carre a chaque quart de carrefour, et la seconde posee y perd sa maison — **154 candidats refuses sur 705**. Le bridage par l'entraxe precedent, lui, n'en refuse que **19 sur 705** (2,7 %), et le rabot de largeur **aucun** : ce n'est pas la rangee qui serre, c'est le carrefour. Releve final, imprime par `plantest` :

> **515 batiments sur les huit bourgs, soit 64,4 par bourg** — 61 (Saint-Elme), 68 (Corbeny), 63 (La Fresnaie), 70 (Malassis), 62 (Vieux-Bourg), 65 (Les Essarts), 60 (Peyrelade), 66 (Brumaire). Facade moyenne **8,05 m**, **58,6 %** du lineaire utile bati.

Le compte se referme sur lui-meme, et c'est ce qui le rend croyable : 64,375 × 8,05 = **518 m** de facade batie sur les 885 m utiles, soit **58,6 %** — le meme taux de remplissage qu'avant le resserrement, au dixieme pres. *Ce n'est pas la rangee qui s'est desserree, c'est le carrefour qui a pris sa place.*

Et **l'entraxe ne bride qu'a peine** — mesure en recompilant town_plan.gd avec d'autres valeurs (l. 148-154) : 9-14 m rend 64,4 maisons par ville, 8-13 en rend 67,0, 7,5-12 en rend 66,9, 7-11 en rend 66,8, 6,5-10 en rend 64,9, 10-15 en rend 61,9, 11-16 en rend 58,5. **Ceci renverse ce que le plan disait** (« serrer l'entraxe ne fait que multiplier les refus ») : c'etait vrai du temps de la garde sur les centres, ca ne l'est plus. Descendre a 8-13 rapporterait **+2,6 maisons par bourg**. On garde quand meme les 9 a 14 m — *un ecart au plan se decide dans le plan*, et celui-la ne vaut pas 2,6 maisons.

**Fenetres — LE CHIFFRE N'ETAIT PLUS MESURE ; IL L'EST DEPUIS LE J3, ET LA BORNE QUI TENAIT LIEU DE MESURE ETAIT FAUSSE.** *(Ce qui suit jusqu'au releve est le raisonnement d'avant le J3 : il est laisse entier parce que c'est SA nature qui est en cause, pas son arithmetique.)* p = 0,30 par travee-etage, `bays = clamp(largeur / 1,6 ; 1 ; 8)` et `etages = clamp(hauteur / 2,6 ; 1 ; 3)` (town_plan.gd:165-169), **sur la face qui donne sur la rue seulement**. Le plan annoncait ≈ 360 par bourg ; le premier recalage a releve **223** — mais ce releve datait des **562 batiments a 8,77 m de facade**, et **aucun banc du depot n'imprime le compte de fenetres**. Il est donc perime, et on ne peut pas le remplacer par un autre releve : on le **borne**.

- `etages` : `BLD_H` est tire uniformement dans [4,6 ; 9,4], donc `int(h / 2,6)` vaut 1 pour 12,5 % des maisons, 2 pour 54,17 % et 3 pour 33,33 % → **2,208 etages** en moyenne. *Exact, pas estime.*
- `travees` : la facade moyenne relevee vaut 8,05 m, et pour tout `w`, `w/1,6 − 1 < int(w/1,6) ≤ w/1,6`. Donc la moyenne des travees tombe entre **4,03 et 5,03**.
- Fenetres par batiment = 0,30 × 2,208 × travees, soit **entre 2,67 et 3,33**. Par bourg : 64,375 × ca = **entre 172 et 214**. Sur les huit : entre 1 375 et 1 715.

**ET `villetest` LES COMPTE DEPUIS LE J3 : LA FOURCHETTE CI-DESSUS EST FAUSSE.** Le banc lit le masque de bits de chaque batiment et imprime le compte : **Corbeny 159, Malassis 177, Saint-Elme 188, La Fresnaie 201** — et Corbeny, le bourg que la carte traverse en premier, tombe **13 fenetres SOUS la borne basse de 172**.
**La faute n'est pas dans l'arithmetique, elle est dans ce qu'on a borne.** `WIN_P = 0,30` n'est pas un taux de remplissage : c'est un **tirage**, `if rng.randf() < WIN_P` par travee-etage (town_plan.gd, `_windows`). Les trois puces ci-dessus bornent donc l'**esperance** du tirage — correctement —, et pas le tirage lui-meme. L'ordre de grandeur de l'ecart se pose : 159 fenetres a p = 0,30 supposent ~**530** travees-etages offertes a Corbeny, et un tirage binomial de 530 essais a p = 0,30 a pour ecart-type `√(530 × 0,3 × 0,7) =` **10,6** — trois ecarts-types font **32 fenetres**, quand la fourchette entiere n'en faisait que 42. **Une esperance bornee a ±21 ne peut pas borner un tirage qui bat de ±32**, et c'est vrai avant meme de compter que le nombre de travees varie d'un bourg a l'autre.
*(Les quatre autres bourgs ne sont comptes que dans le commentaire de tete de `town.gd`, qui donne **1 493 fenetres sur les huit, soit 186,6 par bourg**, et nomme les deux extremes : **Peyrelade 154** et **Brumaire 225**. Ce sont des chiffres a dater, pas des releves de banc — `villetest` n'ouvre que quatre villes. §4.6.)*

**Mats** : un tous les 30 m de rue, cotes alternes, **sauf la ou le mat tomberait dans l'emprise d'une autre rue**. Le plan annoncait 29 par bourg ; releve `plantest`, **inchange par le resserrement des batiments** : **187 mats au total, soit 23,4 par bourg** (22, 24, 23, 28, 20, 18, 27, 25). Le refus d'abord de carrefour en retire 56 sur 243 — sans lui, 23 mats tombaient dans la **chaussee** d'une autre rue, dont 8 dans la nationale, le pire a 1,00 m d'un axe, soit 1,60 m **dans** la voie (town_plan.gd:795-813). Un croisement n'a pas de reverbere en son milieu, et la ville n'ayant pas de collision, le joueur aurait **traverse le poteau**.

Materiau : `Retro.mat(Color(0.09,0.075,0.045), 0.6)` avec `emission = Color(0.55,0.38,0.16)` — **exactement** town.gd:42-43, donc **aucune variante de shader neuve a compiler**. C'est le poste qui compte : le brouillard a 0.030 ne laisse passer que 5 % a 100 m, et les **60 a 70 boites** d'albedo 0,030 ne rendent rien au-dela de la portee des phares. **Ce qui fait une ville de nuit, ce sont les fenetres, les tetes de lampadaire et le repere dans le brouillard** — et les fenetres se comptent desormais : **159 a 201 par bourg** sur les quatre que `villetest` ouvre, plus 22 a 28 tetes. C'est la moitie de ce que le plan promettait, et c'est le chiffre sur lequel juger le rendu : si le bourg parait vide, c'est la que ca se decide — en montant `WIN_P`, pas en esperant 120 maisons que la geometrie ne peut pas porter. Et `WIN_P` est le bon levier **precisement parce que** les fenetres sont des quads dans une surface deja emise : monter p de 0,30 a 0,45 coute 90 quads et **zero appel de dessin**.

### 4.4 Les mots dans le monde

Une adresse qui n'existe que sur un ecran n'est pas un lieu. On pose donc, en `Label3D` (chacun son appel de dessin — on les compte) :
- **2 panneaux** : entree et sortie, `town.make_sign()` **reutilise tel quel** (town.gd:116-147).
- **jusqu'a 4 plaques de rue**, seulement sur les rues qui portent une adresse, a 2,2 m de haut, du bon cote.
- **1 numero d'adresse**, arme **uniquement pour la course en cours**, sous un **porche eclaire** (trois quads emissifs dans la surface 6). L'adresse visee se voit dans les phares avant d'etre atteinte.

Total : **7 Label3D**, qui portent le compte du bourg a **17 objets dessinables** avec les six surfaces. Ce plan en deduisait 28 appels de dessin sur les quatre vues, et 52 en tout : **le banc en releve 27 a 29 pour le bourg ENTIER** — les panneaux, les plaques et le numero sont hors champ ou derriere la voiture la plupart du temps, et le cull les retire vue par vue (§7). On ne va pas au-dela pour autant : cinquante enseignes de commerce, ce sont cinquante objets a culler par vue, et le cull ne les retire pas toujours.

### 4.5 Les adresses et les commodites

**4 adresses par ville.** Une adresse = `{nom, tronçon, abscisse t, cote}`. Zone de validation, dans le repere de l'adresse (origine sur l'**axe** de la rue, -Z le long de la rue, +X vers le trottoir de l'adresse) :
```
|z| < 8,0 m   et   0,5 m < x < 5,0 m   et   |car.speed| <= 0,40 m/s
```
Soit un rectangle de **16 × 4,5 m le long du bon trottoir** : se garer du mauvais cote ne compte pas. Le cap reste libre (comme aujourd'hui, taxi.gd:279-287) — le test de cote suffit et une exigence de cap se retournerait contre le joueur dans une ville ou l'on arrive de n'importe ou.

**Deux des quatre adresses portent une commodite tiree de `MapScript.amenities(id)`** (map.gd:20-37), qui n'est lue aujourd'hui qu'a phone_apps.gd:344-345, pour remplir un Label. On en rend **une** fonctionnelle :

> **Le cafe de nuit.** S'arreter plus de 2 s dans sa baie appelle `sleep.drink_boost("cafe")` (sleep.gd:235-245, nouvelle entree, `boost_cafe := 0.30`, soumise a `caffeine_window`), une fois par visite de ville.

Ce n'est pas un ornement : c'est la **reponse chiffree** au cout que la ville impose a la vigilance. Et ce cout a **trois** termes, la ou ce plan n'en comptait qu'un et demi — dont un qu'il comptait a tort. Le drain vaut `(1 / full_span) × _sleepers() × _remedies()` ; en face d'une nationale a 90 km/h et plus, ou `_remedies` vaut 0,75 :

| Terme | Ce que fait le code | Ce que ca coute en ville |
|---|---|---|
| `speed_factor = 0,75` **perdu** | `sleep.gd:152-153` ne le donne qu'au-dessus de **25 m/s** (90 km/h) | **× 1,33**, des qu'on ralentit sous 90 |
| `mono_factor = 1,6` **arme** | `sleep.gd:142-143`, apres `mono_after = 10 s` de vitesse etale et de volant sous 0,04 (`sleep.gd:163`) | **× 1,6**, et §1 le mesure : **9 traversees sur 10** l'arment |
| `slow_factor = 1,3` | `sleep.gd:140-141`, **sous 11,1 m/s** (40 km/h) seulement | **× 1,3**, mais **pas a 45 km/h** |

**Le plan se trompait sur le troisieme terme, et dans le sens qui l'arrangeait.** Il ecrivait : *« Une traversee de 21 s a 45 km/h coute `(1,3 / 0,75) = 1,73` fois le debit de la nationale. »* Non : 45 km/h font **12,5 m/s**, et `slow_factor` demande **moins de 11,1**. A 45 km/h il ne mord pas. Le compte juste :

- **a 45 km/h** — la vitesse a laquelle `rubantest` traverse — : **× 1,33**, et **× 2,13** des que la monotonie s'arme ;
- **sous 40 km/h** — la vitesse a laquelle on cherche une plaque de rue dans les phares — : **× 1,73**, et **× 2,77** monotonie armee.

Le 1,73 du plan etait donc juste, mais **pour une autre vitesse que celle qu'il citait**, et il ratait le facteur 1,6 qui est le plus gros des trois. **Le vrai cout de la traversee est du double au triple du debit de la nationale**, pas des trois quarts en plus. La ville prend de la vigilance — par la lenteur *et* par la monotonie —, le cafe en rend. C'est un arbitrage, pas une punition ; il est simplement plus cher qu'annonce, et c'est `LE CAFE REND UNE GORGEE` (J4) qui dira si `boost_cafe = 0,30` le paie.

Les autres commodites restent de la signaletique (plaque + porche) — a construire plus tard, pas dans ce plan.

### 4.6 Le maillage : un noeud, six surfaces, quatre images

> **AUCUN PAVE DE CARREFOUR — LE PLAN EN PROMETTAIT HUIT, ET LE CODE A EU RAISON DE N'EN POSER AUCUN.** La surface 1 de ce plan disait « chaussees (tronc + rues) **+ paves de carrefour** », et l'invariant `TOUT EST A L'ENDROIT` du J3 demandait l'aire signee « sur les **8 paves de carrefour** ». `town.gd` n'en pose pas un seul, et son argument tient en une phrase : **un pave est un rectangle d'asphalte pose la ou deux chaussees se croisent, c'est-a-dire exactement la ou l'une des deux passe deja.** Coplanaire, meme materiau, meme hauteur `Y_ROAD` : ce n'est pas un carrefour plus epais, c'est **du z-fighting en travers des phares** — le defaut que le masque de §3.3 existe precisement pour eviter entre le ruban et la traversante, et qu'un pave aurait reintroduit huit a douze fois par bourg.
>
> **Ce que `town.gd` fait a la place, et c'est la regle de tout le fichier : A CHAQUE CROISEMENT, UNE SEULE DES DEUX RUES PASSE.** Le tronc passe sous les transversales, les transversales passent sur les paralleles, et **celle qui cede est COUPEE a l'emprise de celle qui garde**. Ni trou, ni recouvrement, et le carrefour se dessine tout seul — il est le morceau de chaussee que la rue qui passe a laisse en travers de celle qui cede. Le meme raisonnement coupe l'accotement et le trottoir du tronc a chaque transversale (surfaces 2 et 3), et c'est ce qui fait tomber la surface 2 sous le chiffre annonce.
>
> **Et l'invariant y gagne au lieu d'y perdre**, ce qui est la vraie raison d'ecrire ce paragraphe. Un controle « sur les 8 paves » aurait porte sur huit rectangles nommes a la main. Celui qui est livre parcourt **TOUS les triangles du bourg** — 19 624 sur les quatre villes que le banc ouvre, murs, toits, fenetres, mats et repere compris — et il le fait avec **deux** mesures au lieu d'une, parce que l'aire signee en (x, z) ne veut rien dire d'un mur vertical (§6).

**CE TABLEAU N'EST PLUS UNE ESTIMATION : `villetest` ouvre le maillage et compte, surface par surface.** Les colonnes « annonce » sont ce que la version precedente de ce document promettait ; les colonnes « releve » sont Corbeny, le bourg que le banc traverse et le plus lourd des huit en triangles.

| Surface | Contenu **reel** | Annonce (v. precedente) | **Releve — Corbeny** |
|---|---|---|---|
| 1 asphalte | chaussees (tronc + rues), **aucun pave de carrefour** | ~817 / ~966 | **713 / 852** |
| 2 accotement | les deux bandes du tronc, `y = 0,000`, **coupees a chaque transversale** | ~684 / ~680 | **636 / 616** |
| 3 trottoir | bandes du tronc en ville (coupees aussi) + bandes de rue, `y = 0,030` | ~1 064 / ~1 056 | **1 036 / 960** |
| 4 peinture | lignes de rive du tronc, `y = 0,026`, **pas de pointilles en ville** | ~684 / ~680 | **684 / 680** |
| 5 bati | 68 boites a 5 faces + 24 mats hexagonaux **+ le repere** (clocher : 392 / 612) | ~1 568 / ~924 | **2 040 / 1 580** |
| 6 emissif | **159 fenetres comptees** + 24 tetes + 4 porches **+ le cadran du clocher** (112 / 148) | ~794 a ~962 / ~397 a ~481 | **988 / 682** |
| **TOTAL** | **1 `MeshInstance3D`, 6 surfaces** | ~5 610 a ~5 780 / ~4 700 a ~4 790 | **6 097 / 5 370** |

Les trois autres bourgs que `villetest` ouvre, releves aux memes lancements : **Malassis 5 809 / 4 844**, **Saint-Elme 5 733 / 4 786**, **La Fresnaie 5 635 / 4 624**.

**CES COMPTES NE BOUGENT PAS AVEC LE RUBAN — MAIS ILS BOUGENT AVEC LES REPERES, ET LA SERIE DE DIX L'A ATTRAPE EN DIRECT.** Neuf lancements consecutifs ont rendu les quatre memes totaux au sommet pres, alors que la courbure du ruban est retiree a chaque fois : le plan est seme par le **nom** de la ville, et la traversante ne change que la **place** des sommets, jamais leur nombre. **Au dixieme, Saint-Elme est passe a 5 757 / 4 830** — et il y est reste au onzieme — — +24 sommets et +44 triangles — parce que son totem avait ete rebati plus haut *pendant la serie* (12,60 m et 336 sommets sur les neuf premiers, 20,05 m et 360 sur le dernier), en meme temps que trois autres reperes. **Ce n'est pas du bruit de mesure, c'est un asset qui a change sous le banc**, et c'est la meilleure demonstration possible de la regle de l'annexe B : *une mesure a une date*. Les trois autres bourgs, eux, n'ont pas bouge d'un sommet sur les dix.

**LE COUT UNITAIRE, LUI, N'A JAMAIS BOUGE — ET C'EST LA SEULE PARTIE DE L'ANCIEN BUDGET QUI SURVIT AU BANC.** Le budget total a baisse deux fois avant le J3 (120 boites et 360 fenetres, puis 70,3 et 223, puis 64,4) et le J3 l'a rendu caduc en ouvrant le maillage. Ce qui reste vrai au sommet pres, et qui referme le compte de la surface 5 ci-dessus, c'est le prix a l'unite :

- une **boite a 5 faces** = 5 quads a normales plates = **20 sommets, 10 triangles** (120 × 20 = 2 400 des 2 748 sommets de l'ancienne ligne 5, et 120 × 10 = 1 200 de ses 1 548 triangles) ;
- un **mat hexagonal** = 6 faces laterales a sommets partages = **12 sommets, 12 triangles** (2 748 − 2 400 = 348 = 29 × 12 ; 1 548 − 1 200 = 348 = 29 × 12) ;
- une **fenetre**, une **tete** et un **porche** sont un quad chacun = **4 sommets, 2 triangles** (1 568 − 360 × 4 = 128 = 32 × 4 pour 29 tetes + 3 porches ; 784 − 720 = 64 = 32 × 2).

**Et ce prix a l'unite referme le compte de Corbeny, ce qui est la meilleure preuve qu'on le tienne :** 68 × 20 + 24 × 12 = **1 648 sommets**, et la surface 5 relevee en vaut **2 040** — la difference, **392**, est le clocher au sommet pres. Cote triangles, 68 × 10 + 24 × 12 = **968**, releve **1 580**, difference **612** : le clocher encore. Le calcul du plan n'etait pas faux, **il ne comptait pas le repere** — et le repere n'existait pas quand il a ete pose.

**CE QUE LE BANC A DEMENTI, SURFACE PAR SURFACE.** Le total tombe **au-DESSUS** de la borne haute annoncee — 6 097 contre 5 780 pour Corbeny, soit +5,5 % — et les raisons ne se compensent pas entre elles :

- la **4** (peinture) tombe **au sommet pres** : 684 / 680, exactement le chiffre annonce. C'est la seule surface qui ne depende que du tronc, et le tronc n'a pas bouge — 171 echantillons dessines (`CROSS + 2 × PAD + 1`) × 2 sommets = 342 par bande, deux bandes = 684 ;
- la **2** (accotement) fait **636 a 648**, pas 684. **Le plan la disait « exacte » et se trompait de mecanisme** : `town.gd` **coupe** l'accotement et le trottoir du tronc a chaque transversale — une rue qui debouche sur la nationale n'a pas un trottoir en travers de sa bouche —, et ce sont les bandes de la transversale qui rebouchent la coupe, dans la surface **3**. Deux surfaces echangent des sommets ; aucune des deux n'est le calcul du plan ;
- les **1** et **3** etaient chiffrees sur 880 m de rue et huit carrefours quand Corbeny en porte **1 090 et douze**, et le plan les annoncait **basses** pour cette raison. Elles sortent **sous** l'estimation quand meme (713 contre ~817, 1 036 contre ~1 064) : une transversale est **une droite du monde et se pose en deux points**, pas en cinquante comme le tronc courbe. Le plan avait raison de dire qu'il ne savait pas ; il s'etait trompe de signe ;
- la **5** vaut **2 040** contre ~1 568 annonces, et l'ecart n'est pas une derive : le calcul « 68 boites × 20 + 24 mats × 12 = 1 648 » ne comptait **pas le repere**, qui verse ses triangles **dans** cette surface. Le clocher de Corbeny y met **392 sommets / 612 triangles**, et son cadran **112 / 148** dans la surface 6 ;
- la **6** n'est plus une fourchette : elle se **compte**.

**LES FENETRES SE COMPTENT, ET LA FOURCHETTE DU PLAN RATE DEUX BOURGS SUR HUIT.** `villetest` imprime le compte de fenetres allumees de chaque bourg qu'il ouvre : **Corbeny 159, Malassis 177, Saint-Elme 188, La Fresnaie 201**. La fourchette annoncee etait « **172 a 214** par bourg » (§4.3) : elle rate deja Corbeny par le bas, sur le seul bourg que le banc traverse.
**Pourquoi elle rate, et c'est une faute de nature, pas d'arithmetique.** `WIN_P = 0,30` n'est pas un taux de remplissage, c'est un **tirage** : `if rng.randf() < WIN_P` par travee-etage. Le calcul de §4.3 bornait donc l'**esperance** du tirage, pas le tirage. Ordre de grandeur, pose : 159 fenetres a p = 0,30 supposent environ **530 travees-etages** offertes a Corbeny, et l'ecart-type d'un tirage binomial de 530 essais a p = 0,30 vaut `√(530 × 0,3 × 0,7) =` **10,6** — trois ecarts-types font 32 fenetres, avant meme de compter que le nombre de travees varie d'un bourg a l'autre. **Une esperance bornee a ±21 ne borne pas un tirage.**

**Le pire bourg n'est pas celui que le plan designait.** Il pariait sur **Malassis** (70 maisons, 28 mats). `villetest` le mesure a **5 809 / 4 844** — plus leger que **Corbeny, 6 097 / 5 370**, qui est le pire des quatre bourgs que le banc ouvre, et il l'est par ses **1 090 m de rue, ses douze carrefours et son clocher**, pas par ses maisons.

**Les seuils du J3 ne bougent pas, et ils couvrent maintenant du mesure.** Ils sont a `< 8 000` sommets et `< 6 500` triangles (§6). Contre le pire compte releve au banc — **6 097 / 5 370** —, il reste **1 903 sommets et 1 130 triangles** de marge, soit **+31 % et +21 %** du compte. `villetest` imprime la meme marge dans l'autre convention (part du seuil) : **24 % et 17 %**.

> **CE QUI RESTE NON MESURE PAR UN BANC, ET IL FAUT LE DATER.** `villetest` n'ouvre que **quatre** bourgs sur huit — Corbeny, Malassis, Saint-Elme, La Fresnaie. Les quatre autres ne sont comptes que dans le commentaire de tete de `scripts/town.gd`, en instrumentant le fichier : **Les Essarts 5 525 / 4 544, Peyrelade 5 929 / 5 160, Vieux-Bourg 6 009 / 5 088, Brumaire 6 305 / 5 066**, ce qui ferait une moyenne de 5 880 / 4 935 sur les huit et designerait **Brumaire** comme le plus lourd en sommets, par ses **225 fenetres**. **Ces quatre-la sont exactement le genre de chiffre que l'annexe B reproche a ce document** : mesures une fois, a une date, par personne d'autre que le banc. Une boucle sur les huit villes dans `villetest` couterait quelques lignes et fermerait le trou ; tant qu'elle n'existe pas, seuls les quatre premiers comptes sont a resservir.

`cast_shadow = SHADOW_CASTING_SETTING_OFF` partout — le modele de town.gd (OFF a 75, 97, 105, 125, 134, 159, 172), **pas** celui de road.gd:795-800, qui a laisse les 96 arbres et 18 poteaux dans les deux cartes d'ombre des phares.

**Hauteurs.** `sol -0,040 | accotement 0,000 | chaussee 0,020 | peinture 0,026 | trottoir 0,030`. Le trottoir est **une bande separee, au-dela de l'accotement** (de 5,8 a 8,0 m), pas un rehaussement de l'accotement : aucun conflit de hauteur avec le ruban aux deux coutures. Le trottoir est **plat et sans collision** — la voiture roule dessus sans rien sentir. Un vrai trottoir de 12 cm serait un MUR (`floor_max_angle` vaut 45° par defaut, jamais regle) et arreterait net une voiture lancee.
Albedo trottoir 0,130 contre accotement 0,085 : ecart 0,045, au-dessus du pas du tramage (32 niveaux, 8/255 = 0,031). **Le trottoir se lit.**

**La construction est etalee sur QUATRE images**, en machine a etats — c'est le plan, pas la parade :

| Etape | Contenu | Cout attendu | **Cout releve** *(mediane, dix lancements)* |
|---|---|---|---|
| 1 | plan (memoise) + mapping curviligne -> monde + chaussees | ~1,2 ms | **0,56 a 0,74 ms** |
| 2 | accotements + trottoirs + peinture | ~1,3 ms | **1,40 a 1,89 ms** — *la pire des quatre, aux DIX lancements* |
| 3 | batiments + mats + repere | ~2,8 ms | **1,29 a 1,61 ms** |
| 4 | emissif + `_commit` des 6 surfaces + `_town_ready = true` | ~2,3 ms | **1,04 a 1,32 ms** |

**LES QUATRE COUTS SONT MESURES DEPUIS LE J3, ET LE PLAN S'ETAIT TROMPE D'ETAPE.** `ELLE SE BATIT SANS SAUTER UNE IMAGE` chronometre douze reconstructions du meme bourg, journal coupe, chaque etape appelee a part : **la pire etape est la 2 et jamais une autre, aux dix lancements**, entre 1,40 et 1,89 ms pour un seuil de 4,0 ; la plus longue des quarante-huit mesures d'un lancement va de **1,73 a 2,81 ms**. Le plan pariait sur l'etape **3** (les boites) et lui donnait 2,8 ms : elle en fait **1,3 a 1,6**, et c'est exactement le « si l'etape 3 tombe a 1,5 ms, c'est attendu » qu'il ecrivait. Ce qu'il n'avait pas vu, c'est que **les trottoirs coutent plus cher que les maisons** — la surface 3 est la deuxieme du bourg (1 036 sommets sur Corbeny, §4.6), elle se coupe a chaque transversale, et chacune de ses bandes redemande le mapping curviligne. **Le cout n'etait pas dans les boites : il etait dans les appels de `point()`**, la ou le plan disait qu'il faudrait aller le chercher s'il n'y etait pas.

**L'armement, lui, se mesure dans le PIRE CAS et pas dans le cas ordinaire** : le banc porte la voiture au bout du ruban vivant pour que road.gd pousse **150 echantillons dans une seule image** — le plafond exact de son garde-fou —, et `town.arm()` tombe dedans. Cette image-la a dure **7,47 ms** au lancement de reference, ses voisines 7,05 avant et 10,41 apres. Un banc qui mesurerait le cas facile annoncerait un cout qu'aucun joueur ne paie.

Justification : `town.arm()` est appele depuis `_append_sample` (road.gd:313), lui-meme appele **jusqu'a 150 fois dans une image** par le garde-fou de road.gd:199-207 et en boucle par `_swap_to_branch` (road.gd:648-650) ; et `_rebuild()` suit ligne 209. Les deux couts peuvent tomber sur la **meme** image. Un `_build_mesh` monolithique de ~6 ms plus un `_rebuild` de ~1,6 ms sur une image de 8,69 ms fait 16,3 ms, soit 60 ips pile. La ville est armee 276 m devant, soit **11 s a 90 km/h** : quatre images coutent 35 ms, on a trois cents fois la marge.

### 4.7 Collisions : AUCUNE, et une consequence quand meme

Pas de `StaticBody3D` dans ce plan. Voir §8 pour l'argument complet. A la place, dans taxi.gd et car.gd :

> Quand `road.in_town()` et `road.off_road_dist(p) > 8,0 m` : un raclement (le bruit d'accotement existant), un `car.impact(Vector3(0, 0, 2.5))` toutes les 0,4 s, et le juge `offroad` qui parle. Le joueur sait qu'il n'est plus sur la rue **avant** d'etre dans un salon.

### 4.8 Eclairage

- **3 `OmniLight3D`** (contre 1 dans le hameau d'avant) : couleur `(1,0 / 0,62 / 0,22)`, energie 1,4, portee 14 m, `shadow_enabled = false`, et — **correction gratuite, faite au J3** — `light_volumetric_fog_energy = 0,15`, la ou l'ancienne town.gd etait **la seule lumiere du depot a laisser le defaut de 1,0** (car.gd pose 0,12 / 0,16 / 0,10, dome_light.gd 0,0, police_car.gd les siennes) **[verifie]**. Seize lampes a energie volumetrique pleine seraient le seul poste capable de couter des millisecondes. `villetest` le mesure : **3 `OmniLight3D` exactement, 3 allumees a chaque image, brouillard volumetrique 0,15 au plus pour un plafond de 0,2**.
- Elles **se deplacent** : `_relight()` a 4 Hz reassigne une lumiere quand son lampadaire passe a plus de 70 m derriere, et **seulement vers un lampadaire a plus de 60 m** — a 60 m le brouillard a 0,030 laisse passer 16 %, un allumage y est invisible. Le banc releve la distance **minimale** d'allumage sur une traversee **avec demi-tour**.
- Les **autres** tetes luisent par emission de materiau (surface 6), cout nul — **19 a 25 par bourg** sur les quatre que `villetest` ouvre (22 a 28 mats moins les trois qui portent une vraie lampe), et non les 26 que le plan deduisait de 29 (§4.3). C'est le compromis deja ecrit dans la ville d'avant, passe a l'echelle.
- **Toujours deux seules ombres dans tout le jeu : les phares.**

### 4.9 Le jury du client devient contextuel — taxi.gd:393-410

| Seuil | Nationale | En ville (`road.in_town()`) |
|---|---|---|
| `SPEED_MAX` | 29,2 m/s (105 km/h) | **13,9 m/s (50 km/h)** |
| `LATERAL_MAX` | 4,5 m/s² | **6,5 m/s²** |
| `JOLT_MAX` | 6,0 m/s² | **8,5 m/s²** |
| calage | 1,5 pt des le 1er echantillon | **2 echantillons de grace (1 s)** |

Arithmetique verifiee, et elle contredit ce que le premier dossier annoncait : `car.gd:186` plafonne `max_lateral = 8,0` et `car.gd:734-736` bride le lacet a `8,0/v` des `v > 0,5`. **A pleine butee au-dessus de 28 km/h, l'acceleration laterale vaut donc exactement 8,0 m/s²** — aucun seuil sous 8,0 ne peut rendre un virage serre gratuit. Un seuil a 8,5 ne jugerait plus rien.
On assume donc que 6,5 **parle** : `lateral = v²/R`, un quart de tour de rayon 12 m a 30 km/h donne 5,78 (silence), le meme a 45 km/h donne 13,0 (le client parle). Cout reel : un virage dure ~1,5 s = 3 echantillons a 1,0 pt ; sur une course de 1 400 m (112 echantillons, budget `112 × 1,5 = 168`), quatre virages mal pris coutent 12 pts, soit `norm = 0,071` et **4,7 etoiles**. Ralentir en ville est un choix qui rapporte, pas une taxe.

**Le pire piege du dossier**, taxi.gd:409 : `road._closest_dist(road._pos, ...) > 5,8` devient `road.off_road_dist(...) > 5,8`. Sans ca, la premiere rue laterale sature `norm` a 1,0 en UN echantillon (poids 1,5 = `COMFORT_FULL`) et la course finit a 1 etoile quoi qu'on fasse, **sans erreur de compilation**. Cette ligne est reecrite au **jalon 2**, avant que la ville n'existe — et elle l'est : `LE JUGE NE LIT PLUS LES PRIVES` est vert.

> **Le piege est desarme depuis le J3, et il l'est du bon cote.** Le J2 avait migre l'appel — un seul endroit a corriger au lieu d'un acces prive dissemine — mais `off_road_dist` rendait encore la distance a la **nationale seule**, faute de `town.street_dist()`. La methode existe : elle porte le point dans le repere du bourg et le pose a la grille de 20 m du plan. Ce que `villetest` en mesure, c'est que **la reponse n'est plus une constante** — 9,00 m a 9 m de l'axe du tronc entre deux transversales, 1,20 m pour le meme point ramene sur la voie —, et qu'un **demi-tour au volant** ne sort jamais des 5,80 m : off_road_dist reste sous **3,1 m** sur toute la manoeuvre, onze fois sur onze.
> **Ce qui reste au J4, c'est le juge, pas la distance.** `LE JUGE CONNAIT LES RUES` — 380 m de rues laterales roulees, points `offroad` = **0** — n'existe pas encore, et les seuils contextuels du tableau ci-dessus ne sont pas dans `taxi.gd` : `SPEED_MAX` y vaut toujours 29,2 et `LATERAL_MAX` 4,5, sans branche « en ville ».

---

## 5. LE GPS

### 5.1 D'ou viennent les traits — trois sources, toutes reelles

1. **La ville** : `town.gps_lines()`, un `PackedVector2Array` en metres **monde**, construit une fois a l'armement — **le meme tableau** dont on a extrude les triangles des rues. Le GPS ne peut pas mentir.
2. **Le ruban vivant** : `road._pos`, 150 points de 2 m, dont 276 m devant. Exact — et **deja plus que ce que l'ecran montre** : au zoom par defaut la carte couvre 90 m de large. Le GPS n'a jamais besoin de plus que ce que road.gd tient deja en memoire. C'est pour ca qu'on ne rend **pas** la route reproductible et qu'on ne pre-calcule **rien**.
3. **La trace** : `road.trail()`, la ligne mediane deja passee, un point tous les 8 m.

Au cran le plus large seulement, le ruban s'arrete avant le bord : au-dela on trace un **pointille** (`draw_dashed_line`) vers la ville visee, dont on connait la distance (`edge_length × (1 - nav_progress())`) et le cap (celui du bout du ruban). **Un GPS qui a perdu le detail le dit ; il n'invente pas de virages.**

### 5.2 Projection, orientation, marqueur

Une seule transform par passe, **isotrope, en metres** :
```gdscript
_px_per_m = 196.0 / ZOOM_M[zoom]
draw_set_transform(_origin_px, -cap, Vector2(_px_per_m, _px_per_m))
```
On abandonne `MapScript.at(t) * size` (phone_apps.gd:73-74), une multiplication composante par composante sur un Control de 196 × 251 qui etirait la carte de 30 %. **Un rond-point redevient un rond.**
`draw_set_transform` est gratuit (releve du dossier : +0,04 µs l'appel). Les largeurs de trait sont pre-divisees par l'echelle.

**Correction obligatoire** : `draw_set_transform_matrix(Transform2D())` **avant** les `draw_string` et le marqueur — sinon les glyphes taille 9 sortent a 8 px ou a 50 px, et **tournent avec le cap**.

Cap en haut par defaut (`cap = car.global_rotation.y`), nord en haut au tap sur la carte (`_gui_input` ; le tap synthetique de phone.gd:322-333 y arrive tel quel). Le marqueur est un triangle de 9 px en `draw_colored_polygon`, pose a `(0,50 ; 0,68)` du cadre : **on voit devant soi, pas autour de soi.**

### 5.3 Zoom — trois crans, et la molette n'est pas volee

`ZOOM_M := [220.0, 90.0, 35.0]` metres sur les 196 px de large, soit 0,891 / 2,178 / 5,60 px/m. Defaut : cran 1.
`phone_apps.scroll(dir)` (phone_apps.gd:438-444) est **etendu**, pas detourne :
```gdscript
func scroll(dir: int) -> bool:
    if page == "gps" and _gps_map.zoom_step(dir):
        return true              # un cran de zoom, on reste sur la carte
    ...suite inchangee
```
`zoom_step` rend `false` en butee : le quatrieme cran passe a la page suivante. Borne, pas circulaire — exactement l'argument que phone_apps.gd:438-444 fait deja pour les pages.
**On ne touche pas a `PHONE_WHEEL_LOCK = 0,25 s`** (interaction.gd:87, verrou applique **avant** l'appel a `scroll`, donc incontournable depuis phone_apps) : il mange le rebond de molette de Windows, et sans lui on passerait des rapports. Trois crans prennent **0,75 s**. C'est le prix, il est ecrit.

### 5.4 Itineraire et guidage

Deux etages, cousus. Inter-villes : `MapScript.path()` (Dijkstra sur dix aretes, inchange) avec l'index d'adjacence statique neuf. Intra-ville : `plan.route(su_from, su_to)` sur ≤ 12 noeuds, recalcule seulement quand le tronçon le plus proche change. Le dictionnaire des aretes de l'itineraire est construit **une fois** par `refresh()` — la boucle actuelle est en O(aretes × itineraire), **refaite a chaque image** (phone_apps.gd:74-79).

Le bandeau `_gps_line` (phone_apps.gd:335-348) passe de deux phrases a un vrai guidage :
```
hors ville, arete    "Vers Corbeny — 1 048 m"
hors ville, Y        "Y dans 240 m : gauche Malassis, droite Vieux-Bourg"
en ville, en route   "A droite dans 60 m — rue des Tanneurs"
en ville, arrivee    "Arrivee : 12 rue des Tanneurs, a droite"
```
Le sens de la manoeuvre vient du **signe du produit vectoriel** des deux directions ; la distance est mesuree **le long de la polyligne reelle**, exacte au metre.

### 5.5 Les primitives, choisies sur les releves — et la correction qui compte

Le premier dossier bannissait `draw_circle` (14,7 µs **et son propre appel de dessin**) puis commettait la meme faute avec `draw_polyline` : **34 polylignes = 34 appels de dessin et 315 µs**, contre 1 appel et 27 µs pour un `draw_multiline` equivalent.

| Element | Primitive | Appels |
|---|---|---|
| fond | `draw_rect` | en lot |
| **rues + tronc de la ville** | **`draw_mesh` d'un `ArrayMesh` PRIMITIVE_TRIANGLES bati une fois** | **1** (4,8 µs, constant) |
| trace (≤ 120 pts, decimee) | `draw_multiline` | 1 (~24 µs) |
| ruban vivant (decime a 40 pts) | `draw_polyline` | 1 (~15 µs) |
| itineraire (≤ 30 pts) | `draw_polyline` | 1 (~20 µs) |
| marqueur + destination | `draw_colored_polygon` | 1 (12 µs) |
| ≤ 4 etiquettes | `draw_string` | en lot (~10 µs) |

Le maillage GPS est reconstruit **au changement de zoom seulement** (les largeurs sont en metres, calculees pour le cran courant) — jamais par image.
**Budget : ~165 µs de `_draw`, ~7 appels de dessin.** Seuils du banc : **≤ 300 µs et ≤ 8 appels**, releves aux trois crans.

**Aucun `draw_circle`, aucun polygone d'ilot.** Les pates de maisons ne sont pas dessines : dans un GPS de nuit, les rues sont claires sur du noir, et le noir entre elles fait les blocs. Plus lisible a 149 × 204 pixels reels, fidele au jeu, et gratuit.

### 5.6 Lisibilite

Le cadre mesure **196 × 251 texels** a (10, 55) dans le viewport de 216 × 384 (phone.gd:53), affiche sur ~**149 × 204 pixels reels** en main (0,34 m de l'oeil, fov 50, fenetre 900 px), en filtre NEAREST : **rien sous 2 px n'est fiable**.

| | z0 (220 m) | z1 (90 m) | z2 (35 m) |
|---|---|---|---|
| nationale `clamp(6,8·ppm, 3, 10)` | 6,1 px | 10,0 | 10,0 |
| rue `clamp(5,2·ppm, 2,5, 7)` | 4,6 px | 7,0 | 7,0 |
| rapport | **1,31** | 1,43 | 1,43 |

Le rapport au cran large vaut **1,31, pas 1,4** — c'est justement la que tout est le plus fin.
Palette espacee d'au moins trois crans de tramage (32 niveaux, pas de 0,031) : rue `(0,42 / 0,46 / 0,54)`, nationale `(0,75 / 0,80 / 0,88)`, trace `(0,26 / 0,30 / 0,37)`, itineraire `(0,95 / 0,62 / 0,25)`.
**`clip_contents = true` est OBLIGATOIRE** et absent aujourd'hui (phone_apps.gd:197-201) : des que la carte se deplace, le dessin peint par-dessus la barre d'etat.
**Au berceau**, l'ecran entier ne pese que 58 × 111 pixels reels et la carte 53 × 72 : un plan de rues n'y est pas lisible. `_gps_map.compact = phone.docked and not phone.viewing` : en mode compact, seuls l'itineraire (une polyligne epaisse), le marqueur et une grosse fleche de manoeuvre avec sa distance.

### 5.7 Le correctif sans lequel rien ne bouge — phone.gd:212-215

**[verifie]** Dans la branche `viewing`, `_process` ne fait que poser `UPDATE_ALWAYS` ; `_apps.refresh()` n'est appele qu'a phone.gd:220 (pouls du berceau), 233 (`set_screen_power`), 245 (`set_viewing`) et 258 (`set_docked`) — **jamais pendant qu'on regarde l'ecran**. Le SubViewport se re-rend a 100 % du temps sur un contenu **fige**, et le commentaire de phone_apps.gd:296-298 promet l'inverse.

On separe :
- `refresh()` — les textes, au changement de page et au pouls du berceau : **inchange**.
- `tick(delta)` — **neuf**, appele chaque image en consultation : `_gps_map.queue_redraw()`, et les textes a 4 Hz seulement (`refresh()` appelle `MapScript.path` et reconstruit des chaines : pas soixante fois par seconde).

Cout honnete : `tick` **ajoute** ~165 µs de CPU par image quand le telephone est en main (1,9 % du budget de 8,69 ms). Ce n'est pas la suppression d'un gaspillage, c'est un achat — mais on cesse de payer un rendu complet pour une image morte.

---

## 6. LES JALONS

> **Convention.** Chaque banc imprime `NOM EN MAJUSCULES : true/false   (releve chiffre)`. **La regle d'origine — les valeurs ci-dessous sont des SEUILS, pas des releves — ne vaut plus que pour le J4 et le J5** : les quatre premiers jalons sont livres, et leurs lignes portent maintenant les **releves reels a cote de leurs seuils**. Les captures partent a **87** — 81 a 86 sont deja prises (`81_ville`, `82_y`, `83_gps` par `maptest` ; `84_offre`, `85_embarquement`, `86_avis` par `faretest`) **[verifie]**.
> Aiguillage : une chaine de `elif` dans `_ready` de main.gd, avant `faretest` — six bancs de ce plan y sont branches, `plantest`, `rubantest` et `villetest` compris.

> **L'ETAT REEL DES SIX JALONS.** **Quatre sont livres et tournent ; deux ne sont pas commences.** Ce tableau est le premier de ce document a dire ou en est le monde plutot que ou il devrait aller, et c'est lui qu'il faut lire avant les listes qui suivent : sous J0, J1, J2 et J3, les puces portent des **releves** ; sous J4 et J5, elles portent encore des **seuils**.
>
> | Jalon | Etat | Banc | Compte |
> |---|---|---|---|
> | **J0** — l'ecran qui vit | **livre** | `phonetest` etendu | **18/18** *(reporte, non relance ici)* |
> | **J1** — le plan et la geometrie partagee | **livre** | `plantest`, deterministe | **9/9** — **relance pour cette version** |
> | **J2** — le trou, la tangente et le juge | **livre** | `rubantest` | **9/9** dix fois *(reporte)* |
> | **J3** — la ville posee | **livre** | `villetest` | **11/11** — **relance DIX FOIS pour cette version** |
> | **J4** — le metier en ville | **pas commence**, deux morceaux exceptes | `adressetest` n'existe pas | — |
> | **J5** — le GPS | **pas commence** | `gpstest` n'existe pas ; `scripts/gps_map.gd` non plus | — |
>
> *(Les deux lignes marquees « relance » sont les seules que cette version a mesurees elle-meme ; les autres sont rapportees et **datent du jour ou leur jalon a ete livre**. C'est exactement la distinction que l'annexe B demande de tenir : un chiffre recopie n'est pas un releve.)*
>
> **CE QUI MANQUE AU J4, NOMMEMENT, ET QUI SE LIT D'UN `grep`** : `taxi.gd` n'a **aucun** seuil contextuel — `SPEED_MAX = 29,2` et `LATERAL_MAX = 4,5` y sont des constantes sans branche « en ville » —, pas de `_at_address()`, pas de grace de calage, pas de raclement hors rue ; `sleep.gd` n'a pas d'entree `"cafe"` dans `drink_boost` ; le Y n'est pas repousse (§3.8). **Deux morceaux du J4 sont pourtant deja la** : `off_road_dist` est branche dans `taxi.gd` depuis le J2, et la derive metrique est corrigee dans `main.gd` avec sa ligne `LA METRIQUE NE DERIVE PLUS` dans `maptest` (§3.8). Un jalon n'est pas une boite : ce qui etait pret est parti plus tot.
>
> **CE QUI MANQUE AU J5** : tout. `phone_apps.gd` porte encore sa classe interne `GpsMap`, et le J0 lui a seulement donne un `tick()` qui la redessine.

### J0 — L'ECRAN QUI VIT — **LIVRE** *(une heure, ne dependait de rien)*
`phone.gd:212-215` gagne `_apps.tick(delta)` ; `phone_apps.gd` gagne `tick()`.
**Banc : `phonetest` etendu** (main.gd:5010).
- `L'ECRAN BOUGE EN MAIN` — deux captures du SubViewport a 30 images d'intervalle, voiture a 20 m/s : **> 200 pixels differents**. (Avant : 0.)
- `LE COUT RESTE PLAT` — temps d'image consulte contre non consulte : **ecart < 0,5 ms**.

### J1 — LE PLAN ET LA GEOMETRIE PARTAGEE — **LIVRE**
`scripts/strip.gd` (extraction de road.gd:397-451, road.gd branche dessus), `scripts/town_plan.gd`, `map.gd` + `seed` + `_ADJ`. **Rien dans le monde ne change.**
**Banc : `plantest`** — headless, instantane, plus huit plans traces en ASCII.
- `CORBENY EST TOUJOURS CORBENY` — trois reconstructions du meme plan : tableaux identiques au bit.
- `LES HUIT VILLES SONT DIFFERENTES` — nombres de rues et longueurs cumulees deux a deux distincts.
- `TOUT CARREFOUR EST UN RECTANGLE` — ecart a l'angle droit en curviligne **< 0,001 rad** sur les **73** carrefours des huit bourgs (et non « 8 × 8 = 64 » : le compte est `n_transversales × (1 + n_paralleles)`, de 6 a 12, §4.2). Releve : **0,000000 rad**.
- `AUCUNE RUE NE SE CROISE HORS CARREFOUR` — force brute sur toutes les paires : **127 paires examinees, 0 croisement**.
- `LE GRAPHE EST CONNEXE ET BOUCLE` — `route()` non vide de la porte d'entree vers les 4 adresses ; cycles = aretes − noeuds + morceaux **>= 1**. Releve : **1 seul morceau par bourg, cycles mini 2, 32/32 itineraires du panneau a une porte, 3 rues au plus**.
- `AUCUN BATIMENT SUR UNE RUE` — **0 empietement** sur les **515 batiments** des huit bourgs (et non ~960 : le plan les comptait a 120 par ville, ni 562 : c'etait avant que l'abord de carrefour se mesure sur l'empreinte, voir §4.3), soit **3 153 couples mur/rue** examines. La marge se mesure **du mur au BORD DE TROTTOIR de la rue d'en face, pas a son axe** : le bourg a deux emprises, 4,2 m de demi-emprise pour une rue et 8,0 pour le tronc, et un seuil unique a 4,5 m derivait de la premiere en laissant deux maisons **dans** le trottoir de la nationale (town_plan.gd:106-117). Releve actuel : tronc **+0,896 m**, transversale **+1,456**, parallele **+0,541** ; **pire cas +0,541 m** sur Malassis, sur une parallele.
  **Ce que cette ligne ne regarde pas** : le **centre des carrefours**. Elle compare des murs a des **rues**. C'est par ce trou-la que 120 couples mur/carrefour sous les 12 m ont vecu (§4.3) sans qu'aucun banc rougisse, et il est toujours ouvert.
- `LES ADRESSES SONT SUR UN TROTTOIR` — **32 portes pour 8 bourgs** ; 0 sur le tronc, 0 hors de la bande de trottoir de leur rue, 0 hors de leur rue. Marges mini : **+0,80 m au caniveau, +0,80 m au mur, +1,0 m au bout de la rue**. Le seuil « ecart a l'axe entre 2,6 et 6,0 m » qu'annoncait ce plan **mesurait une constante** : une porte vaut par construction `point(i, t, side × walk_mid(i))`, donc son ecart a l'axe **est** `walk_mid(i)` — 3,40 m sur une rue —, et le releve l'imprimait tout haut, « de 3.40 a 3.40 ». Une fenetre qui entoure une constante de 0,8 m d'un cote et de 2,6 m de l'autre ne peut rien attraper. La bande de trottoir depend de l'emprise (2,6 a 4,2 m sur une rue, 5,8 a 8,0 sur le tronc) : le test est donc **par rue porteuse**, plus le refus du tronc **dans le verdict** et le compte de quatre portes par ville (main.gd:5765-5810).
- `LA GRILLE REPOND JUSTE` — 2 000 points tires, dont 672 a 600 m du bourg : **0 desaccord** avec le balayage complet, pres comme loin ; troncons visites par requete **< 12**. Releve : **4 au maximum**, cout moyen **1,73 troncon** sur un bourg de 5 rues et **2,13** sur un bourg de 7 ; loin, 4,98 et 6,70 — le balayage complet, assume.
- `LA VILLE SE COUD AU RUBAN` — les cotes que la ville donne a son tronc sont **celles de la nationale, au bit** : pas 2,00 = 2,00 m, demi-chaussee 3,40 = 3,40, accotement 2,40 = 2,40, sur **8 troncs sur 8**.
  **Cette ligne compare des CONSTANTES, pas de la geometrie**, et le banc le dit lui-meme a la ligne suivante. Ce qui roule et qui mesure, c'est `LE RUBAN EST SANS COUTURE` dans `maptest`. Et ce qui prouvera que les deux ne se dessinent pas l'un sur l'autre, c'est `LE MASQUE EST OUVERT`, au **J3** (§3.3) — pas ici.
- `LE RUBAN N'A PAS BOUGE` — `maptest` rejoue apres l'extraction de `strip.gd` : pas maxi **< 3,0 m**, virage maxi **< 4,0 deg/pas** (les deux invariants de `maptest`, a l'identique).

*(`plantest` porte les **neuf premieres** lignes de cette liste et imprime **9/9** ; la dixieme est une relance de `maptest`. Et les deux dernieres de `plantest` sont d'un genre plus faible que les sept autres : `LA VILLE SE COUD AU RUBAN` compare une constante a une constante, et `LA GRILLE REPOND JUSTE` mesure une structure de recherche, pas la ville. Sept lignes mesurent vraiment le plan.)*

### J2 — LE TROU, LA TANGENTE ET LE JUGE — **LIVRE**
`road.gd` seul : tangente d'avance (196/200), `_simulate_town_path` + consommation dans `_append_sample`, `_town_in`/`_town_out` poses **a l'armement**, courbure bornee `TOWN_CURVE`, masque dans `strip.ribbon` et `_dashes`, `_place_props` filtre par categorie (portail exempte), `town_left`, `off_road_dist`, `in_town`, `trail`, `suspend_town`. **taxi.gd:409 migre sur `off_road_dist` DANS CE JALON.** town.gd encore l'ancienne.
**Banc : `rubantest`** — le premier banc du ruban ; il n'en existe aucun aujourd'hui.
> **ETAT DU BANC — ET IL A CHANGE TROIS FOIS PENDANT QUE CETTE SECTION S'ECRIVAIT.** `rubantest` existe et tourne. La courbure du ruban est retiree a chaque lancement (`_rng.randomize()`), donc **un vert unique ne prouve rien** : tout ci-dessous est compte sur **dix** lancements consecutifs.
>
> **Etat de depart : six lignes vertes dix fois sur dix, trois rouges.** Les trois rouges n'etaient pas trois bogues du meme genre, et c'est ce que le releve a servi a trancher :
>
> | Invariant | Verts / 10 | Releve | Nature |
> |---|---|---|---|
> | `ROULER EN TRAVERS…` | **10** | 0 echantillon de defile, seuil 2 | — |
> | `LA COUTURE EST NETTE` | **10** | 0,0000 m d'ecart, seuil 0,02 | — |
> | `LA TRAVERSEE NE SE REPLIE PAS` | **10** | courbure 0,00067 a 0,00143 ; compression 3,9 a 8,6 % | — |
> | `LE RUBAN RESTE SANS COUTURE` | **10** | pas 2,000 m ; virage 0,45 a 1,02 deg/pas | — |
> | `LE PORTAIL SURVIT` | **10** | ecart 0 echantillon, seuil 5 | — |
> | `LE JUGE NE LIT PLUS LES PRIVES` | **10** | 0 resultat | — |
> | `LE VOLANT TRAVAILLE EN VILLE` | **1** | silence de 7,7 a **21,1 s**, seuil 8,0 | **une decision du plan etait fausse** |
> | `AUCUN ARBRE NI POTEAU DANS LA VILLE` | **3** | 0 a 29 arbres dans la zone silencieuse | **la fenetre du filtre etait trop courte** |
> | `LA TRACE SE RECOUD AU Y` | **1** | saut de 8,00 a **16,00 m**, seuil 12 | **un compteur lisait un index** |
>
> **Les trois ont ete corrigees dans `road.gd` pendant la redaction**, et les trois corrections sont de natures differentes — c'est le seul enseignement que ce tableau doit laisser :
> - le **volant** a demande de changer le monde (le slalom, §3.2) : le banc avait raison, le plan avait tort ;
> - les **arbres** ont demande d'elargir une fenetre : `quiet` retombe desormais sur `_town_g`, la ville **promise**, quand `_town_in` n'existe pas encore — les 20 echantillons de `PAD` d'avant le panneau sont enfin couverts ;
> - la **trace** a demande de compter au lieu de lire : `_trail_due` compte les echantillons **pousses**, la ou l'ancienne cadence testait un multiple de `TRAIL_EVERY` sur `_index0` — que `_swap_to_branch` repose, et dont le saut enjambait un point une fois sur deux.
>
> **Etat au moment ou ces lignes ont ete ecrites : les huit premieres lignes vertes, la neuvieme dependant du reglage en cours.** Le compte exact n'etait pas fige, et c'etait volontaire : `TOWN_WEAVE` bougeait encore. **Relancez dix fois.**
>
> **ETAT REPORTE AU J3 : `rubantest` est 9/9, dix lancements.** Ce chiffre-la n'a pas ete remesure par la version de ce document qui l'ecrit — seuls `plantest` et `villetest` l'ont ete — et il **date du jour ou le J3 a ete livre**. La regle de l'annexe B s'applique a lui comme aux autres : avant de s'en servir, relancez.

- `ROULER EN TRAVERS NE FAIT PLUS AVANCER LA ROUTE` — 100 m perpendiculaires : `head_index()` bouge de **< 2 echantillons**. Releve : **0**, dix fois sur dix. Et le releve de reference, celui du nez de la voiture, vaut **261 echantillons**, pas les 38 que §3.1 calculait — **un facteur sept** : le nez ne rate pas seulement l'avance, il en fabrique. C'est la ligne la plus rentable du J2.
- `LA COUTURE EST NETTE` — ecart entre le dernier sommet emis avant la ville et le premier point de la traversante : **< 0,02 m**, mesure **apres au moins 5 km roules** (l'ulp du float32 vaut 1 mm a 10 km : un banc lance a froid prouverait la mauvaise chose).
- `LA TRAVERSEE NE SE REPLIE PAS` — courbure maxi sur les 171 echantillons **<= 0,0016 rad/m** ; compression laterale a 60 m de l'axe **< 12 %**.
- `LE RUBAN RESTE SANS COUTURE` — pas maxi **< 3,0 m**, virage maxi **< 4,0 deg/pas** partout, y compris aux deux raccords.
- `LE VOLANT TRAVAILLE EN VILLE` — `|car.steer|` doit depasser 0,04 au moins une fois toutes les 8 s ; le banc conduit **au volant et non au rail**, a 12,5 m/s, sur une traversee de 21,0 s.
  **C'est la ligne qui a fait tomber la decision 4**, et elle merite d'etre lue deux fois. Avec la courbure qui erre, silence maxi releve sur dix lancements : **7,7 / 11,3 / 11,7 / 12,6 / 16,0 / 16,8 / 16,9 / 17,1 / 17,5 / 21,1 s** — neuf au-dessus des 10 s de `mono_after`, un de 21,1 s sur 21,1, **1 vert sur 10**. Avec le slalom : silence **3,9 a 10,6 s**, portion la plus plate tombee de **178 m a 6 m**, majoritairement vert. Le raisonnement complet — et l'inegalite qui interdisait a jamais de s'en sortir par le plafond de courbure — est en **§1** et **§3.2**.
  **On ne l'a pas maquillee, et c'etait la tentation :** baisser son seuil a 22 s l'aurait rendue verte sans rien changer au jeu. Elle demande une chose vraie — que la traversee reveille — et tant qu'elle repondait non, c'est le monde qui avait tort. **Le banc a gagne contre le plan. C'est pour ca qu'on ecrit des bancs.**
- `AUCUN ARBRE NI POTEAU DANS LA VILLE` — **0** sur les 191 echantillons ou road.gd promet le silence, contre ~105 arbres et ~21 poteaux que le tirage y promettait (p = 0,55 par echantillon).
  **Etait rouge 7 fois sur 10, et le banc disait lui-meme ou :** 0 sur les 171 echantillons que la ville dessine **a partir du panneau**, dix fois sur dix, mais jusqu'a 15 arbres dans les **20 echantillons de `PAD` d'avant le panneau** — nes **avant** que `_town_in` n'existe, puisque les bornes se posent a l'armement et que la ville dessine `PAD` echantillons plus tot que ca. **Ce n'etait pas le filtre qui etait faux, c'etait la fenetre**, et c'est la fenetre qui a bouge : `quiet` retombe maintenant sur `_town_g` — la ville **promise**, connue bien avant l'armement — quand `_town_in` n'est pas encore pose. La ligne est verte.
- `LE PORTAIL SURVIT` — un portail demande a un echantillon interieur a la ville est bien pose : `road.portal_index >= 0`, ecart au rendez-vous **< 5 echantillons**.
- `LE JUGE NE LIT PLUS LES PRIVES` — `grep "road\._" scripts/taxi.gd` : **0 resultat**.
- `LA TRACE SE RECOUD AU Y` — aucun saut > 12 m dans `trail()` apres un `_swap_to_branch`.
  **Etait rouge 9 fois sur 10**, releve **8,00 / 13,99 / 13,99 / 14,00 / 14,00 / 15,99 / 15,99 / 15,99 / 16,00 / 16,00 m** sur les 28 points poses autour de l'echange. Les valeurs n'etaient pas quelconques : **1,00, 1,75 et 2,00 fois la cadence de 8 m** — la trace ne derivait pas, elle **perdait un point**. La cause etait de la meme famille que le nez de la voiture au §3.1 : **on lisait un index la ou il fallait compter**. La cadence testait un multiple de `TRAIL_EVERY` sur `_index0`, et `_swap_to_branch` repose `_index0` sur `_fork_g + 1 + start` ; quand le saut enjambait le multiple, le point n'etait jamais pousse. Un compteur d'echantillons **pousses** (`_trail_due`) ne connait pas les index et ne peut pas les rater. Releve apres correction : **8,00 m, 1,00 fois la cadence**, sur toute la nuit. La ligne est verte.
  *(Le seuil n'a pas bouge d'un metre. Elargir 12 a 17 aurait rendu la ligne verte sans rendre un seul point a la trace — et le GPS aurait dessine un trait qui saute.)*

### J3 — LA VILLE POSEE — **LIVRE**
`scripts/town.gd` reecrit : maillage a 6 surfaces bati en **quatre etapes**, trois lumieres mobiles a `light_volumetric_fog_energy = 0,15`, panneaux d'entree et de sortie, plaques de rue, `draws_trunk()`, `contains()`, `street_dist()`, `address_pose()`, `gps_lines()`, `set_dark()` — **et un repere par ville**, cousu dans les surfaces 5 et 6, que ce plan n'avait pas prevu au J3.
**Banc : `villetest` — 11/11, ONZE lancements** : dix d'affilee, puis un de controle apres que `road.gd`, `town.gd` et quatre `.glb` de repere eurent change sous le banc. La courbure du ruban est retiree a chaque fois. Captures `87_ville_entree.png`, `88_ville_carrefour.png`, `89_ville_rue.png` et **`90_ville_repere.png`** — et non `90_ville_cauchemar.png` comme ce plan l'annoncait : la ville teintee du cauchemar n'a **ni capture ni ligne de banc** (§3.10).

> **LES QUATRE PROMESSES DU J2 SONT TENUES.** `road.gd` demandait `draws_trunk()`, `contains()`, `street_dist()` et `set_dark()` derriere quatre `has_method` qui rendaient faux ; les quatre existent. Le masque creuse, la garde du demi-tour tient, le juge connait les rues, et la ville du cauchemar s'eteint — cette derniere sans que rien ne la mesure.
>
> **ET TROIS DES ONZE LIGNES CI-DESSOUS NE MESURENT PAS CE QUE CE DOCUMENT DEMANDAIT.** Ce n'est pas un ecart de discipline : dans les trois cas le banc livre mesure **mieux** que ce que le plan avait ecrit, et c'est le plan qui a ete recale sur lui. Les trois sont signalees d'un **[ECART]** et resumees en annexe B.4.

- `LE MASQUE EST OUVERT` — **la ligne qui manquait, et elle est verte.** Ville armee et batie, `road._town_ready` vrai ; on compte les triangles emis par `_rebuild()` dont **les deux extremites** tombent entre `_town_in` et `_town_out + PAD`. **Releve, onze fois sur onze : 0** sur les trois surfaces du ruban et sur les quatre villes auditees — et **2 262 a 3 076** dans la MEME fenetre, a la MEME image, une fois `road._town_in` ramene a −1 a la main. Meme ruban, meme fenetre, meme code de comptage.
  **La couture est mesuree SUR LE DESSIN** : ecart maxi entre le dernier sommet d'asphalte que road.gd emet avant le trou et le premier que la ville pose — **0,000000 m sur 12 sommets, seuil 0,001**. Son temoin dit qu'elle n'est pas une constante : decaler de 5 cm le seul echantillon `_pos[_town_in]` et re-trianguler la porte a **0,0498 a 0,0500 m** ; le remettre la ramene a zero.
  **Pourquoi `LA COUTURE EST NETTE` ne la remplacait pas :** cette derniere (rubantest) compare les 150 transforms pre-calculees a l'armement a celles que `_append_sample` repose ensuite. C'est une identite de **donnee**, et elle etait vraie pendant tout le temps ou le masque ne creusait rien. **Elle ne regarde aucun triangle.**
- `LA VILLE TIENT EN SIX SURFACES` — **1 `MeshInstance3D`, 6 surfaces, 0 ville hors des six.** Pire compte releve : **6 097 sommets et 5 370 triangles** (Corbeny) pour des seuils de **8 000 et 6 500** — il reste **1 903 sommets et 1 130 triangles**, soit 24 % et 17 % du seuil. Les quatre bourgs ouverts : Corbeny 6 097/5 370, Malassis 5 809/4 844, **Saint-Elme 5 733/4 786 puis 5 757/4 830** (son totem a ete rebati plus haut au dixieme lancement, cf. §4.6), La Fresnaie 5 635/4 624.
  **Les seuils n'ont pas bouge, et c'est le budget qui est venu a eux** : ils avaient ete poses a 8 000 / 6 500 contre une estimation de ~5 780 / ~4 790 qui s'est revelee **basse de 5,5 %**, faute d'avoir compte le repere (§4.6). Un seuil couvre ce qu'on n'a pas mesure ; ici, ce qu'on n'avait pas mesure valait 300 sommets, et la marge l'a absorbe sans qu'on y touche.
- `ELLE SE BATIT SANS SAUTER UNE IMAGE` — douze reconstructions du meme bourg, journal coupe, chaque etape appelee et chronometree a part. **Pire etape : la 2 (accotements, trottoirs, peinture), et jamais une autre aux dix lancements — 1,40 a 1,89 ms pour un seuil de 4,0** ; la plus longue des quarante-huit mesures d'un lancement va de 1,73 a 2,81 ms. Medianes : chaussees 0,56 a 0,74, trottoirs 1,40 a 1,89, bati 1,29 a 1,61, emissif 1,04 a 1,32 ms.
  **L'armement est mesure dans le PIRE CAS** que road.gd sache produire : une image qui pousse **150 echantillons**, le plafond exact de son garde-fou, avec `town.arm()` dedans. Un banc qui mesurerait le cas facile — une image qui pousse UN echantillon — annoncerait un cout qu'aucun joueur ne paie.
- `LES APPELS DE DESSIN SONT COMPTES` — **[ECART]** hausse **27 a 29 appels par image sur les quatre vues, onze fois sur onze, pour un seuil de 60**. Releve en A/B : **460 a 499 appels le bourg allume contre 431 a 471 eteint**, medianes de 120 images de chaque cote, la visibilite basculee toutes les quatre images sur la MEME traversee.
  **CE N'EST PAS LA MESURE QUE CE PLAN DEMANDAIT, ET LA SIENNE AURAIT MENTI.** Il demandait « sur la nationale nue, puis au centre de la ville ». Le banc la releve quand meme, et la voici : la **nationale nue et plantee demande 1 257,5 a 1 639,4 appels par image**, le bourg **460 a 499**. La mesure du plan aurait donc rendu une **BAISSE de mille appels**, et elle aurait conclu que la ville est gratuite — ou plutot qu'elle rembourse.
  **La raison n'est pas dans la ville, elle est dans ce que la ville fait TAIRE.** `_place_props` eteint les arbres, les poteaux, la police, le geant et l'etrangleur sur les echantillons de la traversee : un arbre tombe a **p = 0,55 par echantillon** sur la nationale, et **zero** dans le bourg. Comparer deux ENDROITS, c'est comparer un bourg sans arbres a une nationale qui en porte cent, avec le tirage de la nuit par-dessus. **On bascule donc la ville, on ne change pas de paysage** : seul `town.visible` bouge, quatre metres separent deux blocs consecutifs a 12,5 m/s, et les deux medianes portent sur le meme decor.
- `TOUT EST A L'ENDROIT` — **[ECART]** ce plan demandait l'aire signee « sur les **8 paves de carrefour** et sur toutes les bandes ». **Il n'y a aucun pave de carrefour** (§4.6), et la ligne livree est plus large : elle parcourt **TOUS les triangles du bourg** — **19 624 sur les quatre villes** (19 668 au dixieme lancement, le totem de Saint-Elme ayant grossi entre-temps), murs, toits, fenetres, mats et repere compris. **Releve : 0 aire du mauvais signe, 0 normale geometrique contredisant la normale d'ombrage, 0 triangle degenere.**
  **Et elle mesure DEUX choses la ou le plan n'en demandait qu'une, parce qu'une seule ne suffisait pas.** L'aire signee en (x, z) ne parle que des triangles **a plat** — 12 602 des 19 624, dont **92 qui regardent le SOL** et dont le signe attendu est donc **inverse**, par construction et pas par erreur ; un mur vertical se projette sur un segment, son aire vaut zero, et lui demander un signe serait demander n'importe quoi. La seconde mesure, **normale geometrique contre normale d'ombrage**, vaut pour les 19 624. Le pire produit releve vaut **+0,946**, la ou la chaussee de la nationale vaut +1.
  **Le signe de reference est RELEVE sur la nationale, pas ecrit** — « enroulement horaire vu du dessus » est une phrase, et le depot a paye deux fois pour avoir cru la lire. Les **776** triangles a deux faces (les `_quad2` des tetes de lampadaire, qui emettent expres les deux enroulements) sont reconnus a ce que le meme triple de sommets existe deux fois dans la surface : une propriete du tampon, pas une liste de cas particuliers a tenir a jour.
- `TROIS LUMIERES, JAMAIS SOUS LE NEZ` — **3 `OmniLight3D` exactement, 3 allumees a chaque image** de la traversee et du retour ; **17 a 23 allumages releves, le plus proche a 60,0 a 60,7 m pour un plancher de 60,0** ; `light_volumetric_fog_energy` = **0,15** pour un plafond de 0,2. La distance d'allumage se prend a l'image **d'avant**, et c'est oblige : `_relight` tourne apres le `_process` du banc, et la mesurer depuis la position courante rognerait 40 cm sous un plancher de 60,0 — un vert deviendrait rouge sans que la ville ait rien fait.
  Temoin : sur la traversee, **le mat le plus proche que la voiture ait croise etait a 7,18 m** — une lampe qui prendrait le plus proche au lieu du plus proche **au-dela de 60 m** se serait allumee la, sous le nez.
- `AUCUNE OMBRE NEUVE` — **2** lumieres a ombres dans toute la scene, bourg arme : `HeadlightL` et `HeadlightR`. Temoin : `shadow_enabled` remis a vrai sur une seule lampe du bourg et le compte passe a 3 ; remis a faux, il retombe a 2.
- `LE DEMI-TOUR TIENT` — **[ECART]** ce plan disait « 200 m dans la ville, demi-tour ». **Le banc le fait AU CARREFOUR** — la transversale la plus proche de 200 m apres le panneau, `s = 212 m` sur Corbeny — **au volant, plein braquage a 4 m/s, 180 degres de cap rendus**. Releve : `off_road_dist` **2,88 a 3,08 m au plus dans l'arc**, autant sur la manoeuvre entiere, **1,20 m sur la traversee d'approche**, pour un seuil de **5,80** ; la voiture revient a 11,8 a 12,0 m du panneau d'entree, et `contains()` repond vrai sur **toutes** les images du demi-tour et du retour.
  **LE CARREFOUR N'EST PAS UNE COQUETTERIE, C'EST DE L'ARITHMETIQUE.** A 4 m/s, `grip = 0,8` et `stability = 0,938` (car.gd), le lacet vaut 1,15 × 0,8 × 0,938 = 0,86 rad/s et le rayon **4,6 m** : un demi-tour emmene la voiture a `1,2 − 2 × 4,6 =` **8,0 m de l'axe du tronc**, hors des 5,80 m de chaussee plus accotement. Ce qui la rattrape, ce n'est pas la nationale, **c'est l'AUTRE rue** : au point le plus ecarte elle est sur l'axe de la transversale, et `off_road_dist` prend le plus petit des deux.
  **Le temoin le dit en un chiffre, et c'est le plus utile du banc** : le meme point pose a 9 m de l'axe du tronc **soixante metres plus loin**, `s = 272 m`, **entre deux transversales**, rend **9,00 m** — une fois et demie le seuil de 5,80. Ramene sur la voie, il rend 1,20 m. **La mesure n'est pas une constante, et le demi-tour n'est pas gratuit partout.**
  **CE QUE CA VEUT DIRE POUR LE JOUEUR, ET IL FAUT L'ECRIRE AINSI :** on fait demi-tour **aux croisements**, pas n'importe ou. Se retourner au milieu d'un pate de maisons met la voiture dans un jardin — le juge de course parlera, et le raclement du J4 la reprendra. C'est vrai d'une vraie rue, et c'est ce qui rend une ville sans collision lisible quand meme : **la geometrie dit non a la place des murs.**
- `LA VILLE NE S'ETEINT PAS DEDANS` — **0 image eteinte** sur les **1 583 a 2 721** images de la traversee, du demi-tour et du retour, onze fois sur onze. Les **240** images ou le banc eteint la ville **lui-meme** pour le A/B sont comptees a part et imprimees : le temoin de la ligne est son propre compteur, qui les voit.
- `DEUX VILLES JAMAIS ENSEMBLE` — **6 bourgs armes, 5 marges** mesurees entre l'extinction de l'un et l'armement du suivant ; la plus courte vaut **272 a 294 m** pour un seuil de 100, et **0 image** ou le nom a change sans que la ville se soit eteinte. La marge se compte **en metres de route**, pas en images : le noeud-ville etant unique, deux bourgs ne peuvent pas etre a l'ecran ensemble par construction ; ce que la ligne surveille, c'est qu'`arm()` ne tombe pas sur une ville encore visible.
- `LE COUT NE SE VOIT PAS` — **[ECART]** vert dix fois sur dix, **et la ligne est fragile**. Le bourg est traverse a 12,5 m/s, sa visibilite basculee toutes les quatre images. Releve sur dix lancements : **mediane +0,35 ms, soit +3,8 %** ; moyenne +0,20 ms (+2,0 %) — **pour une etendue qui va de −1,34 ms (−11,2 %) a +1,20 ms (+8,9 %)**, seuil 15 %.
  **LE CHIFFRE EST BON, L'INSTRUMENT EST TROP GROSSIER.** L'etendue de la distribution vaut **20,1 points de pourcentage**, soit **cinq fois** la mediane qu'elle entoure ; en millisecondes, 2,54 ms d'etendue pour 0,35 de mediane. **Trois lancements sur dix rendent un cout NEGATIF** — le bourg rendrait l'image plus rapide —, ce qui n'a aucun sens pour cinq mille triangles de plus : c'est la signature d'un **ecart entre deux medianes bruitees**, pas d'une mesure. Le denominateur n'aide pas : l'image « ville eteinte » va de **7,94 a 13,79 ms** d'un lancement a l'autre, un facteur 1,74, si bien qu'un meme cout absolu s'imprime en pourcentages qui varient du simple au double.
  **Ce qui a deja ete corrige, et qui n'a pas suffi.** La premiere version mesurait **a l'arret** au coeur du bourg, ou l'image tombe a ~3 ms : 0,3 ms y pesait dix pour cent, pour un seuil de quinze. Le banc roule maintenant et prend le denominateur du **jeu**. Ca a rendu le chiffre juste ; ca n'a pas rendu l'instrument fin.
  **CE QU'IL FAUDRAIT POUR LE MESURER PROPREMENT — et le depot sait deja le faire, au J0.** `LE COUT RESTE PLAT` (phonetest) ne compare pas deux medianes : il prend la mediane des **differences APPARIEES**, une par bloc, **en inversant l'ordre des deux cotes d'un bloc a l'autre** — ce qui annule toute derive lente de la machine —, et **il imprime sa propre resolution**, mesuree sur place, en comparant la mediane des 48 premiers blocs a celle des 48 derniers : deux mesures independantes de la meme chose. Une ligne qui ne connait pas sa resolution ne sait pas si son releve est un signal.
  **Les trois corrections a faire, dans cet ordre** : (1) **apparier les blocs** et prendre la mediane des differences ; (2) **imprimer la resolution** mesuree sur place ; (3) **poser le seuil en millisecondes et non en pourcentage** — un budget d'image se compte en ms, et le pourcentage n'a fait ici que multiplier le bruit par l'inverse d'un denominateur qui bouge. Tant que ce n'est pas fait, **ce que cette ligne prouve, c'est que le cout est petit devant le bruit ; pas qu'il vaut 4 %.**
  *(Les statistiques ci-dessus portent sur les **dix** lancements d'affilee. Le onzieme, de controle, a rendu **+0,45 ms / +3,0 %** et 11/11. L'etat remis a cette version signalait **un rouge sur dix**, et la dispersion relevee ne l'exclut pas : entre le pire releve, +8,9 %, et le seuil de 15, il y a **moins d'un tiers de l'etendue de la distribution**.)*

> **ET LE BANC PORTE NEUF TEMOINS, QUI NE SONT PAS DES INVARIANTS.** Chaque ligne du dessus est reprise sur une geometrie ou une liste d'evenements **deliberement fausse**, avec le meme code de mesure : un seul triangle retourne dans une copie de la surface 0 fait passer le compte de 0 a **1 sur 774** ; `_town_in` ramene a −1 fait passer le masque de 0 a **2 262-3 076** triangles ; la marge entre deux villes ramenee a 60 m fait rendre **false** a la ligne qui rend true a 272. **Les temoins portent un chiffre et le mot ROUGIRAIT, jamais un verdict** — le compte de lignes vertes du banc reste celui des invariants. C'est la reponse du J3 a la lecon du J2 : *trois de ses neuf lignes ne mesuraient pas ce que leur titre annoncait, et aucune ne savait le dire.*

### J4 — LE METIER EN VILLE — **RESTE A FAIRE**
`taxi.gd` : seuils contextuels, grace de calage, `_at_address()` a la place de `_zone_stop` (taxi.gd:279-287), raclement hors rue. `main.gd` : Y a `nav["start_g"] + 210`, `_on_fork_committed` recale sur `nav["start_g"]`, garde du cauchemar, `_town_rail()` pour les bancs. `sleep.gd` : `boost_cafe`. `phone_apps.gd` affiche l'adresse.
**Bancs : `adressetest` (neuf) + `faretest` (main.gd:5386) amende + `maptest` (main.gd:5213) amende.** Captures `91_adresse.png`, `92_cafe.png`.
- `L'ADRESSE SE TROUVE` — arret dans la baie : accepte, ecart au point d'adresse **< 3,0 m**.
- `LE MAUVAIS COTE NE COMPTE PAS` — meme point en miroir : **refuse**.
- `LE JUGE CONNAIT LES RUES` — 380 m de rues laterales roulees : points `offroad` = **0** (avant : la note plancher en un echantillon).
- `UN VIRAGE NORMAL NE COUTE RIEN` — quart de tour de **rayon >= 12 m a 30 km/h** : `lateral` releve **< 6,5 m/s²** (calcul : `v²/R = 8,33²/12 = 5,78`).
- `UN VIRAGE JETE COUTE` — le meme a 45 km/h : le client parle (`v²/R = 13,0`).
- `LA VITESSE EN VILLE SE PAIE` — 80 km/h dans la traversante : points `speed` **> 0**.
- `UN CALAGE COURT EST PARDONNE` — calage de 0,8 s : **0 point** ; de 2,5 s : **> 0**.
- `LE CAFE REND UNE GORGEE` — vigilance apres l'arret **>= +0,25**, une seule fois par visite.
- `LA TRAVERSEE NE SE FACTURE PAS DEUX FOIS` — prix identique au bareme d'avant, au **centime** (`FARE_BASE + 0,90 × path_length/1000`, taxi.gd:212-213).
- `LE Y TOMBE APRES LA SORTIE` — fourche a **420 m** du panneau (120 m apres la sortie) ; panneau du Y a 330 m, soit **>= 20 m** apres la fin du masque.
- `LA METRIQUE NE DERIVE PLUS` — `maptest` etendu : la ville tombe a **< 30 m** de la longueur annoncee sur **trois aretes consecutives dont deux avec Y** (aujourd'hui main.gd:5252-5255 n'en mesure qu'une).
- `LA COURSE ENTIERE` — offre, adresse de prise, traversee, adresse de depose, paiement : note **>= 3,0**.
- `LE CAUCHEMAR NE PERD PAS LA CARTE` — `sleeptest` etendu : apres un aller-retour, la ville suivante tombe a **< 30 m**.

### J5 — LE GPS — **RESTE A FAIRE**
`scripts/gps_map.gd`, `phone_apps.gd` allege (classe interne retiree, `clip_contents`, `scroll` etendu), `road.trail()` branche.
**Banc : `gpstest`.** Captures depuis le SubViewport (modele main.gd:5343-5352) : `93_gps_rue.png`, `94_gps_ville.png`, `95_gps_route.png`, `96_gps_berceau.png`.
- `LES TRAITS SONT LE MONDE` — 20 points pris dans `town.gps_lines()`, projetes puis reprojetes par l'inverse de la transform : ecart **< 0,5 m** ; et 12 points pris dans l'`ArrayMesh` des rues 3D tombent tous **dans** un trait dessine.
- `LA CARTE EST ISOTROPE` — un carre de 50 × 50 m du plan mesure L × L a l'ecran : ecart **< 1 %** (l'ancienne etirait de 30 %).
- `LE CAP EST EN HAUT` — voiture tournee de 90° : la traversante tourne de **90° ± 2°**.
- `LE MARQUEUR EST LA VOITURE` — `world_to_screen(car)` a **< 1 px** du point de reference sur 60 images.
- `LA CARTE EST VIVANTE EN MAIN` — le marqueur bouge de **> 20 px** en 2 s de conduite (sans J0 : 0).
- `TROIS CRANS PUIS LA PAGE TOURNE` — z0, z1, z2, puis `avis` ; **0 changement de page** dans les trois premiers crans.
- `RIEN NE DEBORDE` — 2 000 pixels hors du cadre (10,55)-(206,306) **inchanges** apres zoom, deplacement et cap a 45°.
- `LE TEXTE NE TOURNE PAS` — hauteur de glyphe **identique a ±1 px** a cap 0° et a cap 45°, aux trois crans.
- `LISIBLE` — rue la plus etroite **>= 4,5 px** au cran large ; aucun trait **< 2,5 px**.
- `LE COUT TIENT` — `_draw` **< 300 µs**, appels de dessin **<= 8**, aux trois crans, ville armee.
- `LE GUIDAGE DIT LA MANOEUVRE` — annonce a N m du carrefour, manoeuvre reelle a **< 5 m** de N.
- `LE BERCEAU NE MONTRE PAS DE PLAN` — `compact` vrai au berceau, **0 trait de rue** dessine.

---

## 7. LE BUDGET

*(Machine de reference du depot : RX 6750 XT, 1600×900, MSAA 4×, D3D12 Forward+, cache de shaders chaud — 8,69 ms par image au volant, 115 ips. Il reste ~8 ms avant 60 ips.)*

### Sommets et triangles, par vue

| | Sommets | Triangles | Surfaces | Reconstructions |
|---|---|---|---|---|
| Ruban vivant (aujourd'hui, **inchange**) | 1 802 | 1 864 | 3 | **~12,5 par seconde** a 90 km/h |
| Ville d'aujourd'hui (town.gd) | ~1 200 | ~1 400 | 17 MI + 1 Label3D | 0 |
| **Ville neuve** *(releve, `villetest`)* | **5 635 a 6 097** | **4 624 a 5 370** | **6, sur 1 MI** | **1 par visite**, en 4 images |

*(Corrige trois fois, et **la troisieme est la premiere qui soit une mesure**. Le tableau annoncait ~7 600 / ~5 700 sur 120 boites et 360 fenetres ; le premier recalage l'a ramene a ~5 930 / ~4 865 sur 70,3 boites et 223 fenetres ; le resserrement de l'abord de carrefour a donne ~5 610 a ~5 780 / ~4 700 a ~4 790 — **et le J3 a ouvert le maillage**. Les quatre bourgs que `villetest` compte font **5 635 / 4 624** (La Fresnaie) a **6 097 / 5 370** (Corbeny) ; la borne haute de l'estimation etait **basse de 5,5 %**, faute d'avoir compte le repere dans les surfaces 5 et 6. Le detail est en §4.6.)*

La ville neuve est **3,1 a 3,4 fois** le ruban en sommets (5 635 a 6 097 contre 1 802), mais elle est batie **une fois toutes les 45 secondes**, quand le ruban se refait douze fois par seconde. Et le masque supprime bien les 3 surfaces du ruban sur la traversee : au coeur du bourg, `_rebuild()` a **moins** de triangles a ecrire — **ce n'est plus une promesse, c'est un releve** (§3.3, §6 : `LE MASQUE EST OUVERT` compte 0 triangle du ruban dans la fenetre du bourg, contre 2 262 a 3 076 des qu'on referme le masque a la main).

### Appels de dessin (tout est rendu **4 fois** : vue principale + 3 retroviseurs en `UPDATE_ALWAYS`, `cull_mask` couche 1, mirror.gd:29/33/84)

| | Objets dessinables | Annonce, × 4 vues | **Releve, × 4 vues** |
|---|---|---|---|
| Ville d'aujourd'hui | 17 MI (dont 4 lampadaires a materiau unique, non fusionnables) + 1 Label3D | ~60–72 | — |
| **Ville neuve** | **17** : 6 surfaces + 2 panneaux (poteau, tole, nom) + 4 plaques de rue + 1 numero | 52 | **+27 a +29 appels par image**, dix lancements |

**LE RELEVE EST UNE HAUSSE, PAS UN TOTAL, ET C'EST VOULU.** `LES APPELS DE DESSIN SONT COMPTES` (§6) bascule `town.visible` toutes les quatre images sur la meme traversee et compare deux medianes de 120 images : **460 a 499 appels le bourg allume contre 431 a 471 eteint**. Ce que la ville ajoute vaut donc **27 a 29**, la ou ce tableau en annoncait 52 — l'annonce comptait les dix-sept objets **tous visibles dans les quatre vues a la fois**, ce qui n'arrive jamais : les deux panneaux, les quatre plaques et le numero sont derriere la voiture ou hors champ la plupart du temps, et le cull les retire vue par vue.

**On ne promet pas une division par dix.** Une ville **dix-huit fois** plus etendue (§4.1) coute **le meme ordre d'appels de dessin** que le hameau qu'elle remplace — et c'est deja le bon resultat. Le contre-exemple qu'on evite : 64 batiments + ~180 fenetres en `MeshInstance3D` = **~245 noeuds = ~980 appels par image** (le plan ecrivait 480 et 1 920 sur 120 boites et 360 fenetres, le premier recalage 293 et 1 172 — l'argument a perdu la moitie de sa taille en deux passes et **pas un gramme** de sa force : ~980 appels contre **29 mesures**, c'est toujours plus de **trente fois** trop).

**Et il y a un chiffre bien plus gros a cote, que ce tableau n'avait jamais regarde : la nationale.** Le meme banc releve **1 257,5 a 1 639,4 appels par image** sur la nationale nue et plantee, contre 460 a 499 dans le bourg. **Ce ne sont pas les villes qui coutent des appels de dessin dans ce jeu, ce sont les arbres** — et c'est exactement pour ca que la mesure « nationale nue puis centre de la ville » qu'ordonnait ce plan aurait rendu une baisse de mille appels et conclu de travers (§6).

Contrepartie honnete : la ville neuve echange un cull fin (17 noeuds testes un par un) contre un cull grossier (une AABB de **340 × 112 m**, l'etendue relevee, tout ou rien). Au pire compte releve, **5 370 × 4 = 21 480** triangles peuvent ne pas se voir. Ce que le banc mesure de ce gaspillage, c'est son **cout d'image** : §6, `LE COUT NE SE VOIT PAS` — mediane +0,35 ms, et un instrument trop grossier pour en dire plus.

### Noeuds

| | |
|---|---|
| Ville d'aujourd'hui | 28 (1 racine + 4 panneau + 1 pave + 13 lampadaires + 9 maisons) |
| Ville neuve | 1 racine + 1 `MeshInstance3D` + les 2 panneaux et leurs supports + 4 plaques + 1 numero + 3 `OmniLight3D` — **17 objets DESSINABLES**, le compte qui decide des appels |

### Lumieres

| | Route de nuit | + ville | Pointe (avec police) |
|---|---|---|---|
| Aujourd'hui | 7 | +1 | 12 |
| Demain | 7 | **+3** | **14** |

Toujours **deux seules ombres dans tout le jeu : les phares** (car.gd:1421). Les trois lampes de ville posent explicitement `light_volumetric_fog_energy = 0,15` — la ville d'aujourd'hui est le **seul** endroit du depot a laisser le defaut de 1,0 **[verifie]**.

### Materiaux et shaders

Six materiaux, tous fabriques par `Retro.mat()` (retro.gd:13-19) sur le shader unique deja compile ; deux utilisent l'uniforme `emission`, deja pose par town.gd:43 et town.gd:170. **Aucune variante de shader neuve.** Le releve du depot (23 ips sur la premiere image a cache vide contre 115 a chaud) dit pourquoi c'est le point le plus important du budget : au milieu d'une ville, c'est le pire moment possible pour compiler quoi que ce soit. Et **aucun `ShaderMaterial` n'est fabrique dans `arm()`** — tous naissent au `_ready` de town.gd, comme aujourd'hui (town.gd:37-43).

### Memoire

| Poste | |
|---|---|
| Huit plans (`PackedFloat32Array` paralleles, **pas de Dictionary par batiment**) | ~50 Ko |
| Maillage de la ville vivante *(releve : 5 635 a 6 097 v × 24 o + 4 624 a 5 370 × 3 × 4 o)* | **~191 a ~211 Ko** |
| Maillage GPS (rues en metres, un cran a la fois) | ~20 Ko |
| Trace (`TRAIL_MAX = 4096` × 8 o) | 32 Ko |
| **Total ajoute** | **< 350 Ko** |

*(Corrige trois fois, la derniere sur des comptes releves : 5 635 × 24 = 135 Ko et 4 624 × 12 = 55 Ko au plus leger (La Fresnaie), 6 097 × 24 = 146 Ko et 5 370 × 12 = 64 Ko au plus lourd (Corbeny), soit **191 a 211 Ko** — contre 200 apres le premier recalage et 250 dans le plan d'origine. Le total ajoute va donc de ~293 a **~313 Ko**. Le seuil de 350 Ko, lui, ne bouge pas : c'est une reserve, pas une prevision, et il tient encore sur le bourg le plus lourd des quatre mesures.)*

Le maillage n'est **pas** memoise par nom de ville : il depend du ruban, donc il est unique a chaque visite. C'est le prix d'une traversante qui suit la route ; il est paye en quatre images.

---

## 8. CE QU'ON NE FAIT PAS, ET POURQUOI

**Pas d'origine flottante, pas de chunks, pas de recentrage.** La route serpente en marche aleatoire de longueur de persistance ~750 m : une nuit complete (~29 km roules) laisse la voiture a ~10 km de l'origine, ou l'ulp du float32 vaut 1 mm pour des peintures de 15 cm de large. Le seuil visible (1 cm d'ulp) est a 131 km de l'origine. Un recentrage casserait `head_index`, les rendez-vous des monstres, l'ancre du portail et huit bancs — pour corriger un probleme qui n'existe pas.

**Pas d'atlas, pas de route reproductible, pas de pays ferme.** Poser les dix aretes d'avance obligerait a re-deriver les huit ancres **et** les caps de porte sous contrainte de longueur, ce qui casse `maptest` au dixieme de metre (main.gd:5222, `absf(rlen - 3400.0) < 0.1`) et `faretest` au centime. Et c'est inutile : au zoom par defaut la carte couvre 90 m, quand road.gd tient deja 276 m de ruban **exact** devant la voiture. On ne pre-calcule que ce dont on a besoin — la ville. La ou le ruban s'arrete, le GPS trace un pointille et le dit.

**Pas de collision.** C'est le sacrifice le plus lourd, et il est deja paye ailleurs : giant.gd:62-65 documente noir sur blanc pourquoi le geant n'a pas de collider. Ajouter des murs obligerait a rebrancher `move_and_slide()` sur `speed` — car.gd:758-760 recalcule `velocity` a zero **chaque tick** depuis un scalaire que le script possede : sans boucle de retour, la voiture vibre contre le mur plein gaz, compteur a 90, sans un bruit. Il faudrait aussi decider du sort des retroviseurs (collider 1,675 m contre 2,02 m hors-tout), et faire compter les chocs par le jury de confort. Ce serait un autre projet, et il commencerait par une **boucle de retour physique dans car.gd**, pas par une ville. Attenuation retenue et **incluse** au J4 : facades a 6 m de l'axe, plus le raclement et l'`impact()` au-dela de 8 m — une consequence sans mur.

**Pas de relief.** `velocity.y = 0.0` chaque tick (car.gd:759), aucune gravite, aucun raycast, `MOTION_MODE_GROUNDED` avec `floor_max_angle` a 45° : un trottoir monte serait un MUR. La ville reste rigoureusement plate a y = 0, et les trottoirs sont une **difference de couleur** (10 mm de decalage pour le z-fighting, pas pour le pied).

**Pas de carrefour dans le graphe de la carte.** Le degre reste borne a 3 (map.gd:12-13), la bifurcation reste un Y, **dehors**, tranchee au volant par comparaison de distance a deux rubans (road.gd:246-262). Les carrefours de la ville sont de la geometrie pure, sans semantique de navigation. Generaliser `program_fork` a N sorties casserait main.gd:4065, phone_apps.gd:339-341 et l'invariant imprime par `maptest` (main.gd:5227-5231), pour offrir un choix que la carte ne saurait pas nommer.

**Pas de deuxieme ville vivante.** Le pool reste a un exemplaire (road.gd:754-756) : `_pickup_missed`/`_drop_missed` (taxi.gd:292-299) testent l'identite de `road.town.town_name`, et deux villes allumees annuleraient silencieusement la course en cours. La marge est de 244 m sur l'arete la plus courte ; le banc la mesure et echoue sous 100 m.

**Pas de MultiMesh, pas de LOD, pas de FogVolume.** Un MultiMesh n'a qu'une AABB et aucune visibilite par instance ; le depot n'en contient aucun. Un seul `ArrayMesh` fusionne de **4 624 a 5 370** triangles — le releve, pas l'estimation — est plus simple, plus previsible, et suffit. Un trou de brouillard local demanderait un FogVolume, une piece entierement neuve, dans un Environment qui n'a **qu'un seul proprietaire** (daycycle.gd:9-11, qui le reecrit a chaque image).

**Pas de pates de maisons sur le GPS, pas un seul `draw_circle`.** Ces primitives emettent **chacune** leur propre appel de dessin (14,7 et 11,7 µs piece) et le budget de l'ecran est d'environ 60 par image. La carte est des rues claires sur du noir.

**Pas de circulation, pas de pietons, pas de feux, pas d'interieurs.** Une ville a deux heures du matin ou il n'y a personne, c'est le sujet du jeu. Mais il faut l'assumer : le seul enjeu de la conduite en ville est de **trouver l'adresse**, et c'est pour ca que les rues paralleles existent — pour qu'on puisse se tromper de rue et faire le tour du pate — et pour ca que les plaques et le porche eclaire existent : **pour qu'on puisse la trouver dans les phares plutot que sur un ecran.**

**~~Pas de nouvel asset Blender.~~ SI, UN PAR VILLE : le repere — ET LES HUIT SONT LA.** Cette ligne disait « aucun `build_*.py`, aucun `.glb`, aucune texture, aucune scene ». Elle est **fausse depuis** `assets/blender/build_landmarks.py`, et la version precedente de ce document ne connaissait encore que le premier des huit, `landmark_clocher.glb`. **Les huit `.glb` existent et sont lus** : le clocher de Corbeny, le totem de la station de Saint-Elme, le chateau d'eau de La Fresnaie, le silo de Malassis, la porte fortifiee de Vieux-Bourg, la cheminee des Essarts, la halle de Peyrelade, le pont du chemin de fer de Brumaire. Chacun dit le **metier** du bourg, pas son decor. La raison tient en une phrase, et elle est ecrite en tete du fichier : *un bourg qu'on ne reconnait pas est un decor ; un bourg qu'on reconnait est un lieu.* Huit plans differents ne suffisent pas a ca dans le brouillard ; une silhouette, oui.

Ce qui **reste vrai** de la ligne d'origine, et qui etait son vrai argument : **aucun materiau importe, aucune variante de shader neuve.** Les reperes sont **cousus** dans le maillage fusionne de la ville — un objet dont le nom finit par `_Lit` part dans la surface **6** (emissive), tout le reste dans la surface **5**. C'est le seul contrat entre le fichier Blender et Godot. Un repere qui deviendrait un `MeshInstance3D` couterait son propre appel de dessin, **quatre fois par image** avec les retroviseurs.

**LE COUT DES HUIT SE LIT AU BANC, A CHAQUE LANCEMENT, ET IL NE SE RECOPIE PAS.** `plantest` et `villetest` impriment la meme ligne au demarrage : `[reperes] 8 modeles lus en N ms au _ready, X sommets et Y triangles en reserve`. **Et ce X a bouge PENDANT la serie de dix lancements de cette version** : **3 132 sommets / 3 412 triangles** sur les neuf premiers, **3 212 / 3 612** sur le dixieme et le onzieme, parce que quatre des huit modeles ont ete rebatis plus hauts entre-temps — totem 12,60 -> 20,05 m, porte 14,80 -> 20,50, halle 13,37 -> 20,65, pont 12,05 -> 21,30. **Ce document ne fige donc aucun compte par repere** : la ligne du banc est la seule source, et elle est a relire, pas a citer.

**Ce que `villetest` mesure en plus, et qui est le vrai chiffre a surveiller : la part du repere DANS le bourg qui le porte.** Sur les quatre villes qu'il ouvre — **8,3 %** pour le clocher de Corbeny, **6,3 %** pour le totem de Saint-Elme apres sa reprise (5,9 % avant), **4,8 %** pour le silo de Malassis, **4,7 %** pour le chateau d'eau de La Fresnaie. Le clocher reste le plus lourd des quatre, et il l'etait deja.

**LA CRAINTE ETAIT « sept reperes de plus a ce prix et le budget serait a refaire ». ELLE NE S'EST PAS REALISEE, ET IL FAUT DIRE POURQUOI.** Le clocher, sur lequel les 8,8 % avaient ete calcules, est **le plus lourd** des quatre que le banc pese ; les trois autres tiennent entre **4,7 et 6,3 %**. Un pire cas avait ete pris pour la regle. Et surtout, le budget n'a pas ete a refaire parce que le repere ne coute **aucun appel de dessin** : ses sommets sont verses dans les surfaces 5 et 6 qui existent deja — le corps dans la 5, tout noeud dont le nom finit par `_Lit` dans la 6. C'est le seul contrat entre le fichier Blender et Godot. **Les dix-sept objets dessinables du bourg sont dix-sept, avec ou sans lui.**

**Ce que la lecture des huit `.glb` coute, et quand.** Ils sont lus par `GLTFDocument` au `_ready` et nulle part ailleurs — pas par `load()`, parce que sept des huit n'ont pas de fichier `.import`, que seul un passage dans l'editeur ecrirait, et l'editeur n'est jamais ouvert quand un banc tourne. Releve sur douze lancements : **99,5 a 311,0 ms**, une fois, au demarrage — et la borne haute est celle du lancement qui a suivi la reecriture de quatre `.glb`, cache disque froid. Le choix du site des huit, lui, coute **5,09 a 7,34 ms** au total, soit **0,64 a 0,92 ms par bourg** — et c'est ce que paie l'etape 3 au premier armement, sous un seuil de 4,0 ms.

> **LES DEUX PIEGES PAYES AU MODELAGE.** Ils ne se voient **ni dans les chiffres ni a la compilation** — les deux se sont vus au premier rendu du clocher. *(Les sept reperes suivants ont ete batis depuis, et ces deux lignes sont ce qui a permis de ne pas les repayer sept fois. Elles restent ici pour le neuvieme modele, quel qu'il soit.)*
>
> 1. **`civic_lib.place()` prend les rotations en DEGRES** et refait le `math.radians` lui-meme. Passer des radians les divise une seconde fois par 57 et **rien ne tourne**. Releve au rendu : le cadran de l'horloge etait couche a plat comme une etagere, et le chainage d'angle tombait au milieu des faces au lieu des aretes. Aucune erreur, aucun avertissement — un modele parfaitement valide, simplement faux.
> 2. **Un `lathe` a quatre pas prend le rayon CIRCONSCRIT, pas le demi-cote.** Un profil a `cote / 2` donne donc un prisme `√2` fois trop petit : le premier jet a coute **une tour de 2,55 m au lieu de 3,60**, et le chainage d'angle flottait autour d'elle comme quatre pieds de table. Le remede tient en une constante, `DIAG = 2 ** 0.5`, appliquee a chaque rayon de profil.
>
> Les deux sont deja documentes a leur point d'emploi (`build_landmarks.py`, la ou `DIAG` et `rot=` sont poses). Ils sont recopies ici parce que le prochain repere se batira en lisant **ce plan**, pas le fichier du precedent.

**Pas de sortie par l'entree.** `_index0` ne decroit toujours pas. La ville couvre 40 m avant son panneau ; au-dela on retombe sur le plan de sol nu (main.gd:3789-3800, 900 × 900 m recentre chaque image). Limitation assumee, a documenter mot pour mot dans le README, comme le depot documente deja ses pieges payes. **La ville est le seul endroit du jeu ou l'on peut faire demi-tour** — et c'est un fait mesure par `villetest`, pas une image. **Mais on le fait AU CARREFOUR**, pas n'importe ou dans la rue, et c'est la moitie de ce que le J3 a appris : voir §6, `LE DEMI-TOUR TIENT`. C'est vrai d'une vraie rue aussi, et c'est ce qui rend la limitation supportable — on ne se retourne pas au milieu d'un pate de maisons, on attend le croisement.

---

## ANNEXE A — CE QUE LES DOSSIERS PRECEDENTS DISAIENT DE FAUX

Relu ligne a ligne ; a ne pas recopier :

- **« Le brouillard de nuit vaut 0,024 »** — non : **0,030**. `daycycle.gd:115-127` **photographie** l'Environment pose par `_build_environment()` pour son moment "nuit" ; `main.gd:22` exporte `fog_density := 0.030`. Le 0,024 est celui de l'**aube** (6 h 18, daycycle.gd:133).
- **« `_rebuild` est gratuit »** — non : ~1,6 ms avec le pilote, soit 18 % d'une image, douze fois et demie par seconde. Le commentaire road.gd:10-11 (« ~1500 sommets, c'est gratuit ») est faux sur les deux termes ; le vrai compte est **1 802 sommets / 1 864 triangles / 3 surfaces**.
- **« `draw_polyline` se met en lot »** — non : 34 polylignes = **34 appels de dessin** et 315 µs. D'ou le `draw_mesh` pour les rues.
- **« La ville actuelle fait 400 triangles »** — non : ~1 400, parce que `make_sign` (town.gd:119-123) et `_lamp` (town.gd:153-156) fabriquent des `CylinderMesh` **sans toucher `radial_segments`**, donc au defaut de Godot (64 segments). *Correction de trois lignes a faire au passage en J3 : `radial_segments = 8`, comme road.gd le fait deja pour ses troncs et ses poteaux.*
- **« 96 arbres = 180 appels de dessin »** — non : Godot 4.8 Forward+ fusionne les surfaces identiques, et road.gd:778-800 partage mesh **et** materiau. C'est de l'ordre de 24 appels.
- **« Une acceleration laterale de 7,0 rend un carrefour gratuit »** — non : `car.gd:186` plafonne a **exactement 8,0** et la voiture roule **au** plafond des 28 km/h. Aucun seuil sous 8,0 ne rend un virage serre gratuit, et aucun seuil au-dessus ne juge quoi que ce soit.
- **« `program_town` peut porter les bornes de la traversee »** — non : main.gd:4046-4051 l'appelle pour la ville **suivante** au panneau de la ville courante. C'est le defaut qui aurait ruine les quatre villes de degre 2.
- **« `_on_town_reached` peut lire `_town_g` »** — non : road.gd:234-235 le remet a -1 **avant** d'emettre `town_reached`.
- **« `_strip_of` se reutilise tel quel depuis town.gd »** — non : c'est une methode **privee d'instance** qui ecrit dans les accumulateurs membres `_v`/`_n`/`_f` (road.gd:105-108). D'ou `scripts/strip.gd`.
- **« Un `return` en tete de `_place_props` est sans consequence »** — non : il eteint le **portail du cauchemar** (road.gd:525-529), la seule sortie du cauchemar.
- **« La ville double les kilometres sans les facturer »** — non : la traversee est **dans** l'arete (panneau a panneau), et `MapScript.path_length` la facture deja. Seuls les detours vers une adresse (≤ 240 m) echappent au bareme.
- **Captures 84/85/86** — deja prises par `faretest` (main.gd:5430, 5480, 5570). Les nouvelles partent a **87**.

---

## ANNEXE B — CE QUE **CE** PLAN DISAIT DE FAUX

L'annexe A juge les dossiers d'avant. Celle-ci juge ce document, releve par releve. Elle a **quatre** parties : **B.1** est ce que le plan d'origine disait de faux, **B.2** ce que **son premier recalage** disait de faux — un recalage fait sur des releves, honnetement, et perime en un jour parce que le code a bouge sous lui —, **B.3** les affirmations de fond qui n'etaient pas des chiffres, et **B.4**, neuve, **ce que le J3 a dementi en le livrant**.

**B.4 est desormais la plus instructive, et pour une raison qui n'est celle d'aucune des trois autres.** B.1 punit une soustraction jamais faite ; B.2 punit une mesure vieillie ; B.3 punit une decision fausse. **B.4 ne punit rien** : le code y a pris des decisions MEILLEURES que celles du plan, et le seul defaut est que le plan ne les portait pas. Un document qui ne sait pas enregistrer une bonne surprise ment autant qu'un document qui rate une erreur.

**Le code a raison, le plan avait tort**, et trois fois plutot qu'une.

### B.1 — Le plan d'origine

*(Les numeros de ligne de la premiere colonne sont ceux de la version d'origine — ils ne pointent plus dans le fichier d'aujourd'hui, ils datent la faute. La colonne du milieu porte la valeur **d'aujourd'hui**, pas celle du premier recalage : quand les deux different, la ligne est reprise en B.2.)*

| Ce que le plan disait | Ce que le monde dit aujourd'hui | Ou c'est mesure |
|---|---|---|
| **120 batiments** par ville (l. 283) | **64,4** — 515 sur huit bourgs, de 60 a 70 ; plafond geometrique **77** | `plantest`, §4.3 |
| ~960 batiments sur les huit (l. 484) | **515** | `plantest`, J1 |
| **360 fenetres** allumees par bourg (l. 285) | **159 a 201** sur les quatre bourgs que le banc ouvre — **comptees**, plus bornees | `villetest`, §4.3 |
| **29 mats** par bourg (l. 285, 320-321) | **23,4** — 187 au total | `plantest`, §4.3 |
| **26 tetes** emissives (l. 350) | **20** | §4.8 |
| Transversales **3 a 5** (l. 271) | **3 a 4** — cinq demanderaient 192 m dans une plage de 180 | town_plan.gd:179-188 |
| Paralleles **0 a 2** (l. 272) | **1 a 2** — zero rend le graphe acyclique | town_plan.gd:193-198 |
| **8 carrefours** « pour une ville type » (l. 277) | **6 a 12**, moyenne **9,1**, 73 au total | `plantest`, §4.2 |
| **64 carrefours** au banc du J1 (l. 481) | **73** | `plantest` |
| Emprise **150 m** de large (l. 258) | **98 a 122 m**, moyenne **111,8** | `plantest`, §4.1 |
| Rue cumulee **~880 m** (l. 262) | **921,5 m**, de 760 a 1 090 | `plantest`, §4.1 |
| **20 fois** la surface du hameau (l. 264) | **18 fois** (37 995 m² contre 2 080) | §4.1 |
| **34 %** de l'arete la plus courte (l. 264) | **36 %** (342 m sur 950) | map.gd:48 |
| Surface 5 : **~2 748** sommets / **~1 548** triangles (l. 320) | **2 040 / 1 580** sur Corbeny — dont **392 / 612** de clocher | `villetest`, §4.6 |
| Surface 6 : **~1 568 / ~784** (l. 321) | **988 / 682** sur Corbeny | `villetest`, §4.6 |
| Ville neuve : **~7 600 / ~5 700** (l. 322, 561) | **5 635 / 4 624 a 6 097 / 5 370** — releve, plus estime | `villetest`, §4.6, §7 |
| **4,2 fois** le ruban en sommets (l. 563) | **3,1 a 3,4 fois** | §7 |
| Contre-exemple **480 noeuds, 1 920 appels** (l. 572) | **~245 noeuds, ~980 appels** | §7 |
| Maillage de ville en memoire **~250 Ko** (l. 600) | **~191 a ~211 Ko** — 5 635 x 24 + 4 624 x 12 au plus leger, 6 097 x 24 + 5 370 x 12 au plus lourd | §7 |
| Seuils du J3 : **< 11 000 / < 8 000** (l. 505) | **< 8 000 / < 6 500**, tenus : pire releve **6 097 / 5 370** | `villetest`, §6 |
| « Aucun batiment a moins de 12 m d'un carrefour » (l. 281) | **Vrai**, et des **empreintes** : 12,73 m au plus juste, 0 faute sur 4 691 — mais ca n'a ete vrai qu'apres le resserrement, voir B.2 | §4.3 |
| Marge facade/axe **>= 4,5 m** au banc (l. 484) | Mesure du mur au **bord de trottoir** ; pire marge **+0,541 m**, 0 empietement | `plantest`, J1 |
| Adresses : ecart a l'axe **entre 2,6 et 6,0 m** (l. 485) | La mesure valait une **constante** (3,40 m) ; quatre tests par rue porteuse la remplacent | `plantest`, J1 |
| Derive du Y : **+26 m**, **+52 m** apres correction (l. 228) | **+314 m** sur 1 100, **+272 m** sur 1 350 | §3.8 |
| Rouler 100 m en travers : **38 echantillons** de defile (l. 132) | **261** | `rubantest`, §3.1 |
| Traversee a 45 km/h : **1,73 fois** le debit de vigilance (l. 364) | **1,33**, et **2,13** monotonie armee — `slow_factor` ne mord pas a 45 km/h | sleep.gd:140-143, 152-153, §4.5 |
| « Pas de nouvel asset Blender » (§8) | **HUIT** `.glb`, et leur poids **changeait encore pendant la mesure** : 3 132 / 3 412 en reserve sur neuf lancements, **3 212 / 3 612** aux deux suivants | `plantest` / `villetest`, §8 |

### B.2 — Le premier recalage, perime par le lot de corrections qui l'a produit

Ces valeurs-la ont ete **mesurees**, pas devinees. C'est ce qui rend cette table interessante : elles etaient justes le jour ou elles ont ete ecrites, et fausses le lendemain, parce que `town_plan.gd` a resserre son abord de carrefour — le curseur saute desormais `CORNER_FREE + BLD_W.x / 2` = **15 m** au lieu de **12** (§4.3). **Une mesure a une date. Un plan qui n'ecrit pas la date de ses mesures ment a retardement.**

| Ce que le recalage mesurait | Ce que le banc mesure aujourd'hui |
|---|---|
| **562** batiments, **70,3** par bourg, de 64 a 76 | **515**, **64,4** par bourg, de 60 a 70 |
| **3 436** couples mur/rue | **3 153** |
| Marges au bord de trottoir : tronc **+0,519**, transversale **+1,103**, parallele **+0,548** | **+0,896 / +1,456 / +0,541** |
| Pire marge **+0,519 m** sur **Vieux-Bourg** | **+0,541 m** sur **Malassis**, sur une parallele |
| Adresses : **+2,0 m** au bout de la rue | **+1,0 m** |
| Abords de carrefour retires : **43 %** (sur 12 m) | **52 %** (sur 15 m) |
| Lineaire utile **1 051 m**, plafond geometrique **91** | **885 m**, plafond **77** |
| Facade moyenne **8,77 m** | **8,05 m** |
| Coin d'ilot : **210 refus sur 854** | **154 sur 705** |
| Mur le plus proche d'un carrefour : **7,59 m**, **120 couples sur 5 102** sous 12 m | **12,73 m**, **0 sur 4 691** |
| « Serrer l'entraxe ne fait que multiplier les refus » | **Faux desormais** : 8-13 m rend +2,6 maisons par bourg |
| Ilot : 48 − 2 × 12 = **24 m** de facade | 48 − 2 × 15 = **18 m** |
| **1 785** fenetres, **223** par bourg, **3,18** par batiment | **Comptees depuis le J3** : 159 a 201 sur les quatre bourgs ouverts (la borne 172-214 qui les remplacait rate Corbeny) |
| Largeurs relevees 111 / 123 / 121, moyenne **112,1 m** | 110 / 122 / 120, moyenne **111,75 m** |
| Surface 5 **~1 687 / ~984**, surface 6 **~998 / ~499** | **2 040 / 1 580** et **988 / 682** — releve sur Corbeny, repere compris |
| Ville neuve **~5 930 / ~4 865**, pire cas **~6 200 / ~5 025** | **5 635 / 4 624 a 6 097 / 5 370** — releve, et le pire des quatre est **Corbeny**, pas Malassis |
| **3,3 fois** le ruban ; **293 noeuds, 1 172 appels** ; **~200 Ko** | **3,1 a 3,4 fois** ; contre-exemple ~245 noeuds / ~980 appels, quand le bourg livre en ajoute **27 a 29** ; **191 a 211 Ko** |

**Ce que B.2 coute vraiment**, et ce n'est pas les 47 maisons : c'est que **trois de ses valeurs n'etaient plus mesurables du tout**. Le compte de fenetres, la facade moyenne et la distance mur/carrefour ne sortaient d'**aucun banc** — les deux dernieres ne vivent que dans les commentaires de `town_plan.gd`, mesurees en recompilant le fichier a la main. `plantest` compare des murs a des **rues**, jamais a des **centres de carrefour** ; c'est par ce trou-la qu'un mur a 7,59 m d'un croisement a vecu sous un banc vert. **Deux lignes de banc fermeraient les trois** : `AUCUN MUR DANS UN CARREFOUR` et un compte de fenetres dans `villetest`.

> **UNE DES TROIS EST FERMEE DEPUIS LE J3, ET ELLE A FAIT TOMBER LA FOURCHETTE QUI LA REMPLACAIT.** `villetest` compte les fenetres allumees de chaque bourg qu'il ouvre : **159, 177, 188, 201** pour Corbeny, Malassis, Saint-Elme et La Fresnaie. La borne « 172 a 214 » que B.2 avait posee faute de mieux **rate Corbeny par le bas**, et pour une raison de nature : elle bornait l'**esperance** d'un tirage, pas le tirage (§4.3). **Les deux autres restent ouvertes** : ni la facade moyenne ni la distance mur/carrefour ne sortent d'un banc, et `AUCUN MUR DANS UN CARREFOUR` n'existe toujours pas dans `plantest`.

### B.3 — Les trois qui n'etaient pas des chiffres

| Ce que le plan affirmait | Ce que le code fait |
|---|---|
| **Decision 4** : « courbure bornee, pas annulee : pas de declenchement de la monotonie de `sleep.gd` » | **La traversee ARMAIT la monotonie.** Silence du volant de 7,7 a 21,1 s sur une traversee de 21,0 s, pour un `mono_after` de 10 s ; **9 lancements sur 10** au-dessus du seuil, **1 vert sur 10** au banc. Et le remede que le plan sous-entendait — plus de courbure — **n'existait pas** : la compression a 60 m plafonne `k` a 0,0020, soit 0,027 de volant contre 0,04 demandes. `road.gd` a repondu par un **slalom** (alternance de bord), pas par un plafond plus haut. §1, §3.2 |
| **§3.3** : le masque de dessin, « ecart de couture nul par identite », presente comme acquis | **Le masque n'avait jamais tourne** — la faute etait de le presenter comme prouve, et elle tient toujours pour la version qui l'a ecrite. `_town_ready` etait conditionne a `town.draws_trunk()`, que `town.gd` n'avait pas ; idem pour `contains()`, `street_dist()` et `set_dark()` : **quatre appels, quatre `has_method` qui rendaient faux**. **Le J3 a livre les quatre**, et `LE MASQUE EST OUVERT` le prouve sur des triangles : 0 dans la fenetre du bourg, 2 262 a 3 076 des qu'on referme le masque a la main. §3.3, §6, B.4 |
| **§3**, en titre : « numeros de ligne d'aujourd'hui » | **Perimes, et pour la troisieme fois.** Ils dataient d'avant le J2 ; `road.gd` a bouge **trois fois pendant la redaction de cette version**. Regle adoptee : **on cite une fonction ou une constante, pas une ligne** — un `grep` sur un symbole survit a une refonte. §3 |

### B.4 — CE QUE LE J3 A DEMENTI EN LE LIVRANT

*(Releve le jour de cette version, `plantest` une fois et `villetest` **dix fois**, la courbure du ruban retiree a chaque lancement. Les **cinq premieres lignes** portent les quatre ecarts de DECISION — les deux premieres sont les deux faces du meme, le pave de carrefour et l'invariant qui le nommait ; les suivantes sont des chiffres que le banc a mesures la ou le plan estimait.)*

| Ce que ce plan disait | Ce que le J3 a livre, et pourquoi c'est mieux | Ou c'est mesure |
|---|---|---|
| Surface 1 : chaussees **+ paves de carrefour** ; invariant « sur les **8 paves de carrefour** » | **Aucun pave.** Un pave est coplanaire avec la chaussee qu'il recouvre, meme materiau, meme hauteur : du **z-fighting** en travers des phares, huit a douze fois par bourg. `town.gd` fait passer **une seule des deux rues** a chaque croisement et **coupe** celle qui cede. Et l'invariant livre couvre **tous** les triangles, pas huit rectangles nommes a la main | `villetest`, §4.6, §6 |
| `TOUT EST A L'ENDROIT` : **une** mesure, l'aire signee en (x, z) | **Deux** mesures, parce qu'une seule ne pouvait pas juger un mur : l'aire signee ne vaut que pour les **triangles a plat** (12 602 sur 19 624, dont 92 qui regardent le sol et dont le signe attendu est **inverse**), et la normale geometrique contre la normale d'ombrage vaut pour les 19 624. Le signe de reference est **releve sur la nationale**, pas ecrit | `villetest`, §6 |
| `LES APPELS DE DESSIN` : « sur la **nationale nue**, puis au **centre de la ville** » | **Un A/B sur la seule visibilite du bourg**, sur la meme traversee. La mesure du plan aurait rendu une **BAISSE** : 1 257,5 a 1 639,4 appels sur la nationale plantee contre 460 a 499 dans le bourg — parce que le **silence des props** y supprime les arbres (p = 0,55 par echantillon). Le vrai chiffre est une **hausse de 27 a 29** pour un seuil de 60 | `villetest`, §6, §7 |
| `LE DEMI-TOUR TIENT` : « **200 m dans la ville**, demi-tour » | **Le demi-tour tient AU CARREFOUR.** A 4 m/s le rayon vaut 4,6 m et la voiture passe a 8,0 m de l'axe du tronc — hors des 5,80 m ; ce qui la rattrape, c'est **l'autre rue**. Le temoin du banc le chiffre : le meme point **60 m plus loin, entre deux transversales**, rend **9,00 m** pour un seuil de 5,80. Pour le joueur : **on se retourne aux croisements, pas n'importe ou** — ce qui est vrai d'une vraie rue | `villetest`, §6, §8 |
| `LE COUT NE SE VOIT PAS` : « chute **< 15 %** », comme si 15 % etait une marge | Mediane **+0,35 ms (+3,8 %)** sur dix lancements — **mais une etendue de −11,2 % a +8,9 %**, cinq fois la mediane, et **trois lancements sur dix rendent un cout NEGATIF**. Le chiffre est bon, **l'instrument est trop grossier** : c'est un ecart entre deux medianes bruitees, sur un denominateur qui va de 7,94 a 13,79 ms | `villetest`, §6 |
| Surfaces **2 et 4** « exactes » a 684 / 680 | La **4** tombe au sommet pres. La **2** fait **636 a 648** : `town.gd` **coupe** l'accotement et le trottoir du tronc a chaque transversale, et ce sont les bandes de la transversale qui rebouchent | `villetest`, §4.6 |
| Surface 5 : **~1 568 / ~924** ; ville neuve **~5 610 a ~5 780 / ~4 700 a ~4 790** | **2 040 / 1 580** et **5 635 / 4 624 a 6 097 / 5 370**. Le calcul unitaire etait juste — 68 × 20 + 24 × 12 = 1 648 — **il ne comptait pas le repere** : 2 040 − 1 648 = **392**, le clocher au sommet pres | `villetest`, §4.6, §7 |
| Fenetres : « **entre 172 et 214** par bourg », faute de banc | **Comptees : 159, 177, 188, 201** sur les quatre bourgs ouverts. La borne **rate Corbeny par le bas**, et pour une faute de nature : `WIN_P = 0,30` est un **tirage**, pas un taux, et le calcul bornait l'**esperance**. Ordre de grandeur : ~530 travees-etages a p = 0,30 ont un ecart-type de **10,6** | `villetest`, §4.3 |
| Construction : etape **3** la plus chere (~2,8 ms), etape 2 a ~1,3 | **L'etape 2 est la pire aux dix lancements** (1,40 a 1,89 ms), l'etape 3 en fait 1,29 a 1,61. **Les trottoirs coutent plus cher que les maisons** : la surface 3 est la deuxieme du bourg et chaque bande redemande le mapping curviligne. Le plan disait ou chercher si les boites n'y etaient pas ; c'etait la | `villetest`, §4.6 |
| Capture `90_ville_cauchemar.png` ; `set_dark()` prouve au J3 | La capture 90 est **`90_ville_repere.png`**. `set_dark()` existe et s'execute — **et rien ne la mesure** : ni ligne de banc, ni capture. C'est le **seul** des quatre appels du §3.3 dans ce cas | §3.10 |
| « Le clocher de Corbeny, **premier des huit** » | **Les huit sont batis et lus.** Et leur poids **bougeait encore pendant cette serie de mesures** : 3 132 sommets / 3 412 triangles en reserve sur neuf lancements, **3 212 / 3 612** aux deux suivants, quatre modeles ayant ete rebatis plus hauts entre-temps | `plantest` / `villetest`, §8 |

**CE QUE B.4 APPREND, ET QUI N'EST DANS AUCUNE DES TROIS AUTRES.** B.1 punit une soustraction jamais faite, B.2 une mesure vieillie, B.3 une decision fausse. **Ici, quatre fois, le code a eu raison contre le plan sans que le plan soit bete** — il avait raisonne juste sur des objets qu'il n'avait pas encore. Un plan ne peut pas savoir qu'un pave de carrefour z-fightera avant que quelqu'un ne pose les deux chaussees ; il peut seulement **etre relu quand elles sont posees.** C'est ce que cette version fait, et c'est tout ce qu'un plan peut faire.

**ET UNE SURPRISE DE METHODE, ARRIVEE PENDANT LA MESURE.** Sur les **dix** lancements de `villetest`, neuf ont rendu les memes comptes de maillage au sommet pres ; le dixieme a rendu Saint-Elme a **5 757 / 4 830** au lieu de 5 733 / 4 786, parce que son totem avait ete **rebati plus haut pendant la serie** — et un onzieme lancement, de controle, a confirme la nouvelle valeur. Ce n'etait pas du bruit, ce n'etait pas le ruban : **c'etait un asset qui avait change sous le banc**. Un lancement unique aurait donne un chiffre juste et l'aurait fige a la mauvaise date. **Dix lancements ne servent pas seulement a attraper le hasard : ils attrapent aussi le depot qui bouge.**

**LES TROIS TROUS QUI RESTENT, ET AUCUN N'EST DANS LE CODE LIVRE — ILS SONT DANS LES BANCS :**
1. **`AUCUN MUR DANS UN CARREFOUR` n'existe toujours pas** dans `plantest`. Il compare des murs a des **rues**, jamais a des **centres de carrefour** : c'est par ce trou-la qu'un mur a 7,59 m d'un croisement a vecu sous un banc vert (B.2), et le 12,73 m qui le remplace ne sort **d'aucun banc**.
2. **`villetest` n'ouvre que quatre bourgs sur huit.** Les quatre autres — Les Essarts, Peyrelade, Vieux-Bourg, Brumaire — ne sont comptes que dans un commentaire de `town.gd`, et c'est ce commentaire qui designe **Brumaire** comme le plus lourd en sommets. Une boucle sur les huit fermerait le trou.
3. **La ville du cauchemar n'a ni banc ni capture** (§3.10).

**La lecon, une fois, pour les deux jalons qui restent.** Ce plan avait raison sur la forme, sur les coutures et sur les pieges — l'annexe A tient toujours. Ce qui l'a fait mentir la premiere fois, c'est **une soustraction ecrite mais jamais faite** : « moins les abords de carrefour ». Trois mots, poses en fin de ligne, jamais chiffres. Ils ont suffi a fausser la densite, puis les fenetres, puis les mats, puis le budget de sommets, puis **le seuil du banc cense attraper l'erreur**.

**Ce qui l'a fait mentir la seconde fois est plus retors, et c'est le vrai sujet de cette annexe : rien.** Personne n'a estime, personne n'a arrondi. Le recalage a mesure, cite ses bancs, pose ses calculs — et il a ete faux le lendemain parce que **le code qu'il decrivait a change dans le meme lot de corrections**. Cinq defenses, et la cinquieme est venue de cette version-ci :

1. **Relancer les bancs, pas les relire.** Un chiffre recopie depuis la version precedente du document n'est pas un releve, c'est une citation.
2. **Dater ce qu'on ne peut pas relancer.** Les mesures qui vivent dans un commentaire de `town_plan.gd` — facade moyenne, distance mur/carrefour, refus — ne se relancent pas : elles doivent dire *sur quel etat du fichier* elles ont ete prises, ou devenir des lignes de banc.
3. **Un chiffre qui n'a plus de banc redevient une fourchette, pas un souvenir.** Le compte de fenetres est passe de « 223 » a « entre 172 et 214 » ; c'est moins flatteur, et c'est la seule chose honnete a ecrire tant que `villetest` n'existe pas.
4. **Citer un symbole, pas une ligne.** Un numero de ligne ne survit pas a une insertion ; un nom de fonction survit a une refonte, et il se verifie d'un `grep`. Ce document s'est fait prendre trois fois par ses propres numeros de ligne — la troisieme pendant qu'il ecrivait la lecon des deux premieres.
5. **Dix lancements n'attrapent pas que le hasard, ils attrapent le depot qui bouge.** Le dixieme `villetest` de cette version a rendu un maillage different des neuf premiers — pas par tirage, mais parce qu'un `.glb` avait ete rebati entre-temps (B.4). **Un banc lance une fois ne sait pas s'il mesure le monde ou l'instant.**

**Et une derniere, qui vaut pour la section 3.2 en particulier :** quand le code bouge pendant qu'on l'ecrit, **ecrire le mecanisme, dater la mesure, et dire ou est l'invariant.** Un mecanisme — « la consigne alterne de bord » — reste vrai apres le reglage ; un releve — « silence maxi 4,3 s » — ne survit pas a la valeur suivante de `TOWN_WEAVE`. Le plan doit porter le premier et pointer vers le banc pour le second.

**Quand un chiffre de ce document n'est pas suivi du banc qui l'imprime ou du calcul qui le pose, il est a verifier avant de s'en servir.** Et quand un calcul contient les mots « moins », « environ » ou « a peu pres », on le finit.