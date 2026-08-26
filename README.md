# Route de nuit — prototype

FPS au volant d'une Honda Civic EF (1990), sur une route de campagne, la nuit,
dans le brouillard. Pour l'instant : on conduit. C'est tout, et c'est fait exprès.

## Lancer

Ouvrir le projet dans Godot 4.8 et appuyer sur F5.

| Touche | Action |
|---|---|
| Z/W ou ↑ | accélérer |
| S ou ↓ | freiner |
| Q/A, D ou ←, → | tourner |
| **Maj** | **embrayage** |
| **Molette ↑ / ↓** | **monter / descendre les rapports** |
| **Clic molette** | **point mort direct** (embrayage enfoncé) |
| Espace | frein à main (maintenu en roulant, verrouillé à l'arrêt) |
| **Clic gauche maintenu** sur la clé de contact | **la prendre** (caméra libre) |
| **Molette ↑ / ↓**, clé en main | **démarrer** / **couper le moteur** |
| H | phares |
| Souris | regarder autour |
| **Clic droit maintenu** | **se pencher dans la direction du regard** (sauf arme en main : elle se lève) |
| **Clic gauche maintenu** sur le rétroviseur ou un pare-soleil | **le placer** (regard bloqué) |
| **Clic gauche maintenu** sur une manivelle de vitre | **tenir la poignée** (caméra libre) |
| **Molette ↓ / ↑**, poignée en main | **descendre** / **remonter** la vitre (la boîte ne bouge pas) |
| **Clic gauche** sur le plafonnier | **l'allumer / l'éteindre** — et le pare-brise se remplit de son reflet |
| F12 | capture d'écran |
| Échap | libérer la souris |

Les touches sont mappées en *physical keycode* : ZQSD sur AZERTY et WASD sur
QWERTY tapent les mêmes touches physiques, les deux marchent sans rien changer.

## La boîte

Manuelle, 5 rapports plus la marche arrière. La grille est linéaire :

```
R  ←  N  →  1  →  2  →  3  →  4  →  5
```

Molette vers le haut pour monter, vers le bas pour descendre. **Il faut
débrayer** (Maj) pour passer un rapport, sinon le HUD refuse et affiche
« DEBRAYE ». Pour désactiver cette contrainte : `require_clutch = false` dans
[car.gd](scripts/car.gd).

La boîte est verrouillée `shift_cooldown` secondes après chaque passage : sous
Windows un seul cran de molette produit plusieurs événements, et sans ce délai on
saute deux ou trois rapports d'un coup.

Vitesses maxi mesurées (`godot --path . -- geartest`), sur le rupteur sauf la
5e qui est limitée par la traînée :
**50 / 87 / 122 / 155 / 172 km/h**, et 0-100 km/h en **12,2 s**.

Le 0-100 était de 11,9 s avant le calage (voir « Caler ») : le départ passe
désormais par un régime qui monte depuis zéro au lieu de commencer au ralenti,
donc par le creux de couple, et les trois dixièmes sont là. Les vitesses maxi,
elles, ne bougent pas d'un km/h — le facteur qui rend le calage possible vaut 1
partout au-dessus de la vitesse de ralenti de chaque rapport.

**Attention en relevant ces chiffres :** les vitesses maxi se mesurent sur 10 s
*réelles* en `time_scale` 6, donc sur 60 s de jeu **si la machine suit**. Sur une
machine chargée elle ne suit pas, les rapports longs n'ont pas le temps de
converger, et on relit la fenêtre de mesure au lieu de la voiture — le même piège
qu'au paragraphe précédent, par un autre chemin. Une 5e qui s'arrête sous le
rupteur (ici 6536 tr/min) n'a pas fini de converger. Le 0-100 et le frein à main,
eux, comptent en temps *simulé* et ne craignent rien.

`engine_power` est passé de 6.0 à **4.2 m/s²** (0-100 : 8,1 s → 12,0 s) : la
voiture accélérait trop fort pour ce qu'elle est censée être. Les vitesses maxi
n'ont pas bougé — elles viennent de `GEAR_TOP` et du rupteur, pas de la poussée.
Seul le temps pour y arriver s'allonge, beaucoup sur les rapports longs où la
poussée n'excède la traînée que d'un ou deux dixièmes de m/s².

Piège du banc d'essai : il mesurait chaque rapport sur 20 s de jeu, trop court
pour que la 5e converge — on lisait la fenêtre de mesure, pas la voiture. Elle
est passée à 60 s.

Le modèle est arcade, pas une simulation : chaque rapport a une vitesse au
rupteur (`GEAR_TOP`) et une poussée (`GEAR_PULL`). Ça suffit pour que la boîte
se *pilote* — partir en 4e patine, rester en 2e hurle, et le régime moteur
affiché sert vraiment à décider quand passer.

**Le rupteur.** Quand le régime touche la ligne rouge (6800 tr/min), l'allumage
est coupé `limiter_cut_time` (60 ms) : plus de poussée, frein moteur, puis ça
repart — et ça rebondit à ~8 Hz. En prise, c'est ce qui fixe la vitesse maxi
de chaque rapport (`GEAR_TOP`). À vide (débrayé ou au point mort),
l'accélérateur vise *au-delà* de la ligne rouge et c'est le rupteur qui arrête
l'aiguille, qui rebondit de ~230 tr/min. Le son suit l'état `limiter_cut` de la
physique. En prise on teste la vitesse plutôt que le régime affiché : lissé par
un `lerp`, celui-ci n'atteint la ligne rouge qu'asymptotiquement.

Quand tu débrayes, la main droite quitte le volant pour aller sur le levier, le
levier se déplace dans sa grille en H, et le pied gauche appuie sur la pédale.

### Caler

Lâche l'embrayage trop bas et **le moteur meurt**. Il faut alors le relancer, et
ça se fait **à la clé** — voir « La clé de contact » juste après.

Ce n'est pas un test ajouté par-dessus le modèle, c'est un **plancher qu'on a
retiré**. Le régime en prise valait `idle + (v/GEAR_TOP)·(ligne rouge − idle)`,
qui donne le ralenti à l'arrêt : embrayage lâché, moteur calé sur 850 tr/min, la
voiture immobile en 5e ronronnait comme au point mort. Il est maintenant
multiplié par `v / creep_speed`, borné à 1 :

```
creep_speed(rapport) = GEAR_TOP · ralenti / ligne rouge
```

C'est la vitesse à laquelle un rapport fait tourner le moteur **à son ralenti**,
et elle sort du même tableau que tout le reste — rien à régler à la main, rien
qui puisse se désynchroniser de `GEAR_TOP` :

| | R | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| en dessous, il faut débrayer | 3,6 | 6,3 | 10,8 | 15,3 | 19,4 | 22,5 km/h |

**Au-dessus, le facteur vaut exactement 1** et le modèle est celui d'avant, au
tour près : les vitesses maxi, le 0-100 et la courbe de couple mesurés plus haut
sont tous relevés là, et aucun ne bouge. En dessous, le régime s'effondre, et
sous `stall_rpm` (450) le moteur meurt.

Personne n'a écrit qu'on calait plus facilement en 5e qu'en 1re : c'est la
**démultiplication** qui le veut, et elle tombe toute seule du tableau.

**Le délai avant de mourir n'est pas de la clémence, c'est ce qui rend le départ
possible.** À l'instant où l'on lâche l'embrayage à l'arrêt, la vitesse est
nulle, donc le régime aussi : un calage immédiat rendrait *tout* départ
impossible, y compris plein gaz. `stall_grace` (0,7 s) laisse à la voiture le
temps de prendre les quelques km/h qui remontent le régime — et si le pied reste
levé, elle ne les prend pas et ça cale. Le comportement qu'on voulait tombe tout
seul, sans qu'on ait à distinguer les deux cas. Et un vrai moteur ne s'arrête pas
non plus sur une image : il tousse d'abord.

Moteur mort, l'accélérateur ne commande plus rien et la boîte traîne un moteur
qui résiste (`stall_drag`, plus fort que le frein moteur ordinaire) : c'est ce
qui **plante** la voiture au lieu de la laisser rouler en roue libre.

**On démarre embrayé, et ce n'est pas une règle du jeu.** Une EF de 1990 n'a
aucun contacteur qui l'impose ; c'est la mécanique. Lancer un moteur mort avec un
rapport engagé, c'est demander au démarreur de pousser la voiture — il n'en a pas
la force. Elle avance de quelques centimètres, elle sursaute, et rien ne part.
C'est exactement ce que fait le jeu.

### La clé de contact

On ne démarre pas à une touche : **on vise la clé**, on maintient le clic gauche
pour la prendre, et la **molette** la tourne — vers le haut on lance, vers le bas
on coupe.

C'est **le geste de la manivelle de vitre**, et c'est voulu. La molette est le
seul mouvement de la souris qui soit *rotatif*, et une clé de contact, ça tourne :
le sens tombe alors tout seul — vers le haut on arme, vers le bas on coupe — au
lieu d'être une convention à retenir. La caméra reste libre, comme à la
manivelle : une clé, on la tourne sans la regarder.

Pour [interaction.gd](scripts/interaction.gd), [ignition.gd](scripts/ignition.gd)
**est** une manivelle : il expose `wind()`, donc le clic maintenu le fait passer
en `GRIPPING`, et `crank()`, donc les crans lui parviennent. Rien n'a eu à changer
là-bas — c'est tout l'intérêt d'avoir fait tenir le geste dans deux méthodes.

**L'angle de la clé montre l'état du moteur, il ne le commande pas.** Il est
déduit de `car` à chaque image et n'est jamais mémorisé : arrêt (0°), contact
(−30°), et la position démarreur (−55°) pendant le lancement. Elle en revient donc
toute seule quand le moteur prend, comme une vraie clé rappelée par son ressort,
et elle reste juste même si on lâche le clic en plein lancement.

Le démarreur, lui, **tourne seul une fois lancé**, jusqu'au bout de `start_time` :
la clé donne un *coup* de démarreur, elle ne le tient pas. C'est ce que permet un
geste ponctuel là où une touche se maintenait — un démarreur qui s'arrêterait au
relâchement du clic serait intenable à la molette.

Les trois pièces existaient déjà dans le `.glb` (`STR_Ignition` le barillet,
`STR_Key` le panneton, `STR_KeyHead` la tête) : seules les deux dernières passent
sous le pivot, le barillet est vissé à la colonne. **L'axe n'est pas deviné**,
c'est la droite qui joint le centre du barillet à celui de la tête — la clé
elle-même. Lire l'axe long de l'AABB du barillet donnerait le mauvais : il fait
20 mm de long pour 24 de diamètre, sa boîte est plus large que profonde. Son
*sens* est choisi pour pointer vers le conducteur, ce qui donne un sens à
« horaire » quelle que soit l'orientation du modèle.

Mesuré (`godot --path . -- stalltest`, avec fenêtre) :

| | |
|---|---|
| débrayé, à l'arrêt, en 1re | **850 tr/min**, il tient |
| le même, embrayage lâché | **cale**, puis 0 tr/min |
| plein gaz une fois calé | **0,00 km/h** — rien ne part |
| clé tournée, rapport engagé | ne démarre pas, la voiture **sursaute de 0,45 m/s** |
| clé tournée, embrayage enfoncé | **démarre**, 850 tr/min |
| la clé a tourné | arrêt **0°** → contact **−30°** |
| revenue de la position démarreur | oui (contact −30°, démarreur −55°) |
| molette vers le bas | **contact coupé**, clé revenue à **0°** |
| départ plein gaz depuis l'arrêt | **21,2 km/h sans caler** |
| même départ, pied levé | **cale** |
| à 5,0 km/h en 1re | **1156 tr/min**, tient |
| à 5,0 km/h en 5e | **cale** |

Le banc **injecte de vrais clics et de vrais crans** plutôt que d'appeler
`car.key_start()` par en dessous : ce qui doit être éprouvé, c'est la chaîne
visée → prise → molette. Appeler la méthode directement prouverait que le moteur
démarre, et rien du tout sur la façon dont on le démarre.

Il écrit aussi `19_cle_arret.png` et `19_cle_contact.png`, de part et d'autre du
geste. Ce n'est pas de l'illustration : **le sens de rotation ne se lit dans
aucun chiffre**. Un signe faux donnerait exactement les mêmes 30°, de l'autre
côté de l'axe, et tous les tests passeraient pendant qu'à l'écran la clé
tournerait à l'envers. Il faut le voir.

Deux pièges y sont tombés, tous deux du banc et non du jeu :

- **`--headless` ne peut pas cliquer.** `interaction.gd` ignore la souris tant
  qu'elle n'est pas capturée, ce qu'un moteur sans fenêtre ne peut pas offrir :
  la clé était visée, mais l'état restait `IDLE` et pas un cran ne passait. Tous
  les bancs à clics tournent donc avec une fenêtre.
- **Le sursaut se mesure PENDANT.** Le démarreur pousse la voiture puis s'arrête,
  et `stall_drag` la ramène à zéro en un dixième de seconde. Relever la vitesse
  une fois tout fini, c'est mesurer le retour au calme et conclure qu'il ne s'est
  rien passé. On suit donc la pointe.

Les deux dernières lignes sont le cœur du banc, et la vitesse y est **maintenue**
pendant la mesure. Pied levé, une voiture ralentit jusqu'à l'arrêt et finit par
caler dans n'importe quel rapport : un banc qui la laisse faire mesure le frein
moteur, pas la démultiplication, et il voit deux calages qui ne prouvent rien.
C'est le premier défaut qu'a eu celui-ci.

Le **frein à main** a deux comportements selon que la voiture roule ou non :

- **En roulant** — il est actif tant que tu tiens Espace, comme un frein de
  secours. Tu lâches, il lâche. La main droite reste sur le levier pendant ce
  temps.
- **À l'arrêt** — si tu l'as tenu jusqu'à l'arrêt complet (sous 0,3 m/s), il se
  **verrouille** : c'est devenu un frein de stationnement, il reste serré même
  après avoir lâché la touche. Un nouvel appui le desserre, et la main fait
  l'aller-retour vers le levier.

L'état « tenu » est lu directement dans l'entrée à chaque frame, pas via une
bascule : c'est ce qui le rend impossible à désynchroniser.

C'est un frein **arrière seulement** : 4 m/s² en roulant, contre 17 pour la
pédale. Il se raidit à 20 m/s² sous 4 m/s, sinon « serrer le frein » ne
tiendrait pas la voiture. Mesuré (`godot --path . -- hbtest`) :
**90 km/h → arrêt en 3,8 s**, et **0,0 km/h plein gaz en 1re, frein serré**.

C'était 4,4 s avant le calage, et la différence n'est pas dans le frein : à
freiner à mort en 4e sans débrayer, **le moteur cale en route**, et un moteur
calé retient la transmission plus fort qu'un moteur qui tourne (`stall_drag`
contre `engine_brake`). Le banc mesure donc désormais le frein à main *plus* un
calage — ce qui est bien ce que vit le joueur qui freine sans toucher à
l'embrayage.

Le **pied droit** passe de l'accélérateur au frein avec son propre
amortissement, et se soulève au passage. L'entrée de freinage passe de 0 à 1 en
une frame : sans ça, le pied se téléporte d'une pédale à l'autre.

## Tourner le volant

Les mains ne sont plus soudées à 10 h 10. Elles **tiennent** la jante et la
suivent au degré près ; quand une main arrive au bout de sa course, elle
**lâche, passe au-dessus du volant et se repose plus loin** pendant que l'autre
tient. C'est ce qui permet d'aller jusqu'aux 270° de `WHEEL_MAX_ANGLE` sans
qu'un bras ait à faire trois quarts de tour — l'ancien suivi saturait les deux
mains ensemble à 140° et la jante filait sous des paumes figées.

Une seule règle gouverne l'ensemble : **une main ne lâche que si l'autre tient**.
Quand la droite est au levier, à l'appui-tête, au frein à main ou qu'elle tient
un objet, la gauche ne peut plus lâcher : la jante finit par filer sous sa paume
(compression en tangente hyperbolique vers `GRIP_RESERVE`, 30°). L'ancien
comportement n'a pas disparu, il est devenu le cas particulier où il se justifie.

**Deux butées par main, pas une.** Le geste n'est pas symétrique : la main qui
*tire* — la gauche qui descend vers 7 h quand on braque à gauche — travaille
dans l'axe de son épaule et va loin (`GRIP_PULL`, 105°) ; celle qui *pousse*
traverse devant le buste et est en bout de bras bien avant (`GRIP_PUSH`, 65°).
C'est cette différence qui fait **alterner** les mains au lieu de les faire
lâcher ensemble : celle qui pousse arrive en butée 40° de volant avant l'autre,
et l'écart se conserve d'une prise à la suivante.

Les deux chiffres sont **mesurés**. `-- wheeltest` imprime la portée
épaule → poignet le long de la jante, en mètres :

| angle de la main | −125° | −75° | −25° | 0 | +25° | +75° | +125° |
|---|---|---|---|---|---|---|---|
| main droite | 0,662 | 0,630 | 0,634 | **0,650** | 0,670 | 0,710 | 0,727 |

Descendre de son côté ne coûte rien — la main droite est *plus près* de son
épaule à 4 h (0,63 m) qu'à 10 h 10 (0,65 m) — tandis que traverser coûte 2 cm
tous les 25°. C'est `GRIP_PUSH` qui borne cette traversée. En dessous de 65° la
main lâcherait dans un virage de route ordinaire, ce qu'aucun conducteur ne
fait ; au-dessus, l'avant-bras — **invisible**, le modèle n'a plus de bras —
traverserait le buste sans que rien ne le montre à l'écran.

**Il n'y a pas de rangement automatique.** Une main ne lâche que si elle y est
forcée, c'est-à-dire au bout de sa course : volant immobile, elle reste
**agrippée là où elle tient**, même de travers. C'est ce qu'on fait, et une main
qui se replace toute seule pendant qu'on ne tourne pas se remarque
immédiatement — un tic. Ce qui les ramène à 10 h 10 après une manœuvre n'est
donc pas un rangement, c'est le volant qui rentre et leur file sous les paumes
(voir plus bas), et il les y ramène tout seul.

Une version intermédiaire rangeait les mains au bout de 0,6 s d'immobilité, avec
deux seuils selon que le volant était droit ou tenu braqué. Elle a été retirée :
même bien réglée, elle produisait un mouvement que rien ne demandait.

Quatre pièges, tous trouvés par le banc et tous corrigés :

- **Le saut au lâcher.** Une main qui attend son tour est bornée par la
  compression ; partir de l'angle *brut* de la jante la faisait sauter d'un
  quart de tour sur l'image du lâcher. On part d'où la main est **vue**.
- **Les mains qui se traversent.** Elles se croisent forcément, c'est le geste :
  seul le retrait hors du plan de la jante les sépare (`REGRIP_LIFT`, 85 mm, en
  racine de sinus pour que la main se lève *d'un coup* et se repose doucement).
  À 45 mm et en sinus nu, le banc les relevait à 16 mm l'une de l'autre.
- **Se reposer sur l'autre main.** Pendant qu'une main traverse, l'autre
  continue de descendre avec la jante : c'est sa position **d'arrivée** qu'il
  faut dégager (`GRIP_SEPARATION`, 45°), pas celle qu'elle occupe au départ. Et
  cette position passe par la même compression — une main bloquée en butée était
  créditée d'une dérive qu'elle ne fait pas, on la croyait partie, et l'autre
  venait se poser dessus. 5 mm au relevé.
- **Le transfert de durée fixe.** À plein braquage il tenait la main suivante
  bloquée 180 ms, pendant lesquelles le volant tournait de 85°. Le geste presse
  donc le pas avec la vitesse de rotation (`REGRIP_TIME` 0,26 s → 0,13 s).

Les doigts s'ouvrent au décollage et se referment à la repose, dans le même
sinus que le retrait : une main qui se déplace poing fermé au-dessus du volant
se voit tout de suite.

### Le volant qui rentre tout seul

Sortie de virage, on ne *ramène* pas le volant : **on desserre les doigts et on
le laisse filer sous les paumes**, rendu au centre par le couple
d'auto-alignement des roues. C'est ce que fait le conducteur maintenant, et ça
ne s'invente pas dans `driver.gd` : `car.gd` sait seul faire la différence entre
une jante qu'on tourne et une jante qui rentre, puisque c'est lui qui distingue
l'entrée du joueur du rappel (`wheel_returning`, sous 2° de jante il n'y a plus
rien qui file). Il l'écrit dans `driver.wheel_slip`, comme `interaction.gd`
écrit `item_blend`.

Pendant le glissement, la main **cesse de suivre la jante** et rentre à 10 h 10
à son propre rythme (`SLIP_HOME`), sans rapport avec la vitesse de la jante —
c'est exactement ce qui distingue les deux gestes. Son point de prise est recalé
image par image, donc elle reprend le volant d'où elle est dès que le joueur y
retouche.

Effet de bord, et c'est le bon signe : le retour au centre ne demande plus
**aucun** changement de prise. Avant, la jante entraînant les mains, il en
fallait deux ou trois — les mains repartaient en arrière au lieu de rentrer.

Mesuré, plein braquage puis touche relâchée : la jante parcourt **215°**, les
mains **30°**, soit **14 %** du chemin ; les doigts se desserrent à **0,55** de
fermeture, et les mains finissent à 10 h 10 à un degré près.

### Une main prise : l'autre conduit à plat

Une canette, une arme — la main libre ne peut plus enserrer la jante : elle **se
pose à plat dessus et la fait tourner par appui**, du côté conducteur du volant,
**dos de la main vers le joueur**, paume sur la jante, doigts détendus dans le
prolongement de l'avant-bras. Un poing fermé, là, tiendrait la jante *et*
l'objet.

Piège de repère, et il retourne littéralement la main : `PALM_AWAY` est la
normale **sortante** de la paume — c'est ainsi que `_open_grip` la pose sur un
pare-soleil et que `held_offset` écarte l'objet tenu. L'envoyer sur l'axe côté
conducteur mettait donc la paume face au joueur, le dos contre le volant, et la
main passait de l'autre côté de la jante. C'est `-axis` qu'il faut viser.

**Et la main accompagne la jante d'un bout à l'autre du braquage.** À plat, le
poignet ne se tord pas et rien ne s'enroule autour du tube : les butées
`GRIP_PULL`/`GRIP_PUSH`, qui ne valent que pour un poing fermé, sont élargies à
toute la course du volant. La main suit donc les 270° au degré près au lieu de
buter à mi-chemin — mesuré : **+272° de main pour un volant à +270°**.

**Mais on ne conduit à plat que *pendant* qu'on tourne.** Le volant reposé, la
main libre **referme les doigts sur la jante** et la tient, comme n'importe
quelle main au volant : on ne reste pas la paume posée dessus à ne rien faire.
**Les deux sens ne se ressemblent pas**, et c'est voulu :

- **Se raccrocher est une question de temps.** `FLAT_GRAB_DELAY` (0,2 s) sans
  que la jante bouge, et la main se referme. Le délai évite qu'elle ouvre et
  referme entre deux corrections ; une demi-seconde, elle, se lisait comme une
  hésitation — on referme la main sur un volant dès qu'on cesse de le tourner,
  pas après réflexion. Mesuré, jante arrêtée net : **0,27 s**, fondu compris.
- **S'ouvrir est une question de CHEMIN.** Une main posée sur un volant ne se
  remet pas à plat parce qu'il a bougé : elle le fait quand le mouvement
  s'installe, et une correction de trajectoire n'est pas un mouvement qui
  s'installe. Il faut donc `FLAT_TURN_TRAVEL` (40°) de jante parcourus depuis
  qu'elle s'est agrippée, et le compteur repart de zéro dès que la jante se tait
  — sinon une suite de petites corrections finirait par l'ouvrir. Le fondu
  d'ouverture est aussi plus lent que celui de fermeture
  (`FLAT_OPEN_SMOOTH`) : on lâche une prise sans y penser, on la reprend d'un
  coup.

Réserve sur la mesure : le banc relève **124°** de jante avant l'ouverture, pour
un seuil de 40. L'écart est du **débit d'images**, pas du réglage — sous le
rendu complet la machine tombe à quelques images par seconde, et à 450°/s de
braquage une seule image vaut déjà 50 à 100° de jante. C'est `FLAT_TURN_TRAVEL`
qui fait foi ; monte-le si la main s'ouvre encore trop tôt à l'œil.

Seule la **pose** change alors, jamais la place de la main : les butées restent
celles de la main à plat tant que l'objet est en main. Les resserrer en même
temps ramènerait la main de 272° à sa butée d'un coup, c'est-à-dire un saut d'un
demi-tour de jante. Mesuré : en se raccrochant, elle bouge de **1,3°**.

Cette pose rend gratuite une chose qui était une rustine : une main à plat n'a
pas besoin de lâcher pour laisser filer la jante. C'est pour ça que le braquage
complet à une main ne produit aucun changement de prise.

La mesure ne dépend d'aucun état interne, elle se lit sur la transform de la
main : `palm_tilt()` donne l'angle entre le **dos** de la main et l'axe du volant
côté conducteur — **0°** à plat, 45° pour un poing refermé autour du tube,
au-delà la main est retournée. Mesuré, paquet réellement pris (vraie visée, vrai
clic) : **en tournant**, dos à **0°** et doigts à **0,12** de fermeture ;
**volant reposé**, dos à **45°** et doigts à **1,00** — elle s'est raccrochée.

Mesuré (`godot --path . -- wheeltest`), braquage complet dans les deux sens
puis retour au centre :

| | relevé |
|---|---|
| virage de route (volant à 50°) | **0 prise** — on ne lâche pas pour une correction |
| braquage à fond (270°) | **2 prises**, alternées |
| au moins une main sur la jante | **toujours** (minimum observé : 1) |
| écart minimum entre les deux mains | **0,117 m** |
| portée de la prise la plus tendue | **+0,056 m** sur la pose 10 h 10 (l'ancien suivi saturé : +0,08 m) |
| main droite au levier, braquage à fond | **0 prise**, main gauche bornée à 135° |
| volant rendu (rappel seul) | **0 prise** — la jante glisse, les mains font 10 % du chemin |
| volant figé à 162°, 2,5 s | les mains bougent de **0,0°** — elles restent agrippées |
| paquet en main, braquage à fond | **0 prise**, dos de la main à **0°** de l'axe, main à **+272°** |

## Prendre et reposer les objets

Un **paquet de cigarettes** est posé sur l'assise passager. Vise-le : il se met
en surbrillance et le HUD affiche « Clic gauche : prendre ».

- **Prendre** — un clic. Le bras part le chercher, puis le ramène devant toi.
- **Poser** — **maintiens** le clic : un fantôme translucide montre où l'objet
  va atterrir, et il suit ta visée. **Relâche** pour le lâcher là.

C'est la **main du conducteur** qui porte l'objet, pas la visée. Au clic, le bras
part le chercher (0,45 s), le ramène devant toi et le tient ; au clic suivant il
repart le poser. L'objet suit la main exactement, y compris pendant le trajet.
Le buste accompagne le geste (`REACH_LEAN`) mais **seulement quand on va chercher
loin** : sans ça l'épaule reste en arrière et le bras bute — le paquet sur le
siège passager est à 63 cm de l'épaule, pour 62 cm de bras.

Le point de maintien (`HOLD_POINT`) est **fixe dans l'espace de la voiture**,
surtout pas en local caméra : la main suivrait le regard et le bras se tordrait
à chaque mouvement de tête. Une main ne suit pas les yeux. Mesuré : la main
bouge de 0,0000 m quand la tête part à 160° à droite puis à gauche.

Si tu ne vises aucune surface, il reste en main et le HUD affiche « Vise une
surface ».

### Les objets sont simulés, mais dans le repère de la voiture

Le paquet tombe, glisse et se cale — **sans passer par le moteur physique**.

`RigidBody3D` a été essayé et abandonné. Les collisions de l'habitacle sont
accrochées à une caisse qui roule : à 170 km/h elles se téléportent de 0,8 m par
image, le solveur y lit une pénétration énorme et éjecte l'objet. C'était « le
paquet vole dans tous les sens ». Les rustines intermédiaires — `AnimatableBody3D`,
adhérence simulée, frottement coupé — n'ont fait que déplacer le problème.

Dans le repère de la voiture, **rien ne bouge**. [cig_pack.gd](scripts/cig_pack.gd)
y intègre lui-même sa vitesse et résout ses collisions contre la **forme relevée
sur le modèle** ([cabin_shape.gd](scripts/cabin_shape.gd)). C'est stable à
n'importe quelle vitesse, parce qu'il n'y a plus de vitesse du tout de ce point
de vue.

Ce qu'on ressent quand la voiture accélère, freine ou tourne vient des **forces
d'inertie** : `car.gd` publie `frame_accel`, son accélération dans son propre
repère (longitudinale, plus la centripète ω·v), et l'objet en subit l'opposé.

Quatre pièges rencontrés, tous corrigés — les deux qui manquent à la liste
d'origine (boîtes qui se chevauchent, plancher trop court) ont disparu avec les
boîtes elles-mêmes, voir « Une seule géométrie » plus bas :

- **Tunnelling** — une tôle d'une case se fait traverser par un objet qui tombe
  de 6 cm par image. L'intégration se fait donc en sous-pas d'**une demi-case**
  (1 cm) : deux positions successives se recouvrent toujours, et rien ne peut
  passer entre.
- **Pas d'adhérence statique** — le frottement était *visqueux* : il amortissait
  la vitesse après coup, sans jamais empêcher le départ. La moindre poussée
  mettait donc l'objet en mouvement, et il dérivait indéfiniment. C'est un
  frottement de **Coulomb** qu'il faut : un *seuil*. Sous `static_mu * g`
  (2,4 × 9,81 = 23,5 m/s²) la vitesse tangentielle est remise à zéro et la force
  d'inertie n'est pas appliquée du tout. Le seuil passe **au-dessus de tout ce
  que la conduite produit** : le pire cas n'est pas le frein seul (17 m/s²),
  c'est le frein *plus* le frein moteur, 3,4 de plus en 1re, soit 20,4 ; le
  moteur (4,2) et les virages (8) sont loin derrière. Il reste sous le plafond
  de `frame_accel` (60 m/s²), ce qui laisse la bande 23,5-60 aux **chocs** : un
  impact, lui, décroche tout.
- **Pointes d'accélération** — `frame_accel` se calcule en dérivant `speed` d'une
  image à l'autre. Un changement de rapport ou une coupure du rupteur y font un
  saut, donc une pointe à plusieurs centaines de m/s² sur une seule image : de
  quoi catapulter l'habitacle entier. `car.gd` la borne à 25 m/s² et la lisse.
- **La voiture tournait à 2 g** — le paquet tenait en ligne droite et lâchait
  dans le moindre virage. Ce n'était pas lui : le modèle de lacet ne plafonnait
  rien et produisait jusqu'à **2,1 g** latéraux, soit un rayon de 42 m à
  100 km/h — une monoplace. Tout objet posé dépassait donc son seuil d'adhérence
  dès qu'on tournait le volant. `max_lateral` (8 m/s², 0,82 g) plafonne
  maintenant le taux de lacet : au-delà la voiture sous-vire.

Un filet de sécurité remet quand même l'objet sur le siège s'il sort de
l'habitacle, plutôt que de le perdre.

Mesuré (`godot --path . -- packtest`), posé sur la planche de bord :

| | déplacement |
|---|---|
| accélération plein gaz jusqu'à 50 km/h | **0,000 m** |
| virage à fond de volant, 0,82 g latéraux | **0,000 m** |
| freinage d'urgence jusqu'à l'arrêt | **0,000 m** |
| choc | **0,068 m** |

### La visée aussi est sans physique

[interaction.gd](scripts/interaction.gd) ne lance **aucun rayon physique**. Tout
est résolu analytiquement en **espace voiture**, où la caméra, les objets et les
surfaces sont immobiles les uns par rapport aux autres :

- **objets** — test rayon/sphère (rayon 7,5 cm ; viser une boîte de 5 cm à un
  mètre au pixel près serait injouable) ;
- **surfaces** — on marche dans la grille de l'habitacle jusqu'à la première
  case pleine, et on se pose sur la tôle qu'elle contient.

C'est ce qui a corrigé « je ne peux pas saisir le paquet en roulant » : un
`StaticBody3D` accroché à une caisse qui roule ne transmet sa position au
serveur physique qu'au pas suivant. À 24 m/s le rayon passait **40 cm à côté** —
à l'arrêt l'écart était nul, d'où l'impression que ça ne marchait que garé.

**On ne pose que sur ce qui est à peu près plat.** Un pare-brise, une
contre-porte sont de la tôle comme le reste et le rayon les trouve ; y poser un
paquet n'aurait aucun sens. C'est la normale rendue par la grille qui tranche.

## Une seule géométrie, relevée sur le modèle

Trois choses posaient chacune leur question à l'habitacle — où peut-on poser un
objet, qu'est-ce qui l'arrête, sur quoi le mille-pattes marche-t-il — et
`cabin.gd` répondait par **trois listes de boîtes saisies à la main** :
`surfaces`, `solids`, `crawl_solids`. Elles décrivaient chacune une partie du
même habitacle, aucune ne décrivait le vrai, et **les trois défauts que voyait
le joueur étaient le même défaut**.

- **Un objet lancé s'arrêtait dans la paroi.** Les portières étaient déclarées à
  x 0,79, qui est la **tôle** ; la garniture qu'on voit est à 0,70. L'objet
  s'arrêtait donc proprement — **neuf centimètres derrière le panneau**. Rien ne
  le mesurait : `-- throwtest` contrôle les *fuites* hors de la caisse, et un
  objet enfoncé dans une portière n'a fui nulle part. Les deux défauts sont
  opposés, et la coque ne promettait que le premier.
- **On ne pouvait pas poser sur tout le tableau de bord.** Le fond de planche
  n'avait de boîte que côté passager. Le maillage, lui, court d'un montant à
  l'autre à 93-95 cm : la tôle était là, la surface de dépose non. Le commentaire
  qui justifiait l'absence — « c'est le bloc compteurs, encastré » — était faux,
  et la carte de hauteurs le dit : le capot des compteurs est à **0,944**, au ras
  de la planche.
- **Le mille-pattes ne marchait pas partout.** `crawl_solids` ajoutait à la main
  les trois faces verticales auxquelles on avait pensé — nez de planche,
  contre-portes, pare-brise. Les montants, le tunnel, le capot des compteurs, les
  dossiers, les bas de caisse n'y étaient pas, donc ils n'existaient pas pour lui.

Et les boîtes se contredisaient entre elles. `cabin.gd` s'imposait en toutes
lettres « aucune boîte ne doit en chevaucher une autre », parce que `prop.gd` les
résolvait **l'une après l'autre** et qu'un recouvrement fait défaire à la seconde
ce que la première vient de faire. La règle était tenue à la main : elle était
enfreinte **treize fois**.

### Ce qui remplace les trois listes

Un relevé du `.glb`, et un seul. [cabin_shape.gd](scripts/cabin_shape.gd) en
porte deux formes, parce qu'aucune ne sait faire les deux choses :

- **une grille de cases de 2 cm** — une case est pleine si un triangle du modèle
  la traverse. C'est ce qui **arrête**, et c'est ce qui attrape les faces
  *verticales* que rien d'autre ne voit : contre-portes, nez de planche, bas de
  caisse, tunnel, dossiers. Deux cases ne peuvent pas se contredire, ce qui
  retire la règle du chevauchement au lieu de la faire respecter ;
- **un champ de hauteurs** — la cote exacte de la tôle sous chaque colonne. C'est
  ce qui **porte** : la grille poserait l'objet au demi-centimètre près, ce qui
  se verrait ; le champ le pose au millimètre.

Les **surplombs tombent tout seuls** : une case n'est pleine que là où il y a de
la matière, donc le pédalier reste vide sous une planche de bord pleine, 60 cm
plus haut. Un simple champ de hauteurs aurait rempli le pédalier jusqu'à la
planche — c'est la raison d'être de la grille.

Le vitrage, lui, n'est **pas** dans le relevé : on le regarde au travers, et une
vitre pleine rendrait l'habitacle aveugle. Le haut de caisse reste donc quelques
boîtes (`cabin.shell`), mais c'est de la géométrie qu'on connaît — le pare-brise
est un plan, défini par ses deux lignes de baie, et les autres glaces sont des
plaques.

### Elle est cuite, pas calculée au démarrage

Rastériser 108 000 triangles coûte une minute. On ne la paie pas à chaque
lancement :

```bash
godot --headless --path . --script res://tools/bake_cabin.gd
```

écrit `assets/cabin_shape.res` (83 ko), que `cabin.gd` charge au démarrage. À
relancer quand `civic_interior.glb` change ; `cabin.gd` prévient si le fichier
manque, avec la commande.

Le relevé est **le même pour le jeu et pour les sondes**
([mesh_probe.gd](scripts/mesh_probe.gd)) : deux réponses à « où est la tôle ? »
finissent par diverger, et c'est exactement le défaut qu'on corrige.

### Quatre pièges de la cuisson, tous relevés au banc

- **Les creux fermés étaient vides.** La rastérisation ne marque que les cases
  *traversées* : elle produit une coque, pas un volume. Le tunnel, la console et
  les sièges étaient donc creux, et un objet qui y entrait n'avait plus rien pour
  l'en sortir — il tombait au fond et y restait. On remplit maintenant ce qui ne
  communique pas avec l'extérieur (**47 935 cases**). L'habitacle, lui, communique
  largement : le vitrage étant absent du relevé, les baies sont des trous béants.
  Un garde-fou vérifie que la place du conducteur est restée vide et refuse
  d'écrire sinon — si un jour le modèle fermait ses baies, ce remplissage
  avalerait la voiture entière sans que rien ne le montre.
- **Le champ de hauteurs était pris au centre de la case.** `prop.gd` s'en sert
  pour *poser* un objet, et un objet couvre plusieurs cases : il lui faut une
  borne **supérieure** de la tôle sous lui. Sur un coussin de siège, bombé, la
  tôle entre deux centres monte plus haut qu'aux deux centres, et l'objet s'y
  enfonçait. On prend donc le maximum sur neuf échantillons par case. Sur une
  surface plane les neuf sont égaux et le relevé reste exact : on ne perd de la
  précision que là où il y a une pente, et **du bon côté**.
- **Le recalage se battait avec la résolution.** Posé sur la tôle exacte, un
  objet est forcément *dans* la case qui contient cette tôle — une case fait
  2 cm. Les enchaîner faisait remonter l'objet à la case, redescendre au
  triangle, remonter : **9 %** des lancers ne se stabilisaient jamais. On résout
  d'abord, autant de fois qu'il faut, et on se pose **une seule fois**, à la fin.
- **La sortie la moins coûteuse passait par dehors.** La grille ne sait pas où
  est l'intérieur de la voiture : contre le bas de caisse, l'objet est à quelques
  centimètres de la portière et à un demi-mètre du milieu de l'habitacle, donc le
  moins coûteux est de le pousser **à travers la tôle**. La coque le ramenait,
  la grille le repoussait, et il restait planté dans le panneau. On passe
  maintenant les bornes de l'habitacle à la résolution : une direction qui fait
  sortir n'est pas candidate.

### Le plancher de la coque, et pourquoi 0,33

La coque (`HULL_MIN`/`HULL_MAX`) reste ce qu'elle était : une borne par axe, qui
ne peut pas fuir quels que soient l'angle, la vitesse ou le pas de temps. Mais
son plancher devait se mettre d'accord avec le relevé, et **les deux mauvaises
valeurs ont été essayées** :

| plancher de coque | ce qui se passe |
|---|---|
| **0,35** (l'ancien) | 2 cm **au-dessus** du plancher modélisé : c'est la coque qui arrête les objets, et ils flottent — de deux planchers en désaccord, c'est le plus haut qui gagne, et c'était le faux |
| **0,30** | elle passe **dessous**, et c'est pire : le maillage ne couvre pas les coins arrière, la coque y est le seul plancher, et les objets descendaient 3 cm sous le plan du sol, c'est-à-dire dans la tôle qui le borde — **92 %** des lancers finissaient dans `BODY_Floor` |
| **0,33** | les deux sont d'accord au millimètre |

Un filet ne doit ni dépasser ni manquer.

### L'écart qu'il y avait, et qui a motivé tout ça

[probe_surfaces.gd](tools/probe_surfaces.gd) lit le `.glb`, projette les
triangles plats sur une grille en x/z, garde le plus haut — c'est exactement ce
sur quoi un objet se poserait — et le compare aux boîtes historiques, que
`cabin.gd` garde pour cette comparaison-là et pour rien d'autre :

```bash
godot --headless --path . --script res://tools/probe_surfaces.gd
```

Le défaut ne se lisait dans **aucune coordonnée** : il fallait la carte du
maillage réel.

| boîte déclarée | ce qu'il y a dessous | écart |
|---|---|---|
| assises avant (plan 0,494) | 0,330 à 0,481 | **−164 à −13 mm** |
| banquette (plan 0,488) | 0,407 à 0,478 | −81 à −10 mm |
| casquette (plan 0,945) | 0,933 à 0,945 | −12 à 0 mm |
| planche passager (plan 0,930) | 0,915 à 0,930 | −15 mm |
| console (plan 0,600) | 0,330 à 0,830 | −270 à **+230 mm** |

Un objet posé sur le siège flottait donc de 1 à 16 cm, et la console dépassait
de 23 cm au-dessus de son propre plan — c'est le levier de vitesses, qui la
traverse.

La surbrillance passe par l'uniforme `emission` de `retro.gdshader`, noir par
défaut donc sans effet sur le reste. Elle pulse lentement : dans le noir, un
éclat fixe ne se distingue pas d'un reflet.

Banc d'essai : `godot --path . -- packtest` vise, prend, déplace et repose le
paquet en injectant de vrais clics, et vérifie qu'il redevient attrapable.

### Lancer

**Clic molette**, et ce qu'on tient part **dans l'axe du regard** à 4,5 m/s.
Poser vise une surface, montre un fantôme et fait faire tout un geste au bras ;
lancer ne vise rien et est immédiat. C'est le même objet, ce n'est pas le même
geste — on jette une canette sans regarder où elle tombe.

L'objet part avec sa vitesse **en espace voiture**, là où il vit déjà : jeté
vers le pare-brise à 170 km/h il traverse l'habitacle exactement comme à
l'arrêt. La voiture ne le rattrape pas, elle l'emmène.

Il **culbute** en vol, autour d'un axe perpendiculaire au lancer (un tour par
seconde à la vitesse de consigne), puis se **remet d'aplomb** en se posant. Sans
ça il garderait son inclinaison au sol et s'enfoncerait dans le siège : sa boîte
de collision est alignée sur les axes, elle ne tourne pas avec lui. Il revient
donc à la pose de repos du jeu, celle-là même que donne une dépose au viseur.

**Le même bouton passe au point mort** (`car.gd`). Les deux ne se marchent pas
dessus : `interaction.gd` est un *enfant* de la voiture dans l'arbre, et
l'entrée non gérée remonte des feuilles vers la racine. Il consomme donc le clic
quand une main est pleine, et le laisse descendre au levier quand elles sont
vides.

**L'habitacle était ouvert au-dessus de la ceinture de caisse.** Tant que les
objets ne faisaient que tomber et glisser, personne n'y montait jamais. Un objet
*lancé*, si : jeté vers le haut du pare-brise il passait par-dessus le tablier,
sortait de la caisse, et le filet de sécurité le reposait sur le siège — une
canette qui disparaît dans la vitre et réapparaît sur vos genoux. `cabin.gd`
ferme donc le haut de caisse : le pare-brise en **six marches** dont la pente est
*déduite* des deux lignes de baie (bas 0,93 m, haut 1,28 m), la lunette arrière,
et les glaces latérales, dont les cotes sont **lues sur la glace du modèle**
plutôt qu'écrites. En dessous de la ceinture, c'est la garniture qui arrête, et
elle vient du relevé — à sa vraie place (0,70) et non à celle de la tôle (0,79)
où l'ancienne boîte l'avait mise. C'est là que les objets s'enfonçaient.

Le pavillon n'a plus de boîte : le ciel de toit est dans le relevé, donc il
arrête ce qui monte, et un peu plus bas que la coque — à la garniture, pas à la
tôle.

Mesuré (`godot --path . -- throwtest`), paquet pris puis jeté au clic molette :

| | |
|---|---|
| écart entre la vitesse de départ et le regard | **0,00°** |
| vitesse de départ | **4,50 m/s** (consigne 4,50) |
| rapport engagé avant le lancer | **intact** (le clic n'a pas débrayé) |
| jeté droit dans le haut du pare-brise | monte à **1,29 m**, arrêté sous le pavillon (1,30) |
| bond inexpliqué par la vitesse (= fuite) | **0,039 m** |
| inclinaison une fois posé | **0,00°** de la verticale |
| mains vides, même clic | **point mort** |

L'écart mesuré est un **angle**, pas un point de chute : une vitesse de la bonne
longueur mais tournée de quinze degrés donnerait un point d'arrivée
parfaitement plausible dans l'habitacle, et un lancer qui part de travers, ce
qui se voit du premier coup d'œil.

## Les rétroviseurs

Les trois glaces — l'intérieure et les deux de portière — sont de **vrais
miroirs plans**, pas des textures peintes. [mirror.gd](scripts/mirror.gd) donne
à chacune un `SubViewport` et une `Camera3D`, et `cabin.gd` les fabrique
directement à partir des glaces du `.glb` : la transform du mesh donne le repère
(X droite, Y haut, Z normale), son AABB **locale** donne les côtes du panneau.
Prendre l'AABB monde serait faux — les glaces de portière penchent de 8°, et une
boîte englobante inclinée est plus large que le panneau qu'elle contient.

**La caméra est à l'œil réfléchi, pas au miroir.** C'est la seule différence qui
compte. Une caméra posée sur la glace et tournée vers l'arrière donne une image
figée, qui trahit le truquage dès qu'on bouge — et ici on bouge beaucoup
(regard arrière, tête à la vitre). Ici la caméra est au symétrique de l'œil par
rapport au plan de la glace, avec un **frustum asymétrique** dont la fenêtre au
plan proche est exactement le rectangle du miroir. L'image bouge donc comme dans
un vrai miroir, et elle se plaque pile sur le cadre sans réglage de champ.

`near` vaut la distance œil-glace, ce qui coupe gratuitement tout ce qui est
entre la caméra virtuelle et le plan du miroir. Sans ça le rétroviseur intérieur
montrerait le pare-brise et le capot, qui sont devant lui.

**Un rétroviseur, ça se règle.** Le modèle monte la glace intérieure à plat,
normale plein arrière. Or un miroir renvoie l'image symétrique du regard par
rapport à sa normale : vu de la place du conducteur, 33 cm à gauche, une glace
plate montre l'arrière-**droite**, pas ce qui suit la voiture. `_swivel()`
calcule la bissectrice entre « vers l'œil » et « vers ce qu'on veut voir », et
fait pivoter **la tête entière** du rétroviseur de 13° vers le conducteur — ne
bouger que la surface réfléchie laisserait une glace de travers dans son cadre.
Les glaces de portière sont déjà orientées dans le modèle et n'ont rien à
corriger.

Le conducteur est sur une **couche de rendu à part** (`DRIVER_LAYER`), que les
caméras de miroir ne regardent pas : le modèle est fait pour la vue subjective,
tête masquée, et un buste sans tête dans le rétroviseur serait pire que rien.

**Les feux arrière** ont été ajoutés pour ça. La nuit, sur une route déserte,
rien n'éclaire l'arrière de la voiture : les trois glaces étaient noires et on
ne pouvait pas voir qu'elles marchaient. Deux spots rouges peu plongeants
(portée 16 m) posent une flaque entre 7 et 14 m en arrière, exactement dans le
champ des glaces de portière. Ils suivent l'interrupteur des phares (H).

### Régler le rétroviseur intérieur

Vise-le — il se met en surbrillance — puis **maintiens le clic gauche** : le
regard se bloque et la souris oriente la glace. Relâche pour terminer, le réglage
est gardé. Débattement ±24° en lacet, ±15° en tangage.

Le regard *doit* se bloquer : viser et orienter avec le même geste est
impossible, on perdrait la glace de vue au premier mouvement. `car.gd` détourne
donc les événements de souris vers `interaction.adjust()` tant que
`interaction.adjusting` est vrai.

La sensibilité est la **moitié** de celle du regard : un miroir double l'angle,
tourner la glace d'un degré déplace l'image de deux.

Le rétroviseur est enfant de son pivot de tête : le régler emmène le boîtier, la
glace et la caméra virtuelle d'un bloc. Si le quad restait accroché à la cabine,
tourner la tête décalerait l'image du cadre.

**La main va s'y poser** et suit l'objet pendant le réglage (le pare-soleil
bouge sous elle) : main gauche pour le pare-soleil conducteur et le rétro
gauche, main droite pour le rétro intérieur, le pare-soleil passager et le
rétro droit. C'est possible depuis que le modèle n'a plus de bras : avant, l'IK
butait (73 cm d'épaule à rétro) et l'avant-bras étiré passait en travers de
l'écran, juste devant ce qu'on réglait.

Vérifié (`godot --path . -- shot`) : les trois caméras virtuelles tombent à
**0,0000 m** du symétrique calculé de l'œil, et les captures `15_*.png` montrent
ce que chaque glace reflète, sous l'éclairage de nuit réel.

Vérifié (`godot --path . -- mirrortest`), en injectant de vrais clics et
mouvements de souris : pendant le réglage la tête bouge de **0,0000 rad** et la
glace de **7,37°** ; la caméra virtuelle suit à **0,0000 m** ; après relâchement
la tête repart et le réglage ne bouge plus de **0,00°**.

## Les pare-soleil

Même geste que le rétroviseur : vise-en un, **maintiens le clic gauche**, le
regard se bloque et la souris lui donne l'angle que tu veux — n'importe lequel,
pas deux positions. Relâche pour terminer.

Un seul axe, celui de la tige, sur **90°** de course :

- **rangé** (le départ) — le panneau pointe vers le conducteur, sous le
  pavillon ;
- **déployé** — vertical, en travers du haut du pare-brise, 44 mm sous la ligne
  des yeux. Mesuré, parce qu'un pare-soleil qui ne descend pas sous les yeux ne
  sert à rien.

[cabin.gd](scripts/cabin.gd) lit l'axe sur la tige du modèle (`BODY_VisorRod_*`)
et n'y accroche que le panneau : le clip qui le retient rangé et le support sont
vissés au pavillon, et la tige est *sur* l'axe, la faire tourner ne se verrait
pas. Le matériau du panneau est dupliqué à la construction — celui du `.glb` est
partagé avec le ciel de toit et les montants, et sans ça viser un pare-soleil
ferait pulser la moitié de l'habitacle.

Deux angles ont demandé une mesure plutôt qu'une intuition :

- **Rangé « à plat », c'est vers le CONDUCTEUR.** Le modèle pose le panneau
  pointant vers le pare-brise ; le coucher à plat dans ce sens-là le collait
  contre la glace, pointe en avant, et on n'en voyait plus que la tranche.
- **Et pas rigoureusement à plat.** La tige est à 1,242 m, le ciel de toit
  commence à 1,234. À l'horizontale exacte le panneau se retrouve *à la hauteur*
  de la garniture, c'est-à-dire dedans — exactement le défaut qu'on venait de
  corriger. Il est donc rangé 7° plongeant, ce qui fait descendre son extrémité
  libre 13 mm sous la garniture. À l'œil ça reste « à plat », et un vrai
  pare-soleil rangé n'est jamais affleurant non plus.

Vérifié (`godot --path . -- visortest`), en injectant de vrais clics et
mouvements de souris : déployé il descend de **114 mm** et passe **44 mm sous
l'œil** ; rangé sa boîte englobante s'aplatit à **31 mm**, passe **derrière la
tige** (donc vers le joueur) et dépasse de **13 mm** sous la garniture.

## Les vitres

Une Civic de 1990 n'a pas de lève-vitres électriques : c'est **la manivelle**
qu'on manipule. Vise-la sur la contre-porte et **maintiens le clic gauche** :
la main saisit la poignée et y reste. **Roule ensuite la molette** — vers le bas
la vitre descend, vers le haut elle remonte. Lâche le clic et la main lâche la
poignée — la vitre reste où elle en est, à mi-course si c'est là que tu t'es
arrêté. **Trois tours** pour la course complète : ce que demande une vraie, et ça
reste lisible ; un seul tour ferait jouet.

La molette plutôt qu'une touche tenue : c'est le seul geste de la souris qui soit
**rotatif**, et il est déjà dans la main qui tient la poignée. On roule la
molette comme on roulerait la manivelle, et la course suit le poignet cran par
cran au lieu de défiler toute seule tant qu'une touche est enfoncée.

Un cran vaut **0,15 de course** (`step`) : sept crans du haut en bas, la longueur
d'un coup de molette continu, et assez fin pour s'arrêter sur une vitre
entrouverte de deux doigts. Les crans ne sautent pas à la vitre, ils s'empilent
et la manivelle les **rattrape** à `open_rate` (0,5 de course par seconde) — un
coup de molette rapide donne une manivelle qui tourne, pas une glace qui se
téléporte. Lâcher le clic **oublie** ce qui restait à rattraper, sinon la
manivelle finirait sa course poignée lâchée.

Le même cran **passe les rapports**. Les deux cohabitent comme le clic molette et
le lancer : `interaction.gd` est enfant de `car.gd` dans l'arbre, il voit
l'événement le premier et ne le consomme que la main *posée sur la poignée*.
Ailleurs, le cran redescend jusqu'au levier.

**La caméra reste libre**, contrairement au rétroviseur et aux pare-soleil. Ce
n'est pas une incohérence : ceux-là, on les *regarde* en les réglant, donc bloquer
le regard est ce qui rend le geste possible. Une manivelle, au contraire, on la
tourne **sans la regarder**, les yeux sur la route — la bloquer aurait retiré au
geste ce qui en fait l'intérêt. La souris ne commande donc rien pendant ce
temps-là, elle continue simplement de regarder autour.

`cabin.gd` monte deux pivots par portière :

- **la manivelle**, au moyeu, axe X. Seuls le bras et le bouton y sont
  accrochés : le moyeu est la rosace, vissée à la contre-porte, elle ne tourne
  pas. Le point de saisie de la main est le **bouton**, exprimé dans le repère du
  pivot — il tourne donc avec la manivelle au lieu de rester planté au centre.
- **les vitres**, un pivot sans rotation qu'on descend simplement en Y. Il en
  porte **deux** : le modèle d'habitacle et celui de carrosserie ont chacun leur
  glace, à 12 mm l'une de l'autre. N'en bouger qu'une laisserait l'autre en
  l'air, bien visible de l'extérieur — c'est ce que vérifie le banc d'essai.

Le pivot évite aussi d'avoir à se soucier du repère d'origine des pièces : les
portières du `.glb` pendent sous un `DOOR_*_Root` tourné de 90/90 degrés, où
« vers le bas » n'est pas Y du tout. Reparentées sous un pivot sans rotation,
elles retrouvent les axes de la voiture.

La course est de **26,5 cm**, la hauteur de la glace : baissée à fond, son bord
supérieur passe sous l'enjoliveur de ceinture et elle a disparu dans la portière.

Vérifié (`godot --path . -- windowtest`), en injectant de vrais clics, crans de
molette et mouvements de souris : poignée en main, la tête tourne de **0,264
rad** pendant la manœuvre et la souris ne fait **rien** tourner ; huit crans vers
le bas donnent **3,0 tours** de manivelle, la glace descend de **265 mm** et son
haut passe à 0,970 sous une ceinture à 0,998 ; les **deux** glaces bougent du
même nombre de millimètres ; huit crans vers le haut la remontent exactement d'où
elle vient. La **boîte ne bouge pas** pendant ce temps-là, embrayage pourtant
enfoncé : le cran s'arrête à la poignée.

Le relâchement est vérifié **à mi-course**, pas vitre fermée ni course finie :
six crans demandés, le clic lâché à 0,51 laisse la vitre à 0,51 — le reste des
crans est oublié — et la molette ensuite ne lui fait plus rien. En butée, ou une
fois la course rattrapée, il n'y aurait rien eu à prouver.

## Le plafonnier, et ce qu'il coûte

Vise le luminaire au pavillon et **clique** : la main monte le toucher, il
s'allume ou il s'éteint. L'habitacle sort du noir — et **le pare-brise se
remplit**.

C'est là tout le sujet. Allumer la lumière en roulant de nuit **se paie**, et ça
se paie de la seule façon qui tienne : pas une pénalité posée par-dessus, mais ce
que fait l'optique quand on éclaire l'intérieur d'une boîte vitrée. La planche de
bord se reflète dans la vitre et vient se poser **sur** la route.

### C'est un vrai miroir, pas un dégradé peint

[windshield_glare.gd](scripts/windshield_glare.gd) monte le pare-brise **comme un
rétroviseur** ([mirror.gd](scripts/mirror.gd)) : un `SubViewport`, une `Camera3D`
au **symétrique de l'œil** par rapport au plan de la vitre, un **frustum
asymétrique** dont la fenêtre au plan proche est exactement le rectangle de la
glace. Une glace de plus, simplement très grande et très inclinée.

On reflète donc l'habitacle **tel qu'il est** — la casquette, la console, les
aérateurs, le rétroviseur, et ce qu'on a posé dessus : un paquet laissé sur la
planche de bord se voit dans le pare-brise. Et l'image **bouge avec la tête**, ce
qu'aucune texture collée sur la vitre ne saurait faire.

Deux différences avec un rétroviseur, et elles font tout :

- **le mélange est additif**, pondéré par le **Fresnel**. Un rétroviseur
  *remplace* ce qu'il y a derrière ; un pare-brise laisse passer 96 % du paysage
  et *pose* son reflet dessus. C'est ce qui écrase le contraste de la route au
  lieu de la masquer ;
- **la caméra regarde vers l'intérieur.** Éteint, l'habitacle est noir et l'image
  l'est aussi : **le reflet s'éteint tout seul**, sans qu'on ait à le lui dire.
  Le facteur `energy` ne sert plus qu'à arrêter la passe de rendu quand il n'y a
  plus rien à refléter.

Le reste du [shader](shaders/windshield_glare.gdshader) n'est que des propriétés
du **verre**, jamais de ce qu'il reflète :

- **Fresnel.** Le verre renvoie 4 % de face et bien plus en rasant. Le pare-brise
  est couché de **59° sur la verticale**, donc on le regarde justement en
  rasant : c'est de là que vient la force du reflet, et c'est pour ça qu'il est
  plus marqué en bas de la vitre qu'en haut. Ce dégradé ne se peint pas, il tombe
  de la formule.
- **Le voile.** Une vitre n'est pas un miroir propre : l'épaisseur du verre et la
  poussière *étalent* une part de ce qu'elle reflète. C'est ce halo, et non
  l'image nette, qui lave les noirs de la route.
- **Les traces d'essuie-glace.** Elles restent accrochées à la **vitre** pendant
  que le reflet, lui, glisse dessous quand on bouge la tête. Les deux ne se
  déplacent pas ensemble — c'est exactement ce qu'on voit dans une voiture.

### Un flou étale, il ne recopie pas

Le voile a d'abord été **cinq canettes**. Posez-en une sur le tableau de bord et
elle se reflétait en cinq exemplaires, bien alignés.

Ce n'était pas un flou, c'étaient des **copies**. Le halo prenait *quatre*
échantillons de l'image réfléchie, écartés de 11 % de la vitre : à ce compte-là
on ne dilue rien, on duplique — l'original plus ses quatre fantômes, chacun à
14 % de l'original, largement de quoi les compter. Un flou demande assez de
points, assez rapprochés, et assez **faibles chacun** pour qu'aucun ne se
reconnaisse. Ils sont maintenant **douze**, en deux anneaux, et le plus lourd
pèse 8 % du total.

Deux détails s'y cachaient :

- **`repeat_disable`.** Un halo va chercher ses échantillons *autour* de chaque
  point, et près du bord ils sortent de l'image. En répétition — le défaut de
  Godot — ils reviennent par le côté opposé, et le pare-brise se met à refléter
  son bord gauche sur son bord droit.
- **L'aspect.** La vitre est deux fois et demie plus large que haute. Un rayon
  exprimé en coordonnées de texture y donne une **ellipse couchée**, trois fois
  plus étalée en travers qu'en hauteur ; il est donc corrigé de cet aspect au
  moment de l'échantillonnage.

Le plan de la vitre n'est pas relevé sur le `.glb` : il est **déduit des deux
lignes de baie** que [cabin.gd](scripts/cabin.gd) déclare déjà, celles-là mêmes
qui ferment le pare-brise contre les objets lancés. Un pare-brise est plan, ces
deux lignes le définissent entièrement, et le reflet ne peut donc pas glisser à
côté de la vitre sur laquelle il se pose. Les caractéristiques de l'ampoule sont
**lues sur elle** (`dome_light.bulb()`) plutôt que recopiées, et l'état de la
lampe est relu **à chaque image** : deux jeux de constantes finissent toujours
par diverger, et un reflet resté allumé sous une lampe éteinte serait
indébuggable.

### Ce qu'il prend à la route

Ce qu'on mesure n'est pas « y a-t-il un reflet » — une capture le dirait. C'est
**ce qu'il prend à la route**. Le banc lit la même fenêtre de pare-brise, lampe
éteinte puis allumée, **voiture figée** : les deux images doivent être la même
image à la lampe près, sinon la route défile entre les deux, le contraste change
tout seul et on n'attribue plus rien à personne.

Un voile lumineux a une signature qu'on ne peut pas confondre : il fait **monter**
la luminance et **baisser** le contraste rapporté à cette luminance. Une image
simplement plus claire ferait monter les deux. C'est donc le troisième chiffre qui
dit si la vision empire vraiment.

Mesuré (`godot --path . -- glaretest`) :

| | luminance | contraste (RMS / moyenne) |
|---|---|---|
| plafonnier éteint | 0,1275 | 0,7303 |
| plafonnier allumé | 0,1746 | **0,4706** |
| | **+37 %** | **−36 %** |

**Ces valeurs bougent de quelques points d'un lancement à l'autre**, et c'est
normal : la voiture se fige là où elle se trouve, donc jamais deux fois devant le
même bout de forêt. C'est l'écart entre les deux lignes qui se lit, pas la
troisième décimale.

La lampe est actionnée **par le vrai geste** (visée, clic, la main qui monte au
luminaire) et non en écrivant `on` par en dessous : ce qui doit être éprouvé,
c'est que le reflet suive l'interrupteur, pas qu'un uniforme fasse ce qu'on lui
demande.

**La fenêtre de mesure est serrée exprès.** Prise plus large, elle mordait sur le
pare-soleil rangé et sur le rétroviseur intérieur, deux pièces que le plafonnier
éclaire en plein : elles faisaient à elles seules la moitié du « voile » mesuré,
et on aurait réglé le reflet sur la luminosité du plastique qui l'entoure.

### Combien de fois une canette se reflète-t-elle ?

Le défaut a été rapporté comme ça — *une canette posée sur le tableau de bord s'y
reflète cinq fois* — et c'est comme ça qu'il se mesure.

On ne mesure pas l'image, on mesure **ce que la canette y ajoute** : deux captures
où seule la canette change. La route, la planche, le halo, les traces d'essuie-
glace, tout s'annule, et il ne reste dans la bande basse du pare-brise que ses
reflets à elle. Compter des bosses dans l'image entière ne voudrait rien dire —
l'habitacle en a des dizaines, et c'est normal. Ici, **chaque bosse au-delà de la
première est une canette de trop**.

La mesure se fait **amplifiée** (`strength` poussé à 8) : au réglage de jeu le
reflet d'une canette pèse un niveau sur 255, et le tramage plein écran le noie.
C'est le nombre de copies qu'on compte, pas leur luminosité.

| | reflets |
|---|---|
| une canette sur la casquette | **1** |
| **témoin** — une seconde à 24 cm | **2** |

**Le témoin n'est pas décoratif.** Un banc qui annonce « un seul reflet » sans
avoir jamais su en voir deux n'annonce rien du tout : il aurait pu répondre 1
parce qu'il est aveugle. C'est la deuxième ligne qui donne son sens à la première.

Une version intermédiaire mesurait à la place la **finesse de détail** du halo
(une copie garde le détail, un flou l'efface). Elle a été retirée : au niveau où
vit le halo, elle ne mesurait que le bruit de quantification et annonçait un
défaut là où il n'y en avait plus. Une mesure qui ment est pire que pas de mesure.

### Il bouge avec la tête

C'est ce qui sépare un reflet d'une décalcomanie, et aucun des chiffres ci-dessus
ne le dirait : une texture collée sur la vitre donnerait exactement le même voile.

La mesure se fait sur la **soustraction** allumé − éteint, pas sur l'image.
Il le faut : décaler l'œil déplace aussi la route, les arbres et les montants, et
un centre de gravité lu sur l'image entière suivrait tout ça sans qu'on sache ce
qui a bougé. La différence, elle, ne contient plus que ce que la lampe a ajouté.

Œil décalé de **16 cm** vers le passager, sans que le regard tourne : le centre du
reflet se déplace de **54 px en x et 25 px en y** (54 à 77 px selon le relevé).

### Le calibrage

`strength` est le seul nombre arbitraire de l'affaire, et c'est le réglage de
jouabilité : le Fresnel donne la **forme** du reflet, celui-ci sa **présence**. Le
banc balaie la plage en une seule exécution — le régler à l'œil, une valeur par
lancement, reviendrait à comparer des images prises sur des routes différentes.

| `strength` | 0,5 | 1,0 | 1,5 | 2,0 | **2,8** | 3,5 | 5,0 |
|---|---|---|---|---|---|---|---|
| luminance | +11 % | +17 % | +23 % | +29 % | **+37 %** | +44 % | +58 % |
| contraste perdu | −16 % | −22 % | −27 % | −31 % | **−36 %** | −39 % | −44 % |

**2,8** est la valeur retenue. Elle est montée de 2,0 après essai à l'écran : le
reflet y était juste, mais trop discret pour qu'on hésite à laisser la lampe
allumée — et une contrepartie qu'on ne pèse pas n'en est pas une. À 2,8 le voile
se voit sans qu'on le cherche et la route reste lisible.

Le plafond est vers 5 : au-delà, les arbres disparaissent purement et simplement
du brouillard, ce qui n'est plus une contrepartie mais une punition. La courbe
s'aplatit d'ailleurs — le contraste perdu ne gagne que 8 points de 2,8 à 5,0,
pour 21 points de voile en plus. On paie de plus en plus cher de moins en moins
d'effet.

## Regarder derrière

Au-delà de 62° de rotation de tête, le conducteur ne se contente pas de tourner
les yeux : **la caméra se déplace**, façon Euro Truck.

- **À droite** — jusqu'à 160° (torsion du buste 40° + rotation du cou 120°). Le
  buste pivote, la caméra glisse entre les deux appuis-tête et la main droite
  quitte le volant pour se poser sur l'appui-tête passager. La gauche reste au
  volant. On voit vraiment la route derrière, par la lunette.
- **À gauche** — le buste se penche, la tête sort par la vitre et la main gauche
  s'agrippe au haut de la portière. La droite reste au volant. La limite va
  jusqu'à 165° : en dessous de 150 on regarde le champ, pas le flanc de la voiture.

Les deux mouvements sont lissés (`lerp` à 7/s) pour donner du poids à la caméra,
et accompagnés d'un léger roulis.

Les **feux de recul** s'allument en marche arrière. Sans eux, se retourner ne
montrait qu'un mur noir.

La **lunette arrière est ouverte**, comme le pare-brise : à la place d'un panneau
plein, il n'y a que les montants C et la traverse basse. Sinon on a beau tourner
la tête, on ne voit que de la tôle.

Réglages dans [car.gd](scripts/car.gd) : `HEAD_BACK`, `HEAD_OUT`,
`look_back_start`, `lean_out_start`, `yaw_limit_left`, `yaw_limit_right`, et
`TWIST_MAX` dans [driver.gd](scripts/driver.gd) pour la torsion du buste.

## Se pencher

Se retourner et sortir la tête sont **déduits** de l'angle du regard. Se pencher
est le seul mouvement que le joueur **décide** : **clic droit maintenu**, et le
buste part dans la direction de la caméra.

Un seul geste, trois usages : se pencher au pare-brise à un feu, fouiller devant
le siège passager, et aller chercher ce qui traîne sur la banquette arrière.

**On avance exactement le long du regard.** C'est ce qui rend le geste
pilotable : ce qu'on a sous le viseur y reste, puisqu'on se déplace sur son
rayon. La première version n'en prenait que la composante horizontale, la
verticale réduite — et le buste passait *au-dessus* de ce qu'il visait. Une
canette posée à l'arrière finissait sous le menton, à 70° de plongée pour 62° de
débattement de nuque : plus moyen de la viser, donc plus moyen de la prendre.

**La longueur est constante** (`lean_reach`). Une version l'écourtait le long du
regard pour s'arrêter court de la première surface rencontrée : très bien tant
qu'on ne bouge pas la tête, catastrophique dès qu'on tourne. En balayant la vue,
la distance à la surface visée change en permanence — la planche est à 90 cm, la
console à 60, le vide à l'infini — donc la longueur du mouvement avec elle. La
caméra avançait et reculait le long de son propre axe : **un zoom**, et rien
d'autre.

Deux garde-fous, tous deux positionnels :

- `lean_clear` (0,25 m) — de combien la tête reste **au-dessus** de ce qui est
  posé sous elle (assises, banquette, console, planche, plancher). Une
  correction verticale : on remonte la tête, on ne raccourcit pas le mouvement.
- `LEAN_MIN`/`LEAN_MAX` — la boîte de l'habitacle, plus `LEAN_WHEEL_Y` :
  au-dessus du volant, la tête ne descend pas sous sa jante. En fondu, pas par
  un test franc, sinon la caméra sauterait de 15 cm en passant la console. La
  boîte est volontairement large — dès qu'une borne mord, elle pousse la tête
  *hors* du rayon du regard et casse la propriété ci-dessus.

Le corps suit : le buste à 85 % (le cou fait le reste), le bassin à 25 % — on
glisse sur l'assise, on ne quitte pas le siège. Les pieds restent aux pédales.

**Les mains ne quittent pas le volant** — elles changent de prise *dessus*
(« Tourner le volant »), mais ne vont se retenir nulle part ailleurs. Une
version l'a essayé — passé un
certain débattement, la main lâchait la jante pour se retenir à la console ou au
dossier passager, au motif que l'épaule s'en éloigne. Mais on *conduit* : une
main qui quitte le volant dès qu'on se penche coûte plus cher que les quelques
centimètres d'allonge qu'elle économise. Et le prix mesuré s'est révélé nul —
`-- leantest` relève **×1.000 d'allongement sur les deux avant-bras** dans
toutes les poses, parce que le buste emmène les épaules avec la tête au lieu de
la laisser partir seule.

### S'enrouler autour du siège

Se tourner franchement à droite **et plonger le regard**, c'est aller chercher
quelque chose derrière soi. Le buste quitte alors le dossier **de lui-même** —
pas besoin du clic droit, c'est le geste qui déclenche (`wrap_yaw` 105°,
`wrap_pitch` 12°). La plongée compte autant que le lacet : on se retourne *aussi*
pour reculer, plein arrière mais le regard à l'horizontale, et la tête ne doit
surtout pas partir se glisser entre les sièges à ce moment-là.

On ne se vrille pas sur place, on **contourne le dossier**.

**L'enroulement vise une pose fixe** (`HEAD_WRAP`), et c'est tout l'intérêt.
Il est déclenché par la rotation de la tête ; s'il déplaçait la tête *le long du
regard* comme le fait le clic droit, tourner ferait avancer et reculer la caméra
sur son propre axe — un zoom. Une fois la place prise, entre les deux dossiers,
**tourner la tête ne déplace plus rien** : `-- leantest` balaie toute la
banquette et relève **0 mm** de déplacement. On regarde autour de soi depuis une
place qu'on a prise, comme quand on s'est vraiment retourné dans une voiture.

Les marges de relâchement (`WRAP_YAW_RELEASE` 55°, `WRAP_PITCH_RELEASE` 25°) sont
larges, et pas par prudence : s'enrouler déplace la tête d'un demi-mètre, ce qui
change de plusieurs dizaines de degrés le relevé de ce qu'on regarde. Une canette
visée à 123° depuis le siège n'est plus qu'à 68° une fois entre les dossiers.
Avec une marge étroite, la suivre des yeux faisait sortir de la zone, donc
revenir au siège, donc la renvoyer à 123° : le buste faisait la navette et
l'objet devenait inattrapable. On s'enroule sur un geste franc, on se déroule
quand on revient vers l'avant ou qu'on relève les yeux — pas entre les deux.

Le clic droit garde son rôle : c'est lui qui penche vers l'**avant** (boîte à
gants, plancher), là où l'enroulement ne se déclenche pas.

- `TWIST_MAX_LEAN` — 95° de torsion contre 40° assis. C'est le chiffre qui fait
  passer l'épaule droite *derrière* le plan du dossier (z 0,53) au lieu de la
  laisser coincée devant, où le bras bute dessus.
- `SPINE_WRAP` — l'axe du mouvement recule de 0,44 à 0,56, vers le dossier. Sans
  ce recul, l'épaule tourne autour d'un axe placé *devant* le dossier et revient
  vers l'avant au lieu de passer derrière.

Les deux conditions comptent : se retourner seul garde le dos calé contre le
dossier — ce qui est justement ce qui empêche de s'enrouler ; se pencher seul,
vers l'avant, n'a aucune raison de déplacer l'axe. Le mélange est
`look_back × lean_amt`.

Mesuré, enroulé : **épaule droite à z = 0,80 à 1,07** selon l'angle, largement
derrière le dossier (0,53), et la canette arrière à **0,48 m** de cette épaule
pour 0,58 m de bras — attrapée **sans toucher au clic droit**.

### Ce que ça débloque : la banquette arrière

Assis, une canette posée à l'arrière est à **0,78 m de l'épaule pour 0,58 m de
bras**. Le geste existait — mais `_set_bone` allongeait l'avant-bras pour arriver
au bout, et un bras de gorille se voit immédiatement. Penché, la même canette est
à **0,24 m** : elle se prend pour de bon, avant-bras au repos.

Trois réglages accompagnent le mouvement :

- `REACH_LEAN_OFF_SEAT` (0,30 contre 0,13 assis) — déjà penché, le dos a quitté
  le dossier : le buste est en porte-à-faux, libre d'aller chercher les derniers
  centimètres.
- `lean_yaw_bonus` (+30°, soit 190°) — les 160° assis sont la limite d'un dos
  calé contre son dossier. Il s'applique **des deux côtés**, et pas par symétrie
  décorative : la direction du regard est un seul nombre, et les deux butées en
  découpent un intervalle. Tant qu'il ne couvre pas le tour complet, il reste un
  secteur — juste derrière — qu'on ne peut atteindre par aucun des deux côtés
  alors qu'il est physiquement devant les yeux.
- `pitch_limit` 70° et non 62° — enroulé, on est *au-dessus* de ce qu'on va
  chercher et le regard y plonge de plus de 60°. À 62, une canette derrière son
  propre siège demandait 63° : un de trop, et elle devenait impossible à viser
  donc à prendre.

Banc d'essai : `-- leantest`, **avec une fenêtre** (se pencher demande la souris
capturée, que `--headless` ne fournit pas). Il mesure épaule → objet assis puis
penché, l'allongement des deux avant-bras, la position de l'épaule droite par
rapport au dossier, vérifie que la tête reste dans la caisse, et **balaie le
regard enroulé pour contrôler que la caméra ne bouge pas** — c'est le test
anti-zoom, seuil 20 mm sur l'axe du regard.

Réserve honnête : sa boucle de visée ne se cale pas sur ce qui est pratiquement
**plein arrière**. À un demi-tour de là, le lacet requis bascule d'un bord à
l'autre pour quelques centimètres de tête, et le banc part du mauvais côté. Ce
qu'il établit sur ces points-là, c'est la **pose** — portée, enroulement,
allongement — et elle est bonne. La *prise* n'y est prouvée que pour l'arrière
côté passager, où elle passe de bout en bout. Une souris n'a pas cette
discontinuité, mais ça reste à confirmer manette en main.

## Le son du moteur

Il n'y a pas d'enregistrement : le moteur est **synthétisé**, comme le reste.

```bash
python tools/make_engine_sounds.py
```

écrit `assets/audio/engine/engine_on_0900.wav`, `engine_off_0900.wav`, … jusqu'à
7000 tr/min (numpy seulement). Ajouter un régime, c'est ajouter un nombre dans
`RPM_POINTS` et relancer : le jeu découvre les fichiers tout seul.

**Pourquoi plusieurs boucles.** Une seule boucle pitchée de 850 à 6800 tr/min,
c'est ×8, trois octaves : ça sonne comme un jouet, parce que les résonances
de la ligne d'échappement et de la caisse montent avec le régime. Avec une
boucle tous les ~40 %, [engine_audio.gd](scripts/engine_audio.gd) prend à
chaque image **les deux boucles qui encadrent le régime**, les pitche pour
qu'elles jouent *exactement* à ce régime (`pitch = régime / régime_de_la_boucle`,
donc jamais plus de ~20 %) et les fond l'une dans l'autre. C'est ça qui fait
les montées et les descentes : le régime de `car.gd` est continu, le son le
suit sample près.

**Comment une boucle est faite.** Un 4 cylindres 4 temps explose deux fois
par tour : la fréquence de « tir » vaut `régime / 30`, 28 Hz au ralenti,
227 Hz au rupteur. Chaque boucle, à un régime fixe, c'est :

- **l'échappement** — un train d'impulsions, une par explosion, attaque raide
  (0,6 ms, c'est le mordant ; plus court, ça grésille) et décroissance sur
  120° de vilebrequin. Les
  quatre cylindres n'ont pas tout à fait la même force ni le même calage,
  ce qui crée les demi-ordres qui font entendre un 4 cylindres et pas une
  sirène. Le tout passe dans un filtre à **résonances fixes** (boom de caisse
  à 62 Hz, ligne à 128/215/390 Hz, tôle du tablier qui coupe raide au-dessus
  de 3 kHz), en phase minimale pour que la résonance *suive* le coup ;
- **l'admission** — du bruit haché au rythme des soupapes, filtré autour de
  330 Hz, presque muet pied levé ;
- **la mécanique** — un sifflement de courroies qui monte avec le régime,
  très loin derrière (−25 dB). Les tocs de culbuteurs existent dans le script
  mais sont à zéro : du siège on ne les entend pas, et à 450 clics par seconde
  ça grésille. L'oreille est 20 à 30 dB plus sensible à 3 kHz qu'à 30 Hz :
  un souffle « négligeable » sur un spectre ne l'est pas à l'écoute.
  `--no-noise` rend l'échappement seul, pour diagnostiquer.

Chaque régime existe en deux couches, **`on`** (gaz) et **`off`** (frein
moteur : explosions faibles et irrégulières, admission muette), fondues selon
la *charge*, l'accélérateur lissé avec une attaque plus vive que le relâché.
Une troisième, **`out`**, ne sert qu'aux vitres ouvertes (voir plus bas).

**Boucles en phase.** Chaque fichier contient un nombre *entier* de cycles
moteur et commence sur l'explosion du cylindre 1 ; un chunk `smpl` porte la
boucle, Godot la détecte à l'import. Comme toutes les lectures démarrent à la
même image, les boucles restent en phase entre elles : en les fondant, les
impulsions s'additionnent au lieu de se battre. D'où un fondu **linéaire**, pas
à puissance constante.

### Le démarreur et le calage

```bash
python tools/make_starter_sounds.py
```

écrit `assets/audio/starter/starter.wav` (bouclée) et `stall.wav`.

**Un démarreur, ce sont deux machines à la fois**, et c'est leur superposition
qui fait reconnaître le bruit. Le moteur électrique tourne treize fois plus vite
que le vilebrequin (pignon de 9 dents sur une couronne de 120) : à 250 tr/min de
vilebrequin il fait 3300 tr/min, et ses 9 dents engrènent à ~500 Hz — c'est le
**sifflement**, la partie aiguë, celle qui ne varie pas. Dessous, le moteur
thermique entraîné n'explose pas, il **comprime** : deux fois par tour, soit
8,3 Hz, et c'est le « wouh-wouh-wouh » qu'on compte quand une voiture a du mal à
partir. Le sifflement seul fait perceuse ; les compressions seules font moteur au
ralenti.

`STARTER_RPM` y est recopié depuis `car.gd` : la cadence des compressions du
fichier en dépend, et l'aiguille du compte-tours la contredirait.

**Le calage n'est pas un fondu.** Un moteur qui cale ne baisse pas le volume : il
**ralentit**, ses compressions s'espacent, et il s'arrête sur l'une d'elles — la
plus forte et la plus grave, celle que le vilebrequin n'a plus l'énergie de
passer. Le fichier suit donc un régime qui tombe de 850 à 0 et place ses coups là
où la **phase** du vilebrequin franchit un demi-tour, au lieu de les espacer « de
plus en plus » à la main. Un fondu de volume, lui, s'entendrait comme quelqu'un
qui baisse la radio.

Côté jeu, l'extinction demande **les deux moitiés** : `car.gd` fait plonger le
régime, les boucles moteur le suivent en pitch, et le nouveau paramètre `running`
de [engine_audio.gd](scripts/engine_audio.gd) éteint le volume au même rythme.
Sans `running`, on entendrait le moteur descendre indéfiniment dans les graves ;
sans la descente de régime, on entendrait quelqu'un couper le son. Pendant le
démarreur, en revanche, `running` tombe à zéro d'un coup : `starter.wav` contient
déjà les compressions du moteur entraîné, et les deux ensemble feraient deux
moteurs.

Le raccord de la boucle est **mesuré**, pas supposé : 0,031 d'écart entre le
dernier échantillon et le premier, pour un saut interne maximal de 0,046. Un
raccord qui dépasse ce que le signal fait déjà tout seul s'entend comme un clic à
chaque tour.

Le reste est cosmétique : flottement du ralenti (`wobble`), rupteur qui hache
(`limiter_hz`), volume qui monte avec le régime et la charge (`volume_db`).
Les résonances et l'équilibre des couches se règlent en tête du script Python
(`exhaust_response`, `layer_params`).

Banc d'essai : `godot --path . -- audiotest` imprime, pendant un coup de gaz
puis un départ en 1re, les boucles choisies, le pitch et les volumes, puis
passe un rapport et tire le frein à main pour vérifier les sons de l'habitacle.

**Descente de régime.** À vide (débrayé ou au point mort), le régime retombe
linéairement à `rpm_fall_rate` = 3500 tr/min/s — de la ligne rouge au ralenti
en 1,7 s, l'inertie du volant moteur qui freine à couple constant. Avant, il
retombait en `lerp` à 7/s comme la montée : 6000 → 1700 en un quart de seconde,
inaudible. En prise, le régime suit toujours les roues à 7/s.

## Les autres sons

Même principe, tout est synthétisé par `python tools/make_cabin_sounds.py`
dans `assets/audio/cabin/`, et joué par [cabin_audio.gd](scripts/cabin_audio.gd).

**La route et le vent dépendent de la vitesse, pas du régime.** C'est leur
écart avec le moteur qui fait sentir les rapports : en 2e à fond le moteur
hurle et le vent est timide, en 5e c'est l'inverse.

- **Route** — grondement des pneus à travers le plancher (25–350 Hz, bosse de
  caisse à 70 Hz), plein niveau à `road_full_speed` (30 m/s) et pitché de 0,85
  à 1,2 avec la vitesse.
- **Vent** — deux boucles, un souffle sourd (< 600 Hz) et un souffle ouvert
  (jusqu'à 3 kHz), fondues l'une dans l'autre de `wind_start` (4 m/s) à
  `wind_full` (40 m/s). Elles partagent les mêmes rafales, donc le fondu ne
  pompe pas.

Les boucles de bruit sont construites directement en fréquence (amplitude
voulue × tirage aléatoire, phase aléatoire, FFT inverse) : elles sont
parfaitement périodiques, sans couture ni fondu. Les rafales sont une
modulation lente à nombre entier de cycles, pour la même raison.

**Levier et frein à main** : synthèse modale, quelques sinus amortis (le
« tonc » de la tringlerie vers 60–200 Hz, le « toc » vers 500–1300 Hz, le
« clic » du cliquet vers 2–3 kHz) plus une bouffée de bruit de quelques
millisecondes. Le levier fait deux coups (il quitte sa grille, il arrive dans
l'autre 45 ms plus tard), le frein à main six clics qui s'accélèrent puis une
butée, et au relâché le bouton puis le levier qui retombe. Chaque lecture est
désaccordée au hasard de ±6 % (`shot_pitch_spread`) pour ne pas entendre deux
fois le même clac.

`car.gd` ne déclenche rien : `cabin_audio.gd` regarde `gear` et `handbrake_on`
changer d'une image à l'autre. Pas de signal à brancher, pas de logique en
double, et les bancs d'essai qui forcent `car.gear` font sonner le levier.

**Vitres ouvertes.** `car.gd` calcule une *ouverture acoustique* (celle du
conducteur compte plein, celle du passager 70 % ; produit des fermetures, pour
que deux vitres ne fassent pas deux fois plus de bruit) et la passe aux deux
nœuds. Une fente suffit à siffler : l'effet monte en puissance 0,6. Ce qui
change quand on ouvre :

- **le vent** (`wind_open`) — un grondement turbulent qui s'engouffre,
  ∝ vitesse^1,3 ; plus le **battement** sourd (`wind_buffet`, un 35–150 Hz
  modulé à 18 Hz, la résonance de Helmholtz de l'habitacle, le « wub-wub »),
  qui ne vit qu'autour de 90 km/h ;
- **l'échappement « dehors »** — huit boucles `engine_out_*`, le râpeux de
  300 Hz à 7 kHz que la glace retirait. Mêmes explosions que `on` (même graine
  aléatoire), donc en phase : elles s'ajoutent au lieu de se battre. Dosées par
  l'ouverture, plus fort sous charge, et tout le moteur monte de 25 % ;
- **les pneus** (`road_open`) — le sifflement de roulement par la vitre ;
- **la manivelle** (`crank`) — le mécanisme, tant que la vitre bouge.

Réglages : `window_volume_db`, `window_boost` dans `engine_audio.gd` ;
`wind_open_volume_db`, `buffet_volume_db`, `road_open_volume_db`,
`crank_volume_db` dans `cabin_audio.gd`.

**Balance.** `python tools/render_audio_demo.py out.wav` rend 23 s de conduite
avec *tous* les sons aux niveaux par défaut des deux nœuds (départ, deux
passages, pied levé, freinage, frein à main) : c'est là qu'on juge si la route
couvre le moteur ou si le levier claque trop fort, sans lancer le jeu. Si on
change un `volume_db` dans un script, le reporter dans `LEVELS`.

## Ce qu'il y a dedans

| Fichier | Rôle |
|---|---|
| `scripts/main.gd` | ambiance : brouillard, lune, sol, tonemapping, captures |
| `scripts/car.gd` | boîte manuelle, physique, caméra, phares, HUD |
| `scripts/cabin.gd` | intérieur et extérieur Blender (`civic_interior.glb`, `civic_exterior.glb`), pivots des commandes, roues |
| `scripts/driver.gd` | corps du conducteur (`civic_driver.glb`), IK des bras, mains sur les commandes |
| `assets/blender/build_civic_all.py` | reconstruit, rend et exporte les trois `.glb` depuis Blender |
| `scripts/mirror.gd` | rétroviseur : vrai miroir plan (SubViewport + caméra à l'œil réfléchi) |
| `scripts/visor.gd` | pare-soleil : bascule autour de sa tige, placé à la souris |
| `scripts/window.gd` | vitres de portière, descendues à la manivelle |
| `scripts/ignition.gd` | clé de contact : prise au clic, tournée à la molette |
| `scripts/prop.gd` | objets libres de l'habitacle : simulation en repère voiture, frottement de Coulomb |
| `scripts/cabin_shape.gd` | **la forme de l'habitacle relevée sur le `.glb`** : grille de 2 cm et champ de hauteurs. Une seule géométrie pour la dépose, les collisions et la reptation |
| `scripts/mesh_probe.gd` | le maillage rangé pour être interrogé vite (dessus d'une colonne, boîte contre triangles). Partagé par le jeu et les sondes |
| `tools/bake_cabin.gd` | cuit `assets/cabin_shape.res` depuis `civic_interior.glb` : rastérisation, remplissage des creux fermés, champ de hauteurs |
| `tools/check_shape.gd` | relit la forme cuite et vérifie qu'elle répond juste (dépose, visée, reptation) |
| `tools/probe_collisions.gd` | avant/après du même balayage de lancers : combien s'immobilisent **dans** la tôle visible |
| `scripts/road.gd` | route infinie et lisse, arbres, poteaux, voiture de police, apparition du géant |
| `scripts/police_car.gd` | voiture de police garée (`police_car.glb`) : gyrophares rotatifs, faisceaux bleus |
| `scripts/giant.gd` | le géant : anatomie déduite du pied, course procédurale sans patinage, piétinement |
| `tools/make_giant_sounds.py` | synthèse du pas et du cri (`assets/audio/giant/`), dosés à la sonie |
| `assets/blender/build_police_car.py` | construit, rend et exporte `police_car.glb` depuis Blender (ligne de commande) |
| `assets/blender/build_police_car_simple.py` | idem pour la version basse-poly `police_car_simple.glb` (non utilisée) |
| `scripts/retro.gd` | fabrique de matériaux, tous branchés sur le shader |
| `scripts/engine_audio.gd` | son du moteur : fondu entre boucles, pitch, charge, rupteur |
| `scripts/cabin_audio.gd` | route, vent, levier, frein à main |
| `tools/make_engine_sounds.py` | synthèse des boucles moteur (`assets/audio/engine/`) |
| `tools/make_cabin_sounds.py` | synthèse des sons d'habitacle (`assets/audio/cabin/`) |
| `tools/make_starter_sounds.py` | synthèse du démarreur et du calage (`assets/audio/starter/`) |
| `scripts/centipede.gd` | mille-pattes : entre par les grilles ou la vitre, marche sur les surfaces de l'habitacle |
| `tools/probe_surfaces.gd` | carte de hauteurs du maillage, comparée aux boîtes **historiques** de `cabin.gd` — l'écart qui a motivé le relevé |
| `tools/probe_vents.gd` | bouches d'aération du `.glb` : boîte englobante et axe du flux |
| `tools/render_audio_demo.py` | rendu hors ligne de tous les sons aux niveaux du jeu, pour la balance |
| `shaders/retro.gdshader` | tramage ordonné (Bayer 4×4) |

## L'intérieur

L'habitacle vient de `assets/models/civic_interior.glb`, construit dans Blender
par `assets/blender/build_civic_interior.py` (script re-jouable). Il couvre
plancher, planche de bord, compteurs, console, sièges, pédales, portières,
montants, ciel de toit, rétroviseur et ceintures — 300 objets.

Il a été modélisé **sur les constantes du code**, donc rien à recaler : volant à
`(-0.33, 0.78, -0.38)` incliné de 68°, pédales à -0.24 / -0.39 / -0.52, pommeau
de levier à 0,80 m. Les valeurs relevées sur le `.glb` correspondent au
centimètre près à `WHEEL_CENTER`, `WHEEL_TILT` et aux constantes de `driver.gd`.

Le jeu **anime les pièces du modèle** plutôt que d'en cacher et d'en refaire en
primitives. `cabin.gd` crée trois pivots et y reparente les pièces mobiles :

| Pivot | Pièces déplacées |
|---|---|
| volant | `STR_Rim`, `STR_Pad`, `STR_Spoke_*`, klaxons, badge |
| levier | `CON_ShiftLever/Knob/Badge/Boot` |
| frein à main | `CON_BrakeLever/Grip/Button` |

Le reste (colonne, fourreau, contacteur, commodos, soufflets fixes) ne bouge pas.
`driver.gd` ne fabrique plus aucune commande : il reçoit ces pivots via
`use_controls()` et se contente de les faire bouger et d'y accrocher ses mains.

Un ajustement fait au chargement, à corriger un jour à la source dans le script
Blender :

- **Albédos multipliés par `INTERIOR_DIM` (0,62).** Le modèle est en teintes
  crème ; tel quel le montant A devenait l'objet le plus lumineux d'une scène
  éclairée par la seule lueur des compteurs.

Il y en avait un deuxième — **pare-soleil relevés de 7,5 cm** — et c'est
exactement le genre de rustine qui pourrit en silence. Elle datait d'un modèle
qui les posait à 1,18 m, rabattus en travers du pare-brise. Le `.glb` a été
refait depuis, avec des pare-soleil rangés d'origine (panneau à 1,163-1,237),
et le décalage les enfonçait alors dans un ciel de toit qui commence à 1,234 :
invisibles, tiges et supports passés au-dessus, hors de la caisse. **Un
rattrapage au chargement doit mourir avec le défaut qu'il corrige** ; sinon,
personne ne pense à le relire quand le modèle change.

Le frein à main du modèle est posé levier **baissé**, donc `driver.gd` lui
applique un delta de rotation (`HB_TRAVEL`), pas un angle absolu.

`tools/inspect_glb.gd` liste le contenu du `.glb` (échelle, hiérarchie, position
de chaque pièce) :

```bash
godot --headless --path . --script res://tools/inspect_glb.gd
```

## L'extérieur et le conducteur

Depuis le refacto des scripts Blender, tout vient de `assets/blender/` :

| Module | Rôle |
|---|---|
| `civic_dims.py` | toutes les cotes, dont les contours de vitrage partagés par l'intérieur et l'extérieur |
| `civic_lib.py`, `civic_materials.py` | primitives procédurales, matériaux |
| `build_civic_interior.py` | habitacle → `civic_interior.glb` |
| `build_civic_driver.py` | conducteur → `civic_driver.glb` |
| `build_civic_exterior.py` | carrosserie → `civic_exterior.glb` |
| `build_civic_all.py` | `main()` : reconstruit tout, rend, sauvegarde le `.blend`, exporte les trois `.glb` |

**Extérieur.** `cabin.gd` instancie `civic_exterior.glb` (même repère que
l'intérieur, rien à recaler) : coque unique avec baies découpées, vitres,
feux, rétroviseurs, roues. Les quatre roues (`EXT_Wheel_FL/FR/RL/RR`) tournent
sur leur essieu avec la vitesse et les deux avant braquent (`set_wheels()`,
appelé par `car.gd`). Pas d'ombre portée, comme l'intérieur, sinon la caisse
bloque ses propres phares.

**Conducteur.** `driver.gd` ne fabrique plus de capsules : chaque segment vient
de `civic_driver.glb`, modélisé dans le repère que le script anime (origine à
l'articulation proximale, axe -Z vers la suivante). `_set_bone` étire le
maillage le long de -Z pour coller à la longueur de l'os (`REST_LEN`). Les
mains et les pieds sont des sous-arbres du `.glb` adoptés tels quels, le buste
est exprimé depuis `SPINE`, la tête est masquée (la caméra est dedans). Les
albédos sont assombris (`BODY_DIM`) comme ceux de l'habitacle.

**Mains et bras.** Ce sont ceux de l'asset « Player_Arms » fourni par
l'auteur (`assets/blender/ref/Player_Arms.blend`, texture
`assets/blender/textures/player_hands.png` : manche en jean, dos de la main,
paume). `assets/blender/civic_hand.py` charge son bras gauche (un seul
maillage rigged, épaule → bouts des doigts), le met à l'échelle (`SCALE`,
anisotrope : l'asset est allongé) et le découpe en trois parties selon l'os
dominant de chaque face — bras, avant-bras, main (poignet + paume + doigts +
pouce) — en rebouchant les coupes. La main est posée en prise par skinning
avec les poids de l'asset : phalanges enroulées autour d'une barre de 16,5 mm
(la jante), pouce couché le long de la jante, roulis `ROLL` vers le
conducteur, puis passage dans le repère attendu par `driver.gd` (origine au
centre de la jante, jante le long de Y, dos de la main vers le conducteur) ;
la main droite est le miroir de la gauche. Un vide `DRV_Wrist_L/R` marque le
poignet : `driver.gd` y fait aboutir l'avant-bras au lieu du centre de la
jante. **Il n'y a plus de bras** : mains seules, façon FPS (les segments
d'asset restent disponibles via `civic_hand.arm_part()` et `driver.gd` les
anime s'ils sont présents dans le `.glb`). La texture est embarquée dans le
`.glb` et filtrée en « nearest » par `driver.gd`. Le buste n'a ni cou ni
tête : la caméra est à leur place.
Mains à 10 h 10 (`GRIP_ANGLE`) — position de *repos* : elles la quittent dès
qu'on braque et s'enchaînent sur la jante, voir « Tourner le volant ». Un objet
tenu ne fixe plus un angle de main :
`_aligned_grip()` oriente la main d'après le coude (poignet vers le coude,
pouce en haut) et l'objet se couche sur l'axe de prise du poing.

**Les doigts s'adaptent à l'objet.** Chaque main est exportée avec un squelette
(les os de phalanges de l'asset : `Hand`, `Index2..4`, …, `Thumb1`, `Thumb3`)
et cinq poses en animations d'une image, générées par `civic_hand.build_hand_rig`
avec la mécanique d'enroulement : `open` (repos) et poings refermés sur des
barres de 10, 16,5, 25 et 32 mm de rayon (`g10`…`g32`). `driver.gd` lit ces
poses au chargement (`_read_poses`) et, chaque image, mélange pour chaque main
un **rayon** (jante 16,5 mm, pommeau 24, frein à main 15, portière 20, objet
tenu = sa demi-épaisseur) et une **fermeture** (ouverte pendant le trajet vers
un objet, à plat sur un pare-soleil ou un rétroviseur, refermée à l'arrivée sur
un objet), par interpolation entre les poses de rayon voisin (`_apply_fingers`).
L'objet tenu est décalé de la paume selon son rayon (`held_offset`). Export :
animations glTF en mode « pistes NLA » — en mode « actions », Blender 5 exporte
la pose de repos partout ; et chaque animation contient les pistes des deux
squelettes, `_read_poses` filtre par main.

Pour modifier la voiture : changer une cote dans `civic_dims.py` (ou une
forme dans le `build_civic_*.py` concerné), relancer `build_civic_all.main()`
dans Blender, puis laisser l'éditeur Godot réimporter les `.glb`.

## La route

Ce n'est pas une suite de blocs. On garde une ligne médiane échantillonnée tous
les 2 m et on reconstruit un **unique ruban de triangles** qui la suit, à chaque
fois qu'on avance d'un échantillon. Aucun joint, aucun chevauchement, aucune
marche, même en plein virage.

Piège : l'enroulement des triangles doit être **horaire vu du dessus**, sinon
Godot les prend pour des faces arrière et la route est purement invisible.

## La voiture de police

Sur l'accotement de droite, une berline de police de 1990 (gabarit Peugeot 405,
livrée Police Nationale : blanche, bande bleue « POLICE », rampe à deux
gyrophares bleus, antenne fouet, plaque arrière jaune d'époque) est garée
gyrophares allumés, le nez un peu tourné vers la route. La première est à
~200 m du départ, les suivantes tous les 1,2 à 2,8 km. Elle ne fait rien : on
passe devant, c'est tout.

Le modèle est `assets/models/police_car.glb`, construit par
`assets/blender/build_police_car.py` avec la technique de la Civic (coque
loftée, subdivision, épaisseur, découpes booléennes ; ~182k triangles), en
ligne de commande :

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python assets/blender/build_police_car.py
```

Il existe aussi une version basse-poly façon PS1 (`police_car_simple.glb`,
~2 200 triangles, `build_police_car_simple.py` : caisse loftée sans
subdivision, vitres opaques, pas d'intérieur) qui porte les mêmes noms de
nœuds : changer `MODEL` dans `police_car.gd` suffit pour l'utiliser.

[police_car.gd](scripts/police_car.gd) instancie le `.glb` et **anime ses
gyrophares**. Un gyrophare de 1990 n'est pas un stroboscope : c'est une ampoule
fixe devant un miroir qui tourne. Le script fait donc tourner les deux pivots
`POL_BeaconMirror_L/R` du modèle (en opposition de phase, 1,6 tr/s) avec un
`SpotLight3D` bleu accroché dessus : c'est ce faisceau qui balaie la route et les
arbres dans le brouillard. Le dôme, lui, ne brille fort que quand le miroir est
tourné vers le joueur (`cos³` de l'angle), comme en vrai. Un petit omni fixe par
dôme pose le bleu sur la caisse blanche.

Piège : l'énergie injectée dans le brouillard volumétrique (`beam_fog`,
`halo_fog`). À 2,5, tout le brouillard virait au bleu à 40 m ; à 1,0 le faisceau
se lit comme un pinceau qui tourne.

[road.gd](scripts/road.gd) la pose : `POLICE_FIRST`, `POLICE_EVERY_MIN/MAX`
(en échantillons de 2 m), `POLICE_OFF` (décalage latéral, sur l'accotement hors
de la voie), `POLICE_YAW`. Une fois dépassée de 80 m elle s'éteint, jusqu'à la
suivante — un seul exemplaire en mémoire. Comme les arbres, elle n'a pas de
collision : rien sur la route n'en a.

Côté Blender, deux pièges rencontrés, tous deux corrigés dans le script :

- **Profil de section non monotone en z** aux stations de fermeture (nez,
  queue) : le décalage de ceinture repliait le flanc, et subdivision + épaisseur
  en faisaient des épines de dix mètres. `lower_pts()` compresse maintenant le
  haut du flanc vers un pivot qui descend avec la ceinture, et une assertion
  vérifie la monotonie.
- **Solidify « épaisseur régulière »** projetait quatre sommets à plusieurs
  mètres (normales mal conditionnées au nez, à la malle et en haut de la
  lunette) : des traits fins qui sortaient de la caisse. `use_quality_normals`
  règle le problème. `stats()` liste tout sommet hors gabarit après chaque
  construction, pour que ça ne revienne pas en silence.

`godot --path . -- shot` produit `17_police_approche.png` (vue du siège, 40 m
avant) et `18_police_exterieur.png` (de côté, sous ses gyrophares et nos phares).

## Le géant

Premier ennemi du jeu. Il attend accroupi dans les sapins, se relève quand la
voiture approche, se met à courir derrière elle et essaie de l'écraser du pied.
Tout est dans [giant.gd](scripts/giant.gd), en primitives animées — pas de
`.glb`, pas de squelette, pas d'`AnimationPlayer`.

### On ne choisit que la taille du pied

Son pied fait la voiture : 3,97 m sur 1,68 m, les cotes d'une Civic EF. C'est la
**seule** mesure réglée à la main. Chez l'humain le pied vaut 15,2 % de la
stature ; un pied de 3,97 m appartient donc à quelqu'un de **26,1 m**, et cuisse,
tibia, buste, bras, tête sont les fractions anthropométriques habituelles
multipliées par cette stature. Rien d'autre n'est arbitraire, et c'est ce qui
évite le monstre en pâte à modeler — celui dont les bras sont trop courts sans
que personne ne sache dire pourquoi il sonne faux.

Une exception, et elle compte : le bassin est à **0,44** de la stature en course,
pas à 0,53. Un sprinteur court genoux fléchis, et il le faut ici aussi — jambe
tendue au repos, il ne resterait pas un centimètre pour aller poser le pied
devant soi.

### Sa vitesse n'est pas choisie non plus

Deux animaux de même forme et de tailles différentes bougent au même **nombre de
Froude** : les vitesses vont comme la racine de l'échelle, les cadences comme son
inverse, les foulées comme l'échelle. Un sprinteur fait 10 m/s à 4,4 pas par
seconde ; à l'échelle 14,9 (26,1 m pour 1,75 m) cela donne :

| | sprinteur | × Froude | le géant |
|---|---|---|---|
| vitesse | 10 m/s | ×3,86 | **38 m/s** (137 km/h) |
| cadence | 4,4 pas/s | ÷3,86 | **1,14 pas/s** |
| foulée | 2,3 m | ×14,9 | **33,3 m** |

Ces trois nombres se recoupent (33,3 × 1,14 = 38), et c'est de là que vient
l'impression de masse : un géant qui court vite en piaffant à la cadence d'un
homme ressemble immanquablement à une maquette filmée en accéléré.

Accessoirement cela **répond à la question de jeu sans qu'on ait à l'arbitrer**.
La Civic plafonne à 180 km/h en 5e, 155 en 4e, 122 en 3e. On ne le sème donc
qu'en 5e, et lentement — 12 m/s d'écart, quinze secondes pleines pour prendre
200 m. En 4e on tient l'écart sans le creuser. En 3e il gagne. Le banc d'essai
mesure les trois : `IL REVIENT`, `il tient l'écart`, `ON LE SÈME`.

### Les pieds ne glissent pas

C'est le seul endroit où une animation procédurale se fait prendre tout de suite,
et rien d'autre ne compte tant que ce n'est pas acquis. Un pied posé est **posé** :
on retient le point du monde où il a touché et il y reste jusqu'au décollage,
quoi que fasse le corps au-dessus. Le banc suit la **pointe** image par image sur
toute la course et relève 0 mm de dérive.

Ce n'est pas la cheville qu'on suit, et la distinction est le cœur du mécanisme :
en fin d'appui le pied **pivote sur ses orteils**, la cheville monte de deux
mètres et avance d'un autre. Sans ce détail rien ne ferme — au décollage la
cheville se retrouve à 9,6 m derrière la hanche pour une jambe de 12,8 m et un
bassin à 11,5 m, et le compte ne tombe pas. Le talon qui se lève est exactement
ce qu'un sprinteur fait, et c'est ce qui referme le triangle. La pointe, elle, ne
bouge pas d'un millimètre pendant ce temps.

Le bassin, de son côté, **ne monte jamais plus haut que ce que la jambe d'appui
autorise**. On n'écrit aucune sinusoïde de rebond : le balancement vertical de la
course (48 cm relevés) sort tout seul de cette contrainte.

### Trois pièges, tous rencontrés

- **La trajectoire du pied en vol se définit par rapport à la hanche, pas dans le
  monde.** Pendant qu'un pied fait ses 65 m, la hanche en fait 50 ; les 15 autres
  sont le pas proprement dit. Un `smoothstep` entre les deux bouts laisse le pied
  sur place pendant que le corps démarre : au quart du vol il traîne treize
  mètres en arrière, pour une jambe qui en fait douze. On rend donc **linéaire**
  la part qui n'est que le déplacement du corps (`_hip_share`) et on ne lisse que
  le reste. L'allongement maxi passe de 34 % à 0,2 %.
- **Le décollage ne se lit pas sur un franchissement de seuil.** Le seuil, c'est
  le rapport cyclique, et il bouge avec la vitesse — de 0,62 à l'arrêt à 0,24
  lancé. Une jambe posée à la phase 0,50 se retrouve du mauvais côté sans avoir
  rien franchi, et reste plantée un cycle entier pendant que le corps s'en va
  sans elle. On énonce l'invariant (« une jambe dont la phase dit *en l'air*
  n'est pas au sol ») plutôt que sa dérivée.
- **On vise où sera la hanche, pas où elle est.** Il accélère pendant que le pied
  vole (7 m/s² sur 1,3 s : neuf mètres d'erreur) et il tourne (0,55 rad/s :
  quarante degrés). On vise donc avec la vitesse moyenne du vol et le milieu de
  l'arc. Et quand ça ne suffit pas — le joueur a le droit de donner un coup de
  volant — un **pas de rattrapage** repose le pied hors du rythme, comme un
  coureur qui trébuche ; le décalage entre les deux jambes se résorbe en deux
  foulées.

### Ce qu'il fait à la voiture

Rien de définitif, pour l'instant : le pied **secoue**, il ne tue pas. Un pas qui
tombe à côté envoie une onde dans le sol (26 m/s² au pied du choc, moitié moins à
14 m) ; un pied qui tombe *dessus* envoie 60 m/s², soit 6 g. Les deux passent par
`car.impact()`, qui les répartit à deux endroits :

- dans `frame_accel`, d'où **tout ce qui traîne dans l'habitacle décolle** dès que
  le coup passe 2,4 g (`static_mu` de [prop.gd](scripts/prop.gd)) — le banc voit
  la canette bondir de 25 cm ;
- dans la suspension : un ressort amorti à 2,4 Hz qui fait tressauter la caméra
  de 3 mm et piquer la tête de 0,8°.

Un choc qui ne ferait que secouer l'image serait un effet de post-traitement.
Celui-là fait sauter les canettes du siège.

Il **n'a pas de boîte de collision**, et c'est délibéré. Un pied solide qui se
pose sur une `CharacterBody3D` la catapulte au `move_and_slide` suivant ; un pied
solide qui se pose à côté arrête net une voiture lancée à 160 km/h. Les deux
demandent une réponse aux dégâts qui n'existe pas encore.

### De nuit, on ne voit que ses yeux

C'est la trouvaille de cette première version, et elle décide de tout le reste.
Il n'a que deux sources de lumière : une lune à 0,15 d'énergie **sans ombres**,
et l'ambiante à 0,055. Les phares regardent devant, les feux arrière ne portent
qu'à seize mètres, et lui est toujours derrière. Ce qui le rend visible n'est
donc pas ce qui l'éclaire, c'est **le brouillard devant lui** : à cinquante
mètres, le brouillard remplit les trois quarts du pixel et lui le quart qui
reste ; il ne se lit qu'en tache un peu plus sombre que la nuit.

D'où trois conséquences :

- Son albédo est à 0,070, dans la famille des troncs de la route (0,075). La
  première version était à 0,052 et **il n'existait tout simplement pas**.
- Ses **yeux débordent de 1** (émission à 4,2), au-dessus du seuil de glow à
  0,95, avec une petite braise omni qui les marque dans le brouillard
  volumétrique. Quand il court à côté de la voiture, c'est la seule chose qu'on
  voit de lui (`55_geant_a_cote.png`).
- **Assis, on ne voit jamais sa tête.** À 46 m elle est à 29° au-dessus de
  l'horizontale et la lunette arrière n'ouvre que sur une dizaine de degrés : on
  voit ses jambes passer, pas lui. Il ne devient franchement visible que quand
  les phares le trouvent — c'est-à-dire quand il est passé devant.

Le son porte donc l'essentiel de la menace : c'est voulu.

### Le pas et le cri

`tools/make_giant_sounds.py` synthétise `step.wav` et `roar.wav` (numpy requis),
joués par des `AudioStreamPlayer3D` accrochés aux pieds et à la tête, sur le bus
**Cabine** — ils sont dehors, ils doivent traverser la caisse comme la route et
le vent, et s'ouvrir quand on baisse une vitre.

Le piège de tout son de géant, et la première version y est tombée : on empile
des graves, on regarde la forme d'onde, on trouve ça énorme — et à l'écoute il ne
reste qu'un frottement de gravier. **À 30 Hz l'oreille perd 40 dB.** Une couche à
24 Hz qui occupe 86 % de l'énergie du fichier peut être parfaitement inaudible
pendant qu'une pincée de bruit à 2 kHz, invisible sur la courbe, porte tout le
son. Chaque couche est donc ramenée à une **sonie unité** (RMS pondéré A) avant
d'être dosée, et l'outil imprime les deux répartitions côte à côte — l'énergie
brute et ce qu'on entend. Pour le pas elles n'ont rien à voir : 65 % de l'énergie
sous 40 Hz, 44 % de la *sonie* entre 80 et 200 Hz.

Le cri est un train de pulsations glottales (modèle de Rosenberg) à fondamentale
descendante, avec jitter, shimmer et une **subharmonique** à f0/2 qui monte au
milieu — le *growl* des gros félins, deux régimes vibratoires à la fois. Deuxième
piège : une bosse lisse (cosinus redressé au cube) n'a que quatre harmoniques
utiles, son spectre s'effondre de 36 dB entre 150 et 400 Hz et il ne reste rien à
mettre dans les formants. C'est **la fermeture brusque de la glotte** qui casse
la dérivée et porte le spectre jusqu'en haut.

Une honnêteté à noter : les formants sont à 190, 560 et 1250 Hz. À l'échelle
stricte, un conduit vocal quinze fois plus long les mettrait à 35, 100 et 220 Hz
et personne ne l'entendrait. C'est le compromis habituel du cinéma, il vaut mieux
l'écrire que le redécouvrir.

### Où il apparaît, et les boutons

[road.gd](scripts/road.gd) le pose comme la voiture de police : `GIANT_FIRST`
(échantillon 240, soit 480 m — le temps de partir, de passer les rapports et de
se croire seul), `GIANT_EVERY_MIN/MAX`, `GIANT_OFF` (15 m de l'axe, dans la bande
d'arbres). Il est posé **275 m devant la voiture et n'y bouge pas** : accroupi il
ne fait que 8,5 m de haut, les sapins en font 6 à 11, il fait partie du paysage.
C'est lui qui décide de se lever, à `notice_distance` (72 m) — le temps qu'il se
déplie (2,2 s), la voiture arrive à sa hauteur. Une fois semé (200 m pendant 3 s)
il s'éteint et la route lui donne un nouveau rendez-vous, loin devant.

Les boutons qu'on tourne en premier : `run_speed` (toute la difficulté est là),
`notice_distance` et `rise_time` (la mise en scène de l'apparition),
`stomp_cooldown` (à 2,6 s il court et frappe ; plus bas il pioche sur place),
`stomp_hit_accel` / `ground_accel` (la violence), et l'albédo de `_mat_hide` si
on le trouve trop ou pas assez visible.

```bash
godot --path . -- gianttest
```

Le banc prouve, dans cet ordre : que la route le pose vraiment dans les arbres,
que le pied fait la voiture, que Froude se recoupe, qu'il se lève seul, que les
pieds ne glissent pas, que les jambes ne s'allongent pas, que foulée × cadence =
vitesse, qu'on le sème en 5e et pas en 4e, et que le pied qui tombe dessus fait
sauter une canette. Il produit `50_geant_tapi.png`, `51_geant_leve.png`,
`52_geant_derriere.png`, `53_geant_course.png`, `54_geant_echelle.png` et
`55_geant_a_cote.png`.

## Le mille-pattes

Le géant piétine la voiture de l'extérieur. Celui-ci fait l'inverse : il
n'essaie pas de casser la caisse, **il entre dedans**. Et il entre par où l'air
entre — les bouches d'aération — ou par la vitre, si tu l'as laissée ouverte.

C'est ce qui en fait un ennemi et pas un décor : la voiture est le seul abri du
jeu, et lui la traverse comme si elle n'en était pas un.

Il arrive au bout de `first_delay` (14 s). Il ne doit pas être là au démarrage :
ce qu'on veut, c'est qu'il **arrive**, et on n'assiste pas à une arrivée dont on
n'a pas connu l'absence.

### Par où il entre

Huit bouches, **relevées sur le `.glb`**, pas saisies à la main :

| | position (espace voiture) | fente |
|---|---|---|
| grille de dégivrage | (0, 0,948, −0,85) | 1100 × 45 mm |
| dégivrage central | (0, 0,946, −0,70) | 150 × 45 mm |
| aérateurs latéraux | (±0,62, 0,839, −0,541) | 82 × 48 mm |
| aérateurs centraux | (±0,075, 0,825, −0,561) | 110 × 45 mm |
| haut-parleurs de portière | (±0,685, 0,57, −0,50) | 95 × 95 mm |

Le haut-parleur en fait partie, et il n'y a aucune raison de le traiter
autrement : c'est une grille, elle donne sur un caisson, et un caisson donne sur
le vide de la portière. Sauf qu'elle est à hauteur de coude.

**L'axe de sortie vient de la boîte englobante.** Une grille est un objet
*plat* — 6 mm d'épaisseur pour 1,10 m de large sur le dégivrage — donc son axe
le plus **mince** est celui du flux d'air, et c'est par là qu'on passe. Le dire
ainsi couvre les trois orientations du jeu sans les énumérer : les aérateurs de
face soufflent vers l'arrière (z), le dégivrage vers le haut (y), les
haut-parleurs vers l'intérieur (x).

**Le sens**, lui, pointe vers l'œil du conducteur, parce que c'est à quoi sert
une bouche d'aération : elle souffle sur les occupants. Seul le *signe* du
produit scalaire compte — même argument que l'axe de la clé de contact — et il
tombe juste sur les huit. Viser le centre de l'habitacle ne marcherait pas : il
est plus *bas* que le dégivrage, qui se retrouverait à souffler dans la planche
de bord.

**Le corps fait 6 mm d'épaisseur, et ce chiffre est mesuré.**
`tools/probe_vents.gd` relève les lames des aérateurs à 10,3 mm d'entraxe pour
4 mm d'épaisseur : il reste **6,5 mm** entre deux lames. C'est par là qu'il
passe, donc c'est ce qu'il mesure. Un mille-pattes est plat pour exactement
cette raison — c'est ce qui lui permet de vivre sous les pierres, et ici d'être
dans la voiture avant toi.

**Et la vitre pèse plus lourd que les huit grilles réunies.** Les bouches sont
toujours ouvertes — une voiture ne se ferme pas de ce côté-là — tandis qu'une
vitre n'est une entrée que si tu l'as baissée. Rouler vitres fermées ne le tient
donc pas dehors, ça le force seulement à prendre le chemin long. C'est une
contrepartie de plus à la vitre ouverte, comme le pare-brise en est une au
plafonnier. Mesuré sur 200 entrées : **0 %** par la vitre quand elles sont
fermées, **61 %** dès que celle du conducteur est baissée.

La hauteur du jour au-dessus de la glace est **lue**, pas écrite : `window.gd`
descend le pivot de `travel * open`, donc le bord supérieur est à
`glass_box.end.y − travel * open`. L'entrée monte avec la ceinture de caisse si
le modèle change.

**Il sort du trou, il n'y apparaît pas.** La trace du corps est semée à l'avance,
droite, en arrière dans le conduit : les anneaux sont donc payés un par un au
lieu d'arriver tous ensemble à l'air libre. Le corps était déjà là, on ne le
voyait pas. Mesuré : à l'instant zéro **14 anneaux sur 15** sont encore dans la
planche, à mi-corps la tête a fait 128 mm, et à 40 cm il est entièrement sorti.

### Il ne tombe pas, il marche

[prop.gd](scripts/prop.gd) simule des objets qui **tombent** : gravité,
frottement de Coulomb, rebond. Rien de tout ça ne s'applique ici. Une bestiole
ne se *pose* pas sur une surface, elle s'y **accroche** — elle monte le montant,
traverse le pavillon et redescend le pare-brise sans qu'aucune de ces trois
choses ne soit « un sol ». Le mille-pattes ne partage donc pas la simulation des
objets ; il partage leur **géométrie**, ce qui est le seul point commun qu'il y
ait vraiment.

Sa marche tient en quatre lignes, répétées chaque image :

1. il avance selon `_dir`, tangent à la surface où il est ;
2. on tire le point d'arrivée de `GRIP` **vers l'intérieur** de la surface ;
3. on le **recolle** à la surface la plus proche de l'habitacle ;
4. `_dir` est reprojeté dans le plan tangent de la nouvelle normale.

**L'étape 2 est celle qui fait tout.** Sans elle, arrivé au bord de la planche
de bord, il continuerait tout droit dans le vide ; avec elle il se retrouve un
millimètre *sous* la tôle, le recollage le ressort par la face la plus proche —
qui n'est plus le dessus mais le nez de la planche — et il bascule par-dessus
l'arête pour continuer sur la face verticale. Passer un angle saillant n'est donc
pas un cas particulier à coder : c'est ce que fait la règle générale, et c'est
aussi ce que fait une vraie bestiole, qui ne « décide » pas de passer un angle,
elle ne lâche simplement jamais prise.

Aucune topologie, aucun graphe de navigation, aucune arête à recoudre : la
question « où est la surface ? » est reposée de zéro à chaque image, sur la tôle
relevée. On la cherche en couronnes croissantes autour de la tête et on s'arrête
dès qu'une couronne ne peut plus faire mieux que ce qu'on tient — le coût ne
dépend donc pas de la taille de l'habitacle mais de la distance à la tôle, qui
est de quelques millimètres puisqu'elle marche dessus.

Ajouter du mobilier au modèle lui donne de nouveaux chemins sans rien
rebrancher : il suffit de recuire.

### Être dedans prime sur être près

Et ce n'est pas un détail de tri. Les deux se mesurent en mètres et se
comparaient donc sur le même pied. Le banc a montré où ça menait : **sous la
banquette arrière**, le plancher est à 5 mm sous le ventre tandis que le coussin
englobe la bestiole sur 13 cm — la face du plancher gagnait, et elle marchait
**enterrée dans le siège**, tranquillement, sur toute la longueur de l'habitacle.

L'ordre correct n'est pas une question de distance mais de nature : « ne traverse
rien » est une *contrainte*, « reste près de quelque chose » est un *souhait*. On
sort donc d'abord de ce dans quoi on est, par la face la plus proche, et on ne
cherche la surface voisine que quand on n'est plus dans rien. Le mille-pattes
**grimpe** alors sur la banquette au lieu d'y disparaître, sans qu'on ait eu à
lui parler de banquette.

### Ce sur quoi on rampe : tout ce qui se voit

Il n'y a plus de liste à tenir. La bestiole marche sur **la tôle relevée**
([cabin_shape.gd](scripts/cabin_shape.gd)), c'est-à-dire sur tout ce que le
modèle contient.

Avant, `cabin.gd` déclarait `crawl_solids` à part de `solids`, et la raison était
bonne : `solids` était fait pour des objets qui *tombent* — du mobilier
horizontal, plus les parois qu'il faut pour qu'une canette ne parte pas dans la
caisse — et il manquait à une bestiole qui *marche* les faces verticales que
personne n'avait jamais heurtées. On en avait donc ajouté trois à la main : le
nez de la planche de bord (40 cm de vide sur toute la largeur, là où sont
précisément les six aérateurs), les contre-portes, le pare-brise.

**Trois, parce qu'on y avait pensé.** Les montants, le tunnel, le capot des
compteurs, les dossiers, les bas de caisse, les enjoliveurs de ceinture n'y
étaient pas, donc ils n'existaient pas pour elle — et c'est exactement ce que
décrit « il ne marche pas sur toutes les surfaces visibles ». Une liste écrite à
la main ne peut pas être complète : elle contient ce dont quelqu'un s'est
souvenu.

Ce qui justifiait de garder deux listes a disparu en même temps. « Les verser
dans `solids` serait un vrai changement de physique » était vrai tant que
`solids` était une approximation grossière : y ajouter le nez de la planche
faisait rebondir une canette là où elle passait avant. Le relevé, lui, **n'est
l'approximation de personne** — il n'y a plus de choix à faire entre « ce sur
quoi on marche » et « ce qui arrête », puisque les deux sont la même tôle, et
c'est celle qu'on voit.

Le recouvrement, lui, n'est plus un sujet non plus : deux cases ne peuvent pas se
chevaucher. Le réglage délicat qu'imposait l'ancien système — le bloc de planche
de bord s'arrêtait à 0,60 parce qu'en descendant plus bas il avalait le dessus de
console, et la bestiole posée dessus se retrouvait *dans* le bloc — n'a plus lieu
d'être.

Restent les glaces (`cabin.shell`), absentes du relevé puisqu'on regarde au
travers : c'est par leurs six marches qu'elle grimpe au pare-brise.

### La coque borne la tête

Exactement l'argument de `prop.gd` : le mobilier pousse **dehors**, la coque
retient **dedans**, et une borne par axe ne peut pas fuir. Sans elle, il suffit
de faire le tour d'une paroi pour se retrouver à marcher sur la carrosserie, vue
de l'extérieur : les portières, le pavillon et le fond de coffre ont tous une
face qui **déborde** de la coque, et rien dans « va vers la surface la plus
proche » ne distingue le bon côté d'une tôle du mauvais. Le banc l'a relevé à
**41 mm dehors** avant qu'elle existe.

Les bornes sont rentrées de `RIDE`, ce qui les met exactement là où le ventre se
pose quand il marche sur une face de la coque : le plancher, le pavillon et la
lunette arrière ne sont déclarés nulle part ailleurs, et il y marche sans que la
coque et le recollage se contredisent d'un millimètre.

### Il court puis il se fige

À vitesse constante, ça ne se lit pas comme un insecte, ça se lit comme un petit
train. Un mille-pattes va par à-coups : il détale, il s'arrête net, il repart.

Et surtout : **les pattes sont animées par la distance parcourue, pas par le
temps.** Figé, il ne pédale donc pas dans le vide — c'est le défaut classique, et
il saute aux yeux — mais il continue de fouiller l'air devant lui, ce que fait
une bestiole arrêtée. Mesuré, figé une seconde : **+0,0000** de phase de pattes.

L'ondulation est **métachronale** : une vague qui descend le corps, pas des
pattes qui battent ensemble. C'est la seule chose qui distingue un mille-pattes
d'un mille-pattes en plastique.

Quand tu plantes les freins, il se plaque et s'arrête : `car.frame_accel` est
déjà publiée pour les objets, elle sert ici à une bestiole qui s'agrippe. Il ne
glisse pas, lui — s'agripper est tout son métier. Mesuré sur 0,5 s de marche :
**0,210 m** libre contre **0,000 m** sous 18 m/s².

### Le corps suit un chemin, pas une suite d'images

Deux pièges, tous deux relevés par le banc et tous deux du même genre — une
approximation qui suppose un pas régulier là où il n'y en a pas :

- **Semer un échantillon de trace par image** marche tant que la tête avance de
  moins d'un pas. Le jour où elle en franchit trois d'un coup — un recollage, une
  image longue — la trace garde un trou, les anneaux qui y tombent s'écartent, et
  le corps s'étire. On sème donc les échantillons *manquants*, pas seulement le
  dernier.
- **Placer les anneaux par indice d'échantillon** suppose que ces échantillons
  sont régulièrement espacés. Ils ne le sont pas : la tête parcourt 7 mm dans une
  image, 12 dans la suivante. On les place donc en **longueur d'arc**. Avant :
  27 mm entre deux anneaux espacés de 19. Après : **19,0 mm**.

Et une bestiole ne se téléporte pas. Là où deux boîtes se recouvrent, « la
surface la plus proche » peut changer de face d'une image à l'autre : on borne
donc le déplacement de la tête au pas qu'elle vient de faire. C'est une
relaxation, elle converge en deux ou trois images.

### Chitine rousse et vernie

Elle était d'abord aussi sombre que la planche de bord — 0,06 d'albédo, la valeur
exacte du plastique une fois rabattu sur la palette de nuit. Résultat en
capture : une bestiole de 27 cm posée en plein sur le tableau de bord, et **on ne
la voyait pas**. Un ennemi qu'on ne voit pas n'en est pas encore un.

Elle est donc quatre fois plus claire que la tôle, et **rousse** là où tout
l'habitacle est gris : ce sont les deux écarts qui la détachent, et une
scolopendre est réellement de cette couleur. Le **verni** compte autant :
rugosité 0,32 et un peu de métallicité font de la chitine un objet qui accroche
des spéculaires — la lueur des compteurs, le retour des phares, le plafonnier —
là où le plastique mat de la planche (0,94) ne renvoie rien. C'est ce qui la
trahit quand elle bouge.

Deux détails de lecture, tous deux visibles sur les captures :

- **les anneaux sont plus courts que leur espacement** (0,84 fois), pour qu'il
  reste 3 mm entre deux. À 1,25 fois ils se recouvraient et le corps se lisait
  comme un ruban : c'est la *segmentation* qui fait le myriapode ;
- **les pattes sont coudées**. Une patte droite ne se lit pas comme une patte, ça
  fait un peigne. Le tarse est enfant de la cuisse, donc il suit la foulée sans
  qu'on ait à l'animer : une seule rotation par patte, pour deux fois plus de
  lisibilité.

La géométrie est en primitives. Un `.glb` construit dans Blender, comme la
voiture et les canettes, reste à faire.

### Banc d'essai

```bash
godot --path . -- centipedetest
```

**Il est avancé à la main**, pas laissé tourner : `_physics_process` est coupé et
le banc l'appelle lui-même avec un pas fixe de 1/60 s. Ce n'est pas un
raccourci, c'est la seule façon de mesurer la *bestiole* et pas la machine — sous
le rendu complet ce projet tombe à quelques images par seconde, et un marcheur
qui avance de 42 cm par image ne prouve rien de son adhérence, il la met en
défaut par la taille du pas. C'est le piège que la 5e du banc de boîte et la main
à plat du banc de volant ont déjà payé, par deux chemins différents. Corollaire :
les 40 s de promenade sont 40 s de bestiole, et le banc entier tient en quelques
secondes.

| | relevé |
|---|---|
| les huit bouches soufflent vers l'habitacle | **8/8** |
| jour entre deux lames / épaisseur du corps | 6,5 mm / **6,0 mm** — il passe |
| 200 entrées, vitres fermées | **0** par la vitre |
| 200 entrées, vitre conducteur baissée | **121** par la vitre (61 %) |
| à l'instant de l'entrée | **14 anneaux sur 15** encore dans la planche |
| après 40 cm | **0** — il est tout sorti |
| 40 s de promenade | **9,12 m**, étendue visitée 1,13 × 0,60 × 1,69 m |
| distance du ventre à la tôle | **1,0 à 5,0 mm** (assise 5,0) — il ne flotte pas |
| enfoncement dans le mobilier | **0,0 mm** |
| dépassement hors de la coque | **0,0 mm** |
| écart maxi entre deux anneaux | **19,0 mm** (espacement 19,0) |
| au nez de la planche | normale (0,1,0) → **(0,0,1)**, puis 318 mm plus bas |
| figé une seconde | **+0,0000** de phase de pattes |
| 0,5 s de marche, libre / sous 18 m/s² | **0,210 m** / **0,000 m** |
| laissé tourner, moteur en marche | **il part seul**, par la vitre conducteur |

La dernière ligne est la seule qui ne soit pas avancée à la main, et elle est là
pour ça : tout le reste prouve *comment* il marche, elle seule prouve que
**quelque chose le déclenche**. Un banc entièrement vert peut très bien couvrir
une bestiole que rien ne réveille.

Le banc écrit aussi `20_millepattes_sort.png` (il émerge du dégivrage),
`21_millepattes_planche.png` et `22_millepattes_gros_plan.png`. Ce n'est pas de
l'illustration : la couleur trop sombre ne se lisait dans **aucun chiffre** — le
mille-pattes marchait parfaitement, aux millimètres près, et restait invisible.
Il faut le voir.

Deux mesures ont dû être refaites, et les deux fois c'est le banc qui avait tort,
pas le jeu :

- **« Derrière le plan de la bouche »** ne veut rien dire pour une fente
  verticale. Le dégivrage souffle vers le *haut* : son plan coupe l'habitacle en
  deux, et tout ce qui est plus bas que la planche comptait comme « pas encore
  sorti », plancher compris. Un anneau est **dans la tôle** ou il n'y est pas, et
  les boîtes le disent.
- **L'angle saillant se mesure à l'instant où il bascule**, pas à l'arrivée. Il
  continue sa route ensuite et finit sur le dessus de console, normale en l'air —
  ce qui donnait « il n'a pas basculé » alors qu'il venait d'y passer.

### La suite

Il se promène, il n'attaque pas encore. Ce qui reste à décider est ce qu'il fait
une fois arrivé sur toi, et ce que tu peux lui faire : le revolver est déjà là,
et `head_point()` donne sa tête à viser.

## L'étrangleur

Troisième ennemi ([strangler.gd](scripts/strangler.gd)). Le géant écrase la
voiture de dehors, le mille-pattes la traverse comme si elle n'existait pas ;
celui-ci considère qu'elle n'est pas un abri mais **une poignée**. Un humanoïde
décharné de 2,02 m, debout au milieu de la voie, dont les bras descendent aux
chevilles — 1,58 m d'épaule au bout des doigts, là où un homme de cette taille
en fait 0,88, soit 3,56 m d'envergure. À 42 m, quand les phares le trouvent, il
écarte les bras : il ne barre pas la route par hasard, il l'annonce. Il se
décale (2,6 m/s) pour rester devant toi ; le percuter ou passer à moins de
1,15 m de la caisse, et il s'agrippe. Ni le freinage ni les embardées ne le
décrochent — sous une secousse de plus de 14 m/s² il s'arrête et se cramponne,
comme le mille-pattes, parce que s'agripper est son métier à lui aussi. Ce qui
le décroche, c'est **cinq balles**. La tête compte double.

### De prise en prise, et une main tient toujours

La carrosserie n'est pas un sol, c'est une suite de **poignées** : bord du
capot, auvent d'essuie-glaces, montant A, ceinture de caisse — vingt prises
nommées, dix par flanc, chacune avec sa normale et la direction de ses doigts.
De chacune, **une seule suivante** mène vers la portière du même côté : pas de
graphe, pas de recherche de chemin, une chaîne, comme une voie d'escalade. Le
côté est fixé par la prise d'accrochage (la plus proche du buste à l'impact),
donc un choc frontal remonte le capot — six prises, on le regarde ramper vers
soi à travers le pare-brise — et un frôlement latéral le met directement à la
ceinture, à deux prises de la portière.

La règle des mains est **celle du volant** : une main ne lâche que si l'autre
tient. Une main plantée est un point fixe en espace voiture (dérive relevée au
banc : **0,0 mm**), l'autre vole vers la prise suivante, et le corps pend sous
les deux — sur les flancs il PEND, chest contre la tôle, pieds calés au bas de
caisse (jamais sur la chaussée : elle défile dessous, un pied posé là serait un
patin) ; sur le capot il RAMPE, accroupi. La posture n'est pas un état de
plus : elle sort de la normale de la prise. Chaque main qui claque passe par
`car.impact()` — on **sent** chaque prise dans la suspension avant d'avoir
tourné la tête, le canal même des pas du géant.

Il change de parent en s'accrochant (`reparent` vers la voiture) : tout son
monde passe en espace voiture, là où vivent déjà les objets, la visée et le
mille-pattes, et 170 km/h redeviennent zéro.

### La portière s'ouvre — vraiment

Arrivé à la ceinture, il secoue la poignée extérieure — **cinq secousses**, le
temps de comprendre ce qui arrive et d'armer le revolver — puis la porte cède.
Les portières s'ouvrent depuis toujours dans le modèle, il n'y avait juste
personne pour le faire : `cabin.gd` monte maintenant une **charnière** par
porte (pivot vertical au bord avant, cote `DOOR_Y_FRONT`), sous laquelle
passent garniture, poignées, haut-parleur ET les deux pivots de vitre créés par
`_build_windows` — la manivelle continue de fonctionner porte ouverte, les deux
mouvements se composent (relevé : poignée de manivelle à x −1,37 porte ouverte,
−0,66 fermée). Ce qui ne tourne pas : le panneau extérieur, fondu dans le flanc
de la caisse — de nuit, vu du siège, la porte EST sa garniture et sa vitre.
`set_door()` / `door_amount()` sont l'API ; une porte ouverte ouvre aussi le
son de l'habitacle (`_window_openness`), et elle **reste** ouverte : personne ne
la referme, c'est la cicatrice de la rencontre.

Si la vitre de ce côté est descendue de plus de moitié, il ne s'embarrasse pas
de la poignée : il passe les bras par le jour. Une vitre ouverte était déjà une
entrée pour le mille-pattes ; elle l'est pour tout le monde.

### Deux fins, choisies par la vitesse

Les bras entrent (1,5 s — la dernière fenêtre de tir), les mains se referment,
et le signal `caught` part vers `main.gd`, qui possède la caméra et l'écran :

- **voiture lancée (« throw »)** — le conducteur est arraché de son siège. La
  caméra est reparentée au monde avec la vitesse de la caisse plus la poussée
  du bras, et à partir de là c'est un corps qui tombe : gravité, rebond,
  glissade, immobilité — puis la tête, couchée sur le bitume, se tourne vers la
  seule chose qu'il reste à voir : les feux arrière qui rétrécissent, portière
  battante (mesuré : la voiture est à **379 m** quand l'écran s'éteint,
  `driverless` coupe les pédales et la jante, les rétroviseurs gèlent — visés
  depuis le bitume leurs frustums dégénèrent). Le point de non-retour est le
  contact des mains.
- **voiture arrêtée (« strangle »)** — les mains se referment sur la gorge, la
  vision bat au rythme d'un cœur qui force et le plancher de la pulsation
  monte ; noir complet en 4,5 s. Celle-ci **s'annule** : une balle pendant
  l'étranglement le fait lâcher (relevé : noir à 0,50 au moment du tir, 0,00
  une demi-seconde après). C'est toute la tension du corps-à-corps — tirer
  pendant que l'écran s'éteint.

Mort, il lâche tout : parti avec la vitesse de la voiture, il culbute sur la
chaussée (pas de moteur physique : gravité, une rotation, le sol), et y reste
en tas — bras rejeté au-dessus de la tête, l'autre en travers, parce qu'un
corps tombe n'importe comment, pas en étoile.

### On le tire au travers du groupe « shootable »

Le rayon du revolver interroge maintenant **deux mondes** : le serveur physique
(la caisse), et le groupe `shootable`, **analytiquement** — chaque créature
répond elle-même à `ray_hit()` sur le squelette de l'image en cours, capsule
par capsule, sphère pour le crâne. Pas de corps physique : un corps accroché à
une caisse qui roule ne transmet sa position au serveur qu'au pas suivant, le
défaut qui faisait déjà rater le paquet de cigarettes à 24 m/s. Le plus proche
des deux gagne et reçoit `hit()`. Les vitres n'arrêtent pas les balles — c'est
une abstraction assumée du prototype, comme le panneau extérieur qui ne tourne
pas.

Piège relevé au banc : la convention de `_bone` envoie (0, −0,5, 0) sur le
*début* de l'os et (0, +0,5, 0) sur sa *fin*. La première version du relevé de
squelette lisait à l'envers — le « poignet » était le coude, la capsule de
l'avant-bras un point, et le banc mesurait des doigts à 65 cm du sol sur un
corps dont ils le touchent (0,07 m une fois remis à l'endroit).

### Blême, et c'est un choix d'éclairage

Tout le décor absorbe (troncs 0,075, géant 0,070) ; lui renvoie **0,34** —
c'est l'ennemi qui vit DANS la lumière du joueur, là où le géant vit dans son
brouillard. Plus un souffle d'auto-lueur (émission 0,04, très loin du seuil de
glow) : sans elle, pendu à la portière côté nuit, il était un trou noir dans du
noir et le joueur qui tournait la tête ne trouvait rien à viser. Les yeux sont
deux orbites **noires** — sur un visage qui luit à peine, des trous lisent
mieux que des braises, et le géant garde les siennes. La pendaison est réglée
pour que le crâne tombe au milieu de la glace (relevé : **1,18 m**, vitre
0,97–1,235) : on tourne la tête, et il est là, à soixante centimètres, qui
regardait déjà. La tête suit le conducteur en permanence — le même fil que le
géant : le corps fait sa vie, le regard jamais.

### Les sons

`tools/make_strangler_sounds.py`, les briques du géant (glotte de Rosenberg,
filtres à phase minimale, dosage à la sonie), six fichiers dans
`assets/audio/strangler/` : le **cri** (une gorge d'homme poussée au-delà — f0
qui monte de 300 à 620 Hz puis se casse, formants de bouche grande ouverte,
coupé à 3,2 kHz pour ne pas grésiller au tramage), le **coup encaissé** (même
appareil, une demi-seconde, f0 qui chute — on sait que la balle a porté sans
regarder), la **respiration** en boucle sans couture (audible à 3 m : on ne
l'entend que quand il est à la vitre, et c'est le but), la **paume sur la
tôle** (coup sourd + partiels inharmoniques d'une plaque, pas d'infra — une
main n'ébranle pas le sol), la **poignée secouée** et la **charnière** (du
stick-slip : la même glotte que la voix, un grincement EST une voix de métal,
f0 de 320 à 90 Hz et le clonc de butée à la fin).

### Banc d'essai

```bash
godot --path . -- stranglertest
```

| | relevé |
|---|---|
| la route le pose | **oui**, au milieu de la voie (0,70 m de l'axe, jeu 0,8), face à la voiture |
| bras épaule → doigts / envergure | **1,58 m** / **3,56 m** (stature 2,02) |
| debout, bout des doigts au-dessus du sol | **0,07 m** |
| frôlé à 1 m sur sa droite | il s'agrippe au **pare-chocs**, vise la portière **gauche** |
| pare-chocs → portière | **12 mains posées**, 6,4 s |
| dérive d'une main posée (espace voiture) | **0,0 mm** |
| images à deux mains en vol | **0** — une main ne lâche que si l'autre tient |
| crâne pendu à la portière | **1,18 m** (vitre 0,97–1,235) |
| secousses de poignée avant que ça cède | **5** |
| porte ouverte | **62°**, garniture à x −0,89 (tôle −0,79), manivelle partie avec (−1,37) |
| voiture arrêtée | mode **« strangle »**, noir à 0,50 à mi-étreinte |
| trois balles pendant l'étreinte (visée réelle, `_nearest_shootable`) | il lâche, noir **annulé**, partie **pas** perdue |
| il finit | au sol, y **0,16 m**, en tas |
| voiture tenue à 20 m/s | mode **« throw »**, caméra reparentée au monde, `driverless` |
| la voiture quand l'écran s'éteint | à **379 m** |

Le banc tient la vitesse **pendant** l'approche et pendant la montée à la
portière, et ce n'est pas un confort : lâchée une fois, la vitesse passe sous
le ralenti du rapport, le moteur cale (voir « Caler ») et la voiture s'arrête à
dix mètres de lui — le banc mesurait alors un frein moteur, pas une prise. Même
piège que le frein à main et la 5e, par un troisième chemin.

Il écrit `60_etrangleur_route.png` (posé par la route), `60b_etrangleur_phares.png`
(la croix dans les phares — l'image que le joueur aura), `61_etrangleur_pendu.png`
(pendu au flanc, caméra montée SUR la voiture, sinon le cadrage fuit de huit
mètres pendant la pose), `61b_etrangleur_vitre.png` (le crâne à la glace, vu du
siège), `62_etrangleur_porte.png` (les bras dans l'ouverture),
`63_etrangleur_etreinte.png`, `63b_etrangleur_abattu.png` et
`64_etrangleur_jete.png` (l'écran de fin). Comme pour le mille-pattes, deux
défauts ne se lisaient dans **aucun chiffre** — la tête qui dépassait du toit en
pendaison, le visage caché derrière son propre avant-bras pendant l'étreinte —
il faut le voir.

## Les boutons à tourner en premier

- **Boîte** — `car.gd` : `GEAR_TOP` (vitesse au rupteur par rapport),
  `GEAR_PULL` (poussée), `engine_power`, `require_clutch`.
- **Tenue de route** — `car.gd` : `steer_rate`, `max_lateral`, `rolling_drag`.
  `max_lateral` est l'adhérence des pneus, en m/s² : elle plafonne le taux de
  lacet à `max_lateral / v`, donc le rayon de braquage à `v² / max_lateral`.
  Au-delà la voiture **sous-vire**, elle ne pivote pas plus vite.
- **Tremblement de caisse** — `car.gd` : `camera_shake`, `0` pour une caméra fixe.
- **Cadrage** — `car.gd` : `HEAD_POS` (position de l'œil) et `fov_base`.
  Un FOV trop large et l'habitacle mange l'écran ; 46° vertical ≈ 73° horizontal.
- **Noirceur** — `main.gd` : `fog_density`, `ambient_light_energy`, et
  `light_energy` des phares dans `car.gd`.
- **Rétroviseurs** — `mirror.gd` : `RES_H` (hauteur de rendu, trois passes de
  scène par image), `swivel_speed` / `yaw_limit` / `pitch_limit` pour le réglage
  à la souris ; `cabin.gd` : `MIRROR_AIM` pour ce que chaque glace doit montrer
  au départ, `MIRROR_HEAD` pour ce qui pivote avec elle, `EYE_REF` qui doit
  rester d'accord avec `HEAD_POS` de `car.gd`.
- **Ce qui reste posé dans l'habitacle** — `prop.gd` : `static_mu`. Le seuil
  doit rester au-dessus du pire cas de conduite (frein + frein moteur, 20,4 m/s²)
  et sous le plafond de `frame_accel` dans `car.gd` (60), sinon plus rien ne peut
  décrocher.
- **Mille-pattes** — `centipede.gd` : `first_delay` (quand il arrive),
  `window_weight` (à quel point une vitre ouverte l'emporte sur les grilles),
  `window_min_open`, `RUN_SPEED`, `RUN_MIN`/`FREEZE_MIN` (le rythme
  course/arrêt), `HAUNTS` (où il va, et avec quel poids). `GRIP` et `RIDE` ne se
  touchent qu'ensemble : `GRIP` doit rester inférieur à `RIDE`, sinon il ne se
  décolle jamais de la tôle. `cabin.gd` : `VENT_MOUTHS` pour ajouter une bouche
  (le nom d'une pièce du `.glb` suffit, tout le reste en est relevé). Pour lui
  ouvrir un chemin, il n'y a plus rien à déclarer : on ajoute la pièce au `.glb`
  et on recuit — elle devient un chemin parce qu'elle est visible, pas parce
  qu'on l'a inscrite quelque part.
- **Prises sur le volant** — `driver.gd` : `GRIP_PULL` et `GRIP_PUSH` (jusqu'où
  une main suit la jante avant de lâcher, en tirant et en poussant),
  `REGRIP_TIME` / `REGRIP_LIFT` (durée et hauteur du passage de main),
  `GRIP_SEPARATION` (écart minimum entre les deux mains),
  `SLIP_HOME` / `SLIP_OPEN` (volant rendu : vitesse de retour des mains et
  desserrage des doigts), `PALM_LIFT` / `FLAT_CLOSE` (pose à plat, une main
  prise).
  Baisser `GRIP_PUSH` fait lâcher dans des virages ordinaires ; le monter fait
  traverser un avant-bras qu'on ne voit pas. `-- wheeltest` mesure les deux.
- **Position de conduite** — `driver.gd` : `SHOULDER_L/R`, `SPINE`, `HIP_L/R`,
  `UPPER_ARM` + `FOREARM`. Attention : si le volant est plus loin de l'épaule
  que `UPPER_ARM + FOREARM`, `_solve_elbow` bute en butée et `_set_bone` étire
  l'avant-bras pour rattraper — bras de gorille.

  Le conducteur est assis **au fond du siège** : la face avant du dossier du
  `.glb` est à `z = 0.410`, l'épaule tombe donc à `0.30` et l'œil à `0.28`
  (`HEAD_POS` dans `car.gd`). Il était auparavant à `0.10`, perché sur l'avant de
  l'assise, le nez sur le volant.

  Contrepartie : le siège du modèle est trop loin du volant — 79 cm entre le
  dossier et l'axe de la jante, là où une Civic en fait 60 à 65. Assis au fond,
  la jante est à 70 cm pour 58 cm de bras (30 + 28). Depuis que l'avant-bras vise
  le poignet du modèle (5 cm avant la jante, mains à 10 h 10), les coudes
  plient à ~130° ; `cabin.gd` rapproche encore la colonne de 2 cm
  (`COLUMN_PULL`) et **laisse le fourreau contre la planche de bord**,
  sinon on verrait le trou par lequel la colonne y entre. À corriger à la source
  dans `build_civic_interior.py` si on veut que ce soit définitif.
- **Grille de la boîte** — `driver.gd` : `GEAR_GATE`, un `Vector2` par rapport.
- **Virages de la route** — `road.gd` : `MAX_CURVE` (rad/m, 0.009 ≈ rayon 110 m).
- **Voiture de police** — `road.gd` : `POLICE_FIRST`, `POLICE_EVERY_MIN/MAX`,
  `POLICE_OFF` ; `police_car.gd` : `turn_hz`, `beam_energy`, `beam_fog`,
  `dome_peak`.
- **Son du moteur** — `engine_audio.gd` : `volume_db`, `wobble`, `load_attack` ;
  `rpm_fall_rate` et `limiter_cut_time` dans `car.gd` pour la descente de
  régime et le rupteur ; le timbre lui-même est dans `tools/make_engine_sounds.py`.
- **Route, vent, commandes** — `cabin_audio.gd` : `road_volume_db`,
  `wind_volume_db`, `wind_start`, `wind_full`, `shift_volume_db`,
  `handbrake_volume_db`.

## Pièges déjà rencontrés

- Les meshes de la voiture sont en `cast_shadow = OFF` : sinon le capot bloque
  ses propres phares.
- La lampe du tableau de bord doit rester **hors** de la boîte de la planche de
  bord, et pas collée à une surface, sinon elle y grille un disque blanc.
- `light_volumetric_fog_energy` élevé sur les phares fait une boule lumineuse
  autour de l'ampoule, qui déborde du capot et se voit depuis le siège.
- L'œil doit être à ~1 m du bas du pare-brise. Plus près, toute la structure
  proche paraît gigantesque — c'était la cause du « la voiture est trop imposante ».
- `Basis.slerp()` caste **ses deux** arguments en quaternion, et Godot refuse
  d'y couler une base non orthonormale. Celle de la main sort d'une chaîne de
  `interpolate_with()` qui la dénormalise d'un cheveu — vecteurs unitaires et
  orthogonaux à 1e-4 près, invisible à l'œil, mais assez pour faire crier la
  console à chaque image où l'arme est levée. Orthonormaliser l'argument reçu
  ne suffit pas, il faut aussi celui sur lequel on appelle la méthode
  ([driver.gd](scripts/driver.gd), `update_pose`).

## Shaders

`shaders/dither_post.gdshader` fait le **tramage**, en post-traitement plein
écran (un `ColorRect` sur une `CanvasLayer` à la couche 0, donc au-dessus de la
3D mais sous le HUD, qui reste net). Motif de Bayer 4×4 ajouté juste avant une
quantification à 32 niveaux par canal — la profondeur 15 bits de la PS1.

Les réglages sont en tête du fichier : `color_steps`, `pixel_size`, `strength`.

**Pourquoi pas dans le matériau.** C'est là que je l'avais mis au départ, et ça
ne se voyait pas : appliqué à l'ALBÉDO, le motif est ensuite multiplié par un
éclairage faible puis passé dans le tonemapping, et il ne restait qu'**un niveau
d'écart sur 255**. En post-traitement, l'écart est de 8 niveaux — le pas de
quantification. La PS1 tramait l'image finale, pas les matériaux.

`shaders/retro.gdshader` n'est plus qu'un matériau de couleur unie avec rugosité
et métallicité. Le vertex snapping, le mapping affine et l'éclairage par sommet
du shader PS1 d'origine ont été retirés — l'éclairage est normal, par pixel et
avec ombres.

`shaders/a_tester_dither_light.gdshader.txt` attend son tour : tramage appliqué
dans la passe `light()`. Il est en syntaxe Godot 3, il faudra le porter avant de
l'essayer (voir l'entête du fichier).

## Captures automatiques

```bash
godot --path . -- shot
```

Autres bancs d'essai en ligne de commande, dont `-- wheeltest` (enchaînement de
prises sur le volant : une main tient toujours, les mains ne se traversent pas,
aucune ne va chercher plus loin que le bras) :
`-- geartest` (vitesse maxi par rapport et 0-100), `-- hbtest` (frein à main :
bascule, filtrage des répétitions clavier, efficacité), `-- audiotest` (son du
moteur), `-- packtest` (prise, dépose, et ce qui reste en place en accélérant,
en virage, au freinage et au choc) , `-- mirrortest` (réglage du rétroviseur :
regard bloqué, glace orientée, caméra virtuelle qui suit) et `-- visortest`
(pare-soleil : déployé sous la ligne des yeux, rangé à plat vers le joueur et
non enterré dans la garniture) et `-- windowtest` (vitre : manivelle qui tourne,
glace qui disparaît sous la ceinture, et les deux panneaux qui suivent) et
`-- throwtest` (lancer : départ dans l'axe du regard, clic molette qui ne
débraye pas, objet qui reste dans la caisse et se repose d'aplomb) et
`-- stalltest` (calage et clé de contact : ce qui tient débrayé meurt embrayage
lâché, la clé tournée ne lance rien en prise, et on part quand même de l'arrêt)
et `-- centipedetest` (mille-pattes : les huit bouches relevées et bien
orientées, l'entrée par la vitre quand elle est baissée, le corps payé hors du
trou anneau par anneau, et 40 s de marche sans flotter, sans s'enfoncer et sans
sortir de la coque) et `-- gianttest` (géant : la route qui le pose dans les
arbres, le pied à la taille de la voiture, Froude qui se recoupe, la pointe du
pied d'appui qui ne dérive pas d'un millimètre, la jambe qui ne s'allonge pas,
foulée × cadence = vitesse, semé en 5e et pas en 4e, et la canette qui saute
quand le pied tombe sur la caisse).
Ils injectent de vrais événements d'entrée, ils ne rejouent pas la logique en
double — à une exception près, assumée et écrite dans le banc : `centipedetest`
avance la bestiole **à la main**, au pas fixe, pour ne pas mesurer le débit
d'images à la place de son adhérence.

### Les sondes, qui ne sont pas des bancs

Elles ne jouent pas le jeu : elles lisent le `.glb` et disent ce qu'il contient.
C'est la différence qui compte — un banc vérifie que le jeu fait ce qu'il dit, une
sonde vérifie que ce qu'il dit correspond au **modèle**, et c'est le second qui
manquait.

```bash
godot --headless --path . --script res://tools/bake_cabin.gd       # cuit la forme
godot --headless --path . --script res://tools/check_shape.gd      # la relit
godot --headless --path . --script res://tools/probe_collisions.gd # avant / après
godot --headless --path . --script res://tools/probe_surfaces.gd   # cartes de hauteurs
godot --headless --path . --script res://tools/probe_vents.gd      # bouches d'aération
```

`probe_collisions.gd` est celle qui a nommé le défaut. Elle rejoue **le même
balayage de 900 lancers avec les deux géométries** — les boîtes d'avant et le
relevé d'après — et pose au maillage une question que ni `packtest` ni
`throwtest` ne posaient : *où l'objet s'est-il arrêté ?* Un chiffre d'« après »
seul ne dirait pas s'il y avait un défaut ; les deux, si.

**Aucun banc à clics ne tourne en `--headless`** : `interaction.gd` ignore la
souris tant qu'elle n'est pas capturée, ce qu'un moteur sans fenêtre ne peut pas
offrir. Le symptôme est trompeur — la cible est bien visée, l'objet se met même
en surbrillance, mais l'état reste `IDLE` et pas un clic ne passe.

Roule 2 secondes puis écrit plusieurs images dans
`%APPDATA%/Godot/app_userdata/Nouveau projet de jeu/` : la vue de conduite, le
poste de conduite, les trois rétroviseurs de près sous l'éclairage de nuit
(`15_*.png`), et deux vues extérieures éclairées pour vérifier la carrosserie.
Pratique pour contrôler un réglage sans jouer. `shot` imprime aussi, pour chaque
glace, l'écart entre sa caméra virtuelle et le symétrique calculé de l'œil : une
image plausible peut sortir d'une caméra mal placée, pas une erreur de 0 mm.

## Suite possible

Clignotants, essuie-glaces et pluie, quelque chose sur la route.

Pour le géant, dans l'ordre : **une réponse aux dégâts**, sans laquelle il ne
peut ni avoir de boîte de collision (un pied solide catapulte une
`CharacterBody3D`) ni tuer. Puis les **arbres qu'il renverse** en coupant à
travers bois, qui diraient sa masse mieux que n'importe quel son. Puis les
**variantes de pas** — il n'a qu'un `step.wav` repitché, et à 1,14 pas par
seconde on l'entend.

Le calage et son démarreur sont faits (voir « Caler »), les rétroviseurs
montrent vraiment l'arrière depuis qu'ils ont chacun leur `SubViewport` (voir
« Les rétroviseurs ») : les deux figuraient ici et n'y ont plus leur place.
