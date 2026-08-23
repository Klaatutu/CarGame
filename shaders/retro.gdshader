shader_type spatial;
//
// Materiau de base : une couleur unie, plus rugosite et metallicite.
//
// C'est tout ce qui reste du shader PS1 d'origine : le vertex snapping, le
// mapping affine des UV, l'eclairage par sommet et l'effet de corruption ont
// ete retires. L'eclairage est celui de Godot, par pixel et avec ombres.
//
// Le tramage n'est PAS ici : il est en post-traitement plein ecran, dans
// dither_post.gdshader. Applique a l'ALBEDO il etait invisible (voir le
// commentaire en tete de ce fichier).
//

uniform vec4 modulate : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// Sert a la surbrillance des objets attrapables. Noir par defaut : aucun effet
// sur les materiaux existants.
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	ALBEDO = modulate.rgb * COLOR.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission.rgb;
}
