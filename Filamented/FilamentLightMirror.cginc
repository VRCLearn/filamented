#ifndef FILAMENT_LIGHT_MIRROR
#define FILAMENT_LIGHT_MIRROR
// Commmon code for sampling from VRC (or similar) mirrors systems.
//
// Use a mirror as the source for the reflection. Multiple samples taken for roughness.
// This is a rough approximation for performance's sake.
// Based on https://www.shadertoy.com/view/DtBXDt (CC0)

#if defined(MIRROR_REFLECTION)
    UNITY_DECLARE_TEX2D_FLOAT(_ReflectionTex0);
    UNITY_DECLARE_TEX2D_FLOAT(_ReflectionTex1);
#endif

class MirrorReflectionSampler
{
    // Calculate R2 for index i
    float2 getR2(float2 i) {
        return frac(i * float2(0.245122333753, 0.430159709002));
    }

    uint hilbert_idx(uint2 uv, uint offset)
    {
        // Hilbert curve:
        uint C = 0xB4361E9Cu;// cost lookup
        uint P = 0xEC7A9107u;// pattern lookup

        uv += uint(offset) * uint2(2447445397u, 3242174893u);

        uint c = 0u;// accumulated cost
        uint p = 0u;// current pattern

        const uint N = 7u;// tile size = 2^N
        for(uint i = N; --i < N;)
        {
            uint2 m = (uv >> i) & 1u;// local uv
            uint n = m.x ^ (m.y << 1u);// linearized local uv
            uint o = (p << 3u) ^ (n << 1u);// offset into lookup tables
            c += ((C >> o) & 3u) << (i << 1u);// accu cost (scaled by layer)
            p = (P >> o) & 3u;// update pattern
        }

        return c;
    }

    inline half4 getMirrorReflection(float2 screenCoord) {
        half4 refl = 0;
#if defined(MIRROR_REFLECTION)
        refl = (unity_StereoEyeIndex == 0)
            ? UNITY_SAMPLE_TEX2D(_ReflectionTex0, screenCoord)
            : UNITY_SAMPLE_TEX2D(_ReflectionTex1, screenCoord);
#endif // MIRROR_REFLECTION
        return refl;
    }

    inline half4 getFilteredMirrorRadiance(const ShadingParams shading, float roughness) {
        half4 refl = 0;
        half weight = 0;

#if defined(MIRROR_REFLECTION)
        float2 refSize;
        _ReflectionTex0.GetDimensions(refSize.x, refSize.y);

        // Since it's possible the user might not know the resolution will have
        // a big impact on performance, force a resolution scale.

        half  totalPixels = refSize.x * refSize.y;
        const half  minArea = 256.0 * 256.0;
        const half  maxArea = 1024.0 * 1024.0;
        half  resScale = saturate((totalPixels - minArea) / (maxArea - minArea));

        // If there is no mirror texture, exit.
        if (totalPixels <= 0) return 0;

        float3 normalOffset = shading.geometricNormal - shading.normal;
        half2 normalVS = mul((float3x3)UNITY_MATRIX_V, normalOffset);

        half2 screenCoord  = shading.normalizedViewportCoord;

        // At 256 or lower, do the full 64 samples and use a low roughness cutoff.
        // At 1024 or higher, perform only one sample and no roughness.

        half roughnessCutoff = lerp(0.1h, 0.01h, resScale);
        uint N = clamp(uint(lerp(64.0h, 1.0h, resScale)), 1, 64); // sample count
        half dmax = roughness * lerp(4.0h, 0.01h, resScale); // max blur distance

        if (roughness >= roughnessCutoff) return 0;

        float sigma = dmax / 2.5;
        sigma *= sigma;

        half idx = fmod(hilbert_idx(uint2(screenCoord * _ScreenParams.xy), 0), 100000.0h);
        half sampleMask = 1.0;

        [loop]
        for (uint i = 0.0; i < N; i++) {
            half2 uvoff = dmax * (getR2(half2(idx + i, idx + i + 1)) - 0.5);
            half bw = exp(-dot(uvoff, uvoff) / sigma);

            half2 sampleCoord = screenCoord + uvoff + normalVS;

            sampleMask *= 1.0 - length(saturate(sampleCoord) - sampleCoord) * bw;

            refl += bw * max(0, getMirrorReflection(sampleCoord));
            weight += bw;
        }

        refl /= weight;
        refl.a = 1 - saturate((roughness - MIN_ROUGHNESS) / roughnessCutoff) * sampleMask;
#endif // MIRROR_REFLECTION
        return max(0, refl);
    }
};
#endif // FILAMENT_LIGHT_MIRROR
