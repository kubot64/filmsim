#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// F-Log2 encode, per channel. Constants from the F-Log2 Data Sheet Ver.1.1.
// Must match FilmSimCore/FLog2.swift and research/filmsim/flog2.py.
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
    }
}
