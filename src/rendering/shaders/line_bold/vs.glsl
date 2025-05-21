uniform mat4 u_model_view_matrix;
uniform mat4 u_projection_matrix;

in vec4 a_position;

void main() {
	// gl_Position = a_position;
  gl_Position = u_projection_matrix * u_model_view_matrix * a_position;
}
