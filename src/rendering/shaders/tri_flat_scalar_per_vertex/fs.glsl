precision highp float;
precision highp int;

uniform vec4 u_ambiant_color;
uniform vec3 u_light_position;

in vec3 v_position;
in float v_value;
in vec4 v_color;

out vec4 f_color;

void main() {
  vec3 N = normalize(cross(dFdx(v_position), dFdy(v_position)));
  vec3 L = normalize(u_light_position - v_position);
  float lambert_term = dot(N, L);
  vec4 result = vec4(v_color.rgb * lambert_term, 1.0);
  result += vec4(u_ambiant_color.rgb, 0.0);
  f_color = result;
}
