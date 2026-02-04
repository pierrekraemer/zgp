layout (points) in;
layout (triangle_strip, max_vertices=4) out;

uniform mat4 u_projection_matrix;

flat in float v_value[];
flat in vec4 v_color[];
flat in float v_radius[];

flat out vec3 sphere_center;
flat out float sphere_value;
flat out vec4 sphere_color;
flat out float sphere_radius;
smooth out vec3 proxy_pos;

void main() {
  sphere_center = gl_in[0].gl_Position.xyz / gl_in[0].gl_Position.w;
  sphere_value = v_value[0];
  sphere_color = v_color[0];
  sphere_radius = v_radius[0];

  vec3 basisX = vec3(1., 0., 0.);
  vec3 basisY = vec3(0., 1., 0.);

  vec4 dx = vec4(basisX * sphere_radius, 0.);
  vec4 dy = vec4(basisY * sphere_radius, 0.);

  vec4 p1 = gl_in[0].gl_Position - dx - dy;
  vec4 p2 = gl_in[0].gl_Position + dx - dy;
  vec4 p3 = gl_in[0].gl_Position - dx + dy;
  vec4 p4 = gl_in[0].gl_Position + dx + dy;

  vec4 center_proj = u_projection_matrix * gl_in[0].gl_Position;

  vec4 dx_proj = u_projection_matrix * dx;
  vec4 dy_proj = u_projection_matrix * dy;

  vec4 p1_proj = center_proj - dx_proj - dy_proj;
  vec4 p2_proj = center_proj + dx_proj - dy_proj;
  vec4 p3_proj = center_proj - dx_proj + dy_proj;
  vec4 p4_proj = center_proj + dx_proj + dy_proj;

  proxy_pos = p1.xyz; gl_Position = p1_proj; EmitVertex();
  proxy_pos = p2.xyz; gl_Position = p2_proj; EmitVertex();
  proxy_pos = p3.xyz; gl_Position = p3_proj; EmitVertex();
  proxy_pos = p4.xyz; gl_Position = p4_proj; EmitVertex();
  EndPrimitive();
}
