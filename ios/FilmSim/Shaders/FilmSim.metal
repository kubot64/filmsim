#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// Must match FilmSimCore (FLog2.swift, HighlightShoulder.swift, WarmHue.swift, ToneCurve.swift, Grain.swift)
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

        // research/filmsim/tone.py x_series_shoulder — lifts luma above 0.6 toward luma^0.5,
        // scales RGB by the luma ratio so hue stays put. Below 0.6 and at 1.0 nothing moves.
        float4 xSeriesShoulder(sample_t s) {
            float3 c = clamp(s.rgb, 0.0f, 1.0f);
            float y = dot(c, float3(0.2126f, 0.7152f, 0.0722f));
            if (y <= 1e-6f) { return float4(c, s.a); }
            float w = smoothstep(0.6f, 1.0f, y);
            float lifted = y * (1.0f - w) + sqrt(y) * w;
            return float4(clamp(c * (lifted / y), 0.0f, 1.0f), s.a);
        }

        // research/filmsim/hue.py x_series_warm_hue — Provia only. Turns the BT.709 Cb/Cr angle
        // by up to -7 deg around 140 deg (raised cosine, width 80); Y' and chroma length stay put.
        float4 xSeriesWarmHue(sample_t s) {
            float3 c = clamp(s.rgb, 0.0f, 1.0f);
            const float kr = 0.2126f, kb = 0.0722f, kg = 1.0f - kr - kb;
            const float cbScale = 2.0f * (1.0f - kb), crScale = 2.0f * (1.0f - kr);
            float y = kr * c.r + kg * c.g + kb * c.b;
            float cb = (c.b - y) / cbScale;
            float cr = (c.r - y) / crScale;
            // Greys have no hue; atan2(0, 0) is NaN under fast math, and rotating nothing is a no-op.
            if (cb * cb + cr * cr < 1e-12f) { return float4(c, s.a); }
            float d = atan2(cr, cb) * (180.0f / M_PI_F) - 140.0f;
            d = d - 360.0f * floor((d + 180.0f) / 360.0f);
            if (fabs(d) >= 80.0f) { return float4(c, s.a); }
            float t = -7.0f * (M_PI_F / 180.0f) * 0.5f * (1.0f + cos(M_PI_F * d / 80.0f));
            float ct = cos(t), st = sin(t);
            float cb2 = cb * ct - cr * st;
            float cr2 = cb * st + cr * ct;
            float r = y + crScale * cr2;
            float b = y + cbScale * cb2;
            float g = (y - kr * r - kb * b) / kg;
            return float4(clamp(float3(r, g, b), 0.0f, 1.0f), s.a);
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
