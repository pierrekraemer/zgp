const std = @import("std");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

pub fn perceptualOppositeRGB(rgb: Vec3f) Vec3f {
    const hsl = rgbToHsl(rgb);
    return hslToRgb(.{ @mod(hsl[0] + 0.5, 1.0), hsl[1], hsl[2] });
}

fn rgbToHsl(rgb: Vec3f) Vec3f {
    const r = rgb[0];
    const g = rgb[1];
    const b = rgb[2];

    const max = @max(r, @max(g, b));
    const min = @min(r, @min(g, b));
    const delta = max - min;

    var h: f32 = 0;
    var s: f32 = 0;
    const l: f32 = (max + min) / 2.0;

    if (delta != 0) {
        s = if (l > 0.5) delta / (2.0 - max - min) else delta / (max + min);
        if (r == max) {
            h = (g - b) / delta + (if (g < b) @as(f32, 6.0) else 0);
        } else if (g == max) {
            h = (b - r) / delta + 2.0;
        } else {
            h = (r - g) / delta + 4.0;
        }
        h /= 6.0;
    }
    return .{ h, s, l };
}

pub fn hslToRgb(hsl: Vec3f) Vec3f {
    const h = hsl[0];
    const s = hsl[1];
    const l = hsl[2];

    if (s == 0) {
        return .{ l, l, l }; // Achromatic (gray)
    }

    const q = if (l < 0.5) l * (1.0 + s) else l + s - l * s;
    const p = 2.0 * l - q;

    return .{
        hueToRgb(p, q, h + 1.0 / 3.0),
        hueToRgb(p, q, h),
        hueToRgb(p, q, h - 1.0 / 3.0),
    };
}

fn hueToRgb(p: f32, q: f32, t_in: f32) f32 {
    var t = t_in;
    if (t < 0) t += 1.0;
    if (t > 1) t -= 1.0;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0 / 2.0) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}
