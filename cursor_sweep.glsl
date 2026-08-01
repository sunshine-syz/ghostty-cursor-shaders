// ===========================================================================
// CONFIGURATION
// A streak appears already stretched behind the cursor, then sweeps forward and
// shrinks into it. Unlike cursor_tail, the head never moves.
// ===========================================================================

// Trail colour. iCurrentCursorColor follows Ghostty's cursor colour, and its
// alpha follows `cursor-opacity`. The alpha is load-bearing: it becomes the
// trail's output alpha, so 0.0 draws nothing. Override eg vec4(0.2,0.6,1.0,0.5).
vec4 TRAIL_COLOR = iCurrentCursorColor;

// Seconds for the streak to sweep in and vanish.
const float DURATION = 0.2;

// How much of the distance just travelled the streak covers when it first
// appears, 0..1. 1.0 reaches all the way back to where the cursor was, 0.0
// disables the streak. It shrinks to nothing from there.
const float TRAIL_LENGTH = 0.5;

// Minimum jump before any trail is drawn, in cursor heights. Raise to skip
// trails on short hops; 0.0 trails every movement.
const float THRESHOLD_MIN_DISTANCE = 1.5;

// Trail only the focused split. TUI apps that repaint on a timer (btop, watch,
// vim) move their own cursor while unfocused, and an unfocused surface renders
// only when its content changes -- it never runs the animation loop -- so that
// single frame leaves a fully-stretched streak frozen there until the next
// repaint. Set to 0.0 to trail every split.
const float FOCUSED_ONLY = 1.0;

// Edge softness in pixels.
const float BLUR = 1.5;

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

// // Linear
// float ease(float x) {
//     return x;
// }

// // EaseOutQuad
// float ease(float x) {
//     return 1.0 - (1.0 - x) * (1.0 - x);
// }

// EaseOutCubic
float ease(float x) {
    return 1.0 - pow(1.0 - x, 3.0);
}

// // EaseOutQuart
// float ease(float x) {
//     return 1.0 - pow(1.0 - x, 4.0);
// }

// // EaseOutQuint
// float ease(float x) {
//     return 1.0 - pow(1.0 - x, 5.0);
// }

// // EaseOutSine
// float ease(float x) {
//     return sin((x * PI) / 2.0);
// }

// // EaseOutExpo
// float ease(float x) {
//     return x == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * x);
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
//                     : pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * C4_ELASTIC) + 1.0;
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

float getSdfParallelogram(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);

    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

    return s * sqrt(d);
}

vec2 normalize(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

float antialising(float distance) {
	return 1. - smoothstep(0., normalize(vec2(BLUR, BLUR), 0.).x, distance);
}

// Which diagonal of the cursor box leads the move. This picks which two corners
// form the parallelogram's leading edge, so the trail shears the right way.
float getTopVertexFlag(vec2 a, vec2 b) {
    float condition1 = step(b.x, a.x) * step(a.y, b.y); // a.x < b.x && a.y > b.y
    float condition2 = step(a.x, b.x) * step(b.y, a.y); // a.x > b.x && a.y < b.y
    return 1.0 - max(condition1, condition2);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif

    // Everything below works in the shader's normalised space: y spans -1..1 over
    // the pane height, so a length of 2.0 is one full pane height.
    vec2 vu = normalize(fragCoord, 1.);
    vec2 offsetFactor = vec2(-.5, 0.5);

    vec4 currentCursor = vec4(normalize(iCurrentCursor.xy, 1.), normalize(iCurrentCursor.zw, 0.));
    vec4 previousCursor = vec4(normalize(iPreviousCursor.xy, 1.), normalize(iPreviousCursor.zw, 0.));

    vec2 centerCC = currentCursor.xy - (currentCursor.zw * offsetFactor);
    vec2 centerCP = previousCursor.xy - (previousCursor.zw * offsetFactor);

    float sdfCurrentCursor = getSdfRectangle(vu, centerCC, currentCursor.zw * 0.5);

     float lineLength = distance(centerCC, centerCP);

     vec4 newColor = vec4(fragColor);

     float minDist = currentCursor.w * THRESHOLD_MIN_DISTANCE;
     float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
     // Apps that hide the cursor (btop, less, vim in some modes) still report a
     // position, and every repaint moves it. Trailing that draws long streaks the
     // user never caused, so a hidden cursor gets no trail at all.
     bool cursorLive = iCursorVisible > 0 && (FOCUSED_ONLY < 0.5 || iFocus > 0);
     if (cursorLive && lineLength > minDist && progress < 1.0) {
         // 0 = streak at full TRAIL_LENGTH, 1 = fully collapsed into the cursor.
         float shrinkFactor = ease(progress);

        // Straight moves collapse the parallelogram to a rectangle, so they get their
        // own axis-aligned SDF; both are evaluated and selected between.
        vec2 delta = abs(centerCC - centerCP);
        float threshold = 0.001;
        float isHorizontal = step(delta.y, threshold);
        float isVertical = step(delta.x, threshold);
        float isStraightMove = max(isHorizontal, isVertical);

        // -- Diagonal move: parallelogram from the cursor back along the path --
        float topVertexFlag = getTopVertexFlag(currentCursor.xy, previousCursor.xy);
        float bottomVertexFlag = 1.0 - topVertexFlag;
        vec2 v0 = vec2(currentCursor.x + currentCursor.z * topVertexFlag, currentCursor.y - currentCursor.w);
        vec2 v1 = vec2(currentCursor.x + currentCursor.z * bottomVertexFlag, currentCursor.y);
        vec2 v2_full = vec2(previousCursor.x + currentCursor.z * bottomVertexFlag, previousCursor.y);
        vec2 v3_full = vec2(previousCursor.x + currentCursor.z * topVertexFlag, previousCursor.y - previousCursor.w);

        vec2 v2_start = mix(v1, v2_full, TRAIL_LENGTH);
        vec2 v3_start = mix(v0, v3_full, TRAIL_LENGTH);
        vec2 v2_anim = mix(v2_start, v1, shrinkFactor);
        vec2 v3_anim = mix(v3_start, v0, shrinkFactor);

        float sdfTrail_diag = getSdfParallelogram(vu, v0, v1, v2_anim, v3_anim);

        // -- Straight move: axis-aligned box, near edge pinned to the cursor --
        vec2 min_center = min(centerCP, centerCC);
        vec2 max_center = max(centerCP, centerCC);

        vec2 bBoxSize_full = (max_center - min_center) + currentCursor.zw;
        vec2 bBoxCenter_full = (min_center + max_center) * 0.5;

        vec2 bBoxSize_start = mix(currentCursor.zw, bBoxSize_full, TRAIL_LENGTH);
        vec2 bBoxCenter_start = mix(centerCC, bBoxCenter_full, TRAIL_LENGTH);

        vec2 animSize = mix(bBoxSize_start, currentCursor.zw, shrinkFactor);
        vec2 animCenter = mix(bBoxCenter_start, centerCC, shrinkFactor);

        float sdfTrail_rect = getSdfRectangle(vu, animCenter, animSize * 0.5);

        float sdfTrail = mix(sdfTrail_diag, sdfTrail_rect, isStraightMove);

        vec4 trail = TRAIL_COLOR;
        float trailAlpha = antialising(sdfTrail);
        // trail.a must reach the output alpha. Substituting newColor.a makes long
        // trails vanish over blank background -- iChannel0's alpha there is too low.
        newColor = mix(newColor, trail, trailAlpha);

        // Restore the cursor cell so the real cursor draws on top of the trail.
        newColor = mix(newColor, fragColor, step(sdfCurrentCursor, 0.));
    }


    fragColor = newColor;
}
