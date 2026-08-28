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

## Les villes : nom -> {at: Vector2 (affichage), amen: [commodites]}.
const TOWNS := {
	"Saint-Elme": {"at": Vector2(0.18, 0.78),
		"amen": ["station-service", "cafe de nuit"]},
	"Corbeny": {"at": Vector2(0.42, 0.86),
		"amen": ["hotel", "distributeur"]},
	"La Fresnaie": {"at": Vector2(0.15, 0.45),
		"amen": ["garage"]},
	"Malassis": {"at": Vector2(0.45, 0.55),
		"amen": ["cafe de nuit", "distributeur", "station-service"]},
	"Vieux-Bourg": {"at": Vector2(0.72, 0.68),
		"amen": ["hotel", "garage"]},
	"Les Essarts": {"at": Vector2(0.30, 0.16),
		"amen": ["distributeur"]},
	"Peyrelade": {"at": Vector2(0.66, 0.30),
		"amen": ["station-service", "hotel"]},
	"Brumaire": {"at": Vector2(0.88, 0.42),
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


static func towns() -> Array:
	return TOWNS.keys()


static func neighbors(town: String) -> Array:
	var out := []
	for e in EDGES:
		if e[0] == town:
			out.append(e[1])
		elif e[1] == town:
			out.append(e[0])
	return out


static func edge_length(a: String, b: String) -> float:
	for e in EDGES:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return e[2]
	return -1.0


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
