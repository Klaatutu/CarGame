extends SceneTree
##
## Outil : decrit la hierarchie de webley.glb (pivots des pieces mobiles).
##   godot --headless --path . --script res://tools/inspect_webley.gd
##

const GLB := "res://assets/models/webley.glb"


func _initialize() -> void:
	var packed: PackedScene = load(GLB)
	if packed == null:
		print("ECHEC : ", GLB, " introuvable")
		quit()
		return
	var node := packed.instantiate()
	_dump(node, Transform3D(), 0)
	quit()


func _dump(n: Node, parent_tf: Transform3D, depth: int) -> void:
	var tf := parent_tf
	var info := ""
	if n is Node3D:
		tf = parent_tf * (n as Node3D).transform
		info = "pos=%s" % [(n as Node3D).position]
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var aabb := mi.mesh.get_aabb()
			info += "  tris=%d  aabb=%s..%s" % [_tris(mi.mesh), aabb.position, aabb.end]
		else:
			info += "  monde=%s" % [tf.origin]
	print("%s%s  %s" % ["  ".repeat(depth), n.name, info])
	for c in n.get_children():
		_dump(c, tf, depth + 1)


func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		t += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
