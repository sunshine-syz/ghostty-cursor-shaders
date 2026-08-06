// ===========================================================================
// CONFIGURATION
// The cursor box is dragged as a quad whose four corners each arrive at a
// different time; that staggering is what produces the warp.
// ===========================================================================

// Trail colour. iCurrentCursorColor follows Ghostty's cursor colour, and its
// alpha follows `cursor-opacity`. The alpha is load-bearing: it becomes the
// trail's output alpha, so 0.0 draws nothing. Override eg vec4(0.2,0.6,1.0,0.5).
vec4 TRAIL_COLOR = iCurrentCursorColor;

// Seconds for the last (trailing) corner to reach the cursor.
const float DURATION = 0.25;

// How far trailing corners lag leading ones, 0..1.
//   0.0  every corner moves together -- the box slides rigidly, no smear
//   0.95 leading corners arrive almost at once, trailing ones stretch behind
//   1.0  leading corners teleport (maximum smear)
const float TRAIL_SIZE = 0.95;

// Minimum jump before any trail is drawn, in cursor cells. Raise to skip trails
// on short hops; 0.0 trails every movement.
const float THRESHOLD_MIN_DISTANCE = 1.5;

// Trail only the focused split. TUI apps that repaint on a timer (btop, watch,
// vim) move their own cursor while unfocused, and an unfocused surface renders
// only when its content changes -- it never runs the animation loop -- so that
// single frame leaves a fully-stretched streak frozen there until the next
// repaint. Set to 0.0 to trail every split.
const float FOCUSED_ONLY = 1.0;

// Edge softness in pixels. Below 2.5 it applies to diagonal moves only --
// horizontal/vertical moves keep a hard edge, which avoids a pulsing artifact
// where the trail meets the cursor. At 2.5 and above it applies to all moves.
const float BLUR = 1.5;

// Trail cross-section as a fraction of the cursor box. 1.0 matches the cursor,
// lower is a thinner ribbon, above 1.0 overflows it.
const float TRAIL_THICKNESS = 1.0;    // vertical
const float TRAIL_THICKNESS_X = 1.0;  // horizontal

// Fade the trail out towards its tail; 0.0 disables it for flat opacity.
const float FADE_ENABLED = 1.0;
// Fade curve. Below 1.0 holds most of the trail opaque and fades only near the
// tail (0.5 = square root); above 1.0 leaves just a bright stub at the cursor.
const float FADE_EXPONENT = 0.5;

// Headroom for eases that return values above 1.0, as a fraction of the distance
// moved. The trail is clipped to a box spanning the two cursor positions so the
// rest of the pane can skip the shape work; an overshooting ease puts the
// leading corners outside that box and they would be cut off. 0.0 suits every
// ease that lands on 1.0 -- which the shipped default does -- and keeps the clip
// tightest.
const float EASE_OVERSHOOT = 0.0;

// Constants for the easing variants below; several stay unused until you
// uncomment the matching ease().
const float PI = 3.14159265359;
const float C1_BACK = 1.70158;
const float C2_BACK = C1_BACK * 1.525;
const float C3_BACK = C1_BACK + 1.0;
const float C4_ELASTIC = (2.0 * PI) / 3.0;
const float C5_ELASTIC = (2.0 * PI) / 4.5;
const float SPRING_STIFFNESS = 9.0;
const float SPRING_DAMPING = 0.9;

// --- EASING FUNCTIONS ---
// Exactly one ease() may be uncommented. It remaps linear time 0..1 to eased
// progress 0..1 and sets the feel of the whole animation.
//
// The Back, Elastic, and Spring variants overshoot past 1.0, which reads as
// springiness here and is fine -- but raise EASE_OVERSHOOT above if you enable
// one, or the overshooting corners are clipped where they leave the bounding box.

// // Linear
// float ease(float x) {
//     return x;
// }

// // EaseOutQuad
// float ease(float x) {
//     float t = 1.0 - x;
//     return 1.0 - t * t;
// }

// EaseOutCubic -- expanded rather than pow(), which lowers to exp2/log2 and is
// undefined for a negative base. Called once per corner, so four times per
// fragment.
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

float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b)
{
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed-distance helpers after Inigo Quilez: https://iquilezles.org/articles/distfunctions2d/
// Written branch-free (step/mix rather than if) so every fragment costs the same.
// Unlike the uniform branches in mainImage, these conditions vary per fragment,
// so real ifs here would diverge inside a wavefront.
float seg(in vec2 p, in vec2 a, in vec2 b, inout float s, float d) {
    vec2 e = b - a;
    vec2 w = p - a;
    vec2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float segd = dot(p - proj, p - proj);
    d = min(d, segd);

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    // c2 is inverted vs. IQ's reference (which tests e.x*w.y > e.y*w.x). Harmless: a
    // horizontal line crosses a closed polygon an even number of times, so flipping s
    // on the complementary set of edges preserves parity. Do not "fix" it.
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    float flip = mix(1.0, -1.0, step(0.5, allCond + noneCond));
    s *= flip;
    return d;
}

// Callers must keep every edge non-degenerate: seg() divides by dot(e, e), so a
// zero-length edge yields NaN rather than an empty shape.
float getSdfConvexQuad(in vec2 p, in vec2 v1, in vec2 v2, in vec2 v3, in vec2 v4) {
    float s = 1.0;
    float d = dot(p - v1, p - v1);

    d = seg(p, v1, v2, s, d);
    d = seg(p, v2, v3, s, d);
    d = seg(p, v3, v4, s, d);
    d = seg(p, v4, v1, s, d);

    return s * sqrt(d);
}

// Pixels to the shader's normalised space, where y spans -1..1 over the pane
// height. isPosition 1.0 recentres the origin on the pane; 0.0 converts a bare
// size or distance.
vec2 toShaderSpace(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

// width is the edge softness already in normalised units -- see aaWidth in
// mainImage. Passed in rather than derived per call: it depends on iResolution,
// so the compiler cannot fold it.
float antialiasing(float distance, float width) {
    return 1.0 - smoothstep(0.0, width, distance);
}

// Picks a corner's duration from how well it aligns with the move direction.
// dot_val is in [-2,2]: >=1 leading, 0 side-on, <=-1 trailing.
float getDurationFromDot(float dot_val, float DURATION_LEAD, float DURATION_SIDE, float DURATION_TRAIL) {
    float isLead = step(0.5, dot_val);
    float isSide = step(-0.5, dot_val) * (1.0 - isLead);

    float duration = mix(DURATION_TRAIL, DURATION_SIDE, isSide);
    duration = mix(duration, DURATION_LEAD, isLead);
    return duration;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #else
    // Nothing else writes fragColor before it is read below, and it is an out
    // parameter -- reading it unwritten is undefined.
    fragColor = vec4(0.0);
    #endif

    // Everything below works in the shader's normalised space: y spans -1..1 over
    // the pane height, so a length of 2.0 is one full pane height.
    vec2 offsetFactor = vec2(-.5, 0.5);

    vec4 currentCursor = vec4(toShaderSpace(iCurrentCursor.xy, 1.), toShaderSpace(iCurrentCursor.zw, 0.));
    vec4 previousCursor = vec4(toShaderSpace(iPreviousCursor.xy, 1.), toShaderSpace(iPreviousCursor.zw, 0.));

    vec2 centerCC = currentCursor.xy - (currentCursor.zw * offsetFactor);
    vec2 halfSizeCC = currentCursor.zw * 0.5;
    vec2 centerCP = previousCursor.xy - (previousCursor.zw * offsetFactor);

    float lineLength = distance(centerCC, centerCP);

    // Scaled by the longest side rather than the height: an underline cursor is a
    // cell wide and a couple of pixels tall, so scaling by height would put the
    // threshold below one character and smear every single-character step.
    float minDist = max(currentCursor.z, currentCursor.w) * THRESHOLD_MIN_DISTANCE;

    float baseProgress = iTime - iTimeCursorChange;

    // Apps that hide the cursor (btop, less, vim in some modes) still report a
    // position, and every repaint moves it. Trailing that draws long streaks the
    // user never caused, so a hidden cursor gets no trail at all.
    bool cursorLive = iCursorVisible > 0 && (FOCUSED_ONLY < 0.5 || iFocus > 0);

    if (!cursorLive || lineLength <= minDist || baseProgress >= DURATION - 0.001) {
        return;
    }

    vec2 vu = toShaderSpace(fragCoord, 1.);

    vec2 moveVec = centerCC - centerCP;
    vec2 s = sign(moveVec);

    // Keep a hard edge on horizontal/vertical moves; softening those makes the
    // trail pulse where it meets the cursor. 1e-4 rather than 0.0 keeps
    // smoothstep's two edges distinct instead of dividing by zero.
    float effectiveBlur = BLUR;
    if (BLUR < 2.5) {
        float isDiagonal = abs(s.x) * abs(s.y);
        effectiveBlur = mix(1e-4, BLUR, isDiagonal);
    }
    // Softness in normalised units, shared by the trail edge and the cursor restore.
    float aaWidth = 2.0 * effectiveBlur / iResolution.y;

    // Nothing is drawn outside the two cursor boxes and the span between them, but
    // the quad SDF below would still run for every pixel of the pane. Bounding it
    // first skips that; the test is uniform-derived, so whole wavefronts take the
    // same side and it costs no divergence. The thickness terms are floored at 1.0
    // because TRAIL_THICKNESS above 1.0 overflows the cursor box.
    vec2 thickness = vec2(max(TRAIL_THICKNESS_X, 1.0), max(TRAIL_THICKNESS, 1.0));
    vec2 pad = max(currentCursor.zw, previousCursor.zw) * thickness
             + vec2(aaWidth + EASE_OVERSHOOT * lineLength);
    vec2 bbMin = min(centerCC, centerCP) - pad;
    vec2 bbMax = max(centerCC, centerCP) + pad;
    if (any(lessThan(vu, bbMin)) || any(greaterThan(vu, bbMax))) {
        return;
    }

    // Corners of both cursor boxes, shrunk about their centres by TRAIL_THICKNESS*.
    float cc_half_height = currentCursor.w * 0.5;
    float cc_center_y = currentCursor.y - cc_half_height;
    float cc_new_half_height = cc_half_height * TRAIL_THICKNESS;
    float cc_new_top_y = cc_center_y + cc_new_half_height;
    float cc_new_bottom_y = cc_center_y - cc_new_half_height;

    float cc_half_width = currentCursor.z * 0.5;
    float cc_center_x = currentCursor.x + cc_half_width;
    float cc_new_half_width = cc_half_width * TRAIL_THICKNESS_X;
    float cc_new_left_x = cc_center_x - cc_new_half_width;
    float cc_new_right_x = cc_center_x + cc_new_half_width;

    vec2 cc_tl = vec2(cc_new_left_x, cc_new_top_y);
    vec2 cc_tr = vec2(cc_new_right_x, cc_new_top_y);
    vec2 cc_bl = vec2(cc_new_left_x, cc_new_bottom_y);
    vec2 cc_br = vec2(cc_new_right_x, cc_new_bottom_y);

    // previous cursor, same construction
    float cp_half_height = previousCursor.w * 0.5;
    float cp_center_y = previousCursor.y - cp_half_height;
    float cp_new_half_height = cp_half_height * TRAIL_THICKNESS;
    float cp_new_top_y = cp_center_y + cp_new_half_height;
    float cp_new_bottom_y = cp_center_y - cp_new_half_height;

    float cp_half_width = previousCursor.z * 0.5;
    float cp_center_x = previousCursor.x + cp_half_width;
    float cp_new_half_width = cp_half_width * TRAIL_THICKNESS_X;
    float cp_new_left_x = cp_center_x - cp_new_half_width;
    float cp_new_right_x = cp_center_x + cp_new_half_width;

    vec2 cp_tl = vec2(cp_new_left_x, cp_new_top_y);
    vec2 cp_tr = vec2(cp_new_right_x, cp_new_top_y);
    vec2 cp_bl = vec2(cp_new_left_x, cp_new_bottom_y);
    vec2 cp_br = vec2(cp_new_right_x, cp_new_bottom_y);

    // Plain floats, not const: max() in a const initializer is not portable, and
    // these fold at compile time regardless. The floor stops TRAIL_SIZE = 1.0
    // dividing by zero in the prog_* terms below.
    float DURATION_TRAIL = DURATION;
    float DURATION_LEAD = max(DURATION * (1.0 - TRAIL_SIZE), 1e-5);
    float DURATION_SIDE = (DURATION_LEAD + DURATION_TRAIL) / 2.0;

    float dot_tl = dot(vec2(-1., 1.), s);
    float dot_tr = dot(vec2( 1., 1.), s);
    float dot_bl = dot(vec2(-1.,-1.), s);
    float dot_br = dot(vec2( 1.,-1.), s);

    float dur_tl = getDurationFromDot(dot_tl, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);
    float dur_tr = getDurationFromDot(dot_tr, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);
    float dur_bl = getDurationFromDot(dot_bl, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);
    float dur_br = getDurationFromDot(dot_br, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);

    // On a rightward move the right edge leads. Give both its corners the
    // edge-averaged duration so it travels as one rigid vertical rail instead of
    // shearing (a diagonal move would otherwise give tr and br different speeds).
    // Mirrored for leftward moves; vertical-only moves use neither rail.
    float isMovingRight = step(0.5, s.x);
    float isMovingLeft  = step(0.5, -s.x);

    float dot_right_edge = (dot_tr + dot_br) * 0.5;
    float dur_right_rail = getDurationFromDot(dot_right_edge, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);

    float dot_left_edge = (dot_tl + dot_bl) * 0.5;
    float dur_left_rail = getDurationFromDot(dot_left_edge, DURATION_LEAD, DURATION_SIDE, DURATION_TRAIL);

    float final_dur_tl = mix(dur_tl, dur_left_rail, isMovingLeft);
    float final_dur_bl = mix(dur_bl, dur_left_rail, isMovingLeft);

    float final_dur_tr = mix(dur_tr, dur_right_rail, isMovingRight);
    float final_dur_br = mix(dur_br, dur_right_rail, isMovingRight);

    float prog_tl = ease(clamp(baseProgress / final_dur_tl, 0.0, 1.0));
    float prog_tr = ease(clamp(baseProgress / final_dur_tr, 0.0, 1.0));
    float prog_bl = ease(clamp(baseProgress / final_dur_bl, 0.0, 1.0));
    float prog_br = ease(clamp(baseProgress / final_dur_br, 0.0, 1.0));

    vec2 v_tl = mix(cp_tl, cc_tl, prog_tl);
    vec2 v_tr = mix(cp_tr, cc_tr, prog_tr);
    vec2 v_br = mix(cp_br, cc_br, prog_br);
    vec2 v_bl = mix(cp_bl, cc_bl, prog_bl);

    float sdfTrail = getSdfConvexQuad(vu, v_tl, v_tr, v_br, v_bl);

    vec4 trail = TRAIL_COLOR;

    float shapeAlpha = antialiasing(sdfTrail, aaWidth);

    if (FADE_ENABLED > 0.5) {
        // Where this fragment sits along the move: 0.0 at the previous cursor centre,
        // 1.0 at the current one. Anchored to those static endpoints rather than to the
        // animated quad, so the half-cell behind centerCP always fades out completely.
        vec2 fragVec = vu - centerCP;
        float fadeProgress = clamp(dot(fragVec, moveVec) / (dot(moveVec, moveVec) + 1e-6), 0.0, 1.0);
        trail.a *= pow(fadeProgress, FADE_EXPONENT);
    }

    // trail.a must reach the output alpha. Substituting newColor.a makes long
    // trails vanish over blank background -- iChannel0's alpha there is too low.
    float finalAlpha = trail.a * shapeAlpha;
    vec4 newColor = mix(fragColor, trail, finalAlpha);

    // Restore the cursor cell so the real cursor draws on top of the trail.
    // Feathered over the same width as the trail edge, so the diagonal moves that
    // soften one soften the other and no stair-stepped seam is left between them.
    // On the straight moves held at 1e-4 blur above this collapses back to a step.
    float sdfCurrentCursor = getSdfRectangle(vu, centerCC, halfSizeCC);
    newColor = mix(newColor, fragColor, 1.0 - smoothstep(-aaWidth, aaWidth, sdfCurrentCursor));

    fragColor = newColor;
}
