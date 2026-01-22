#ifndef COMMON_LIGHTMAP_INCLUDED
#define COMMON_LIGHTMAP_INCLUDED

#include "SharedSHLib.hlsl"

half4 UnityLightmap_ColorIntensitySeperated(half3 lightmap) {
    lightmap += 0.000001;
    return float4(lightmap.xyz / 1, 1);
}

half4 SampleLightmapBicubic(float2 uv)
{
    #if defined(SHADER_API_D3D11)
        float width, height;
        unity_Lightmap.GetDimensions(width, height);

        float4 unity_Lightmap_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        return SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap),
            uv, unity_Lightmap_TexelSize);
    #else
        return SAMPLE_TEXTURE2D(unity_Lightmap, samplerunity_Lightmap, uv);
    #endif
}

half4 SampleLightmapDirBicubic(float2 uv)
{
    // We don't need to sample the directionality with bicubic filtering
    #if defined(SHADER_API_D3D11) && false
        float width, height;
        unity_LightmapInd.GetDimensions(width, height);

        float4 unity_LightmapInd_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        return SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(unity_LightmapInd, samplerunity_Lightmap),
            uv, unity_LightmapInd_TexelSize);
    #else
        return SAMPLE_TEXTURE2D(unity_LightmapInd, samplerunity_Lightmap, uv);
    #endif
}

half4 SampleDynamicLightmapBicubic(float2 uv)
{
    #if defined(SHADER_API_D3D11)
        float width, height;
        unity_DynamicLightmap.GetDimensions(width, height);

        float4 unity_DynamicLightmap_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        return SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(unity_DynamicLightmap, samplerunity_DynamicLightmap),
            uv, unity_DynamicLightmap_TexelSize);
    #else
        return SAMPLE_TEXTURE2D(unity_DynamicLightmap, samplerunity_DynamicLightmap, uv);
    #endif
}

half4 SampleDynamicLightmapDirBicubic(float2 uv)
{
    // We don't need to sample the directionality with bicubic filtering
    #if defined(SHADER_API_D3D11) && false
        float width, height;
        unity_DynamicDirectionality.GetDimensions(width, height);

        float4 unity_DynamicDirectionality_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        return SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(unity_DynamicDirectionality, samplerunity_DynamicLightmap),
            uv, unity_DynamicDirectionality_TexelSize);
    #else
        return SAMPLE_TEXTURE2D(unity_DynamicDirectionality, samplerunity_DynamicLightmap, uv);
    #endif
}

inline half3 DecodeDirectionalLightmapSpecular(half3 color, half4 dirTex, half3 normalWorld,
    const bool isRealtimeLightmap, fixed4 realtimeNormalTex, out Light o_light)
{
    o_light = (Light)0;
    o_light.colorIntensity = float4(color, 1.0);
    o_light.l = dirTex.xyz * 2 - 1;

    // The length of the direction vector is the light's "directionality", i.e. 1 for all light coming from this direction,
    // lower values for more spread out, ambient light.
    half directionality = max(0.001, length(o_light.l));
    o_light.l /= directionality;

    #ifdef DYNAMICLIGHTMAP_ON
    if (isRealtimeLightmap)
    {
        // Realtime directional lightmaps' intensity needs to be divided by N.L
        // to get the incoming light intensity. Baked directional lightmaps are already
        // output like that (including the max() to prevent div by zero).
        half3 realtimeNormal = realtimeNormalTex.xyz * 2 - 1;
        o_light.colorIntensity /= max(0.125, dot(realtimeNormal, o_light.l));
    }
    #endif

    // Split light into the directional and ambient parts, according to the directionality factor.
    half3 ambient = o_light.colorIntensity * (1 - directionality);
    o_light.colorIntensity = o_light.colorIntensity * directionality;
    o_light.attenuation = directionality;

    o_light.NoL = saturate(dot(normalWorld, o_light.l));

    return color * lerp(1.0, o_light.NoL, directionality);
}

#if defined(USING_BAKERY) && defined(LIGHTMAP_ON)
// needs specular variant?
half3 DecodeRNMLightmap(half3 color, half2 lightmapUV, half3 normalTangent, float3x3 tangentToWorld, out Light o_light)
{
    const float rnmBasis0 = float3(0.816496580927726f, 0, 0.5773502691896258f);
    const float rnmBasis1 = float3(-0.4082482904638631f, 0.7071067811865475f, 0.5773502691896258f);
    const float rnmBasis2 = float3(-0.4082482904638631f, -0.7071067811865475f, 0.5773502691896258f);

    half3 irradiance;
    o_light = (Light)0;

    #if defined(SHADER_API_D3D11)
        float width, height;
        _RNM0.GetDimensions(width, height);

        float4 rnm_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        half3 rnm0 = DecodeLightmap(SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM0, sampler_RNM0), lightmapUV, rnm_TexelSize));
        half3 rnm1 = DecodeLightmap(SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM1, sampler_RNM0), lightmapUV, rnm_TexelSize));
        half3 rnm2 = DecodeLightmap(SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM2, sampler_RNM0), lightmapUV, rnm_TexelSize));
    #else
        half3 rnm0 = DecodeLightmap(SAMPLE_TEXTURE2D(_RNM0, sampler_RNM0, lightmapUV));
        half3 rnm1 = DecodeLightmap(SAMPLE_TEXTURE2D(_RNM1, sampler_RNM0, lightmapUV));
        half3 rnm2 = DecodeLightmap(SAMPLE_TEXTURE2D(_RNM2, sampler_RNM0, lightmapUV));
    #endif

    normalTangent.g *= -1;

    irradiance =  saturate(dot(rnmBasis0, normalTangent)) * rnm0
                + saturate(dot(rnmBasis1, normalTangent)) * rnm1
                + saturate(dot(rnmBasis2, normalTangent)) * rnm2;

    #if defined(LIGHTMAP_SPECULAR)
    float3 dominantDirT = rnmBasis0 * luminance(rnm0) +
                          rnmBasis1 * luminance(rnm1) +
                          rnmBasis2 * luminance(rnm2);

    half3 dominantDirTN = normalize(dominantDirT);
    half3 specColor = saturate(dot(rnmBasis0, dominantDirTN)) * rnm0 +
                       saturate(dot(rnmBasis1, dominantDirTN)) * rnm1 +
                       saturate(dot(rnmBasis2, dominantDirTN)) * rnm2;

    o_light.l = normalize(mul(tangentToWorld, dominantDirT));
    half directionality = max(0.001, length(o_light.l));
    o_light.l /= directionality;

    // Split light into the directional and ambient parts, according to the directionality factor.
    o_light.colorIntensity = float4(specColor * directionality, 1.0);
    o_light.attenuation = directionality;
    o_light.NoL = saturate(dot(normalTangent, dominantDirTN));
    #endif

    return irradiance;
}

half3 DecodeSHLightmap(half3 L0, half2 lightmapUV, half3 normalWorld, out Light o_light)
{
    half3 irradiance;
    o_light = (Light)0;

    #if defined(SHADER_API_D3D11)
        float width, height;
        _RNM0.GetDimensions(width, height);

        float4 rnm_TexelSize = float4(width, height, 1.0/width, 1.0/height);

        half3 nL1x = SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM0, sampler_RNM0), lightmapUV, rnm_TexelSize);
        half3 nL1y = SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM1, sampler_RNM0), lightmapUV, rnm_TexelSize);
        half3 nL1z = SampleTexture2DBicubicFilter(TEXTURE2D_ARGS(_RNM2, sampler_RNM0), lightmapUV, rnm_TexelSize);
    #else
        half3 nL1x = SAMPLE_TEXTURE2D(_RNM0, sampler_RNM0, lightmapUV);
        half3 nL1y = SAMPLE_TEXTURE2D(_RNM1, sampler_RNM0, lightmapUV);
        half3 nL1z = SAMPLE_TEXTURE2D(_RNM2, sampler_RNM0, lightmapUV);
    #endif

    nL1x = nL1x * 2 - 1;
    nL1y = nL1y * 2 - 1;
    nL1z = nL1z * 2 - 1;
    half3 L1x = nL1x * L0 * 2;
    half3 L1y = nL1y * L0 * 2;
    half3 L1z = nL1z * L0 * 2;

    #ifdef BAKERY_SHNONLINEAR
        half lumaL0 = dot(L0, half(1));
        half lumaL1x = dot(L1x, half(1));
        half lumaL1y = dot(L1y, half(1));
        half lumaL1z = dot(L1z, half(1));

        half lumaSH = shEvaluateDiffuseL1Geomerics_local(lumaL0, float3(lumaL1x, lumaL1y, lumaL1z), normalWorld);

        #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_ZH3)
            lumaSH = SHEvalLinearL0L1_ZH3Hallucinate(float4(lumaL0, lumaL1y, lumaL1z, lumaL1x), normalWorld);
        #endif

        irradiance = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
        half regularLumaSH = dot(irradiance, 1);
        irradiance *= lerp(1, lumaSH / regularLumaSH, saturate(regularLumaSH*16));
    #else
        irradiance = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
    #endif

    #if defined(LIGHTMAP_SPECULAR)
    half3 dominantDir = float3(luminance(nL1x), luminance(nL1y), luminance(nL1z));

    o_light.l = dominantDir;
    half directionality = max(0.001, length(o_light.l));
    o_light.l /= directionality;

    // Split light into the directional and ambient parts, according to the directionality factor.
    o_light.colorIntensity = float4(irradiance * directionality, 1.0);
    o_light.attenuation = directionality;
    o_light.NoL = saturate(dot(normalWorld, o_light.l));
    #endif

    return irradiance;
}
#endif // USING_BAKERY

#if defined(USING_BAKERY_VERTEXLMSH)
half3 DecodeSHLightmapVertex(half3 L0, half3 ambientSH[3], half3 normalWorld, out Light o_light)
{
    half3 irradiance;
    o_light = (Light)0;

    half3 nL1x = ambientSH[0];
    half3 nL1y = ambientSH[1];
    half3 nL1z = ambientSH[2];

    nL1x = nL1x * 2 - 1;
    nL1y = nL1y * 2 - 1;
    nL1z = nL1z * 2 - 1;
    half3 L1x = nL1x * L0 * 2;
    half3 L1y = nL1y * L0 * 2;
    half3 L1z = nL1z * L0 * 2;

    #ifdef BAKERY_SHNONLINEAR
        half lumaL0 = dot(L0, half(1));
        half lumaL1x = dot(L1x, half(1));
        half lumaL1y = dot(L1y, half(1));
        half lumaL1z = dot(L1z, half(1));
        half lumaSH = shEvaluateDiffuseL1Geomerics_local(lumaL0, half3(lumaL1x, lumaL1y, lumaL1z), normalWorld);

        #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_ZH3)
            lumaSH = SHEvalLinearL0L1_ZH3Hallucinate(float4(lumaL0, lumaL1y, lumaL1z, lumaL1x), normalWorld);
        #endif

        irradiance = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
        half regularLumaSH = dot(irradiance, 1);
        irradiance *= lerp(1, lumaSH / regularLumaSH, saturate(regularLumaSH*16));
    #else
        irradiance = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
    #endif

    #if defined(LIGHTMAP_SPECULAR)
    half3 dominantDir = half3(luminance(nL1x), luminance(nL1y), luminance(nL1z));

    o_light.l = dominantDir;
    half directionality = max(0.001, length(o_light.l));
    o_light.l /= directionality;

    // Split light into the directional and ambient parts, according to the directionality factor.
    o_light.colorIntensity = float4(irradiance * directionality, 1.0);
    o_light.attenuation = directionality;
    o_light.NoL = saturate(dot(normalWorld, o_light.l));
    #endif

    return irradiance;
}
#endif // USING_BAKERY_VERTEXLMSH

#if defined(_BAKERY_MONOSH)
half3 DecodeMonoSHLightmap(half3 L0, half3 dominantDir, half3 normalWorld, out Light o_light, const bool remapDir = true)
{
    o_light = (Light)0;

    // Vertex mode is already in -1 to 1 range.
    half3 nL1 = remapDir? dominantDir * 2 - 1 : dominantDir;
    half3 L1x = nL1.x * L0 * 2;
    half3 L1y = nL1.y * L0 * 2;
    half3 L1z = nL1.z * L0 * 2;

    half3 sh;

    #if BAKERY_SHNONLINEAR
        half lumaL0 = dot(L0, 1);
        half lumaL1x = dot(L1x, 1);
        half lumaL1y = dot(L1y, 1);
        half lumaL1z = dot(L1z, 1);
        half lumaSH = shEvaluateDiffuseL1Geomerics_local(lumaL0, half3(lumaL1x, lumaL1y, lumaL1z), normalWorld);

        #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_ZH3)
            lumaSH = SHEvalLinearL0L1_ZH3Hallucinate(half4(lumaL0, lumaL1y, lumaL1z, lumaL1x), normalWorld);
        #endif

        sh = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
        half regularLumaSH = dot(sh, 1);

        sh *= lerp(1, lumaSH / regularLumaSH, saturate(regularLumaSH*16));
    #else
        sh = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
    #endif

    #if defined(LIGHTMAP_SPECULAR)
    dominantDir = nL1;

    o_light.l = dominantDir;
    half directionality = max(0.001, length(o_light.l));
    o_light.l /= directionality;

    // Split light into the directional and ambient parts, according to the directionality factor.
    o_light.colorIntensity = float4(L0 * directionality, 1.0);
    o_light.attenuation = directionality;
    o_light.NoL = saturate(dot(normalWorld, o_light.l));
    #endif

    return sh;
}
#endif // _BAKERY_MONOSH
#endif // COMMON_LIGHTMAP_INCLUDED
