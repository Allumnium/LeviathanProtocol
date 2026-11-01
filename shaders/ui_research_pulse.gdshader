shader_type canvas_item;

uniform float white_mix : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 surface = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(surface.rgb, vec3(1.0), white_mix), surface.a);
}
