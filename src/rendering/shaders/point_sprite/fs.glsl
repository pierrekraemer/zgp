uniform mat4 u_projection_matrix;
uniform float u_point_size;
uniform vec4 u_color;
uniform vec4 u_ambiant_color;
uniform vec3 u_light_position;

in vec3 sphere_center;
in vec2 sprite_coord;

out vec4 frag_out;

void main()
{
  vec3 billboard_frag_pos = sphere_center + vec3(sprite_coord, 0.0) * u_point_size;
  vec3 ray_direction = normalize(billboard_frag_pos);
  float TD = -dot(ray_direction, sphere_center);
  float c = dot(sphere_center, sphere_center) - u_point_size * u_point_size;
  float arg = TD * TD - c;
  if (arg < 0.0)
    discard;
  float t = -c / (TD - sqrt(arg));
  vec3 frag_position_eye = ray_direction * t ;
  vec4 pos = u_projection_matrix * vec4(frag_position_eye, 1.0);
  gl_FragDepth = (pos.z / pos.w + 1.0) / 2.0;
  vec3 N = normalize(frag_position_eye - sphere_center);
  vec3 L = normalize (u_light_position - frag_position_eye);
  float lambert_term = dot(N, L);
  vec4 result = vec4(u_color.rgb * lambert_term, u_color.a);
  result += vec4(u_ambiant_color.rgb, 0.0);
  frag_out = result.rgba;
}
