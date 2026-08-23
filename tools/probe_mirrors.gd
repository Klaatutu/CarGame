extends SceneTree
##
## Outil : geometrie des retroviseurs dans les deux .glb.
##   godot --headless --path . --script res://tools/probe_mirrors.gd
##

const FILES := {
	"INTERIEUR": "res://assets/models/civic_interior.glb",
	"EXTERIEUR": "res://assets/models/civic_exterior.glb",
}


func _initialize() -> void:
	for label in FILES:
		print("--- %s ---" % label)
		var node := (load(FILES[label]) as PackedScene).instantiate()
		_walk(node, Transform3D())
	quit()


func _walk(n: Node, xform: Transform3D) -> void:
	var t := xform
	if n is Node3D:
		t = xform * (n as Node3D).transform
	var name := String(n.name)
	if "irror" in name or "Mirror" in name or "Retro" in name:
		var line := "  %-26s" % name
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var box: AABB = t * mi.get_aabb()
			line += " centre=%s taille=%s" % [
				(box.position + box.size * 0.5).snappedf(0.001),
				box.size.snappedf(0.001)]
			line += "  basisZ=%s" % t.basis.z.normalized().snappedf(0.01)
		else:
			line += " (pivot) pos=%s" % t.origin.snappedf(0.001)
		print(line)
	for c in n.get_children():
		_walk(c, t)
