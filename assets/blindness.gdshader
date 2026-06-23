shader_type canvas_item;
// Horror tunnel-vision vignette. Edges go dark (hard to see); a small centre
// stays clearer. `tint` shifts toward red when the killer is near.

uniform float intensity : hint_range(0.0, 1.0) = 0.95;   // overall darkness
uniform float clear_radius : hint_range(0.0, 1.0) = 0.16; // size of clearer centre
uniform vec3 tint = vec3(0.0, 0.0, 0.0);

void fragment() {
	vec2 c = UV - vec2(0.5);
	c.x *= 1.7;                       // aspect compensation
	float d = length(c);
	float a = smoothstep(clear_radius, clear_radius + 0.5, d) * intensity;
	COLOR = vec4(tint, a);
}
