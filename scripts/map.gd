extends RefCounted
##
## LA CARTE — le graphe des villes, et rien d'autre.
##
## Huit villes, dix routes, ECRITES A LA MAIN : une carte se lit, se
## memorise, s'apprend — un graphe procedural n'a pas de pays. Les
## coordonnees 2D ne servent qu'a l'AFFICHAGE (l'ecran GPS du telephone) :
## le monde reel est le ruban de road.gd, qui serpente comme il veut et ne
## doit a la carte que les LONGUEURS d'aretes — la geometrie est libre, la
## metrique est un contrat. Le brouillard couvre le reste.
##
## Le degre ne depasse jamais 3 : une bifurcation est un Y, jamais un
## carrefour — un choix au volant se fait entre DEUX sorties.
##
## Les distances sont en METRES de route (l'unite de road : STEP par
## echantillon), les coordonnees d'affichage en unites de carte arbitraires.
##

## Les villes : nom -> {at: Vector2 (affichage), amen: [commodites], seed: int}.
##
## La GRAINE est le bourg entier. town_plan.gd en tire tout ce qui n'est pas
## ecrit a la main : le nombre de rues, leurs abscisses, leur etendue, les
## batiments, les fenetres allumees. Elle est ECRITE ici et pas hachee sur le
## nom, pour deux raisons : deux parties ont la meme Corbeny, jusqu'au numero
## de la porte ; et un bourg laid se re-tire en changeant un entier sur cette
## ligne, sans qu'une ligne de geometrie bouge.
const TOWNS := {
	"Saint-Elme": {"at": Vector2(0.18, 0.78), "seed": 10847,
		"amen": ["station-service", "cafe de nuit"]},
	"Corbeny": {"at": Vector2(0.42, 0.86), "seed": 40213,
		"amen": ["hotel", "distributeur"]},
	"La Fresnaie": {"at": Vector2(0.15, 0.45), "seed": 23561,
		"amen": ["garage"]},
	"Malassis": {"at": Vector2(0.45, 0.55), "seed": 58402,
		"amen": ["cafe de nuit", "distributeur", "station-service"]},
	"Vieux-Bourg": {"at": Vector2(0.72, 0.68), "seed": 31976,
		"amen": ["hotel", "garage"]},
	"Les Essarts": {"at": Vector2(0.30, 0.16), "seed": 47130,
		"amen": ["distributeur"]},
	"Peyrelade": {"at": Vector2(0.66, 0.30), "seed": 62845,
		"amen": ["station-service", "hotel"]},
	"Brumaire": {"at": Vector2(0.88, 0.42), "seed": 19388,
		"amen": ["cafe de nuit"]},
}

## Les routes : paires de villes et longueur en metres. Non orientees.
const EDGES := [
	["Saint-Elme", "Corbeny", 950.0],
	["Saint-Elme", "La Fresnaie", 1250.0],
	["Corbeny", "Malassis", 1100.0],
	["Corbeny", "Vieux-Bourg", 1400.0],
	["La Fresnaie", "Les Essarts", 1300.0],
	["La Fresnaie", "Malassis", 1150.0],
	["Malassis", "Peyrelade", 1350.0],
	["Les Essarts", "Peyrelade", 1600.0],
	["Vieux-Bourg", "Brumaire", 1050.0],
	["Peyrelade", "Brumaire", 1200.0],
]


## L'index d'adjacence, bati une fois et jamais refait. Il n'existe que pour un
## chiffre : taxi.gd:205 appelle path() HUIT FOIS par offre — une par ville
## candidate — et path() rebalayait les dix aretes a chaque neighbors() ET a
## chaque edge_length(), soit une vingtaine de milliers de comparaisons de
## chaines a chaque coup de telephone. Avec l'index, deux cents.
##
## Il est construit dans l'ORDRE DE `EDGES`, dans les deux sens : la liste de
## voisins rendue est exactement celle d'avant, element pour element. C'est ce
## qui compte, parce que main.gd:4046-4061 prend outs[0] et outs[1] pour
## choisir les deux villes d'un Y, et que maptest juge la carte sur ce choix-la.
##
## Le tableau rendu par neighbors() est PARTAGE : c'est la ligne de l'index
## elle-meme, pas une copie — deux appels rendent LE MEME OBJET. Il est donc
## FERME A L'ECRITURE, et ce n'est pas une politesse. Le premier
## "var outs = neighbors(id) ; outs.erase(from)" — la facon evidente d'ecrire
## main.gd:4046, et celle qu'on ecrira le jour ou l'on oubliera ce paragraphe —
## arracherait une arete de la carte POUR TOUTE LA PARTIE, en silence : plus
## de Y a ce bourg, un chemin de Dijkstra qui rallonge, et rien dans la console.
## Ferme, la meme ligne crie. On ne modifie donc pas ce tableau, on le FILTRE
## (main.gd:4046 fait deja .filter(), qui rend un tableau neuf et libre).
static var _adj := {}
static var _len := {}


static func _index() -> void:
	if not _adj.is_empty():
		return
	for t in TOWNS:
		_adj[t] = []
		_len[t] = {}
	for e in EDGES:
		_adj[e[0]].append(e[1])
		_adj[e[1]].append(e[0])
		_len[e[0]][e[1]] = e[2]
		_len[e[1]][e[0]] = e[2]
	# Le verrou : huit appels, une fois par partie, et le piege est ferme pour
	# de bon. Apres cette ligne l'index ne se remplit plus — c'est justement ce
	# qu'on veut, il est bati une fois et jamais refait.
	for t in _adj:
		var out: Array = _adj[t]
		out.make_read_only()


static func towns() -> Array:
	return TOWNS.keys()


static func neighbors(town: String) -> Array:
	_index()
	return _adj[town] if _adj.has(town) else []


static func edge_length(a: String, b: String) -> float:
	_index()
	if not _len.has(a):
		return -1.0
	var d: Dictionary = _len[a]
	return d[b] if d.has(b) else -1.0


## La graine d'un bourg. Les bancs arment des villes qui ne sont pas sur la
## carte : elles ont droit a un plan, mais pas a un numero ecrit a la main.
static func seed_of(town: String) -> int:
	if TOWNS.has(town):
		return int(TOWNS[town]["seed"])
	return hash(town)


static func at(town: String) -> Vector2:
	return TOWNS[town]["at"]


static func amenities(town: String) -> Array:
	return TOWNS[town]["amen"]


## Plus court chemin (Dijkstra sur dix aretes : la version naive suffit
## pour toujours). Rend la liste des villes, depart et arrivee compris, ou
## [] si rien ne relie — ce qui, sur cette carte, n'arrive pas.
static func path(from: String, to: String) -> Array:
	if from == to:
		return [from]
	var dist := {}
	var prev := {}
	var open := []
	for t in TOWNS:
		dist[t] = 1.0e18
	dist[from] = 0.0
	open.append(from)
	while not open.is_empty():
		var best := ""
		var bd := 1.0e18
		for t in open:
			if dist[t] < bd:
				bd = dist[t]
				best = t
		open.erase(best)
		if best == to:
			break
		for n in neighbors(best):
			var nd: float = dist[best] + edge_length(best, n)
			if nd < dist[n]:
				dist[n] = nd
				prev[n] = best
				if not open.has(n):
					open.append(n)
	if not prev.has(to):
		return []
	var out := [to]
	while out[0] != from:
		out.insert(0, prev[out[0]])
	return out


static func path_length(route: Array) -> float:
	var d := 0.0
	for i in route.size() - 1:
		d += edge_length(route[i], route[i + 1])
	return d
