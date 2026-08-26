extends SceneTree
##
## Outil : ce que les boites de collision de cabin.gd se font entre elles.
##
##   godot --headless --path . --script res://tools/probe_collisions.gd
##
## Pourquoi. Le banc `-- throwtest` mesure les FUITES : un objet qui sort de la
## caisse. Il ne mesure pas le defaut inverse, qui est celui qu'on voit a
## l'ecran — un objet qui reste COINCE DANS UNE PAROI. Les deux ne se
## ressemblent pas : la coque garantit qu'on ne sort pas, et elle n'a jamais
## rien promis sur ce qui se passe DEDANS.
##
## Un objet se coince quand deux boites se recouvrent une fois GONFLEES de ses
## demi-cotes. prop.gd les resout l'une apres l'autre, chacune ignorant ce que
## la precedente vient de faire : dans un recouvrement, la seconde defait le
## travail de la premiere, image apres image, et l'objet vibre sur place au lieu
## de tomber.
##
## Le gonflement est la clef, et c'est pour ca que le probleme est INVISIBLE sur
## le papier : deux boites jointives au millimetre ne se recouvrent pas, mais
## elles se recouvrent de 2 x half des qu'un objet les approche. Une canette
## (57 mm de demi-hauteur) en fait donc apparaitre la ou un paquet (11 mm) n'en
## voyait aucun.
##

const CABIN := "res://scripts/cabin.gd"
const MeshProbe := preload("res://scripts/mesh_probe.gd")
const INTERIOR := "res://assets/models/civic_interior.glb"

## Les deux objets du jeu, avec leurs demi-cotes reelles (cig_pack.gd, can.gd).
const PROPS := [
	["paquet", Vector3(0.0275, 0.011, 0.0425)],
	["canette", Vector3(0.033, 0.0575, 0.033)],
]

## Reprise a l'identique de prop.gd : ce qui est eprouve ici est SON algorithme,
## pas une approximation qui pourrait diverger de lui.
const GRAVITY := 9.81
const BOUNCE := 0.10
const STATIC_MU := 2.4
const KINETIC_MU := 0.55
const SLIDE_EPS := 0.03
const THROW_SPEED := 4.5
## Le poing (interaction.gd, HOLD_POINT).
const HOLD_POINT := Vector3(-0.21, 0.93, 0.0)

const SHAPE_PATH := "res://assets/cabin_shape.res"

var _solids: Array = []
var _hull_min: Vector3
var _hull_max: Vector3
var _mesh: MeshProbe
## La forme relevee, et le vitrage : ce contre quoi le jeu resout MAINTENANT.
var _shape: Resource
var _shell: Array = []


func _initialize() -> void:
	var cabin: Node = load(CABIN).new()
	# Les anciennes boites, gardees dans cabin.gd pour cette comparaison-la.
	cabin._build_surfaces()
	cabin._build_walls()
	_solids = cabin.solids
	_hull_min = cabin.HULL_MIN
	_hull_max = cabin.HULL_MAX
	# Le haut de caisse vitre. `windows` est vide ici (pas de .glb instancie),
	# donc seules les marches de pare-brise et la lunette en sortent : c'est
	# assez pour le balayage, qui part de l'interieur et que la coque borne.
	cabin._build_shell()
	_shell = cabin.shell

	_mesh = MeshProbe.new()
	_mesh.load_glb(INTERIOR)
	if ResourceLoader.exists(SHAPE_PATH):
		_shape = load(SHAPE_PATH)
	else:
		push_warning("%s manquant : seul l'ancien algorithme sera mesure" % SHAPE_PATH)

	print("anciennes boites : %d   vitrage : %d   triangles : %d   pieces : %d" % [
		_solids.size(), _shell.size(), _mesh.tris.size() / 3, _mesh.names.size()])
	if _shape != null:
		print("forme relevee    : %d x %d x %d cases de %.0f mm" % [
			_shape.nx, _shape.ny, _shape.nz, _shape.step * 1000.0])

	# `-- quick` saute les diagnostics des anciennes boites et ne joue que la
	# geometrie d'aujourd'hui : de quoi iterer en une minute au lieu de dix.
	var quick := "quick" in OS.get_cmdline_user_args()
	if "trace" in OS.get_cmdline_user_args():
		_trace()
		cabin.free()
		quit()
		return
	if not quick:
		_overlaps()
		_hull_conflicts()
		_box_vs_mesh()
	for p in PROPS:
		if quick:
			_sweep(p[0], p[1], true)
		else:
			_throw_sweep(p[0], p[1])
	cabin.free()
	quit()


# --------------------------------------------------------------------------
# 1. Les recouvrements, boites nues puis gonflees
# --------------------------------------------------------------------------

## cabin.gd le dit en toutes lettres : "Aucune boite ne doit en CHEVAUCHER une
## autre : un objet coince dans une intersection se fait ejecter violemment."
## C'est une regle tenue a la main, donc une regle qu'on peut enfreindre sans
## que rien ne le dise. On la verifie.
func _overlaps() -> void:
	print("\n=== RECOUVREMENTS ENTRE BOITES PLEINES ===")
	var raw := _pairs(Vector3.ZERO)
	print("  boites nues            : %d paire(s)" % raw.size())
	for r in raw:
		print("     %s" % r)
	for p in PROPS:
		var half: Vector3 = p[1]
		var got := _pairs(half)
		print("  gonflees pour %-8s : %d paire(s)" % [p[0], got.size()])
		for r in got:
			print("     %s" % r)


## Les paires de boites qui se recouvrent une fois gonflees de `half`.
func _pairs(half: Vector3) -> PackedStringArray:
	var out := PackedStringArray()
	for i in _solids.size():
		for j in range(i + 1, _solids.size()):
			var a_lo: Vector3 = _solids[i]["min"] - half
			var a_hi: Vector3 = _solids[i]["max"] + half
			var b_lo: Vector3 = _solids[j]["min"] - half
			var b_hi: Vector3 = _solids[j]["max"] + half
			var lo := a_lo.max(b_lo)
			var hi := a_hi.min(b_hi)
			var d := hi - lo
			if d.x <= 0.0 or d.y <= 0.0 or d.z <= 0.0:
				continue
			out.append("#%d x #%d   volume commun %.0f x %.0f x %.0f mm" % [
				i, j, d.x * 1000.0, d.y * 1000.0, d.z * 1000.0])
	return out


# --------------------------------------------------------------------------
# 2. La coque contre les boites
# --------------------------------------------------------------------------

## prop.gd fait deux choses de suite : _resolve() pousse l'objet HORS des
## boites, puis _contain() le rabat DEDANS la coque. Si une boite gonflee
## deborde de la coque gonflee, les deux se contredisent a chaque image et
## l'objet vibre entre les deux — c'est un blocage, et il est structurel.
func _hull_conflicts() -> void:
	print("\n=== BOITES QUI DEBORDENT DE LA COQUE ===")
	for p in PROPS:
		var half: Vector3 = p[1]
		var lo := _hull_min + half         # ou _contain() borne l'objet
		var hi := _hull_max - half
		var n := 0
		for i in _solids.size():
			var s_lo: Vector3 = _solids[i]["min"] - half
			var s_hi: Vector3 = _solids[i]["max"] + half
			# La boite gonflee mord-elle le domaine que la coque autorise ?
			var c_lo := s_lo.max(lo)
			var c_hi := s_hi.min(hi)
			var d := c_hi - c_lo
			if d.x <= 0.0 or d.y <= 0.0 or d.z <= 0.0:
				continue
			# Elle le mord forcement (c'est du mobilier). Ce qui compte, c'est
			# qu'elle ne le mord QUE d'un cote : une boite qui couvre une borne
			# de la coque sur toute son epaisseur y colle l'objet.
			for a in 3:
				if s_lo[a] <= lo[a] and s_hi[a] >= lo[a] and s_hi[a] < hi[a]:
					continue                # elle borde le bas, l'objet peut monter
			n += 1
		# Le cas dur, et le seul qui bloque vraiment : la boite recouvre la
		# borne de la coque, donc l'objet rabattu par _contain() atterrit
		# DEDANS et _resolve() l'en ressort aussitot.
		var stuck := PackedStringArray()
		for i in _solids.size():
			var s_lo: Vector3 = _solids[i]["min"] - half
			var s_hi: Vector3 = _solids[i]["max"] + half
			for a in 3:
				for bound in [lo[a], hi[a]]:
					if bound <= s_lo[a] or bound >= s_hi[a]:
						continue
					# La borne tombe DANS la boite gonflee : y a-t-il de la
					# place autour sur les deux autres axes ?
					var ok := true
					for b in 3:
						if b == a:
							continue
						if s_hi[b] <= lo[b] or s_lo[b] >= hi[b]:
							ok = false
					if ok:
						stuck.append("#%d : la borne %s=%.3f de la coque tombe dans la boite" % [
							i, "xyz"[a], bound])
		print("  %-8s : %d boite(s) contredisent la coque" % [p[0], stuck.size()])
		for s in stuck:
			print("     %s" % s)


# --------------------------------------------------------------------------
# 3. Les boites contre la TOLE VISIBLE
# --------------------------------------------------------------------------

## LE DEFAUT QUE LE JOUEUR VOIT.
##
## Les deux controles precedents comparent les boites entre elles. Aucun ne
## compare les boites AU MODELE — et c'est la que tout se joue : une boite qui
## ne chevauche aucune autre, parfaitement etanche, peut tres bien etre posee
## 9 cm derriere la tole qu'elle pretend representer. L'objet s'y arrete alors
## proprement, sans rien traverser du point de vue de la simulation, et le
## joueur le voit ENFONCE DANS LA PORTIERE.
##
## cabin.gd le sait, d'ailleurs, et l'ecrit dans _build_crawl : "solids place
## les portieres a 0,79, qui est la TOLE ; la garniture qu'on voit et qu'on
## longe est a 0,70". Neuf centimetres. Personne ne l'avait mesure du cote des
## objets.
##
## On pose donc un objet contre chaque face de chaque boite, la ou il
## s'arreterait, et on demande au maillage s'il est dedans.
func _box_vs_mesh() -> void:
	print("\n=== OU S'ARRETE UN OBJET, FACE PAR FACE ===")
	print("  (un objet pose contre la face est-il DANS la tole visible ?)")
	for p in PROPS:
		var label: String = p[0]
		var half: Vector3 = p[1]
		var bad := 0
		var total := 0
		var lines := PackedStringArray()
		for i in _solids.size():
			var lo: Vector3 = _solids[i]["min"]
			var hi: Vector3 = _solids[i]["max"]
			for a in 3:
				for side in [-1.0, 1.0]:
					var hits := 0
					var seen := 0
					var who := ""
					var deep := 0.0
					# Une grille sur la face, sans les bords (les aretes d'une
					# boite ne representent rien).
					for u in range(1, 5):
						for v in range(1, 5):
							var q := Vector3.ZERO
							q[a] = (hi[a] + half[a]) if side > 0.0 else (lo[a] - half[a])
							var b1 := (a + 1) % 3
							var b2 := (a + 2) % 3
							q[b1] = lerpf(lo[b1], hi[b1], float(u) / 5.0)
							q[b2] = lerpf(lo[b2], hi[b2], float(v) / 5.0)
							# Hors de la coque : cette face n'est pas atteignable.
							if q[a] < _hull_min[a] or q[a] > _hull_max[a]:
								continue
							seen += 1
							var name := _mesh.hits_box(q, half)
							if name == "":
								continue
							hits += 1
							who = name
							# De combien faut-il reculer pour en sortir ?
							var d := 0.0
							while d < 0.30:
								d += 0.005
								var qq := q
								qq[a] += side * d
								if _mesh.hits_box(qq, half) == "":
									break
							deep = maxf(deep, d)
					if seen == 0:
						continue
					total += 1
					if hits * 3 < seen:      # moins d'un tiers : un frottement de coin
						continue
					bad += 1
					if lines.size() < 14:
						lines.append("#%-2d face %s%s : %d/%d points DANS %s   (jusqu'a %.0f mm)" % [
							i, "-" if side < 0.0 else "+", "xyz"[a],
							hits, seen, who, deep * 1000.0])
		print("  %-8s : %d faces sur %d arretent l'objet DANS la tole" % [label, bad, total])
		for l in lines:
			print("     %s" % l)


# --------------------------------------------------------------------------
# 4. Le balayage de lancers : combien finissent coinces
# --------------------------------------------------------------------------

## Le meme eventail que `_leak_scan` du banc, mais on ne regarde pas la meme
## chose. Le banc demande "est-il sorti ?" ; ici on demande "ou s'est-il
## arrete ?" — et un objet arrete DANS la tole, ou pire, arrete EN L'AIR contre
## une paroi, est le defaut que le joueur rapporte.
##
## TROIS DEFAUTS, et il faut les trois : un objet peut etre enfonce sans etre
## immobile, immobile sans etre enfonce, et "colle en l'air" sans etre ni l'un
## ni l'autre au sens strict. C'est le troisieme que decrit "il se bloque dans
## les parois" — rien ne le porte, et pourtant il ne tombe plus.
##
## On balaie aussi PLUSIEURS POINTS DE DEPART et une inertie de freinage. Un
## lancer depuis le poing, moteur coupe, ne visite qu'une petite partie de
## l'habitacle : les coins rentrants ou deux boites se contredisent sont
## ailleurs, et c'est precisement la qu'on se coince.
## AVANT / APRES DANS LE MEME OUTIL, sur le meme balayage. Les deux algorithmes
## sont joues cote a cote : celui d'avant (les boites saisies dans cabin.gd,
## resolues l'une apres l'autre) et celui d'apres (la tole relevee, resolue
## contre l'union). Un chiffre de "apres" seul ne dirait pas s'il y avait un
## defaut ; les deux, si.
func _throw_sweep(label: String, half: Vector3) -> void:
	_sweep(label, half, false)
	if _shape != null:
		_sweep(label, half, true)


func _sweep(label: String, half: Vector3, use_shape: bool) -> void:
	print("\n=== BALAYAGE DE LANCERS : %s — %s ===" % [
		label, "APRES (tole relevee)" if use_shape else "AVANT (boites a la main)"])
	# Le poing, plus quelques places d'ou l'on jette vraiment : assise passager,
	# console, planche de bord, milieu de l'habitacle.
	var starts := [
		HOLD_POINT,
		Vector3(0.30, 0.60, 0.10),
		Vector3(0.0, 0.65, -0.24),
		Vector3(0.0, 1.00, -0.70),
		Vector3(0.0, 0.80, 0.30),
	]
	# Sans inertie, puis en plantant les freins (17 m/s^2, car.gd) et en virage.
	var drives := [Vector3.ZERO, Vector3(0.0, 0.0, 17.0), Vector3(8.0, 0.0, 0.0)]

	var tries := 0
	var deep_n := 0
	var jitter := 0
	var hung := 0
	var buried := 0
	var worst := 0.0
	var where := {}
	## Combien de blocages par inertie appliquee. Un defaut qui n'arrive QUE sous
	## un virage tenu quatre secondes n'est pas le meme defaut qu'un defaut qui
	## arrive moteur coupe.
	var by_drive := {}
	var samples := PackedStringArray()
	var deep_samples := PackedStringArray()

	for from in starts:
		for drive in drives:
			for yaw in range(-180, 180, 30):
				for pitch in [-60, -30, 0, 30, 60]:
					var a := deg_to_rad(float(yaw))
					var b := deg_to_rad(float(pitch))
					var dir := Vector3(sin(a) * cos(b), sin(b), -cos(a) * cos(b)).normalized()
					var r := _simulate(from, dir * THROW_SPEED, half, drive, use_shape)
					tries += 1
					var d: float = r["deep"]
					if d > 0.001:
						deep_n += 1
					if not r["settled"]:
						jitter += 1
					if r["hung"]:
						hung += 1
						if samples.size() < 10:
							samples.append(
								"depuis %s  lacet %4d tangage %3d  -> arrete en l'air a %s (vide dessous : %.0f mm)" % [
								str(from.snappedf(0.01)), yaw, pitch,
								str((r["pos"] as Vector3).snappedf(0.001)),
								float(r["gap"]) * 1000.0])
					# LE DEFAUT VISIBLE : il s'est arrete DANS une piece du modele.
					#
					# La boite est RETRECIE d'un millimetre et demi, et ce n'est
					# pas de la complaisance : un objet parfaitement pose TOUCHE
					# la tole sur laquelle il repose, et un test de separation
					# d'axes compte le contact comme une intersection. Sans cette
					# marge, "pose impeccablement sur la planche de bord" et
					# "enfonce de six centimetres dans la portiere" donnent la
					# meme reponse — ce qui rendrait la mesure inutile pile au
					# moment ou elle marche.
					var inside := _mesh.hits_box(r["pos"], half - Vector3(0.0015, 0.0015, 0.0015))
					if inside != "":
						buried += 1
						where[inside] = int(where.get(inside, 0)) + 1
						by_drive[drive] = int(by_drive.get(drive, 0)) + 1
						if deep_samples.size() < 12:
							var q: Vector3 = r["pos"]
							deep_samples.append(
								"dans %-22s a %s   inertie %s   stabilise=%s" % [
								inside, str(q.snappedf(0.001)), str(drive),
								r["settled"]])
					worst = maxf(worst, d)

	print("  %d lancers   (%d departs x %d inerties x 60 directions)" % [
		tries, starts.size(), drives.size()])
	print("  ENFONCE DANS UNE PAROI : %d   (%.1f %%)   enfoncement maxi %.1f mm" % [
		deep_n, 100.0 * float(deep_n) / float(tries), worst * 1000.0])
	print("  ARRETE EN L'AIR        : %d   (%.1f %%)" % [
		hung, 100.0 * float(hung) / float(tries)])
	print("  jamais stabilise       : %d   (%.1f %%)" % [
		jitter, 100.0 * float(jitter) / float(tries)])
	print("  ARRETE DANS LA TOLE    : %d   (%.1f %%)   <-- ce que le joueur voit" % [
		buried, 100.0 * float(buried) / float(tries)])
	var keys := where.keys()
	keys.sort_custom(func(p, q): return where[p] > where[q])
	for n in keys:
		print("     dans %-28s : %d fois" % [n, where[n]])
	for d in drives:
		print("     sous inertie %-18s : %d sur %d" % [
			str(d), int(by_drive.get(d, 0)), tries / drives.size()])
	for s in deep_samples:
		print("     %s" % s)
	for s in samples:
		print("     %s" % s)


## Idem, mais contre la tole relevee. On interroge LA GRILLE, pas le champ de
## hauteurs : le champ rend le dessus de la colonne, et sous la planche de bord
## ce dessus est la planche — un objet pose au pedalier passerait pour flottant.
## La grille, elle, connait les surplombs.
func _shape_gap(pos: Vector3, half: Vector3) -> float:
	var floor_y: float = _hull_min.y + half.y
	if pos.y - floor_y < 0.002:
		return 0.0
	if _shape.grounded_on(pos, half, 0.006):
		return 0.0
	return pos.y - floor_y


## Rien ne le porte : ni une boite sous ses pieds, ni le plancher de la coque.
## `gap` est la hauteur de vide sous lui. Un objet immobile avec du vide dessous
## est tenu par ses COTES — il s'est coince dans une paroi.
func _unsupported(pos: Vector3, half: Vector3) -> float:
	var floor_y: float = _hull_min.y + half.y
	if pos.y - floor_y < 0.002:
		return 0.0
	var best := pos.y - floor_y
	for s in _solids:
		var lo: Vector3 = s["min"] - half
		var hi: Vector3 = s["max"] + half
		# A l'aplomb, marge d'un millimetre : on cherche ce qui le porte, pas ce
		# qu'il frole.
		if pos.x <= lo.x + 0.001 or pos.x >= hi.x - 0.001: continue
		if pos.z <= lo.z + 0.001 or pos.z >= hi.z - 0.001: continue
		if hi.y > pos.y + 0.001:
			continue                        # la boite le depasse : elle ne le porte pas
		best = minf(best, pos.y - hi.y)
	return maxf(best, 0.0)


## UN SEUL LANCER, IMAGE PAR IMAGE.
##
## Quand un balayage designe un coupable et que le raisonnement ne le retrouve
## pas, c'est le raisonnement qui a tort. On suit donc une canette, celle qui
## finit dans le bas de caisse, et on regarde ce que la grille lui fait a chaque
## image plutot que de le deduire.
func _trace() -> void:
	var half: Vector3 = PROPS[1][1]
	var pos := Vector3(0.30, 0.60, 0.10)
	var vel := Vector3(0.0, 0.0, 0.0)
	var accel := Vector3(8.0, 0.0, 0.0)
	var dt := 1.0 / 60.0
	var grounded := false
	print("=== TRACE : canette poussee vers la portiere droite ===")
	for frame in 240:
		var drive := accel
		vel.y -= GRAVITY * dt
		if grounded:
			var tang := Vector3(vel.x, 0.0, vel.z)
			var stop := KINETIC_MU * GRAVITY * dt
			if tang.length() <= SLIDE_EPS and drive.length() <= STATIC_MU * GRAVITY:
				vel.x = 0.0
				vel.z = 0.0
				drive = Vector3.ZERO
			elif tang.length() <= stop:
				vel.x = 0.0
				vel.z = 0.0
			else:
				var d := tang / tang.length()
				vel.x -= d.x * stop
				vel.z -= d.z * stop
		vel += drive * dt
		var steps := clampi(int(ceil(vel.length() * dt / 0.01)), 1, 16)
		var h := dt / float(steps)
		for i in steps:
			pos += vel * h
			var r := _resolve(pos, vel, half, true)
			pos = r[0]
			vel = r[1]
			grounded = r[2]
		if frame % 20 == 0 or frame > 232:
			var pushed: Array = _shape.push_out(pos, half, _hull_min, _hull_max)
			print("  f%3d  pos %s  vel %s  sol=%s  grille touche=%s vers %s  tole='%s'" % [
				frame, str(pos.snappedf(0.001)), str(vel.snappedf(0.01)), grounded,
				pushed[2], str(pushed[1]),
				_mesh.hits_box(pos, half - Vector3(0.0015, 0.0015, 0.0015))])


## L'integration de prop.gd, a l'identique, sans la voiture (frame_accel nulle :
## on cherche un defaut de GEOMETRIE, pas d'inertie).
func _simulate(from: Vector3, v0: Vector3, half: Vector3,
		accel := Vector3.ZERO, use_shape := false) -> Dictionary:
	var pos := from.clamp(_hull_min + half, _hull_max - half)
	var vel := v0
	var grounded := false
	var dt := 1.0 / 60.0
	var last := pos
	var moved_late := 0.0

	for frame in 240:                       # 4 s
		var drive := accel
		vel.y -= GRAVITY * dt
		if grounded:
			var tang := Vector3(vel.x, 0.0, vel.z)
			var stop := KINETIC_MU * GRAVITY * dt
			if tang.length() <= SLIDE_EPS and drive.length() <= STATIC_MU * GRAVITY:
				vel.x = 0.0
				vel.z = 0.0
				drive = Vector3.ZERO        # il colle
			elif tang.length() <= stop:
				vel.x = 0.0
				vel.z = 0.0
			else:
				var d := tang / tang.length()
				vel.x -= d.x * stop
				vel.z -= d.z * stop
		vel += drive * dt

		# Chaque algorithme est joue avec SON sous-pas : 2 cm pour les boites,
		# 1 cm (une demi-case) pour la grille. Comparer deux resolutions sous un
		# pas qui n'est celui d'aucune des deux ne mesurerait ni l'une ni l'autre.
		var steps := clampi(int(ceil(vel.length() * dt / (0.01 if use_shape else 0.02))),
			1, 16 if use_shape else 8)
		var h := dt / float(steps)
		for i in steps:
			pos += vel * h
			var r := _resolve(pos, vel, half, use_shape)
			pos = r[0]
			vel = r[1]
			grounded = r[2]

		# Sur la derniere demi-seconde, un objet pose ne doit plus bouger. S'il
		# bouge encore, c'est qu'il vibre entre deux boites.
		if frame > 210:
			moved_late = maxf(moved_late, pos.distance_to(last))
		last = pos

	# En mode "apres", "enfonce dans une boite declaree" n'a plus de sens — il
	# n'y a plus de boite declaree. La mesure qui compte est la meme dans les
	# deux cas et elle est prise par le maillage : "arrete DANS la tole".
	var gap := _shape_gap(pos, half) if use_shape else _unsupported(pos, half)
	return {
		"pos": pos,
		"deep": 0.0 if use_shape else _penetration(pos, half),
		"settled": moved_late < 0.001,
		# Immobile ET rien dessous : il est tenu par ses cotes.
		"hung": moved_late < 0.001 and vel.length() < 0.05 and gap > 0.005,
		"gap": gap,
	}


## _resolve() de prop.gd : chaque boite l'une apres l'autre, sortie par l'axe de
## moindre penetration, puis la coque.
func _resolve(pos: Vector3, vel: Vector3, half: Vector3, use_shape := false) -> Array:
	var grounded := false
	if use_shape:
		return _resolve_shape(pos, vel, half)
	for s in _solids:
		var lo: Vector3 = s["min"] - half
		var hi: Vector3 = s["max"] + half
		if pos.x <= lo.x or pos.x >= hi.x: continue
		if pos.y <= lo.y or pos.y >= hi.y: continue
		if pos.z <= lo.z or pos.z >= hi.z: continue

		var out_x := hi.x - pos.x if hi.x - pos.x < pos.x - lo.x else lo.x - pos.x
		var out_y := hi.y - pos.y if hi.y - pos.y < pos.y - lo.y else lo.y - pos.y
		var out_z := hi.z - pos.z if hi.z - pos.z < pos.z - lo.z else lo.z - pos.z

		if absf(out_y) <= absf(out_x) and absf(out_y) <= absf(out_z):
			pos.y += out_y
			if out_y > 0.0:
				grounded = true
			vel.y = -vel.y * BOUNCE if absf(vel.y) > 0.5 else 0.0
		elif absf(out_x) <= absf(out_z):
			pos.x += out_x
			vel.x = -vel.x * BOUNCE if absf(vel.x) > 0.5 else 0.0
		else:
			pos.z += out_z
			vel.z = -vel.z * BOUNCE if absf(vel.z) > 0.5 else 0.0

	# _contain()
	var lo_h: Vector3 = _hull_min + half
	var hi_h: Vector3 = _hull_max - half
	if pos.y < lo_h.y:
		pos.y = lo_h.y
		grounded = true
		vel.y = -vel.y * BOUNCE if absf(vel.y) > 0.5 else 0.0
	elif pos.y > hi_h.y:
		pos.y = hi_h.y
		vel.y = -vel.y * BOUNCE if absf(vel.y) > 0.5 else 0.0
	if pos.x < lo_h.x or pos.x > hi_h.x:
		pos.x = clampf(pos.x, lo_h.x, hi_h.x)
		vel.x = -vel.x * BOUNCE if absf(vel.x) > 0.5 else 0.0
	if pos.z < lo_h.z or pos.z > hi_h.z:
		pos.z = clampf(pos.z, lo_h.z, hi_h.z)
		vel.z = -vel.z * BOUNCE if absf(vel.z) > 0.5 else 0.0

	return [pos, vel, grounded]


## L'algorithme d'APRES, repris a l'identique de prop.gd : la tole relevee, puis
## le vitrage, puis la coque — chacun resolu contre l'UNION.
func _resolve_shape(pos: Vector3, vel: Vector3, half: Vector3) -> Array:
	var grounded := false
	for pass_i in 2:
		var r: Array = _shape.push_out(pos, half, _hull_min, _hull_max)
		if not r[2]:
			break
		pos = r[0]
		var res := _bounce(pos, vel, r[1], grounded)
		vel = res[0]
		grounded = res[1]

	# Le vitrage, meme resolution contre l'union.
	var need := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var touched := false
	var b_lo := pos - half
	var b_hi := pos + half
	for s in _shell:
		var lo: Vector3 = s["min"]
		var hi: Vector3 = s["max"]
		var d := Vector3(minf(hi.x, b_hi.x) - maxf(lo.x, b_lo.x),
			minf(hi.y, b_hi.y) - maxf(lo.y, b_lo.y),
			minf(hi.z, b_hi.z) - maxf(lo.z, b_lo.z))
		if d.x <= 0.0 or d.y <= 0.0 or d.z <= 0.0:
			continue
		touched = true
		need[0] = maxf(need[0], hi.x - b_lo.x)
		need[1] = maxf(need[1], b_hi.x - lo.x)
		need[2] = maxf(need[2], hi.y - b_lo.y)
		need[3] = maxf(need[3], b_hi.y - lo.y)
		need[4] = maxf(need[4], hi.z - b_lo.z)
		need[5] = maxf(need[5], b_hi.z - lo.z)
	if touched:
		var best := 0
		for a in range(1, 6):
			if need[a] < need[best]:
				best = a
		const DIRS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN,
			Vector3.BACK, Vector3.FORWARD]
		var n: Vector3 = DIRS[best]
		pos += n * need[best]
		var res2 := _bounce(pos, vel, n, grounded)
		vel = res2[0]
		grounded = res2[1]

	# La coque.
	var lo_h: Vector3 = _hull_min + half
	var hi_h: Vector3 = _hull_max - half
	if pos.y < lo_h.y:
		pos.y = lo_h.y
		grounded = true
		vel.y = -vel.y * BOUNCE if absf(vel.y) > 0.5 else 0.0
	elif pos.y > hi_h.y:
		pos.y = hi_h.y
		vel.y = -vel.y * BOUNCE if absf(vel.y) > 0.5 else 0.0
	if pos.x < lo_h.x or pos.x > hi_h.x:
		pos.x = clampf(pos.x, lo_h.x, hi_h.x)
		vel.x = -vel.x * BOUNCE if absf(vel.x) > 0.5 else 0.0
	if pos.z < lo_h.z or pos.z > hi_h.z:
		pos.z = clampf(pos.z, lo_h.z, hi_h.z)
		vel.z = -vel.z * BOUNCE if absf(vel.z) > 0.5 else 0.0

	# Et on se pose sur la tole, une seule fois, comme prop.gd.
	if grounded:
		pos.y = _shape.settle(pos, half)

	return [pos, vel, grounded]


func _bounce(_pos: Vector3, vel: Vector3, n: Vector3, grounded: bool) -> Array:
	if n.y > 0.5:
		grounded = true
	for a in 3:
		if absf(n[a]) < 0.5:
			continue
		vel[a] = -vel[a] * BOUNCE if absf(vel[a]) > 0.5 else 0.0
	return [vel, grounded]


## De combien l'objet est enfonce dans la boite ou il est le PLUS enfonce.
## Zero s'il n'est dans aucune : il est pose, pas coince.
func _penetration(pos: Vector3, half: Vector3) -> float:
	var worst := 0.0
	for s in _solids:
		var lo: Vector3 = s["min"] - half
		var hi: Vector3 = s["max"] + half
		if pos.x <= lo.x or pos.x >= hi.x: continue
		if pos.y <= lo.y or pos.y >= hi.y: continue
		if pos.z <= lo.z or pos.z >= hi.z: continue
		var d := minf(minf(minf(hi.x - pos.x, pos.x - lo.x), minf(hi.y - pos.y, pos.y - lo.y)),
			minf(hi.z - pos.z, pos.z - lo.z))
		worst = maxf(worst, d)
	return worst
