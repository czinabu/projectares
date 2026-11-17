shader_type spatial;
// The column of smoke over a fight. Faces the camera, ignores the world fog
// (it is the storm, not something lost in it) and fades out within a few
// metres of the lens so standing in the fight is not standing inside a wall
// of cards. Farther cards stay, which is the column you read across the field.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D soft_tex : hint_default_white, filter_linear;
uniform float clear_near = 14.0;
uniform float clear_far = 36.0;

varying vec4 color;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	color = COLOR;
}

void fragment() {
	float dist = length(VERTEX);
	float cam = smoothstep(clear_near, clear_far, dist);
	ALBEDO = color.rgb;
	ALPHA = color.a * texture(soft_tex, UV).a * cam;
}
