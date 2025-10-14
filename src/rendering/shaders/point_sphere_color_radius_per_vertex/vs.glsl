in vec4 a_position;
in vec4 a_color;
in float a_radius;

flat out vec4 v_color;
flat out float v_radius;

void main() {
	gl_Position = a_position;
  v_color = a_color;
  v_radius = a_radius;
}
