// ===========================================================================
// CONFIGURATION
// The trail is the cursor box drawn as a quad. Its four corners reach the
// cursor at different times, and this difference makes the warp.
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

// Seconds for the last (trailing) corner to reach the cursor.
const float DURATION = 0.25;

// How much the trailing corners lag behind the leading corners, 0..1.
//   0.0   all corners move together: the box slides with no smear
//   0.95  leading corners arrive almost at once, trailing corners stretch behind
//   1.0   leading corners jump at once (maximum smear)
const float TRAIL_SIZE = 0.95;

// Minimum move, in cell heights, that draws a trail. 0.0 trails every move.
const float THRESHOLD_MIN_DISTANCE = 1.5;

// 1.0 trails only the focused split. 0.0 trails all splits.
// An unfocused split renders only when its content changes, so it does not
// animate. A TUI that moves its cursor on a timer (btop, watch, vim) would
// leave a full-length streak frozen in that split.
const float FOCUSED_ONLY = 1.0;

// Edge softness in pixels. Below 2.5, only diagonal moves are soft: straight
// moves keep a hard edge, because a soft edge there pulses where the trail
// meets the cursor. At 2.5 and above, all moves are soft.
const float BLUR = 1.5;

// Trail size as a fraction of the cursor size. 1.0 matches the cursor. Lower
// values make a thinner trail. Values above 1.0 make it larger than the cursor.
const float TRAIL_THICKNESS = 1.0;    // vertical
const float TRAIL_THICKNESS_X = 1.0;  // horizontal

// 1.0 fades the trail toward its tail. 0.0 keeps a flat opacity.
const float FADE_ENABLED = 1.0;
// Fade curve. Below 1.0, most of the trail stays opaque and only the tail
// fades (0.5 = square root). Above 1.0, only a short bright part stays at the
// cursor.
const float FADE_EXPONENT = 0.5;

// Extra room for eases that go above 1.0, as a fraction of the distance moved.
// The shader skips the shape work outside a box around both cursor positions,
// so corners that an overshooting ease moves out of that box are clipped.
// 0.0 is correct for eases that stop at 1.0, such as the default.
const float EASE_OVERSHOOT = 0.0;

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
// The Back, Elastic and Spring variants go above 1.0. Here that gives a
// springy motion. If you enable one, set EASE_OVERSHOOT to at least its
// overshoot (Back 0.1, Elastic 0.38, Spring 0.06), or the box clips the
// corners.

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

// Duration of one corner. dotVal is the corner direction dotted with the move
// direction, an integer in -2..2. A leading corner (1 or more) takes
// durationLead, a trailing corner (-1 or less) takes DURATION, and a side
// corner (0) takes the mean of the two.
float getDurationFromDot(float dotVal, float durationLead) {
    return mix(DURATION, durationLead, clamp(0.5 + 0.5 * dotVal, 0.0, 1.0));
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

    float elapsed = iTime - iTimeCursorChange;

    // Apps that hide the cursor (btop, less, vim in some modes) still move it
    // on each repaint. The user did not cause these moves, so a hidden cursor
    // gets no trail.
    bool cursorLive = iCursorVisible > 0 && (FOCUSED_ONLY < 0.5 || iFocus > 0);

    // Ghostty fills iPreviousCursor with zeros until the cursor first moves.
    // Without the size test, the first frame of a new split trails in from the
    // pane corner.
    if (!cursorLive || previousCursor.z <= 0.0 || lineLength <= minDist
        || elapsed >= DURATION - 0.001) {
        return;
    }

    vec2 vu = toShaderSpace(fragCoord, 1.);

    vec2 moveVec = centerCC - centerCP;
    vec2 s = sign(moveVec);

    // Straight moves keep a hard edge (see BLUR). 1e-4, not 0.0, keeps the
    // smoothstep edges different.
    float effectiveBlur = BLUR;
    if (BLUR < 2.5) {
        float isDiagonal = abs(s.x) * abs(s.y);
        effectiveBlur = mix(1e-4, BLUR, isDiagonal);
    }
    float aaWidth = 2.0 * effectiveBlur / iResolution.y;

    // Half size of the trail at each end.
    vec2 thickness = vec2(TRAIL_THICKNESS_X, TRAIL_THICKNESS);
    vec2 halfSizeCC = currentCursor.zw * 0.5 * thickness;
    vec2 halfSizeCP = previousCursor.zw * 0.5 * thickness;

    // Skip the shape work outside the box around both trail ends. The box is
    // the same for all fragments. It uses the fixed ends, not the animated
    // corners: the quad covers most of the move for most of the animation, so
    // a tighter box saves little and costs every fragment the corner work.
    // On each axis a corner travels at most lineLength + maxHalfSize, and an
    // overshooting ease moves it EASE_OVERSHOOT of that past its end.
    vec2 maxHalfSize = max(halfSizeCC, halfSizeCP);
    vec2 pad = maxHalfSize + aaWidth + EASE_OVERSHOOT * (lineLength + maxHalfSize);
    vec2 bbMin = min(centerCC, centerCP) - pad;
    vec2 bbMax = max(centerCC, centerCP) + pad;
    if (any(lessThan(vu, bbMin)) || any(greaterThan(vu, bbMax))) {
        return;
    }

    // Corner directions from the box center.
    const vec2 TL = vec2(-1.0,  1.0);
    const vec2 TR = vec2( 1.0,  1.0);
    const vec2 BL = vec2(-1.0, -1.0);
    const vec2 BR = vec2( 1.0, -1.0);

    // The floor keeps TRAIL_SIZE = 1.0 from dividing by zero below.
    float durationLead = max(DURATION * (1.0 - TRAIL_SIZE), 1e-5);
    float dur_tl = getDurationFromDot(dot(TL, s), durationLead);
    float dur_tr = getDurationFromDot(dot(TR, s), durationLead);
    float dur_bl = getDurationFromDot(dot(BL, s), durationLead);
    float dur_br = getDurationFromDot(dot(BR, s), durationLead);

    // On a horizontal or diagonal move, both corners on the leading side lead.
    // That edge then moves as one rigid vertical rail and does not shear.
    float isMovingRight = step(0.5, s.x);
    float isMovingLeft = step(0.5, -s.x);
    dur_tr = mix(dur_tr, durationLead, isMovingRight);
    dur_br = mix(dur_br, durationLead, isMovingRight);
    dur_tl = mix(dur_tl, durationLead, isMovingLeft);
    dur_bl = mix(dur_bl, durationLead, isMovingLeft);

    float prog_tl = ease(clamp(elapsed / dur_tl, 0.0, 1.0));
    float prog_tr = ease(clamp(elapsed / dur_tr, 0.0, 1.0));
    float prog_bl = ease(clamp(elapsed / dur_bl, 0.0, 1.0));
    float prog_br = ease(clamp(elapsed / dur_br, 0.0, 1.0));

    vec2 v_tl = mix(centerCP + halfSizeCP * TL, centerCC + halfSizeCC * TL, prog_tl);
    vec2 v_tr = mix(centerCP + halfSizeCP * TR, centerCC + halfSizeCC * TR, prog_tr);
    vec2 v_br = mix(centerCP + halfSizeCP * BR, centerCC + halfSizeCC * BR, prog_br);
    vec2 v_bl = mix(centerCP + halfSizeCP * BL, centerCC + halfSizeCC * BL, prog_bl);

    float sdfTrail = getSdfQuad(vu, v_tl, v_tr, v_br, v_bl);

    // Position along the move: 0.0 at the previous cursor center, 1.0 at the
    // current one. It uses the fixed ends, not the animated quad, so the half
    // cell behind centerCP always fades out fully.
    float alongTrail = clamp(dot(vu - centerCP, moveVec) / (dot(moveVec, moveVec) + 1e-6), 0.0, 1.0);

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
    // The restore edge has the same softness as the trail edge: soft on
    // diagonal moves, which prevents a stepped seam, and hard on straight
    // moves. The softness goes outward only, so a thin bar or underline cursor
    // is still fully restored.
    float sdfCurrentCursor = getSdfRectangle(vu, centerCC, currentCursor.zw * 0.5);
    fragColor = mix(newColor, fragColor, antialiasing(sdfCurrentCursor, aaWidth));
}
