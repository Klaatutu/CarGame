extends Node3D
##
## Gerbe d'impact : ce qui saute d'un point quand une balle y porte. Quelques
## eclats — des MeshInstance3D simules a la main, comme tout le reste du
## monde, pas un moteur de particules — qui partent le long de la normale,
## que la gravite rattrape, et qui s'effacent en retombant. Le noeud se
## libere seul quand le dernier eclat s'est eteint : on le pose, on l'oublie.
##
## Tout se passe en espace MONDE (top_level, accroche a la scene et pas a la
## source) : les eclats quittent leur source avec sa vitesse (`inherit`) et
## n'en dependent plus. Le sang d'un corps accroche a une caisse lancee part
## AVEC la caisse — puis la caisse s'en va, et les gouttes retombent ou elles
## sont, sur la chaussee qui ne bouge pas.
##
## Ne d'un coup de feu, il vit une demi-seconde : c'est l'eclair de bouche
## (FLASH_TIME du revolver, trois images de lumiere) qui l'eclaire.

const Retro := preload("res://scripts/retro.gd")

## Fraction de la vie d'un eclat a partir de laquelle il retrecit.
const FADE_FROM := 0.55

var _specks: Array = []


## Fait partir une gerbe et rend le noeud (null hors de l'arbre). `host` ne
## sert qu'a atteindre la scene courante : la gerbe doit rester quand la
## source part, meurt ou s'eteint.
static func spawn(host: Node, pos: Vector3, dir: Vector3, color: Color,
		count: int, speed: float, size: float, life: float,
		inherit := Vector3.ZERO) -> Node3D:
	var tree := host.get_tree()
	if tree == null:
		return null
	var n: Node3D = load("res://scripts/impact_burst.gd").new()
	n.top_level = true
	var root: Node = tree.current_scene if tree.current_scene != null else host
	root.add_child(n)
	n.global_transform = Transform3D()
	n._build(pos, dir, color, count, speed, size, life, inherit)
	return n


func _build(pos: Vector3, dir: Vector3, color: Color, count: int,
		speed: float, size: float, life: float, inherit: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var mat := Retro.mat(color, 0.85)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	for i in count:
		var m := MeshInstance3D.new()
		m.mesh = box
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = pos + Vector3(rng.randf_range(-0.02, 0.02),
			rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02))
		m.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU,
			rng.randf() * TAU)
		add_child(m)
		# Un cone lache autour de la normale : la part dirigee dit d'ou la
		# balle est venue, la part dispersee fait la gerbe.
		var scatter := Vector3(rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) \
			* (speed * 0.55)
		_specks.append({
			"m": m,
			"vel": d * speed * rng.randf_range(0.35, 1.0) + scatter + inherit,
			"t": 0.0,
			"life": life * rng.randf_range(0.65, 1.2),
			"s": rng.randf_range(0.7, 1.4),
			"flat": false,
		})


func _process(delta: float) -> void:
	var alive := 0
	for sp in _specks:
		var m: MeshInstance3D = sp["m"]
		sp["t"] += delta
		var u: float = sp["t"] / maxf(sp["life"], 0.01)
		if u >= 1.0:
			m.visible = false
			continue
		alive += 1
		if not sp["flat"]:
			var v: Vector3 = sp["vel"] + Vector3.DOWN * 9.81 * delta
			var p: Vector3 = m.position + v * delta
			if p.y < 0.012 and v.y < 0.0:
				# Au sol : l'eclat s'ecrase et y reste le temps qui lui reste.
				p.y = 0.012
				v = Vector3.ZERO
				sp["flat"] = true
			sp["vel"] = v
			m.position = p
		var fade := 1.0 - maxf(0.0, (u - FADE_FROM) / (1.0 - FADE_FROM))
		var s: float = sp["s"] * maxf(fade, 0.05)
		m.scale = Vector3(s, s * (0.3 if sp["flat"] else 1.0), s)
	if alive == 0:
		queue_free()


## Ce que les bancs d'essai relisent.
func speck_count() -> int:
	return _specks.size()
