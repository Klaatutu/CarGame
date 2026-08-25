extends SceneTree
##
## Outil : bouches d'aeration de l'habitacle, en ESPACE VOITURE.
##   godot --headless --path . --script res://tools/probe_vents.gd
##
## C'est par la que le mille-pattes entre (centipede.gd), et cabin.gd releve ces
## bouches sur le maillage plutot que de les saisir a la main. Cet outil imprime
## ce qu'il y trouve : le nom, la boite englobante, et l'AXE LE PLUS MINCE de
## cette boite — celui du flux d'air, donc celui par lequel une bestiole sort.
##
## Une grille est un objet PLAT : sa boite a un cote tres inferieur aux deux
## autres, et c'est la normale de la bouche. Le dire ainsi evite d'avoir a
## deviner une direction par bouche, et ca reste juste si le modele bouge.
##

const FILES := {
	"INTERIEUR": "res://assets/models/civic_interior.glb",
	"EXTERIEUR": "res://assets/models/civic_exterior.glb",
}
const WANTED := ["Vent", "Defrost", "Grille", "Duct", "Louvre"]


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
			var line := "  %-30s" % name
			if n is MeshInstance3D:
				var box: AABB = t * (n as MeshInstance3D).get_aabb()
				line += "c=%s  taille=%s  mince=%s" % [
					box.get_center().snappedf(0.001), box.size.snappedf(0.001),
					_thin_axis(box)]
			else:
				line += "(pivot) pos=%s" % t.origin.snappedf(0.001)
			print(line)
			break
	for c in n.get_children():
		_walk(c, t)


## Axe le plus mince de la boite : "x", "y" ou "z". C'est l'axe du flux.
func _thin_axis(box: AABB) -> String:
	var s := box.size
	if s.x <= s.y and s.x <= s.z:
		return "x"
	return "y" if s.y <= s.z else "z"
