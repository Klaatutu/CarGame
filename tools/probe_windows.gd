extends SceneTree
##
## Outil : vitres, manivelles et huisseries des deux .glb.
##   godot --headless --path . --script res://tools/probe_windows.gd
##

const FILES := {
	"INTERIEUR": "res://assets/models/civic_interior.glb",
	"EXTERIEUR": "res://assets/models/civic_exterior.glb",
}
const WANTED := ["Glass", "Window", "Vitre", "Crank", "Winder", "Quarter",
	"DoorCard", "Belt", "Frame"]


func _initialize() -> void:
	for label in FILES:
		print("--- %s ---" % label)
		_walk((load(FILES[label]) as PackedScene).instantiate(), Transform3D())
	quit()


func _walk(n: Node, xform: Transform3D) -> void:
	var t := xform
	if n is Node3D:
		t = xform * (n as Node3D).transform
	var name := String(n.name)
	for w in WANTED:
		if w.to_lower() in name.to_lower():
			var line := "  %-26s" % name
			if n is MeshInstance3D:
				var box: AABB = t * (n as MeshInstance3D).get_aabb()
				line += " x=%.3f..%.3f y=%.3f..%.3f z=%.3f..%.3f" % [
					box.position.x, box.end.x, box.position.y, box.end.y,
					box.position.z, box.end.z]
			else:
				line += " (pivot) pos=%s" % t.origin.snappedf(0.001)
			print(line)
			break
	for c in n.get_children():
		_walk(c, t)
