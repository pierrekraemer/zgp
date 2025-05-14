uniform mat4 u_model_view_matrix;
uniform mat4 u_projection_matrix;

in vec4 a_position;
in vec4 a_color;

out vec3 v_position;
out vec4 v_color;

void main() {
  vec4 pos = u_model_view_matrix * a_position;
  gl_Position = u_projection_matrix * pos;
  v_position = pos.xyz;
  v_color = a_color;
}
