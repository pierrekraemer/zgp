out vec2 v_tex_coord;

void main()
{
  v_tex_coord = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
	gl_Position = vec4(v_tex_coord * 2.0 - 1.0, 0.0, 1.0);
}
