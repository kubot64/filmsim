#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// Must match FilmSimCore (FLog2.swift, ToneCurve.swift, Grain.swift)
// and research/filmsim (flog2.py, tone.py, grain.py).

constant float FL2_A = 5.555556f;
constant float FL2_B = 0.064829f;
constant float FL2_C = 0.245281f;
constant float FL2_D = 0.384316f;
constant float FL2_E = 8.799461f;
constant float FL2_F = 0.092864f;
constant float FL2_CUT1 = 0.000889f;

static inline float flog2(float x) {
    return x >= FL2_CUT1 ? FL2_C * log10(FL2_A * x + FL2_B) + FL2_D : FL2_E * x + FL2_F;
}

extern "C" {
    namespace coreimage {
        float4 flog2Encode(sample_t s) {
            float3 lin = max(s.rgb, 0.0f);
            return float4(clamp(float3(flog2(lin.r), flog2(lin.g), flog2(lin.b)), 0.0f, 1.0f), s.a);
        }

        // research/filmsim/tone.py — per channel, display-referred.
        float4 toneCurve(sample_t s, float highlight, float shadow) {
            float3 x = clamp(s.rgb, 0.0f, 1.0f);
            float3 outc = x;
            if (highlight != 0.0f) {
                float3 w = smoothstep(0.5f, 1.0f, x);
                float gamma = max(1.0f - 0.12f * highlight, 0.2f);
                outc = outc * (1.0f - w) + pow(x, gamma) * w;
            }
            if (shadow != 0.0f) {
                float3 w = 1.0f - smoothstep(0.0f, 0.5f, x);
                float gamma = max(1.0f + 0.12f * shadow, 0.2f);
                outc = outc * (1.0f - w) + pow(x, gamma) * w;
            }
            return float4(clamp(outc, 0.0f, 1.0f), s.a);
        }

        // research/filmsim/grain.py — `noise` is centered, std ≈ 1, in the red channel.
        float4 grainApply(sample_t image, sample_t noise, float amp) {
            float3 c = image.rgb;
            float lum = dot(c, float3(0.2126f, 0.7152f, 0.0722f));
            float l = clamp(lum, 0.0f, 1.0f);
            float weight = sqrt(l) * (1.0f - l) * 2.0f;
            return float4(clamp(c + noise.r * weight * amp, 0.0f, 1.0f), image.a);
        }
    }
}
