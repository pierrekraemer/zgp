layout (lines) in;
layout (triangle_strip, max_vertices=6) out;

uniform mat4 u_model_view_matrix;
uniform mat4 u_projection_matrix;
uniform vec2 u_line_width;

void main() {
  vec4 A = u_model_view_matrix * gl_in[0].gl_Position;
	vec4 B = u_model_view_matrix * gl_in[1].gl_Position;

  float nearZ = 1.0;
  if (u_projection_matrix[2][2] !=  1.0)
    nearZ = - u_projection_matrix[3][2] / (u_projection_matrix[2][2] - 1.0);

  if (A.z < nearZ || B.z < nearZ) {
    if (A.z >= nearZ)
      A = B + (A - B) * (nearZ - B.z) / (A.z - B.z);
    if (B.z >= nearZ)
      B = A + (B - A) * (nearZ - A.z) / (B.z - A.z);

    A = u_projection_matrix * A;
    B = u_projection_matrix * B;
    A = A / A.w;
    B = B / B.w;

    vec2 U2 = normalize(vec2(u_line_width[1], u_line_width[0]) * (B.xy - A.xy));
    vec2 LWCorr = u_line_width * max(abs(U2.x), abs(U2.y));

    vec4 U = vec4(0.5 * LWCorr * U2, 0.0, 0.0);
    vec4 V = vec4(LWCorr * vec2(U2[1], -U2[0]), 0.0, 0.0);
    gl_Position = A - V;
    EmitVertex();
    gl_Position = B - V;
    EmitVertex();
    gl_Position = A - U;
    EmitVertex();
    gl_Position = B + U;
    EmitVertex();
    gl_Position = A + V;
    EmitVertex();
    gl_Position = B + V;
    EmitVertex();
    EndPrimitive();
  }
}
