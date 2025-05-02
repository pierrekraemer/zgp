uniform mat4 projection_matrix;
uniform vec4 ambiant_color;
uniform vec3 light_position;
uniform float point_size;
uniform vec4 color;

in vec2 spriteCoord;
in vec3 sphereCenter;

out vec4 frag_out;

void main()
{
  vec3 billboard_frag_pos = sphereCenter + vec3(spriteCoord, 0.0) * point_size;
  vec3 ray_direction = normalize(billboard_frag_pos);
  float TD = -dot(ray_direction, sphereCenter);
  float c = dot(sphereCenter, sphereCenter) - point_size * point_size;
  float arg = TD * TD - c;
  if (arg < 0.0)
    discard;
  float t = -c / (TD - sqrt(arg));
  vec3 frag_position_eye = ray_direction * t ;
  vec4 pos = projection_matrix * vec4(frag_position_eye, 1.0);
  gl_FragDepth = (pos.z / pos.w + 1.0) / 2.0;
  vec3 N = normalize(frag_position_eye - sphereCenter);
  vec3 L = normalize (light_position - frag_position_eye);
  float lambertTerm = dot(N, L);
  vec4 result = vec4(color.rgb * lambertTerm, color.a);
  result += vec4(ambiant_color.rgb, 0.0);
  frag_out = result.rgba;
}
