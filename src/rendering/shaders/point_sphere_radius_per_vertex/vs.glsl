uniform mat4 u_model_view_matrix;

in vec4 a_position;
in float a_radius;

flat out float v_radius;

void main() {
	gl_Position = u_model_view_matrix * a_position;
  v_radius = a_radius;
}
