layout (points) in;
layout (triangle_strip, max_vertices=4) out;

uniform mat4 u_model_view_matrix;
uniform mat4 u_projection_matrix;

flat in float v_radius[];

out vec3 sphere_center;
out float sphere_radius;
out vec2 sprite_coord;

void corner(vec4 center, float x, float y) {
  sprite_coord = vec2(x, y);
  vec4 pos = center + vec4(v_radius[0] * x, v_radius[0] * y, 0.0, 0.0);
  gl_Position = u_projection_matrix * pos;
  EmitVertex();
}

void main() {
  vec4 pos_center = u_model_view_matrix * gl_in[0].gl_Position;
  sphere_center = pos_center.xyz;
  sphere_radius = v_radius[0];
  corner(pos_center, -1.4,  1.4);
  corner(pos_center, -1.4, -1.4);
  corner(pos_center,  1.4,  1.4);
  corner(pos_center,  1.4, -1.4);
  EndPrimitive();
}
