layout (points) in;
layout (triangle_strip, max_vertices=4) out;

uniform mat4 u_model_view_matrix;
uniform mat4 u_projection_matrix;
uniform float u_point_size;

flat in float v_value[];
flat in vec4 v_color[];

out vec3 sphere_center;
out float sphere_value;
out vec4 sphere_color;
out vec2 sprite_coord;

void corner(vec4 center, float x, float y) {
  sprite_coord = vec2(x, y);
  vec4 pos = center + vec4(u_point_size * x, u_point_size * y, 0.0, 0.0);
  gl_Position = u_projection_matrix * pos;
  EmitVertex();
}

void main() {
  vec4 pos_center = u_model_view_matrix * gl_in[0].gl_Position;
  sphere_center = pos_center.xyz;
  sphere_value = v_value[0];
  sphere_color = v_color[0];
  corner(pos_center, -1.4,  1.4);
  corner(pos_center, -1.4, -1.4);
  corner(pos_center,  1.4,  1.4);
  corner(pos_center,  1.4, -1.4);
  EndPrimitive();
}
