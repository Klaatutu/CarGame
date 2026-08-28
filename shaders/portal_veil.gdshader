shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
//
// Le voile du portail : un quad en travers de la voie, dessine en additif.
// Des vagues lentes qui remontent, un bord qui meurt en douceur, une teinte
// lunaire froide — dans le cauchemar teinte rouge, c'est la seule chose
// froide de l'image, et c'est pour ca qu'on roule vers elle.
//
// fog_disabled : comme la lune. Le brouillard du cauchemar (0.045) eteindrait
// le voile a 130 m ; il doit au contraire se voir DE loin, c'est une sortie.
// L'energie depasse le seuil HDR de l'environnement (0.95) : le glow fait
// l'aureole, le meme mecanisme que le disque lunaire.
//

uniform vec3 tint : source_color = vec3(0.55, 0.72, 1.0);
uniform float energy : hint_range(0.0, 4.0) = 2.2;
// Vitesse de remontee des vagues, et leur nombre sur la hauteur.
uniform float wave_speed : hint_range(0.0, 3.0) = 0.55;
uniform float waves : hint_range(1.0, 12.0) = 5.0;

void fragment() {
	// Bords doux sur les quatre cotes : le voile n'a pas de cadre.
	float bx = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	float by = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.80, UV.y);

	// Deux trains de vagues desaccordes qui REMONTENT : de l'eau a l'envers.
	float w1 = sin((UV.y + TIME * wave_speed) * waves * 6.2831 + UV.x * 3.0);
	float w2 = sin((UV.y + TIME * wave_speed * 0.63) * waves * 3.9 - UV.x * 5.0);
	float shimmer = 0.55 + 0.30 * w1 + 0.15 * w2;

	// Plus dense au centre qu'aux bords : un rideau, pas une plaque.
	float body = mix(0.35, 1.0, smoothstep(0.9, 0.25, abs(UV.x - 0.5) * 2.0));

	// En unshaded c'est l'ALBEDO qui sort a l'ecran (EMISSION y est lettre
	// morte — releve a la sonde : le voile etait un rectangle noir). Le
	// blend_add additionne cette couleur, et au-dela du seuil HDR (0.95)
	// c'est elle que le glow ramasse — le montage exact de la lune.
	ALBEDO = tint * energy * shimmer * body * bx * by;
}
