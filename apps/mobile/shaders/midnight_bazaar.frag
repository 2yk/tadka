#version 460 core

#include <flutter/runtime_effect.glsl>

// The "Midnight Bazaar" living sky — a slow silk-smoke swirl in the game's locked palette,
// with brass lantern-light pooling low and a sparse drift of embers. Five warp folds keep a
// full-screen pass trivial for a phone GPU.

uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;

out vec4 fragColor;

const vec3 kMidnight = vec3(0.090, 0.078, 0.149); // #171426
const vec3 kAwning   = vec3(0.141, 0.122, 0.220); // #241F38
const vec3 kUmami    = vec3(0.557, 0.353, 0.659); // #8E5AA8
const vec3 kBrass    = vec3(0.851, 0.643, 0.255); // #D9A441

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  vec2 p = (frag - 0.5 * uSize) / uSize.y;
  float t = uTime * 0.055;

  // Silk warp: fold space through rotated sine fields; `a` is the accumulated swirl.
  vec2 q = p * 2.1;
  float a = 0.0;
  mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
  for (int i = 0; i < 5; i++) {
    q = rot * q;
    q += 0.34 * vec2(
      sin(q.y * 1.35 + t * (1.0 + 0.33 * float(i))),
      cos(q.x * 1.22 - t * (1.4 + 0.27 * float(i)))
    );
    a += sin(q.x + q.y);
  }
  float swirl = a / 5.0;
  float s = 0.5 + 0.5 * swirl;

  // Night base lifting into awning-purple silk.
  vec3 col = mix(kMidnight * 0.82, kAwning * 1.06, smoothstep(0.18, 0.86, s));
  // Umami bloom where the folds run brightest.
  col = mix(col, kUmami * 0.40, smoothstep(0.62, 0.97, s) * 0.50 * uIntensity);
  // Brass lantern-glow pooling toward the bottom of the screen.
  float warm = smoothstep(0.45, 1.25, uv.y) * smoothstep(0.95, 0.15, abs(swirl));
  col = mix(col, kBrass * 0.30, warm * 0.45 * uIntensity);

  // Sparse rising embers: one faint mote per ~100px grid cell, few cells lit.
  vec2 g = frag / uSize.y + vec2(0.0, uTime * 0.016);
  vec2 cell = floor(g * 9.0);
  vec2 cellUv = fract(g * 9.0) - 0.5;
  vec2 jitter = vec2(hash(cell) - 0.5, hash(cell + 19.7) - 0.5) * 0.7;
  float lit = step(0.965, hash(cell + 4.2));
  float d = length(cellUv - jitter);
  float twinkle = 0.5 + 0.5 * sin(uTime * 0.9 + hash(cell) * 6.2831);
  col += kBrass * lit * smoothstep(0.045, 0.0, d) * (0.22 + 0.30 * twinkle) * uIntensity;

  // Vignette, so panels and cards stay the brightest things on screen.
  float vig = smoothstep(1.30, 0.30, length(p));
  col *= mix(0.78, 1.0, vig);

  fragColor = vec4(col, 1.0);
}
