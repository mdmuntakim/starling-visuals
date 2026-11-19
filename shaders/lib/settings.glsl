// Starling Visuals 2: every option the pack exposes. The defaults are the HIGH profile, the
// one the game's Auto picks on a strong phone; profile.LOW in shaders.properties removes the
// expensive parts for a weaker device. Values are deliberately conservative on a phone: the
// pack spends its pixels on the world and the sky, not on deep sample counts.

// Sun and sky.
#define SUN_STRENGTH 2.6 // [1.5 2.0 2.6 3.0 3.4 3.8]
#define SKY_BRIGHTNESS 1.0 // [0.6 0.8 1.0 1.2 1.4]
#define SKY_SATURATION 1.05 // [0.8 0.9 1.0 1.05 1.1 1.2]
#define BLOCKLIGHT_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5]
#define EXPOSURE 0.85 // [0.5 0.6 0.7 0.8 0.85 0.9 1.0 1.2 1.4]
#define SATURATION 1.0 // [0.8 0.9 1.0 1.0 1.05 1.15 1.25]
#define CONTRAST 1.0 // [0.85 0.9 0.95 1.0 1.0 1.1 1.15 1.2]
#define WARMTH 0.0 // [-0.15 -0.08 0.0 0.08 0.15]
#define FOG_DENSITY 1.0 // [0.0 0.5 0.75 1.0 1.5 2.0 3.0]
#define FOG_HEIGHT 40.0 // [24.0 32.0 40.0 56.0 72.0]

// Shadows. shadowMapResolution and shadowDistance are the two options the game's Auto profile
// also caps, so they are const lines the loader can rewrite.
#define SHADOWS
const int shadowMapResolution = 1024; // [512 1024 2048 4096]
const float shadowDistance = 64.0; // [32.0 48.0 64.0 96.0 128.0]
const float sunPathRotation = -25.0; // [-40.0 -30.0 -25.0 -15.0 0.0 15.0 25.0]
const bool shadowHardwareFiltering = true;
#define SHADOW_DISTORTION 0.9 // [0.0 0.7 0.85 0.9 0.93]
#define SHADOW_FILTER 4 // [1 4]
#define SHADOW_SOFTNESS 1.2 // [0.5 0.8 1.2 1.6 2.4]

// The air and the lens.
#define GODRAYS
#define GODRAYS_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define GODRAYS_SAMPLES 12 // [6 10 12 16]
#define BLOOM
#define BLOOM_STRENGTH 0.08 // [0.03 0.05 0.08 0.12 0.16]
#define BLOOM_THRESHOLD 0.8 // [0.4 0.6 0.8 1.0 1.2]

// Screen-space contact shadows and the extra surface response.
#define SSAO
#define SSAO_STRENGTH 0.7 // [0.0 0.35 0.55 0.7 0.85 1.0]
#define SSAO_SAMPLES 8 // [4 8 12]
#define SPECULAR
#define WATER_WAVES

// The world itself.
#define WAVING_PLANTS
#define EMISSIVE_BLOCKS
#define HAND_LIGHT
#define UNDERWATER_CAUSTICS

// The night sky.
#define STARS
#define AURORA
#define AURORA_STRENGTH 0.4 // [0.0 0.2 0.4 0.6 0.8]

// The lens, at the very end.
#define COLOR_GRADE
#define SHARPEN
#define SHARPEN_STRENGTH 0.2 // [0.0 0.1 0.2 0.3 0.4]
#define VIGNETTE
#define VIGNETTE_STRENGTH 0.22 // [0.0 0.08 0.16 0.22 0.3 0.4]
#define FILM_GRAIN
#define GRAIN_STRENGTH 0.018 // [0.0 0.008 0.018 0.03 0.05]
#define TONEMAP 1 // [0 1 2]

// A torch or another glowing block in the hand lights around the player.
