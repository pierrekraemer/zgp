layout (points) in;
layout (line_strip, max_vertices = 2) out;

uniform mat4 u_projection_matrix;
uniform mat4 u_model_view_matrix;
// uniform vec2 u_vector_width;

in vec3 v_vector_end[];

void main()
{
  vec4 A = u_projection_matrix * u_model_view_matrix * gl_in[0].gl_Position;
  vec4 B = u_projection_matrix * u_model_view_matrix * vec4(v_vector_end[0], 1.0);
  gl_Position = A;
  EmitVertex();
  gl_Position = B;
  EmitVertex();
  EndPrimitive();

  // vec4 A = u_model_view_matrix * gl_in[0].gl_Position;
  // vec4 B = u_model_view_matrix * vec4(v_vector_end[0], 1.0);
  // float nearZ = 1.0;
  // if (u_projection_matrix[2][2] != 1.0)
  //   nearZ = -u_projection_matrix[3][2] / (u_projection_matrix[2][2] - 1.0);
  // if (A.z < nearZ || B.z < nearZ) {
  //   if (A.z >= nearZ)
  //     A = B + (A - B) * (nearZ - B.z) / (A.z - B.z);
  //   if (B.z >= nearZ)
  //     B = A + (B - A) * (nearZ - A.z) / (B.z - A.z);
    
  //   vec3 AB = B.xyz / B.w - A.xyz / A.w;
  //   // vec3 Nl = normalize(cross(AB, vec3(0.0, 0.0, 1.0)));
  //   // vec3 Nm = normalize(cross(Nl, AB));

  //   A = u_projection_matrix * A;
  //   B = u_projection_matrix * B;
  //   A = A / A.w;
  //   B = B / B.w;
  //   vec2 U2 = normalize(vec2(u_vector_width[1], u_vector_width[0]) * (B.xy - A.xy));
  //   vec2 LWCorr = u_vector_width * max(abs(U2.x), abs(U2.y));
  //   vec3 U = vec3(0.5 * LWCorr * U2, 0.0);
  //   vec3 V = vec3(LWCorr * vec2(U2[1], -U2[0]), 0.0);

  //   // N = Nl;
  //   gl_Position = vec4(A.xyz - V, 1.0);
  //   EmitVertex();
  //   // N = Nl;
  //   gl_Position = vec4(B.xyz - V, 1.0);
  //   EmitVertex();
  //   // N = Nm;
  //   gl_Position = vec4(A.xyz - U, 1.0);
  //   EmitVertex();
  //   // N = Nm;
  //   gl_Position = vec4(B.xyz + U, 1.0);
  //   EmitVertex();
  //   // N = -Nl;
  //   gl_Position = vec4(A.xyz + V, 1.0);
  //   EmitVertex();
  //   // N = -Nl;
  //   gl_Position = vec4(B.xyz + V, 1.0);
  //   EmitVertex();
  //   EndPrimitive();
	// }
}
