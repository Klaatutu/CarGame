extends SceneTree
##
## Outil : decrit le contenu de civic_interior.glb.
##   godot --headless --path . --script res://tools/inspect_glb.gd
##
## Les transforms sont accumulees a la main : hors de l'arbre,
## global_transform ne renvoie rien.
##

const GLB := "res://assets/models/civic_interior.glb"
## Familles dont on veut le detail (volant, console, pedales).
const DETAIL := ["SEAT", "DASH", "STR"]


func _initialize() -> void:
	var packed: PackedScene = load(GLB)
	if packed == null:
		print("ECHEC : ", GLB, " introuvable")
		quit()
		return

	var node := packed.instantiate()

	print("--- pivots (Node3D sans mesh) ---")
	for c in node.get_children():
		if c is Node3D and not (c is MeshInstance3D):
			var n3 := c as Node3D
			print("  %s  pos=%s  rot=%s  enfants=%d" % [
				n3.name, n3.position, n3.rotation_degrees, n3.get_child_count()])
			for g in n3.get_children():
				print("      %s" % g.name)

	print("\n--- detail par famille ---")
	for fam in DETAIL:
		print("  [%s]" % fam)
		_detail(node, Transform3D(), fam)

	quit()


func _detail(n: Node, xform: Transform3D, fam: String) -> void:
	var t := xform
	if n is Node3D:
		t = xform * (n as Node3D).transform
	if n is MeshInstance3D and String(n.name).begins_with(fam + "_"):
		var mi := n as MeshInstance3D
		var box: AABB = t * mi.get_aabb()
		print("    %-22s centre=%s  taille=%s" % [
			mi.name,
			(box.position + box.size * 0.5).snappedf(0.001),
			box.size.snappedf(0.001)])
	for c in n.get_children():
		_detail(c, t, fam)
