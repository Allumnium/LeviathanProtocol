shader_type canvas_item;
render_mode unshaded;

uniform vec2 view_slope = vec2(0.0);
uniform float parallax_scale = 0.015;
uniform int flash_count = 0;
uniform vec4 flash_lights[8];
uniform int projectile_light_count = 0;
uniform vec4 projectile_lights[16];
uniform vec3 projectile_light_colors[16];
global uniform vec4 cursor_light;

varying vec4 vertex_tint;
varying vec2 surface_position;
varying vec2 surface_x;
varying vec2 surface_y;

void vertex() {
	vertex_tint = COLOR;
	mat4 surface_transform = CANVAS_MATRIX * MODEL_MATRIX;
	surface_position = (surface_transform * vec4(VERTEX, 0.0, 1.0)).xy;
	surface_x = normalize(surface_transform[0].xy);
	surface_y = normalize(surface_transform[1].xy);
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * vertex_tint;
	// Unmapped artwork, text, lines and backgrounds keep their existing appearance.
	if (textureSize(NORMAL_TEXTURE, 0) == textureSize(TEXTURE, 0)
			&& textureSize(NORMAL_TEXTURE, 0).x > 1) {
		float height = texture(NORMAL_TEXTURE, UV).a;
		// The current orthographic camera has zero view slope: no sprite displacement.
		vec2 uv = clamp(UV + view_slope * (height - 0.5) * parallax_scale,
			vec2(0.0), vec2(1.0));
		vec4 albedo = texture(TEXTURE, uv) * vertex_tint;
		vec3 local_normal = texture(NORMAL_TEXTURE, uv).rgb * 2.0 - 1.0;
		vec3 normal = normalize(vec3(surface_x * local_normal.x - surface_y * local_normal.y,
			local_normal.z));
		vec4 specular_occlusion = texture(SPECULAR_SHININESS_TEXTURE, uv);
		vec3 light_direction = normalize(vec3(-0.45, -0.55, 0.85));
		float lambert = max(dot(normal, light_direction), 0.0);
		vec3 illumination = vec3(0.30, 0.33, 0.375) + vec3(0.78, 0.75, 0.70) * lambert;
		vec3 halfway = normalize(light_direction + vec3(0.0, 0.0, 1.0));
		vec3 shine = specular_occlusion.rgb * pow(max(dot(normal, halfway), 0.0), 24.0) * 0.28;
		if (cursor_light.w > 0.0) {
			vec2 delta = (cursor_light.xy - SCREEN_UV) / SCREEN_PIXEL_SIZE;
			float radius = cursor_light.z / SCREEN_PIXEL_SIZE.x;
			float falloff = pow(max(1.0 - length(delta) / radius, 0.0), 2.0);
			vec3 direction = normalize(vec3(delta, radius * 0.4));
			illumination += vec3(0.85, 0.92, 1.0) * max(dot(normal, direction), 0.0)
				* falloff * cursor_light.w;
		}
		for (int i = 0; i < flash_count; i++) {
			vec2 delta = flash_lights[i].xy - surface_position;
			float radius = flash_lights[i].z;
			float falloff = pow(max(1.0 - length(delta) / radius, 0.0), 2.0);
			vec3 direction = normalize(vec3(delta, radius * 0.3));
			illumination += vec3(1.0, 0.58, 0.25) * max(dot(normal, direction), 0.0)
				* falloff * flash_lights[i].w;
		}
		for (int i = 0; i < projectile_light_count; i++) {
			vec2 delta = projectile_lights[i].xy - surface_position;
			float radius = projectile_lights[i].z;
			float falloff = pow(max(1.0 - length(delta) / radius, 0.0), 2.0);
			vec3 direction = normalize(vec3(delta, radius * 0.3));
			illumination += projectile_light_colors[i] * max(dot(normal, direction), 0.0)
				* falloff * projectile_lights[i].w;
		}
		COLOR = vec4((albedo.rgb * illumination + shine * vertex_tint.rgb)
			* specular_occlusion.a, albedo.a);
	}
}
