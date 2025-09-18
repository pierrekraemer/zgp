uniform mat4 u_model_view_matrix;
uniform mat4 u_projection_matrix;

in vec4 a_position;

out vec3 v_position;

void main() {
  vec4 pos = u_model_view_matrix * a_position;
  gl_Position = u_projection_matrix * pos;
  v_position = pos.xyz;
}
