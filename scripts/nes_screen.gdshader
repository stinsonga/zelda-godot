shader_type canvas_item;
// Palette lookup for NesScreen. Textures hold 2-bit pattern values as grey
// levels (value * 85). Each draw's vertex color carries the palette: red is
// the first palette index / 31, green 1 for a solid fill of that index.
uniform vec4 colors[32];
varying vec4 info;

void vertex() {
	info = COLOR;
}

void fragment() {
	int base = int(round(info.r * 31.0));
	if (info.g > 0.5) {
		COLOR = colors[base];
	} else {
		int value = int(round(texture(TEXTURE, UV).r * 3.0));
		if (value == 0) discard;
		COLOR = colors[base + value];
	}
}
