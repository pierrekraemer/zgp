uniform mat4 u_projection_matrix;
uniform vec4 u_ambiant_color;
uniform vec3 u_light_position;
uniform float u_cone_radius;
uniform vec4 u_vector_color;

flat in vec3 view_v0;
flat in vec3 view_v1;
smooth in vec3 view_pos;

out vec4 f_color;

float fragDepthFromView(mat4 projMat, vec3 viewPoint) {
    vec4 clipPos = projMat * vec4(viewPoint, 1.);
    float z_ndc = clipPos.z / clipPos.w;
    float depth = (z_ndc + 1.0) / 2.0;
    return depth;
}

float interCone(vec3 ro, vec3 rd, vec3 pa, vec3 pb, float ra) {
    // 1. Setup Cone Geometric Parameters
    vec3  axisVec = pa - pb;              // Vector from Tip to Base
    float height  = length(axisVec);      // Height of the cone
    vec3  axisDir = axisVec / height;     // Normalized Axis Direction
    
    // Calculate the square of the cosine of the half-angle
    // cos(theta) = adj / hyp = height / sqrt(height^2 + radius^2)
    float cos2 = (height * height) / (height * height + ra * ra);
    
    // 2. Setup Quadratic Equation: At^2 + Bt + C = 0
    // We work in a coordinate system relative to the Tip (pb)
    vec3  oc = ro - pb; // Ray Origin relative to Tip
    
    // We want to solve: (P . axisDir)^2 = |P|^2 * cos2
    // Substitute P = oc + t*rd
    
    float d_a = dot(rd, axisDir);
    float o_a = dot(oc, axisDir);
    float d_d = dot(rd, rd); // Should be 1.0 if normalized, but good for safety
    float o_o = dot(oc, oc);
    float o_d = dot(oc, rd);
    
    // Quadratic Coefficients
    float A = d_a * d_a - cos2 * d_d;
    float B = 2.0 * (d_a * o_a - cos2 * o_d);
    float C = o_a * o_a - cos2 * o_o;
    
    // 3. Solve Quadratic
    float h = B * B - 4.0 * A * C;
    
    float t = -1.0; // Default to no hit
    
    // --- Base Cap Intersection Logic ---
    // We calculate this first to compare with body hits later
    float tCap = -1.0;
    // Intersect plane at 'pa' with normal 'axisDir'
    // t = (pa - ro) . axisDir / rd . axisDir
    // (pa - ro) = (pb + axisVec - ro) = axisVec - oc
    float den = dot(rd, axisDir);
    if (abs(den) > 0.0001) {
        float tC = dot(axisVec - oc, axisDir) / den;
        if (tC > 0.0) {
            vec3 p = ro + tC * rd - pa;
            if (dot(p, p) <= ra * ra) {
                tCap = tC;
            }
        }
    }

    // --- Body Intersection Logic ---
    if (h >= 0.0) {
        h = sqrt(h);
        float t1 = (-B - h) / (2.0 * A);
        float t2 = (-B + h) / (2.0 * A);
        
        // We need to find the closest valid t
        // A valid t must result in a point P where:
        // 1. The projection onto the axis is positive (in front of tip)
        // 2. The projection is less than height (behind base)
        
        float tBody = -1.0;
        
        // Check t1
        float y1 = dot(oc + t1 * rd, axisDir);
        if (t1 > 0.0 && y1 > 0.0 && y1 < height) {
            tBody = t1;
        }
        
        // Check t2 (if t1 was invalid or we are inside)
        float y2 = dot(oc + t2 * rd, axisDir);
        if (t2 > 0.0 && y2 > 0.0 && y2 < height) {
            if (tBody == -1.0 || t2 < tBody) tBody = t2;
        }
        
        // Combine Body and Cap
        if (tBody > 0.0) {
            if (tCap > 0.0) t = min(tBody, tCap);
            else t = tBody;
        } else {
            t = tCap;
        }
    } else {
        t = tCap;
    }
    
    return t;
}

vec3 calcConeNormal(vec3 p, vec3 pa, vec3 pb, float ra) {
    vec3  axisVec = pa - pb;
    float height = length(axisVec);
    vec3  axisDir = axisVec / height;

    vec3  p_tip = p - pb;
    
    // 1. Check Base Cap
    // Project p_tip onto axis. If it's close to 'height', we are on the base.
    float h = dot(p_tip, axisDir);
    if (h >= height - 0.00001) {
        return axisDir; // Normal points same way as Tip->Base axis
    }
    
    // 2. Body Normal
    // The normal is perpendicular to the surface.
    // Calculate the vector perpendicular to the axis at the hit height.
    vec3 radial = normalize(p_tip - axisDir * h);
    
    // Calculate sine and cosine of the slope angle
    float slantDist = sqrt(height * height + ra * ra);
    float sinSlope = height / slantDist;
    float cosSlope = ra / slantDist;
    
    // The normal points "out" (radial) and "down" (towards base, opposite to axis)
    // Wait: axisDir points Tip->Base. 
    // The surface tilts IN towards the tip.
    // N = Radial * (Height/Slant) - Axis * (Radius/Slant)
    return normalize(radial * sinSlope - axisDir * cosSlope);
}

void main() {
    vec3 rayStart = vec3(0.0, 0.0, 0.0);
	vec3 rayDir = normalize(view_pos);
    
    float t = interCone(rayStart, rayDir, view_v0, view_v1, u_cone_radius);

    if (t > 0.0) {
        vec3 hitPos = rayStart + t * rayDir;
        vec3 normal = calcConeNormal(hitPos, view_v0, view_v1, u_cone_radius);

        gl_FragDepth = fragDepthFromView(u_projection_matrix, hitPos);
        
        vec3 L = normalize(u_light_position - hitPos);
        float lambert_term = dot(normal, L);
        vec4 result = vec4(u_vector_color.rgb * lambert_term, 1.0);
        result += vec4(u_ambiant_color.rgb, 0.0);
        f_color = result;
    } else {
        f_color = vec4(1.0, 0.0, 0.0, 0.0);
    }
}
