uniform mat4 u_model_view_matrix;
uniform float u_vector_scale;

in vec3 a_position;
in vec3 a_vector;

out vec4 v_vector_end;

void main()
{
  vec3 tip = a_position + u_vector_scale * a_vector;
  v_vector_end = u_model_view_matrix * vec4(tip, 1.0);
  gl_Position = u_model_view_matrix * vec4(a_position, 1.0);
}
