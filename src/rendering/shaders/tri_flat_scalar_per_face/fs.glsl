precision highp float;
precision highp int;

uniform vec4 u_ambiant_color;
uniform vec3 u_light_position;
uniform float u_min_value;
uniform float u_max_value;
uniform usamplerBuffer u_face_index_buffer;
uniform samplerBuffer u_face_scalar_buffer;

in vec3 v_position;

out vec4 f_color;

float scale_and_clamp_to_0_1(float x, float min, float max)
{
  float v = (x - min) / (max - min);
  return clamp(v, 0.0, 1.0);
}

vec3 color_map_blue_white_red(float x)
{
  float x2 = 2.0 * x;
  switch (int(floor(max(0.0,x2+1.0))))
  {
    case 0: return vec3(0.0, 0.0, 1.0);
    case 1: return vec3(x2, x2 , 1.0);
    case 2: return vec3(1.0, 2.0 - x2, 2.0 - x2);
  }
  return vec3(1.0, 0.0, 0.0);
}

void main() {    
    vec3 N = normalize(cross(dFdx(v_position), dFdy(v_position)));
    vec3 L = normalize(u_light_position - v_position);
    float lambert_term = dot(N, L);
    int face_index = int(texelFetch(u_face_index_buffer, int(gl_PrimitiveID)).r);
    float scalar = texelFetch(u_face_scalar_buffer, face_index).r;
    scalar = scale_and_clamp_to_0_1(scalar, u_min_value, u_max_value);
    vec3 color = color_map_blue_white_red(scalar);
    vec4 result = vec4(color.rgb * lambert_term, 1.0);
    result += vec4(u_ambiant_color.rgb, 0.0);
    f_color = result;
    if (!gl_FrontFacing) {
        f_color *= 0.5;
    }
}
