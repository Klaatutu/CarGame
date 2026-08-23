extends SceneTree
##
## Outil : ou sont les pare-soleil, avant et apres le decalage de cabin.gd.
##   godot --headless --path . --script res://tools/probe_visors.gd
##

const GLB := "res://assets/models/civic_interior.glb"
## Le decalage applique au chargement par cabin.gd._build_interior().
const LIFT := 0.075
const WANTED := ["Visor", "Headliner", "Roof", "Header"]


func _initialize() -> void:
	var node := (load(GLB) as PackedScene).instantiate()
	_walk(node, Transform3D())
	quit()


func _walk(n: Node, xform: Transform3D) -> void:
	var t := xform
	if n is Node3D:
		t = xform * (n as Node3D).transform
	var name := String(n.name)
	for w in WANTED:
		if w in name:
			var line := "  %-24s" % name
			if n is MeshInstance3D:
				var box: AABB = t * (n as MeshInstance3D).get_aabb()
				line += " y=%.3f..%.3f  z=%.3f..%.3f  x=%.3f..%.3f" % [
					box.position.y, box.end.y,
					box.position.z, box.end.z,
					box.position.x, box.end.x]
				if "Visor" in name:
					line += "   -> apres +%.3f : y=%.3f..%.3f" % [
						LIFT, box.position.y + LIFT, box.end.y + LIFT]
			else:
				line += " (pivot) pos=%s" % t.origin.snappedf(0.001)
			print(line)
			break
	for c in n.get_children():
		_walk(c, t)
