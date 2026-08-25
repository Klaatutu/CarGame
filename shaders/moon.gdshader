shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
//
// La lune : un quad billboard pose loin devant, dessine en additif par-dessus
// le brouillard.
//
// Le brouillard est desactive (fog_disabled) : a 260 m, une densite de 0.030
// laisse passer exp(-7.8), soit 0.04% du disque — la lune serait purement et
// simplement absente. Le voile est donc peint ici, par le halo, ce qui a
// l'avantage de se regler independamment de la portee de vue.
//
// depth_draw_never, mais test de profondeur actif : la lune passe derriere le
// montant du pare-brise et derriere les poteaux, sans pour autant polluer le
// depth buffer des transparences dessinees apres elle.
//

// Le bleu est volontairement appuye : l'environnement desature de 30% en
// sortie (adjustment_saturation = 0.70), un blanc lunaire y devient gris.
uniform vec3 tint : source_color = vec3(0.58, 0.70, 1.0);
// Rayon du disque, en fraction de la demi-largeur du quad. Le reste du quad
// n'existe que pour loger le halo.
uniform float disc_radius : hint_range(0.05, 0.5) = 0.28;
// Au-dela de 1.0 le disque depasse le seuil HDR de l'environnement (0.95) et
// declenche le glow : c'est lui qui donne l'aureole, pas le halo seul.
//
// 1.6 et pas 2.4 : plus haut, le tonemap filmique ecrase tout le disque sur du
// blanc et les mers comme l'assombrissement du limbe disparaissent — on obtient
// un rond de papier decoupe. La lune doit rester brillante, pas cramee.
uniform float disc_energy : hint_range(0.0, 8.0) = 1.9;
uniform float halo_energy : hint_range(0.0, 2.0) = 0.55;
uniform float halo_falloff : hint_range(1.0, 12.0) = 3.5;
// Phase : 0 = pleine lune, 0.9 = fin croissant. Un leger gibbeux se lit mieux
// qu'un rond parfait, qu'on prend vite pour un lampadaire.
uniform float phase : hint_range(0.0, 0.9) = 0.20;
// Largeur du terminateur, en fraction du rayon. Sur un croissant net la lune
// ressemble a un logo ; le vrai terminateur est flou, c'est un limbe rasant.
uniform float terminator : hint_range(0.01, 0.5) = 0.14;
// Lumiere cendree : le cote non eclaire n'est jamais tout a fait noir. Mais
// au-dela de 0.03 il redevient un disque gris visible, et la phase se perd.
uniform float earthshine : hint_range(0.0, 0.5) = 0.025;
// Les mers lunaires. Sans elles, le disque fait pastille de peinture.
uniform float maria : hint_range(0.0, 1.0) = 0.28;


void vertex() {
	// Billboard conservant l'echelle du noeud (recette standard de Godot) : la
	// lune ne doit ni tourner avec la voiture, ni maigrir vue de trois quarts.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}


float blob(vec2 p, vec2 c, float r) {
	return 1.0 - smoothstep(0.0, r, distance(p, c));
}


void fragment() {
	vec2 p = UV - vec2(0.5);          // -0.5 .. 0.5 sur le quad
	vec2 q = p / disc_radius;         // 1.0 = bord du disque
	float d = length(q);

	// Bord adouci sur la largeur reelle d'un pixel : le tramage plein ecran
	// transforme le moindre escalier en scintillement.
	float aa = max(fwidth(d), 0.0015) * 1.5;
	float disc = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);

	// Assombrissement vers le limbe : une sphere, pas un jeton.
	float limb = mix(1.0, 0.62, clamp(d * d, 0.0, 1.0));

	// Phase : on retranche un second disque, decale sur le cote.
	float lit = smoothstep(-terminator, terminator,
			length(q - vec2(-phase * 2.0, 0.0)) - 1.0);
	lit = max(lit, earthshine);

	float dark = maria * (blob(q, vec2(-0.24, 0.28), 0.48)
			+ 0.7 * blob(q, vec2(0.30, -0.12), 0.40)
			+ 0.5 * blob(q, vec2(-0.06, -0.44), 0.32));

	// Halo : mesure depuis le centre du QUAD, pas du disque, pour deborder
	// largement au-dela du limbe.
	float halo = halo_energy * pow(clamp(1.0 - length(p) * 2.0, 0.0, 1.0), halo_falloff);

	ALBEDO = tint * (disc * disc_energy * limb * lit * (1.0 - dark) + halo);
	ALPHA = 1.0;
}
