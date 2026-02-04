uniform mat4 u_projection_matrix;
uniform vec4 u_ambiant_color;
uniform vec3 u_light_position;
uniform float u_sphere_radius;

flat in vec3 sphere_center;
flat in vec4 sphere_color;
smooth in vec3 proxy_pos;

out vec4 f_color;

float fragDepthFromView(mat4 projMat, vec3 viewPoint) {
    vec4 clipPos = projMat * vec4(viewPoint, 1.);
    float z_ndc = clipPos.z / clipPos.w;
    float depth = (z_ndc + 1.0) / 2.0;
    return depth;
}

float interSphere(vec3 ro, vec3 rd, vec3 ce, float ra) {
    vec3 oc = ro - ce;
    
    // Coefficients for quadratic equation: t^2 + 2*b*t + c = 0
    float b = dot(oc, rd);
    float c = dot(oc, oc) - ra * ra;
    
    // Calculate Discriminant (h)
    // h represents the squared distance from the ray's closest approach to the sphere surface
    float h = b * b - c;
    
    // If h < 0, the ray misses the sphere
    if (h < 0.0) return -1.0;
    
    h = sqrt(h);
    
    // Calculate the closest intersection point
    float t = -b - h;
    
    // Handle case where camera is INSIDE the sphere
    // If t is negative, it means the intersection is behind us, so we check the exit point
    if (t < 0.0) {
        t = -b + h;
    }
    
    // If both are negative, the sphere is completely behind the camera
    if (t < 0.0) return -1.0;
    
    return t;
}

void main() {
    vec3 rayStart = vec3(0.0, 0.0, 0.0);
	vec3 rayDir = normalize(proxy_pos);
    
    float t = interSphere(rayStart, rayDir, sphere_center, u_sphere_radius);

    if (t > 0.0) {
        vec3 hitPos = rayStart + t * rayDir;
        vec3 normal = normalize(hitPos - sphere_center);

        gl_FragDepth = fragDepthFromView(u_projection_matrix, hitPos);
        
        vec3 L = normalize(u_light_position - hitPos);
        float lambert_term = dot(normal, L);
        vec4 result = vec4(sphere_color.rgb * lambert_term, 1.0);
        result += vec4(u_ambiant_color.rgb, 0.0);
        f_color = result;
    } else {
        discard;
    }
}
