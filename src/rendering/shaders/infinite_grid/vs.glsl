uniform mat4 u_inv_view_proj;

out vec3 v_near;
out vec3 v_far;

// Reconstruct a world-space point from NDC xy + a given NDC z, using the
// inverse view-projection matrix.
vec3 unproject(float x, float y, float z) {
    vec4 p = u_inv_view_proj * vec4(x, y, z, 1.0);
    return p.xyz / p.w;
}

void main() {
    // Full-screen quad with two triangles from gl_VertexID (0..5), no VBO needed.
    // Vertex positions in NDC:
    //   0: (-1,-1)  1: (+1,-1)  2: (-1,+1)
    //   3: (-1,+1)  4: (+1,-1)  5: (+1,+1)
    vec2 ndc_pos;
    if (gl_VertexID == 0) ndc_pos = vec2(-1.0, -1.0);
    else if (gl_VertexID == 1) ndc_pos = vec2( 1.0, -1.0);
    else if (gl_VertexID == 2) ndc_pos = vec2(-1.0,  1.0);
    else if (gl_VertexID == 3) ndc_pos = vec2(-1.0,  1.0);
    else if (gl_VertexID == 4) ndc_pos = vec2( 1.0, -1.0);
    else                       ndc_pos = vec2( 1.0,  1.0);

    // Unproject the near and far plane points to get ray origin and direction
    v_near = unproject(ndc_pos.x, ndc_pos.y, -1.0);
    v_far  = unproject(ndc_pos.x, ndc_pos.y,  1.0);

    gl_Position = vec4(ndc_pos, 0.0, 1.0);
}
