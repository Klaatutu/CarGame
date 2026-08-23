extends SceneTree
##
## Outil : positions en espace voiture des points d'ancrage du poste de
## conduite (volant, pedales, siege). Sert a caler l'assise du conducteur.
##   godot --headless --path . --script res://tools/probe_anchors.gd
##

const GLB := "res://assets/models/civic_interior.glb"
const WANTED := ["STR_Root", "STR_Rim", "PED_Clutch", "PED_Brake",
	"PED_Throttle", "CON_ShiftKnob", "SEAT_Driver_Back", "SEAT_Driver_Cushion",
	"SEAT_Driver_Headrest", "BODY_Roof", "BODY_Floor"]


func _initialize() -> void:
	var node := (load(GLB) as PackedScene).instantiate()
	for name in WANTED:
		var n := node.find_child(name, true, false)
		if n == null:
			print("  %-22s ABSENT" % name)
			continue
		var t := _world(n)
		var line := "  %-22s pos=%s" % [name, t.origin.snappedf(0.001)]
		if n is MeshInstance3D:
			var box: AABB = t * (n as MeshInstance3D).get_aabb()
			line += "  z=%.3f..%.3f  y=%.3f..%.3f" % [
				box.position.z, box.end.z, box.position.y, box.end.y]
		print(line)
	quit()


func _world(n: Node) -> Transform3D:
	var t := Transform3D()
	var cur := n
	while cur != null and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
