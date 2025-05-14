uniform mat4 u_model_view_matrix;
uniform mat4 u_projection_matrix;

in vec4 a_position;
in vec4 a_color;

out vec4 v_color;

void main() {
  gl_Position = u_projection_matrix * u_model_view_matrix * a_position;
  v_color = a_color;
}
