uniform mat4 u_model_view_matrix;
uniform mat4 u_projection_matrix;
uniform float u_min_value;
uniform float u_max_value;

in vec4 a_position;
in float a_scalar;

out vec3 v_position;
out float v_value;
out vec4 v_color;

float scale_and_clamp_to_0_1(float x, float min, float max)
{
  float v = (x - min) / (max - min);
  return clamp(v, 0.0, 1.0);
}

vec4 color_map_blue_white_red(float x)
{
  float x2 = 2.0 * x;
  switch (int(floor(max(0.0,x2+1.0))))
  {
    case 0: return vec4(0.0, 0.0, 1.0, 1.0);
    case 1: return vec4(x2, x2 , 1.0, 1.0);
    case 2: return vec4(1.0, 2.0 - x2, 2.0 - x2, 1.0);
  }
  return vec4(1.0, 0.0, 0.0, 1.0);
}

void main() {
  vec4 pos = u_model_view_matrix * a_position;
  gl_Position = u_projection_matrix * pos;
  v_position = pos.xyz;
  v_value = scale_and_clamp_to_0_1(a_scalar, u_min_value, u_max_value);
  v_color = color_map_blue_white_red(v_value);
}
