// ===========================================================================
// CONFIGURATION
// A streak appears behind the cursor at full length, then shrinks forward into
// the cursor. Unlike cursor_tail, the head does not move.
// ===========================================================================

// Trail color at the cursor. iCurrentCursorColor is Ghostty's cursor color, and
// its alpha is `cursor-opacity`. The alpha sets the trail opacity, so 0.0 hides
// the trail. To override, use a value such as vec4(0.2, 0.6, 1.0, 0.5).
vec4 TRAIL_COLOR = iCurrentCursorColor;

// Trail color at the tail end. The trail blends from this color to TRAIL_COLOR.
// iPreviousCursorColor is the cursor color before the move. It differs from the
// current color only when the color changes in the same cursor update as the
// move, for example with `cursor-color = cell-foreground`. If you override
// TRAIL_COLOR, set this to TRAIL_COLOR for one flat color.
vec4 TRAIL_COLOR_TAIL = iPreviousCursorColor;

// Seconds for the streak to shrink into the cursor.
const float DURATION = 0.2;

// Start length of the streak, as a fraction of the distance moved (0..1).
// 1.0 reaches back to the previous cursor position. 0.0 disables the streak.
const float TRAIL_LENGTH = 0.5;

// Minimum move, in cell heights, that draws a trail. 0.0 trails every move.
const float THRESHOLD_MIN_DISTANCE = 1.5;

// 1.0 trails only the focused split. 0.0 trails all splits.
// An unfocused split renders only when its content changes, so it does not
// animate. A TUI that moves its cursor on a timer (btop, watch, vim) would
// leave a full-length streak frozen in that split.
const float FOCUSED_ONLY = 1.0;

// Edge softness in pixels.
const float BLUR = 1.5;

// 1.0 fades the trail toward its tail. 0.0 keeps a flat opacity.
const float FADE_ENABLED = 0.0;
// Fade curve. Below 1.0, most of the trail stays opaque and only the tail
// fades (0.5 = square root). Above 1.0, only a short bright part stays at the
// cursor.
const float FADE_EXPONENT = 0.5;

// Constants for the easing functions below. Most are used only by the
// commented-out variants.
const float PI = 3.14159265359;
const float C1_BACK = 1.70158;
const float C3_BACK = C1_BACK + 1.0;
const float C4_ELASTIC = (2.0 * PI) / 3.0;
const float SPRING_STIFFNESS = 9.0;
const float SPRING_DAMPING = 0.9;

// --- EASING FUNCTIONS ---
// Uncomment exactly one ease(). It maps linear time 0..1 to animation progress
// 0..1 and sets the feel of the animation. Use multiplication, not pow():
// pow() is undefined for a negative base.
//
// This shader clamps the eased value to 0..1. The streak must shrink into the
// cursor box, and a value above 1.0 pushes it out past the cursor. The clamp
// changes the overshooting variants: Back and Spring reach 1.0 at about one
// third of the time and stay there, so the streak disappears early. Elastic
// drops below 1.0 again, so the streak briefly comes back. For a springy
// motion, use cursor_tail or cursor_warp.

// // Linear
// float ease(float x) {
//     return x;
// }

// // EaseOutQuad
// float ease(float x) {
//     float t = 1.0 - x;
//     return 1.0 - t * t;
// }

// EaseOutCubic
float ease(float x) {
    float t = 1.0 - x;
    return 1.0 - t * t * t;
}

// // EaseOutQuart
// float ease(float x) {
//     float t = 1.0 - x;
//     return 1.0 - t * t * t * t;
// }

// // EaseOutQuint
// float ease(float x) {
//     float t = 1.0 - x;
//     return 1.0 - t * t * t * t * t;
// }

// // EaseOutSine
// float ease(float x) {
//     return sin((x * PI) / 2.0);
// }

// // EaseOutExpo
// float ease(float x) {
//     return x == 1.0 ? 1.0 : 1.0 - exp2(-10.0 * x);
// }

// // EaseOutCirc
// float ease(float x) {
//     float t = x - 1.0;
//     return sqrt(1.0 - t * t);
// }

// // EaseOutBack
// float ease(float x) {
//     float t = x - 1.0;
//     return 1.0 + C3_BACK * t * t * t + C1_BACK * t * t;
// }

// // EaseOutElastic
// float ease(float x) {
//     return x == 0.0 ? 0.0
//          : x == 1.0 ? 1.0
//                     : exp2(-10.0 * x) * sin((x * 10.0 - 0.75) * C4_ELASTIC) + 1.0;
// }

// // Parametric Spring
// float ease(float x) {
//     x = clamp(x, 0.0, 1.0);
//     float decay = exp(-SPRING_DAMPING * SPRING_STIFFNESS * x);
//     float freq = sqrt(SPRING_STIFFNESS * (1.0 - SPRING_DAMPING * SPRING_DAMPING));
//     float osc = cos(freq * 6.283185 * x) + (SPRING_DAMPING * sqrt(SPRING_STIFFNESS) / freq) * sin(freq * 6.283185 * x);
//     return 1.0 - decay * osc;
// }

float getSdfRectangle(in vec2 p, in vec2 center, in vec2 halfSize)
{
    vec2 d = abs(p - center) - halfSize;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Polygon SDF after Inigo Quilez: https://iquilezles.org/articles/distfunctions2d/
// One step per edge. It uses step() and mix(), not if, because the conditions
// change per fragment.
float seg(in vec2 p, in vec2 a, in vec2 b, inout float s, float d) {
    vec2 e = b - a;
    vec2 w = p - a;
    // max() prevents 0/0 on a zero-length edge. The eases can collapse an edge,
    // and a NaN distance survives every later mix().
    vec2 proj = a + e * clamp(dot(w, e) / max(dot(e, e), 1e-12), 0.0, 1.0);
    d = min(d, dot(p - proj, p - proj));

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    // c2 is the inverse of IQ's test (e.x*w.y > e.y*w.x). This is correct: it
    // counts the crossings of a ray in the opposite direction, which have the
    // same parity. Do not "fix" it.
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    s *= mix(1.0, -1.0, step(0.5, allCond + noneCond));
    return d;
}

// SDF of a quad with its vertices in order around the edge. The quad does not
// need to be convex.
float getSdfQuad(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);

    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

    return s * sqrt(d);
}

// Converts pixels to shader space, where y is -1..1 over the pane height.
// isPosition 1.0 moves the origin to the pane center. 0.0 converts a size.
vec2 toShaderSpace(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

// Coverage of a fragment at a signed distance. width is the edge softness in
// shader space.
float antialiasing(float distance, float width) {
    return 1.0 - smoothstep(0.0, width, distance);
}

// 1.0 when the move goes up-right or down-left, else 0.0. It selects the
// cursor diagonal that forms the ends of the parallelogram, so the trail leans
// the correct way.
float isTopRightLeading(vec2 a, vec2 b) {
    float condition1 = step(b.x, a.x) * step(a.y, b.y); // a.x >= b.x && a.y <= b.y
    float condition2 = step(a.x, b.x) * step(b.y, a.y); // a.x <= b.x && a.y >= b.y
    return 1.0 - max(condition1, condition2);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #else
    // fragColor is read below, so it must have a value.
    fragColor = vec4(0.0);
    #endif

    vec2 offsetFactor = vec2(-.5, 0.5);

    vec4 currentCursor = vec4(toShaderSpace(iCurrentCursor.xy, 1.), toShaderSpace(iCurrentCursor.zw, 0.));
    vec4 previousCursor = vec4(toShaderSpace(iPreviousCursor.xy, 1.), toShaderSpace(iPreviousCursor.zw, 0.));

    vec2 centerCC = currentCursor.xy - (currentCursor.zw * offsetFactor);
    vec2 centerCP = previousCursor.xy - (previousCursor.zw * offsetFactor);

    float lineLength = distance(centerCC, centerCP);

    // No uniform gives the cell height. An underline cursor is only a few
    // pixels tall, so its cell height is estimated as twice its width.
    float cellHeight = iCurrentCursorStyle == CURSORSTYLE_UNDERLINE ? 2.0 * currentCursor.z : currentCursor.w;
    float minDist = cellHeight * THRESHOLD_MIN_DISTANCE;

    float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);

    // Apps that hide the cursor (btop, less, vim in some modes) still move it
    // on each repaint. The user did not cause these moves, so a hidden cursor
    // gets no trail.
    bool cursorLive = iCursorVisible > 0 && (FOCUSED_ONLY < 0.5 || iFocus > 0);

    // Ghostty fills iPreviousCursor with zeros until the cursor first moves.
    // Without the size test, the first frame of a new split trails in from the
    // pane corner.
    if (!cursorLive || previousCursor.z <= 0.0 || TRAIL_LENGTH <= 0.0
        || lineLength <= minDist || progress >= 1.0) {
        return;
    }

    vec2 vu = toShaderSpace(fragCoord, 1.);
    float aaWidth = 2.0 * BLUR / iResolution.y;

    // 0.0 is the full-length streak, 1.0 is fully shrunk into the cursor.
    float shrinkFactor = clamp(ease(progress), 0.0, 1.0);

    // Center of the back end of the streak.
    vec2 tailCenter = mix(mix(centerCC, centerCP, TRAIL_LENGTH), centerCC, shrinkFactor);

    // Skip the shape work outside the bounding box of the streak. The box is
    // the same for all fragments. The pad is the full cursor size, not half,
    // because the parallelogram corners combine the position of one cursor
    // with the width of the other.
    vec2 pad = max(currentCursor.zw, previousCursor.zw) + vec2(aaWidth);
    vec2 bbMin = min(centerCC, tailCenter) - pad;
    vec2 bbMax = max(centerCC, tailCenter) + pad;
    if (any(lessThan(vu, bbMin)) || any(greaterThan(vu, bbMax))) {
        return;
    }

    // A straight move needs only a rectangle. The test is the same for all
    // fragments, so the branch does not diverge.
    vec2 delta = abs(centerCC - centerCP);
    float threshold = 0.001;
    bool isStraightMove = delta.x <= threshold || delta.y <= threshold;

    float sdfTrail;
    if (isStraightMove) {
        // Box from the cursor back along the path.
        vec2 min_center = min(centerCP, centerCC);
        vec2 max_center = max(centerCP, centerCC);

        vec2 bBoxSize_full = (max_center - min_center) + currentCursor.zw;
        vec2 bBoxCenter_full = (min_center + max_center) * 0.5;

        vec2 bBoxSize_start = mix(currentCursor.zw, bBoxSize_full, TRAIL_LENGTH);
        vec2 bBoxCenter_start = mix(centerCC, bBoxCenter_full, TRAIL_LENGTH);

        vec2 animSize = mix(bBoxSize_start, currentCursor.zw, shrinkFactor);
        vec2 animCenter = mix(bBoxCenter_start, centerCC, shrinkFactor);

        sdfTrail = getSdfRectangle(vu, animCenter, animSize * 0.5);
    } else {
        // Parallelogram from the cursor back along the path.
        float topRightLeads = isTopRightLeading(currentCursor.xy, previousCursor.xy);
        float bottomLeftLeads = 1.0 - topRightLeads;

        vec2 v0 = vec2(currentCursor.x + currentCursor.z * topRightLeads, currentCursor.y - currentCursor.w);
        vec2 v1 = vec2(currentCursor.x + currentCursor.z * bottomLeftLeads, currentCursor.y);
        vec2 v2_full = vec2(previousCursor.x + currentCursor.z * bottomLeftLeads, previousCursor.y);
        vec2 v3_full = vec2(previousCursor.x + currentCursor.z * topRightLeads, previousCursor.y - previousCursor.w);

        vec2 v2_start = mix(v1, v2_full, TRAIL_LENGTH);
        vec2 v3_start = mix(v0, v3_full, TRAIL_LENGTH);
        vec2 v2_anim = mix(v2_start, v1, shrinkFactor);
        vec2 v3_anim = mix(v3_start, v0, shrinkFactor);

        sdfTrail = getSdfQuad(vu, v0, v1, v2_anim, v3_anim);
    }

    // Position along the streak: 0.0 at the center of the back end, 1.0 at the
    // cursor center. It follows the shrinking back end, so the fade always
    // reaches zero, and the color reaches TRAIL_COLOR_TAIL, inside the shape.
    vec2 trailAxis = centerCC - tailCenter;
    float alongTrail = clamp(dot(vu - tailCenter, trailAxis) / (dot(trailAxis, trailAxis) + 1e-6), 0.0, 1.0);

    vec4 trail = mix(TRAIL_COLOR_TAIL, TRAIL_COLOR, alongTrail);

    if (FADE_ENABLED > 0.5) {
        trail.a *= pow(alongTrail, FADE_EXPONENT);
    }

    // trail.a scales the coverage. Blend toward alpha 1.0, not trail.a: a
    // second trail.a makes the trail too transparent on a translucent window.
    // Do not take the coverage from the iChannel0 alpha: it is too low over an
    // empty background, and long trails disappear.
    float trailAlpha = antialiasing(sdfTrail, aaWidth) * trail.a;
    vec4 newColor = mix(fragColor, vec4(trail.rgb, 1.0), trailAlpha);

    // Restore the cursor cell, so the real cursor shows on top of the trail.
    // On diagonal moves the restore edge is soft, like the trail edge, because
    // a hard edge leaves a stepped seam. The softness goes outward only, so a
    // thin bar or underline cursor is still fully restored. On straight moves
    // the edge stays hard: there the two edges are on the same line, and two
    // soft edges add up to a visible line. 1e-6, not 0.0, keeps the smoothstep
    // edges different.
    float sdfCurrentCursor = getSdfRectangle(vu, centerCC, currentCursor.zw * 0.5);
    float restoreWidth = isStraightMove ? 1e-6 : aaWidth;
    fragColor = mix(newColor, fragColor, antialiasing(sdfCurrentCursor, restoreWidth));
}
