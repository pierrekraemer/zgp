layout (points) in;
layout (triangle_strip, max_vertices=4) out;

uniform mat4 projection_matrix;
uniform mat4 model_view_matrix;
uniform float point_size;

out vec2 spriteCoord;
out vec3 sphereCenter;

void corner(vec4 center, float x, float y)
{
  spriteCoord = vec2(x, y);
  vec4 pos = center + vec4(point_size * x, point_size * y, 0.0, 0.0);
  gl_Position = projection_matrix * pos;
  EmitVertex();
}

void main()
{
  vec4 posCenter = model_view_matrix * gl_in[0].gl_Position;
  sphereCenter = posCenter.xyz;
  corner(posCenter, -1.4,  1.4);
  corner(posCenter, -1.4, -1.4);
  corner(posCenter,  1.4,  1.4);
  corner(posCenter,  1.4, -1.4);
  EndPrimitive();
}
