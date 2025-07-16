uniform float u_vector_scale;

in vec3 a_position;
in vec3 a_vector;

out vec3 v_vector_end;

void main()
{
  v_vector_end = a_position + u_vector_scale * a_vector;
  gl_Position = vec4(a_position, 1.0);
}
