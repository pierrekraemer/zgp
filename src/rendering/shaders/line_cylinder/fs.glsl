uniform mat4 u_projection_matrix;
uniform vec4 u_ambiant_color;
uniform vec3 u_light_position;
uniform float u_cylinder_radius;
uniform vec4 u_cylinder_color;

flat in vec3 view_v0;
flat in vec3 view_v1;
smooth in vec3 proxy_pos;

out vec4 f_color;

float fragDepthFromView(mat4 projMat, vec3 viewPoint) {
    vec4 clipPos = projMat * vec4(viewPoint, 1.);
    float z_ndc = clipPos.z / clipPos.w;
    float depth = (z_ndc + 1.0) / 2.0;
    return depth;
}

float interCylinder(vec3 ro, vec3 rd, vec3 pa, vec3 pb, float ra) {
    vec3 ba = pb - pa;
    vec3 oc = ro - pa;

    float baba = dot(ba, ba);
    float bard = dot(ba, rd);
    float baoc = dot(ba, oc);

    // Quadratic coefficients (A, B/2, C)
    // Derived from | (ro - pa) x ba + t * (rd x ba) |^2 = (ra * |ba|)^2
    float k2 = baba - bard * bard;
    float k1 = baba * dot(oc, rd) - baoc * bard;
    float k0 = baba * dot(oc, oc) - baoc * baoc - ra * ra * baba;

    // Initialize t to -1.0 (no hit)
    float t = -1.0;

    // --- 1. Body Intersection (Infinite Cylinder clipped) ---
    float h = k1 * k1 - k2 * k0;
    if (h >= 0.0) {
        h = sqrt(h);
        // Calculate the closest intersection (minus sign)
        float tBody = (-k1 - h) / k2;
        
        // Check if the hit is within the segment lengths
        float y = baoc + tBody * bard;
        if (y > 0.0 && y < baba) {
            t = tBody;
        }
    }
    
    // --- 2. End Caps Intersection (Planes) ---
    // Denominator for plane intersection
    // If close to 0, ray is parallel to caps (perpendicular to axis)
    if (abs(bard) > 0.0001) {
        // Cap A (Tail) Intersection
        // t = (Center - Origin) . Normal / Direction . Normal
        // Normal is -ba, but signs cancel out to: -baoc / bard
        float tCapA = -baoc / bard;
        
        // Cap B (Tip) Intersection
        // Normal is ba: (baba - baoc) / bard
        float tCapB = (baba - baoc) / bard;
        
        // Check Cap A validity
        if (tCapA > 0.0) {
            // Is it closer than what we have?
            if (t < 0.0 || tCapA < t) {
                // Check if hit is within radius
                vec3 hit = ro + tCapA * rd - pa;
                if (dot(hit, hit) <= ra * ra) {
                    t = tCapA;
                }
            }
        }
        
        // Check Cap B validity
        if (tCapB > 0.0) {
            // Is it closer than what we have?
            if (t < 0.0 || tCapB < t) {
                // Check if hit is within radius
                vec3 hit = ro + tCapB * rd - pb;
                if (dot(hit, hit) <= ra * ra) {
                    t = tCapB;
                }
            }
        }
    }

    return t;
}

vec3 calcCylinderNormal(vec3 p, vec3 pa, vec3 pb, float ra) {
    vec3 ba = pb - pa;
    vec3 pa_p = p - pa;
    
    // Project point onto the axis line
    float h = dot(pa_p, ba) / dot(ba, ba);
    
    // 1. If projection is effectively 0, we hit Cap A (Tail)
    // Using a small epsilon for float precision
    if (h <= 0.0001) return normalize(-ba);
    
    // 2. If projection is effectively 1, we hit Cap B (Tip)
    if (h >= 0.9999) return normalize(ba);
    
    // 3. Otherwise, we hit the Body
    return normalize(pa_p - ba * h);
}

void main() {
    vec3 rayStart = vec3(0.0, 0.0, 0.0);
	vec3 rayDir = normalize(proxy_pos);
    
    float t = interCylinder(rayStart, rayDir, view_v0, view_v1, u_cylinder_radius);

    if (t > 0.0) {
        vec3 hitPos = rayStart + t * rayDir;
        vec3 normal = calcCylinderNormal(hitPos, view_v0, view_v1, u_cylinder_radius);

        gl_FragDepth = fragDepthFromView(u_projection_matrix, hitPos);
        
        vec3 L = normalize(u_light_position - hitPos);
        float lambert_term = dot(normal, L);
        vec4 result = vec4(u_cylinder_color.rgb * lambert_term, u_cylinder_color.a);
        result += vec4(u_ambiant_color.rgb, 0.0);
        f_color = result;
    } else {
        discard;
    }
}
