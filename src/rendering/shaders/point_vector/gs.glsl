layout (points) in;
layout (triangle_strip, max_vertices = 14) out;

uniform mat4 u_projection_matrix;
uniform float u_cone_radius;

in vec4 v_vector_end[];

flat out vec3 view_v0;
flat out vec3 view_v1;
smooth out vec3 view_pos;

void main() {
  view_v0 = gl_in[0].gl_Position.xyz / gl_in[0].gl_Position.w;
  view_v1 = v_vector_end[0].xyz / v_vector_end[0].w;

  vec3 coneDir = normalize(view_v1 - view_v0);
  vec3 basisX = vec3(1., 0., 0.);
  basisX -= dot(basisX, coneDir) * coneDir;
  if (abs(basisX.x) < 0.1) {
    basisX = vec3(0., 1., 0.);
    basisX -= dot(basisX, coneDir) * coneDir;
  }
  basisX = normalize(basisX);
  vec3 basisY = normalize(cross(coneDir, basisX));

  vec4 dx = vec4(basisX * u_cone_radius, 0.);
  vec4 dy = vec4(basisY * u_cone_radius, 0.);

  vec4 p1 = gl_in[0].gl_Position - dx - dy;
  vec4 p2 = gl_in[0].gl_Position + dx - dy;
  vec4 p3 = gl_in[0].gl_Position - dx + dy;
  vec4 p4 = gl_in[0].gl_Position + dx + dy;
  vec4 p5 = v_vector_end[0] - dx - dy;
  vec4 p6 = v_vector_end[0] + dx - dy;
  vec4 p7 = v_vector_end[0] - dx + dy;
  vec4 p8 = v_vector_end[0] + dx + dy;
  
  vec4 v0_proj = u_projection_matrix * gl_in[0].gl_Position;
  vec4 v1_proj = u_projection_matrix * v_vector_end[0];

  vec4 dx_proj = u_projection_matrix * dx;
  vec4 dy_proj = u_projection_matrix * dy;

  vec4 p1_proj = v0_proj - dx_proj - dy_proj;
  vec4 p2_proj = v0_proj + dx_proj - dy_proj;
  vec4 p3_proj = v0_proj - dx_proj + dy_proj;
  vec4 p4_proj = v0_proj + dx_proj + dy_proj;
  vec4 p5_proj = v1_proj - dx_proj - dy_proj;
  vec4 p6_proj = v1_proj + dx_proj - dy_proj;
  vec4 p7_proj = v1_proj - dx_proj + dy_proj;
  vec4 p8_proj = v1_proj + dx_proj + dy_proj;
  
  view_pos = p7.xyz; gl_Position = p7_proj; EmitVertex();
  view_pos = p8.xyz; gl_Position = p8_proj; EmitVertex();
  view_pos = p5.xyz; gl_Position = p5_proj; EmitVertex();
  view_pos = p6.xyz; gl_Position = p6_proj; EmitVertex();
  view_pos = p2.xyz; gl_Position = p2_proj; EmitVertex();
  view_pos = p8.xyz; gl_Position = p8_proj; EmitVertex();
  view_pos = p4.xyz; gl_Position = p4_proj; EmitVertex();
  view_pos = p7.xyz; gl_Position = p7_proj; EmitVertex();
  view_pos = p3.xyz; gl_Position = p3_proj; EmitVertex();
  view_pos = p5.xyz; gl_Position = p5_proj; EmitVertex();
  view_pos = p1.xyz; gl_Position = p1_proj; EmitVertex();
  view_pos = p2.xyz; gl_Position = p2_proj; EmitVertex();
  view_pos = p3.xyz; gl_Position = p3_proj; EmitVertex();
  view_pos = p4.xyz; gl_Position = p4_proj; EmitVertex();
}
