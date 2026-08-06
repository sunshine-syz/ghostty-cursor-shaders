// ===========================================================================
// CONFIGURATION
// A streak with a head and a tail chases the cursor. On short moves the head
// jumps to the destination and the tail closes in; on long moves the head eases
// across while the tail lags, holding the streak at MAX_TRAIL_LENGTH.
// ===========================================================================

// Trail colour. iCurrentCursorColor follows Ghostty's cursor colour, and its
// alpha follows `cursor-opacity`. The alpha is load-bearing: it scales the
// trail's coverage, so 0.0 draws nothing. Override eg vec4(0.2,0.6,1.0,0.5).
vec4 TRAIL_COLOR = iCurrentCursorColor;

// Seconds for the streak to collapse back into the cursor.
const float DURATION = 0.1;

// Longest gap held between head and tail, in normalised units where 2.0 is one
// full pane height -- so 0.25 is about an eighth of the pane. Note this is
// pane-relative, unlike THRESHOLD_MIN_DISTANCE below, so it scales with window
// size rather than font size. Moves shorter than this drag their whole length.
const float MAX_TRAIL_LENGTH = 0.25;

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
// tail (0.5 = square root); above 1.0 leaves just a bright stub at the head.
const float FADE_EXPONENT = 0.5;

// Headroom for eases that return values above 1.0, as a fraction of the distance
// moved. The trail is clipped to a box spanning the two cursor positions so the
// rest of the pane can skip the shape work; an overshooting ease puts the head
// outside that box and it would be cut off. 0.0 suits every ease that lands on
// 1.0 -- which the shipped default does -- and keeps the clip tightest.
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
// one, or the overshooting head is clipped where it leaves the bounding box.

// // Linear
// float ease(float x) {
//     return x;
// }

// // EaseOutQuad
// float ease(float x) {
//     float t = 1.0 - x;
//     return 1.0 - t * t;
// }

// // EaseOutCubic
// float ease(float x) {
//     float t = 1.0 - x;
//     return 1.0 - t * t * t;
// }

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

// EaseOutCirc -- squares by multiplication because pow() is undefined for a
// negative base, which x - 1.0 is for all x < 1.
float ease(float x) {
    float t = x - 1.0;
    return sqrt(1.0 - t * t);
}

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

    float lineLength = distance(centerCP, centerCC);

    // Scaled by the longest side rather than the height: an underline cursor is a
    // cell wide and a couple of pixels tall, so scaling by height would put the
    // threshold below one character and smear every single-character step.
    float minDist = max(currentCursor.z, currentCursor.w) * THRESHOLD_MIN_DISTANCE;

    float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);

    // Apps that hide the cursor (btop, less, vim in some modes) still report a
    // position, and every repaint moves it. Trailing that draws long streaks the
    // user never caused, so a hidden cursor gets no trail at all.
    bool cursorLive = iCursorVisible > 0 && (FOCUSED_ONLY < 0.5 || iFocus > 0);

    if (!cursorLive || lineLength <= minDist || progress >= 1.0) {
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
    vec2 pad = max(currentCursor.zw, previousCursor.zw)
             + vec2(aaWidth + EASE_OVERSHOOT * lineLength);
    vec2 bbMin = min(centerCC, centerCP) - pad;
    vec2 bbMax = max(centerCC, centerCP) + pad;
    if (any(lessThan(vu, bbMin)) || any(greaterThan(vu, bbMax))) {
        return;
    }

    // Fraction of the animation the tail waits before setting off, so the gap
    // settles near MAX_TRAIL_LENGTH. Capped below 1.0 because on short moves it
    // exceeds 1.0, and smoothstep with edge0 > edge1 is undefined -- a NaN would
    // survive the mix below even though that branch is discarded.
    float tail_delay_factor = min(MAX_TRAIL_LENGTH / lineLength, 0.999);

    float isLongMove = step(MAX_TRAIL_LENGTH, lineLength);

    // Long move: head eases across, tail lags to hold the streak length.
    float head_eased_long = ease(progress);
    float tail_eased_long = ease(smoothstep(tail_delay_factor, 1.0, progress));
    // Short move: head is already there, tail eases in to close the gap.
    float head_eased_short = 1.0;
    float tail_eased_short = ease(progress);

    float head_eased = mix(head_eased_short, head_eased_long, isLongMove);
    float tail_eased = mix(tail_eased_short, tail_eased_long, isLongMove);

    vec2 head_center = mix(centerCP, centerCC, head_eased);
    vec2 tail_center = mix(centerCP, centerCC, tail_eased);

    // Straight moves collapse the parallelogram to a rectangle, so they get their
    // own axis-aligned SDF. Which one applies depends only on the cursor
    // positions, so this branch is uniform across the frame and skips the
    // four-segment polygon walk outright on the common terminal motions.
    vec2 delta_abs = abs(centerCC - centerCP);
    float threshold = 0.001;
    bool isStraightMove = delta_abs.x <= threshold || delta_abs.y <= threshold;

    float sdfTrail;
    if (isStraightMove) {
        // -- Straight move: axis-aligned box spanning head to tail --
        vec2 min_center = min(head_center, tail_center);
        vec2 max_center = max(head_center, tail_center);

        vec2 box_size = (max_center - min_center) + currentCursor.zw;
        vec2 box_center = (min_center + max_center) * 0.5;

        sdfTrail = getSdfRectangle(vu, box_center, box_size * 0.5);
    } else {
        // -- Diagonal move: parallelogram between the head and tail boxes --
        vec2 head_pos_tl = mix(previousCursor.xy, currentCursor.xy, head_eased);
        vec2 tail_pos_tl = mix(previousCursor.xy, currentCursor.xy, tail_eased);

        float topRightLeads = isTopRightLeading(currentCursor.xy, previousCursor.xy);
        float bottomLeftLeads = 1.0 - topRightLeads;

        // The tail's height follows its own progress. Holding it at the previous
        // cursor's height instead leaves a sliver at the back once the tail has
        // arrived -- visible whenever the cursor resizes mid-move, as vim's
        // insert/normal flip does -- which then pops off in a single frame.
        float tailHeight = mix(previousCursor.w, currentCursor.w, tail_eased);

        // v0, v1 : "front" of the trail (head)
        vec2 v0 = vec2(head_pos_tl.x + currentCursor.z * topRightLeads, head_pos_tl.y - currentCursor.w);
        vec2 v1 = vec2(head_pos_tl.x + currentCursor.z * bottomLeftLeads, head_pos_tl.y);

        // v2, v3: "back" of the trail (tail)
        vec2 v2 = vec2(tail_pos_tl.x + currentCursor.z * bottomLeftLeads, tail_pos_tl.y);
        vec2 v3 = vec2(tail_pos_tl.x + currentCursor.z * topRightLeads, tail_pos_tl.y - tailHeight);

        sdfTrail = getSdfParallelogram(vu, v0, v1, v2, v3);
    }

    vec4 trail = TRAIL_COLOR;

    if (FADE_ENABLED > 0.5) {
        // Where this fragment sits along the streak: 0.0 at the tail, 1.0 at the
        // head. Anchored to the animated pair rather than the static endpoints so
        // the gradient always spans the visible shape -- the streak covers only
        // part of the move for most of its life.
        vec2 fadeAxis = head_center - tail_center;
        float fadeProgress = clamp(dot(vu - tail_center, fadeAxis) / (dot(fadeAxis, fadeAxis) + 1e-6), 0.0, 1.0);
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
