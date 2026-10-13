// CONFIGURATION
const float DURATION = 0.15;               // How long the pulse animates (seconds)
const float MAX_RADIUS = 0.06;             // Max radius in shader space (0.5 = 1/4 pane height)
const float ANIMATION_START_OFFSET = 0.0;        // Start the pulse slightly progressed (0.0 - 1.0)
vec4 COLOR = iCurrentCursorColor;         // Cursor color. Or a fixed color, vec4(0.35, 0.36, 0.44, 1.0), or a theme color, vec4(iPalette[4], 1.0)
const float CURSOR_WIDTH_CHANGE_THRESHOLD = 0.5; // Pulse if the width changes by more than this fraction of the larger width. Below 0.5, moves onto or off a wide character also pulse
const float BLUR = 3.0;                    // Blur level in pixels


// Easing functions. pow() is undefined for a negative base, so use
// multiplication there.
float easeOutQuad(float t) {
    return 1.0 - (1.0 - t) * (1.0 - t);
}
float easeInOutQuad(float t) {
    return t < 0.5 ? 2.0 * t * t : 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0;
}
float easeOutCubic(float t) {
    return 1.0 - pow(1.0 - t, 3.0);
}
float easeOutQuart(float t) {
    return 1.0 - pow(1.0 - t, 4.0);
}
float easeOutQuint(float t) {
    return 1.0 - pow(1.0 - t, 5.0);
}
float easeOutExpo(float t) {
    return t == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * t);
}
float easeOutCirc(float t) {
    float u = t - 1.0;
    return sqrt(1.0 - u * u);
}
float easeOutSine(float t) {
    return sin((t * 3.14159265) / 2.0);
}
float easeOutElastic(float t) {
    const float c4 = (2.0 * 3.14159265) / 3.0;
    return t == 0.0 ? 0.0 : t == 1.0 ? 1.0 : pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * c4) + 1.0;
}
float easeOutBounce(float t) {
    const float n1 = 7.5625;
    const float d1 = 2.75;
    if (t < 1.0 / d1) {
        return n1 * t * t;
    } else if (t < 2.0 / d1) {
        return n1 * (t -= 1.5 / d1) * t + 0.75;
    } else if (t < 2.5 / d1) {
        return n1 * (t -= 2.25 / d1) * t + 0.9375;
    } else {
        return n1 * (t -= 2.625 / d1) * t + 0.984375;
    }
}
float easeOutBack(float t) {
    const float c1 = 1.70158;
    const float c3 = c1 + 1.0;
    float u = t - 1.0;
    return 1.0 + c3 * u * u * u + c1 * u * u;
}

// Pulse fade functions
float smoothstepPulse(float t) {
    return 4.0 * t * (1.0 - t);
}
float easeOutPulse(float t) {
    return t * (2.0 - t);
}
float powerCurvePulse(float t) {
    float x = t * 2.0 - 1.0;
    return 1.0 - x * x;
}
float doubleSmoothstepPulse(float t) {
    return smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(0.5, 1.0, t));
}
float exponentialDecayPulse(float t) {
    return exp(-3.0 * t) * sin(t * 3.14159265);
}
float sinPulse(float t) {
    return sin(t * 3.14159265);
}

// Converts pixels to shader space, where y is -1..1 over the pane height.
// isPosition 1.0 moves the origin to the pane center. 0.0 converts a size.
vec2 toShaderSpace(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #else
    // fragColor is read below, so it must have a value.
    fragColor = vec4(0.0);
    #endif

    vec2 vu = toShaderSpace(fragCoord, 1.);
    vec2 offsetFactor = vec2(-.5, 0.5);

    vec4 currentCursor = vec4(toShaderSpace(iCurrentCursor.xy, 1.), toShaderSpace(iCurrentCursor.zw, 0.));
    vec2 centerCC = currentCursor.xy - (currentCursor.zw * offsetFactor);

    // A move onto or off a wide character doubles or halves the width: a
    // change of exactly 0.5 of the larger width. Pixel widths are whole
    // numbers, so the test is exact, and at 0.5 the strict > skips the move.
    // Ghostty fills iPreviousCursor with zeros until the cursor first moves.
    float widthChange = abs(iCurrentCursor.z - iPreviousCursor.z);
    bool isModeChange = iPreviousCursor.z > 0.0
        && widthChange > max(iCurrentCursor.z, iPreviousCursor.z) * CURSOR_WIDTH_CHANGE_THRESHOLD;

    // ANIMATION
    float rippleProgress = (iTime - iTimeCursorChange) / DURATION + ANIMATION_START_OFFSET;

    // Losing focus turns the cursor into a hollow block, and gaining focus
    // turns it back. From a bar cursor, the width test sees both as mode
    // changes. An unfocused split also stops animating, so a pulse there
    // freezes. On focus gain, Ghostty sets iTimeFocus and iTimeCursorChange in
    // the same frame, and 0.05 s allows a few frames of skew. A hidden cursor
    // gets no pulse.
    bool cursorLive = iCursorVisible > 0 && iFocus > 0
        && abs(iTimeCursorChange - iTimeFocus) > 0.05;

    if (cursorLive && isModeChange && rippleProgress < 1.0) {
        // float easedProgress = rippleProgress;
        // float easedProgress = easeOutQuad(rippleProgress);
        // float easedProgress = easeInOutQuad(rippleProgress);
        // float easedProgress = easeOutCubic(rippleProgress);
        // float easedProgress = easeOutQuart(rippleProgress);
        // float easedProgress = easeOutQuint(rippleProgress);
        // float easedProgress = easeOutExpo(rippleProgress);
        float easedProgress = easeOutCirc(rippleProgress);
        // float easedProgress = easeOutSine(rippleProgress);
        // float easedProgress = easeOutBack(rippleProgress);

        // easedProgress = clamp(easedProgress, 0.0, 1.0);

        // RIPPLE CALCULATION
        float rippleRadius = easedProgress * MAX_RADIUS;
        
        // float fade = 1.0; // no fade
        // float fade = 1.0 - easedProgress; // linear fade
        // float fade = 1.0 - smoothstepPulse(rippleProgress);
        float fade = 1.0 - easeOutPulse(rippleProgress);
        // float fade = 1.0 - powerCurvePulse(rippleProgress);
        // float fade = doubleSmoothstepPulse(rippleProgress);
        // float fade = exponentialDecayPulse(rippleProgress);
        // float fade = sinPulse(rippleProgress);
        
        float dist = distance(vu, centerCC);
        
        float sdfCircle = dist - rippleRadius;
        
        // max() keeps the smoothstep edges different when BLUR is 0.0.
        float antiAliasSize = toShaderSpace(vec2(max(BLUR, 1e-4)), 0.0).x;
        float ripple = (1.0 - smoothstep(-antiAliasSize, antiAliasSize, sdfCircle)) * fade;

        // COLOR.a scales the coverage. Blend toward alpha 1.0, not COLOR.a: a
        // second COLOR.a makes the pulse too transparent on a translucent
        // window.
        fragColor = mix(fragColor, vec4(COLOR.rgb, 1.0), ripple * COLOR.a);
    }
}
