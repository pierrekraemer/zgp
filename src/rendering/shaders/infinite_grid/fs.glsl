precision highp float;
precision highp int;

in vec3 v_near;
in vec3 v_far;

uniform mat4 u_view_proj;
uniform float u_near;
uniform float u_far;

out vec4 f_color;

// Compute an antialiased grid line coverage for a given world coord and spacing.
float gridLine(float coord, float spacing) {
    float half_width = 0.1;
    float line = abs(fract(coord / spacing - 0.5) - 0.5) / fwidth(coord / spacing);
    return 1.0 - clamp(line - half_width, 0.0, 1.0);
}

void main() {
    // Ray / XZ-plane intersection (y = 0)
    float t = -v_near.y / (v_far.y - v_near.y);
    if (t < 0.0) discard; // plane is behind the camera from this fragment

    vec3 hit = v_near + t * (v_far - v_near);

    // Fade based on t (ray parameter): 0 = near camera, 1 = far plane.
    // This makes the grid extend all the way to the horizon regardless of
    // camera angle, unlike a fixed world-space radius which clips too close.
    float fade = 1.0 - smoothstep(0.5, 1.0, t);
    if (fade <= 0.0) discard;

    // Grid lines at two scales
    float g1 = gridLine(hit.x, 0.1) + gridLine(hit.z, 0.1);   // fine 0.1-unit grid
    float g10 = gridLine(hit.x, 1.0) + gridLine(hit.z, 1.0);  // major 1-unit grid

    // Axis lines: highlight X (red) and Z (blue) axes
    float axis_width = 0.25;
    float ax = 1.0 - clamp(abs(hit.z) / fwidth(hit.z) - axis_width, 0.0, 1.0); // Z=0 → X-axis
    float az = 1.0 - clamp(abs(hit.x) / fwidth(hit.x) - axis_width, 0.0, 1.0); // X=0 → Z-axis

    // Compose: fine sub-grid (dark), major grid (lighter), axes (colored)
    vec4 grid_color = vec4(0.0);
    float fine_alpha  = clamp(g1,  0.0, 1.0) * 0.15;
    float major_alpha = clamp(g10, 0.0, 1.0) * 0.5;
    float axis_x_alpha = clamp(ax, 0.0, 1.0) * 0.85;
    float axis_z_alpha = clamp(az, 0.0, 1.0) * 0.85;

    grid_color = mix(grid_color, vec4(0.75, 0.75, 0.75, 1.0), fine_alpha);
    grid_color = mix(grid_color, vec4(0.85, 0.85, 0.85, 1.0), major_alpha);
    grid_color = mix(grid_color, vec4(0.45, 0.15, 0.15, 1.0), axis_x_alpha);
    grid_color = mix(grid_color, vec4(0.15, 0.15, 0.45, 1.0), axis_z_alpha);

    float final_alpha = max(max(fine_alpha, major_alpha), max(axis_x_alpha, axis_z_alpha));
    grid_color.a = final_alpha * fade;

    if (grid_color.a < 0.001) discard;

    f_color = grid_color;

    // Write correct depth so the grid occludes geometry behind it
    vec4 clip_pos = u_view_proj * vec4(hit, 1.0);
    float ndc_depth = clip_pos.z / clip_pos.w;
    gl_FragDepth = (ndc_depth + 1.0) * 0.5;
}
