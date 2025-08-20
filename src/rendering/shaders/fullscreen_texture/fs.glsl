uniform sampler2D u_texture_unit;

in vec2 v_tex_coord;

out vec4 f_color;

void main()
{
  f_color = texture(u_texture_unit, v_tex_coord);
}
