shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
//
// LE REFLET DE L'HABITACLE DANS LE PARE-BRISE.
//
// Allumer le plafonnier la nuit se paie. L'habitacle, eclaire, se reflete dans
// la vitre et vient se poser SUR la route. Le melange est ADDITIF, donc il ne
// cache rien : il ECRASE LE CONTRASTE. Les noirs de la route remontent, les
// silhouettes dans le brouillard s'effacent, et on voit moins loin. C'est ce
// que fait un voile lumineux reel, et c'est la contrepartie qu'on cherchait —
// pas une penalite ajoutee par-dessus, la consequence optique de la lampe.
//
// C'EST UN VRAI MIROIR, pas un degrade peint. L'image vient d'un SubViewport
// rendu par une camera posee a l'OEIL REFLECHI sur le plan du pare-brise, comme
// les retroviseurs (mirror.gd) — voir windshield_glare.gd. On reflete donc la
// planche de bord telle qu'elle est, avec la console, les aerateurs, le
// retroviseur, et ce qu'on a pose dessus : un paquet laisse sur la casquette se
// voit dans la vitre. Et l'image BOUGE avec la tete, ce qu'aucune texture collee
// ne saurait faire.
//
// Ce fichier ne fait plus que trois choses, et chacune est une propriete du
// VERRE, pas de ce qu'il reflechit :
//
//   - FRESNEL. Le verre renvoie 4 % de face et beaucoup plus en rasant. Le
//     pare-brise etant couche de 59 degres, on le regarde justement en rasant :
//     c'est de la que vient la force du reflet, et c'est pour ca qu'il est plus
//     marque en bas de la vitre qu'en haut. Le degrade ne se peint pas, il tombe
//     de la formule.
//   - LE VOILE. Une vitre n'est pas un miroir propre : l'epaisseur du verre et
//     la poussiere ETALENT une part de ce qu'elle reflechit. C'est ce halo,
//     et non l'image nette, qui lave les noirs de la route.
//   - LES TRACES D'ESSUIE-GLACE. Elles restent accrochees a la VITRE pendant que
//     le reflet, lui, glisse dessous quand on bouge la tete. Les deux ne se
//     deplacent pas ensemble, et c'est exactement ce qu'on voit dans une voiture.
//

// `repeat_disable` n'est pas un detail : le halo va chercher des echantillons
// AUTOUR de chaque point, et pres du bord ils sortent de l'image. En repetition
// — le defaut de Godot — ils reviennent par le cote oppose, et le pare-brise se
// met a refleter son bord gauche sur son bord droit.
uniform sampler2D reflection : hint_default_black, filter_linear, repeat_disable;

// Reflectivite du verre EN INCIDENCE NORMALE. 4 %, c'est la valeur du verre, pas
// un reglage.
uniform float pane_f0 : hint_range(0.0, 0.2) = 0.043;

// LE VOILE : l'image reflechie etalee au point de n'etre plus qu'une nappe.
//
// C'EST UN FLOU, PAS DES COPIES, et la nuance a coute une version. La premiere
// prenait quatre echantillons ecartes de 11 % de la vitre : sur une canette
// posee sur la planche de bord, ca ne faisait pas un halo, ca faisait CINQ
// CANETTES — l'originale et ses quatre fantomes, chacun a 14 % de l'original,
// largement de quoi les compter. Un flou demande assez de points, assez
// rapproches, et assez FAIBLES chacun pour qu'aucun ne se reconnaisse : ici
// douze, en deux anneaux, dont le plus lourd pese 8 % du total.
//
// `blur` est le rayon de l'anneau interne, en fraction de la HAUTEUR de la
// vitre ; l'externe est au double. Le quad etant deux fois et demie plus large
// que haut, le rayon est corrige de cet aspect au moment de l'echantillonnage —
// sans quoi le halo serait une ellipse couchee, trois fois plus etalee en
// travers qu'en hauteur.
uniform float veil : hint_range(0.0, 3.0) = 0.55;
uniform float blur : hint_range(0.0, 0.3) = 0.055;

// Deux anneaux de six, le second decale d'un demi-pas : douze directions
// distinctes, aucune alignee avec une autre.
const vec2 HALO[12] = {
	vec2(1.000, 0.000), vec2(0.500, 0.866), vec2(-0.500, 0.866),
	vec2(-1.000, 0.000), vec2(-0.500, -0.866), vec2(0.500, -0.866),
	vec2(1.732, 1.000), vec2(0.000, 2.000), vec2(-1.732, 1.000),
	vec2(-1.732, -1.000), vec2(0.000, -2.000), vec2(1.732, -1.000)
};
// L'anneau interne porte la moitie du halo, l'externe un peu moins d'un tiers,
// le point central le reste.
const float HALO_W[12] = {
	0.0833, 0.0833, 0.0833, 0.0833, 0.0833, 0.0833,
	0.0500, 0.0500, 0.0500, 0.0500, 0.0500, 0.0500
};
const float HALO_MID = 0.2;

// LE VERRE N'EST PAS PROPRE. Ce qu'il reflechit bave le long des arcs
// d'essuie-glace, et c'est ca qui gene vraiment — un reflet net, l'oeil le
// contourne ; un reflet etale, non. Le pivot est celui du balai conducteur, en
// bas a gauche, sous la vitre, en metres depuis le centre du quad.
uniform float smear_gain : hint_range(0.0, 2.0) = 0.45;
uniform vec2 smear_pivot = vec2(-0.34, -0.42);
uniform float smear_freq : hint_range(4.0, 120.0) = 38.0;

// LE SEUL NOMBRE ARBITRAIRE DU FICHIER, et c'est le reglage de jouabilite :
// monte-le pour un reflet plus genant, descends-le pour une lampe qu'on peut se
// permettre. Le Fresnel donne la FORME du reflet, celui-ci sa presence.
//
// C'est windshield_glare.gd qui FAIT FOI : il le pose a chaque construction,
// depuis son @export. La valeur ci-dessous n'est la que pour que le shader
// rende la meme chose si on l'ouvre seul dans l'editeur — les deux doivent
// rester d'accord.
uniform float strength : hint_range(0.0, 20.0) = 2.8;
// 0 plafonnier eteint, 1 allume. Pilote par windshield_glare.gd. L'image
// s'eteint deja d'elle-meme avec la lampe — c'est l'habitacle qu'elle
// reflechit ; ce facteur ne sert qu'a ne rien laisser trainer et a couper le
// rendu du SubViewport quand il n'y a plus rien a refleter.
uniform float energy : hint_range(0.0, 1.0) = 0.0;

// Demi-cotes du quad et largeur de l'extinction sur son pourtour. Le frit noir
// et le joint mangent deja 4 cm tout autour ; ce fondu garantit qu'aucun bord
// franc ne puisse trahir le quad, quelle que soit sa taille.
uniform vec2 pane_half = vec2(0.67, 0.255);
uniform float edge_fade : hint_range(0.0, 0.3) = 0.07;

varying vec2 v_pane;     // ou l'on est sur la vitre, en metres


void vertex() {
	v_pane = VERTEX.xy;
}


// Traces d'essuie-glace : deux frequences incommensurables, pour des arcs qui
// ne se repetent pas d'un bout a l'autre de la vitre.
float streaks(float a) {
	return 0.5 + 0.5 * (0.62 * sin(a * smear_freq)
			+ 0.38 * sin(a * smear_freq * 2.37 + 1.7));
}


void fragment() {
	// Un miroir echange la gauche et la droite. La camera virtuelle, elle, rend
	// la scene telle quelle : c'est au placage de retourner l'image.
	vec2 uv = vec2(1.0 - UV.x, UV.y);

	vec3 sharp = texture(reflection, uv).rgb;

	// Le rayon est corrige de l'aspect du quad : `blur` compte en hauteur de
	// vitre, et la vitre est bien plus large que haute.
	vec2 rad = blur * vec2(pane_half.y / pane_half.x, 1.0);
	vec3 haze = sharp * HALO_MID;
	for (int i = 0; i < 12; i++) {
		haze += HALO_W[i] * texture(reflection, uv + HALO[i] * rad).rgb;
	}

	// Schlick, en espace vue : NORMAL est la normale du quad, VIEW pointe vers
	// l'oeil. Aucune matrice a passer, et ca suit la tete tout seul.
	float fres = pane_f0 + (1.0 - pane_f0)
			* pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);

	// La salissure module l'image ET son halo : une vitre sale ne brille que la
	// ou il y a quelque chose a refleter.
	vec3 refl = (sharp + haze * veil) * fres
			* (1.0 + smear_gain * streaks(distance(v_pane, smear_pivot)));

	vec2 q = abs(v_pane);
	float edge = smoothstep(pane_half.x, pane_half.x - edge_fade, q.x)
			* smoothstep(pane_half.y, pane_half.y - edge_fade, q.y);

	ALBEDO = refl * strength * energy * edge;
	ALPHA = 1.0;
}
