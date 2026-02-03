uniform mat4 u_model_view_matrix;

in vec4 a_position;

void main() {
  gl_Position = u_model_view_matrix * a_position;
}
