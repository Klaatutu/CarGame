shader_type canvas_item;
//
// Tramage ordonne plein ecran, facon PS1.
//
// POURQUOI ICI ET PAS DANS LE MATERIAU : appliquer le motif a l'ALBEDO ne se
// voit pas. Il est ensuite multiplie par un eclairage faible puis passe dans le
// tonemapping, et il ne reste qu'un niveau d'ecart sur 255. La PS1 tramait
// l'image FINALE, juste avant de la quantifier en 15 bits. C'est ce qu'on fait.
//
// Le motif de Bayer est ajoute juste avant la quantification : la ou une simple
// troncature ferait des bandes franches, le tramage les casse en damier.
//

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// Nombre de niveaux par canal. 32 = 15 bits, la vraie profondeur de la PS1.
// Plus bas = bandes plus larges et tramage plus gros.
uniform float color_steps : hint_range(4.0, 128.0) = 32.0;
// Taille d'une case du motif, en pixels ecran.
uniform float pixel_size : hint_range(1.0, 8.0) = 2.0;
uniform float strength : hint_range(0.0, 2.0) = 1.0;

const float bayer[16] = float[16] (
	 0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
	 3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
	15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0
);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;

	ivec2 cell = ivec2(FRAGCOORD.xy / pixel_size);
	float threshold = bayer[(cell.x % 4) * 4 + (cell.y % 4)] - 0.5;

	c += threshold * strength / color_steps;
	c = floor(c * color_steps + 0.5) / color_steps;

	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
