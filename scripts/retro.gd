extends RefCounted
##
## Fabrique de materiaux : tout le jeu passe par le shader de tramage.
##
## Le shader n'ajoute que le dithering ; l'eclairage reste celui de Godot,
## par pixel et avec ombres. Donc rien de special a faire cote geometrie.
##

const SHADER := preload("res://shaders/retro.gdshader")


## Materiau opaque de couleur unie.
static func mat(color: Color, rough := 0.9, metal := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("modulate", color)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	return m
