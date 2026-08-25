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
| H | phares |
| Souris | regarder autour |
| **Clic droit maintenu** | **se pencher dans la direction du regard** (sauf arme en main : elle se lève) |
| **Clic gauche maintenu** sur le rétroviseur ou un pare-soleil | **le placer** (regard bloqué) |
| **Clic gauche maintenu** sur une manivelle de vitre | **tenir la poignée** (caméra libre) |
| **Molette ↓ / ↑**, poignée en main | **descendre** / **remonter** la vitre (la boîte ne bouge pas) |
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
**50 / 87 / 122 / 155 / 172 km/h**, et 0-100 km/h en **12,0 s**.

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
**90 km/h → arrêt en 4,4 s**, et **0,0 km/h plein gaz en 1re, frein serré**.

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
y intègre lui-même sa vitesse et résout ses collisions contre les boîtes
déclarées par `cabin.gd`, par axe de moindre pénétration. C'est stable à
n'importe quelle vitesse, parce qu'il n'y a plus de vitesse du tout de ce point
de vue.

Ce qu'on ressent quand la voiture accélère, freine ou tourne vient des **forces
d'inertie** : `car.gd` publie `frame_accel`, son accélération dans son propre
repère (longitudinale, plus la centripète ω·v), et l'objet en subit l'opposé.

Six pièges rencontrés, tous corrigés :

- **Boîtes qui se chevauchent** — un objet coincé dans une intersection se fait
  éjecter. La console est désormais une seule boîte, pas un dessus posé sur un
  caisson, et les deux morceaux de planche de bord sont jointifs.
- **Tunnelling** — une dalle de 2 cm se fait traverser par un objet qui tombe de
  6 cm par image. Les boîtes sont épaisses vers le bas (elles sont invisibles) et
  l'intégration se fait en sous-pas de 2 cm.
- **Plancher trop court** — il s'arrêtait aux pieds, et ce qui glissait vers
  l'arrière tombait dans le vide. Il court maintenant sur toute la longueur.
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
- **surfaces** — intersection avec le plan de leur dessus, puis test d'emprise
  en x/z. Elles sont toutes horizontales, ça suffit.

C'est ce qui a corrigé « je ne peux pas saisir le paquet en roulant » : un
`StaticBody3D` accroché à une caisse qui roule ne transmet sa position au
serveur physique qu'au pas suivant. À 24 m/s le rayon passait **40 cm à côté** —
à l'arrêt l'écart était nul, d'où l'impression que ça ne marchait que garé.

Les surfaces de dépose sont **sept boîtes** déclarées dans
[cabin.gd](scripts/cabin.gd) : les deux assises avant, la banquette arrière, le
dessus de console, le plancher, et le tableau de bord en deux morceaux — la
casquette pleine largeur au ras du pare-brise, plus la partie profonde côté
passager. Côté conducteur cette partie-là est exclue : c'est le bloc compteurs,
encastré dans la planche, et un objet posé dessus flotterait.

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
ferme maintenant le pare-brise (**trois marches** de 10 cm, il est incliné du
bas de baie à 0,93 m au haut de baie à 1,28 m), le pavillon, la lunette arrière
et les glaces latérales.

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
| `scripts/prop.gd` | objets libres de l'habitacle : simulation en repère voiture, frottement de Coulomb |
| `scripts/road.gd` | route infinie et lisse, arbres, poteaux, voiture de police |
| `scripts/police_car.gd` | voiture de police garée (`police_car.glb`) : gyrophares rotatifs, faisceaux bleus |
| `assets/blender/build_police_car.py` | construit, rend et exporte `police_car.glb` depuis Blender (ligne de commande) |
| `assets/blender/build_police_car_simple.py` | idem pour la version basse-poly `police_car_simple.glb` (non utilisée) |
| `scripts/retro.gd` | fabrique de matériaux, tous branchés sur le shader |
| `scripts/engine_audio.gd` | son du moteur : fondu entre boucles, pitch, charge, rupteur |
| `scripts/cabin_audio.gd` | route, vent, levier, frein à main |
| `tools/make_engine_sounds.py` | synthèse des boucles moteur (`assets/audio/engine/`) |
| `tools/make_cabin_sounds.py` | synthèse des sons d'habitacle (`assets/audio/cabin/`) |
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
débraye pas, objet qui reste dans la caisse et se repose d'aplomb). Ils injectent de vrais
événements d'entrée, ils ne rejouent pas la logique en double.

Roule 2 secondes puis écrit plusieurs images dans
`%APPDATA%/Godot/app_userdata/Nouveau projet de jeu/` : la vue de conduite, le
poste de conduite, les trois rétroviseurs de près sous l'éclairage de nuit
(`15_*.png`), et deux vues extérieures éclairées pour vérifier la carrosserie.
Pratique pour contrôler un réglage sans jouer. `shot` imprime aussi, pour chaque
glace, l'écart entre sa caméra virtuelle et le symétrique calculé de l'œil : une
image plausible peut sortir d'une caméra mal placée, pas une erreur de 0 mm.

## Suite possible

Calage moteur si on lâche l'embrayage trop bas (et son démarreur), clignotants,
essuie-glaces et pluie, rétroviseur qui montre vraiment l'arrière
(`SubViewport`), quelque chose sur la route.
