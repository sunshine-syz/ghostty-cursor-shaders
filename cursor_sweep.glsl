// ===========================================================================
// CONFIGURATION
// A streak appears already stretched behind the cursor, then sweeps forward and
// shrinks into it. Unlike cursor_tail, the head never moves.
// ===========================================================================

// Trail colour. iCurrentCursorColor follows Ghostty's cursor colour, and its
// alpha follows `cursor-opacity`. The alpha is load-bearing: it scales the
// trail's coverage, so 0.0 draws nothing. Override eg vec4(0.2,0.6,1.0,0.5).
vec4 TRAIL_COLOR = iCurrentCursorColor;

// Seconds for the streak to sweep in and vanish.
const float DURATION = 0.2;

// How much of the distance just travelled the streak covers when it first
// appears, 0..1. 1.0 reaches all the way back to where the cursor was, 0.0
// disables the streak. It shrinks to nothing from there.
const float TRAIL_LENGTH = 0.5;

// Minimum jump before any trail is drawn, in cursor cells. Raise to skip trails
// on short hops; 0.0 trails every movement.
const float THRESHOLD_MIN_DISTANCE = 1.5;

// Trail only the focused split. TUI apps that repaint on a timer (btop, watch,
// vim) move their own cursor while unfocused, and an unfocused surface renders
// only when its content changes -- it never runs the animation loop -- so that
// single frame leaves a fully-stretched streak frozen there until the next
// repaint. Set to 0.0 to trail every split.
const float FOCUSED_ONLY = 1.0;

// Edge softness in pixels.
const float BLUR = 1.5;

// Fade the trail out towards its tail; 0.0 disables it for flat opacity.
// Off by default here -- cursor_warp ships it on, this shader has always drawn a
// flat streak, and the two look different enough to be worth choosing between.
const float FADE_ENABLED = 0.0;
// Fade curve. Below 1.0 holds most of the trail opaque and fades only near the
// tail (0.5 = square root); above 1.0 leaves just a bright stub at the cursor.
const float FADE_EXPONENT = 0.5;

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
// This shader clamps the result to 0..1 (see mainImage), so the overshooting
// variants -- Back, Elastic, Spring -- lose their overshoot here and read as
// their plain counterparts. That is deliberate: the streak's geometry is a
// collapse *into* the cursor box, and a factor above 1.0 drives the back edge
// out the far side, crossing the parallelogram into a flickering bowtie. Use
// cursor_tail or cursor_warp if you want springiness.

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
// undefined for a negative base.
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

// Parametric Spring
// float ease(float x) {
//     x = clamp(x, 0.0, 1.0);
//     float decay = exp(-SPRING_DAMPING * SPRING_STIFFNESS * x);
//     float freq = sqrt(SPRING_STIFFNESS * (1.0 - SPRING_DAMPING * SPRING_DAMPING));
//     float osc = cos(freq * 6.283185 * x) + (SPRING_DAMPING * sqrt(SPRING_STIFFNESS) / freq) * sin(freq * 6.283185 * x);
//     return 1.0 - decay * osc;
// }

float getSdfRectangle(in vec2 point, in vec2 center, in vec2 halfSize)
{
    vec2 d = abs(point - center) - halfSize;
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
float getSdfParallelogram(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);

    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

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

// Which diagonal of the cursor box leads the move. This picks which two corners
// form the parallelogram's leading edge, so the trail shears the right way.
float isTopRightLeading(vec2 a, vec2 b) {
    float condition1 = step(b.x, a.x) * step(a.y, b.y); // a.x >= b.x && a.y <= b.y
    float condition2 = step(a.x, b.x) * step(b.y, a.y); // a.x <= b.x && a.y >= b.y
    return 1.0 - max(condition1, condition2);
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
    vec2 centerCP = previousCursor.xy - (previousCursor.zw * offsetFactor);

    float lineLength = distance(centerCC, centerCP);

    // Scaled by the longest side rather than the height: an underline cursor is a
    // cell wide and a couple of pixels tall, so scaling by height would put the
    // threshold below one character and smear every single-character step.
    float minDist = max(currentCursor.z, currentCursor.w) * THRESHOLD_MIN_DISTANCE;

    float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);

    // Apps that hide the cursor (btop, less, vim in some modes) still report a
    // position, and every repaint moves it. Trailing that draws long streaks the
    // user never caused, so a hidden cursor gets no trail at all.
    bool cursorLive = iCursorVisible > 0 && (FOCUSED_ONLY < 0.5 || iFocus > 0);

    // TRAIL_LENGTH 0.0 has to be rejected rather than drawn: it collapses the
    // parallelogram's back edge onto its front, and seg() divides by the edge
    // vector -- a NaN that survives every later mix(), not an empty trail.
    if (!cursorLive || TRAIL_LENGTH <= 0.0 || lineLength <= minDist || progress >= 1.0) {
        return;
    }

    vec2 vu = toShaderSpace(fragCoord, 1.);

    // Softness in normalised units, shared by the trail edge and the cursor restore.
    float aaWidth = 2.0 * BLUR / iResolution.y;

    // Nothing is drawn outside the two cursor boxes and the span between them, but
    // the SDF below would still run for every pixel of the pane. Bounding it first
    // skips that; the test is uniform-derived, so whole wavefronts take the same
    // side and it costs no divergence. Padding by the full box rather than the
    // half covers the mixed-size vertices below, which pair one cursor's position
    // with the other's width.
    vec2 pad = max(currentCursor.zw, previousCursor.zw) + vec2(aaWidth);
    vec2 bbMin = min(centerCC, centerCP) - pad;
    vec2 bbMax = max(centerCC, centerCP) + pad;
    if (any(lessThan(vu, bbMin)) || any(greaterThan(vu, bbMax))) {
        return;
    }

    // 0 = streak at full TRAIL_LENGTH, 1 = fully collapsed into the cursor.
    // Clamped because an overshooting ease would drive the back edge past the
    // front and cross the parallelogram -- see the easing header.
    float shrinkFactor = clamp(ease(progress), 0.0, 1.0);

    // Straight moves collapse the parallelogram to a rectangle, so they get their
    // own axis-aligned SDF. Which one applies depends only on the cursor
    // positions, so this branch is uniform across the frame and skips the
    // four-segment polygon walk outright on the common terminal motions.
    vec2 delta = abs(centerCC - centerCP);
    float threshold = 0.001;
    bool isStraightMove = delta.x <= threshold || delta.y <= threshold;

    float sdfTrail;
    if (isStraightMove) {
        // -- Straight move: axis-aligned box, near edge pinned to the cursor --
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
        // -- Diagonal move: parallelogram from the cursor back along the path --
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

        sdfTrail = getSdfParallelogram(vu, v0, v1, v2_anim, v3_anim);
    }

    vec4 trail = TRAIL_COLOR;

    if (FADE_ENABLED > 0.5) {
        // Where this fragment sits along the streak: 0.0 at its back edge, 1.0 at
        // the cursor. Anchored to the animated tail rather than centerCP so the
        // whole gradient stays inside the shape as it collapses -- with the static
        // endpoint the tail would sit partway up the ramp and never reach zero.
        vec2 tailCenter = mix(mix(centerCC, centerCP, TRAIL_LENGTH), centerCC, shrinkFactor);
        vec2 fadeAxis = centerCC - tailCenter;
        float fadeProgress = clamp(dot(vu - tailCenter, fadeAxis) / (dot(fadeAxis, fadeAxis) + 1e-6), 0.0, 1.0);
        trail.a *= pow(fadeProgress, FADE_EXPONENT);
    }

    // trail.a scales coverage as well as reaching the output alpha, so
    // `cursor-opacity` shows text through the trail -- matching cursor_warp.
    // Substituting newColor.a for it makes long trails vanish over blank
    // background: iChannel0's alpha there is too low.
    float trailAlpha = antialiasing(sdfTrail, aaWidth) * trail.a;
    vec4 newColor = mix(fragColor, trail, trailAlpha);

    // Restore the cursor cell so the real cursor draws on top of the trail.
    // Feathered on diagonal moves, where a hard step against the trail's own soft
    // edge leaves a stair-stepped seam. Kept hard on straight moves: there the two
    // edges are collinear, and softening both stacks their ramps into a visible
    // line. 1e-6 rather than 0.0 keeps smoothstep's edges distinct.
    float sdfCurrentCursor = getSdfRectangle(vu, centerCC, currentCursor.zw * 0.5);
    float restoreWidth = isStraightMove ? 1e-6 : aaWidth;
    newColor = mix(newColor, fragColor, 1.0 - smoothstep(-restoreWidth, restoreWidth, sdfCurrentCursor));

    fragColor = newColor;
}
