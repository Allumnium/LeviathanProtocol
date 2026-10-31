shader_type canvas_item;
render_mode unshaded;
uniform vec4 glow_color : source_color = vec4(1.0);
void fragment() {
	float source = texture(TEXTURE, UV).a;
	float halo = 0.0;
	for (int ring = 1; ring <= 3; ring++) {
		for (int i = 0; i < 16; i++) {
			float angle = float(i) * 6.2831853 / 16.0;
			vec2 offset = vec2(cos(angle), sin(angle)) * TEXTURE_PIXEL_SIZE * float(ring) * 5.0;
			halo = max(halo, texture(TEXTURE, UV + offset).a * (1.0 - float(ring) * 0.23));
		}
	}
	COLOR = vec4(glow_color.rgb, halo * (1.0 - source) * glow_color.a);
}
