#ifndef FILAMENT_LIGHT_INDIRECT
#define FILAMENT_LIGHT_INDIRECT

#include "FilamentCommonOcclusion.cginc"
#include "FilamentCommonGraphics.cginc"
#include "FilamentBRDF.cginc"
#include "UnityImageBasedLightingMinimal.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityLightingCommon.cginc"
#include "SharedFilteringLib.hlsl"
#include "SharedSHLib.hlsl"
#include "SharedLightmapLib.hlsl"

#include "FilamentLightLTCGI.cginc"
#include "FilamentLightVRCLV.cginc"

//------------------------------------------------------------------------------
// Image based lighting configuration
//------------------------------------------------------------------------------

// Spherical harmonics sampling algorithm
// Unity's default; basic SH sampling, with L2 SH enabled
#define SPHERICAL_HARMONICS_DEFAULT         0
// Geometrics' deringing lightprobe sampling, using L1 SH
#define SPHERICAL_HARMONICS_GEOMETRICS      1
// Activision's Quadratic Zonal Harmonics, using L1 SH
#define SPHERICAL_HARMONICS_ZH3             2

#define SPHERICAL_HARMONICS SPHERICAL_HARMONICS_ZH3
// VRC Light Volumes-specific
#define SPHERICAL_HARMONICS_VRCLV SPHERICAL_HARMONICS_GEOMETRICS


// Whether to use non-linear SH sampling on Bakery lightmap modes.
// If ZH3 sampling is used, it will be used here. This increases the quality of the directional
// lighting on lightmapped surfaces, in exchange for a performance cost.
#define BAKERY_SHNONLINEAR 0

// IBL integration algorithm
#define IBL_INTEGRATION_PREFILTERED_CUBEMAP         0
#define IBL_INTEGRATION_IMPORTANCE_SAMPLING         1 // Not supported!

#define IBL_INTEGRATION                             IBL_INTEGRATION_PREFILTERED_CUBEMAP

#define IBL_INTEGRATION_IMPORTANCE_SAMPLING_COUNT   64

// Refraction defines
#define REFRACTION_TYPE_SOLID 0
#define REFRACTION_TYPE_THIN 1

#ifndef REFRACTION_TYPE
#define REFRACTION_TYPE REFRACTION_TYPE_SOLID
#endif

#define REFRACTION_MODE_CUBEMAP 0
#define REFRACTION_MODE_SCREEN 1

#ifndef REFRACTION_MODE
#define REFRACTION_MODE REFRACTION_MODE_CUBEMAP
#endif

//------------------------------------------------------------------------------
// IBL prefiltered DFG term implementations
//------------------------------------------------------------------------------

half3 PrefilteredDFG_LUT(half lod, half NoV) {
    #if defined(USE_DFG_LUT)
    // coord = sqrt(linear_roughness), which is the mapping used by cmgen.
    return UNITY_SAMPLE_TEX2D(_DFG, half2(NoV, lod));
    #else
    // Texture not available
    return float3(1.0, 0.0, 0.0);
    #endif
}

//------------------------------------------------------------------------------
// IBL environment BRDF dispatch
//------------------------------------------------------------------------------

half3 prefilteredDFG(half perceptualRoughness, half NoV) {
    #if defined(USE_DFG_LUT)
        // PrefilteredDFG_LUT() takes a LOD, which is sqrt(roughness) = perceptualRoughness
        return PrefilteredDFG_LUT(perceptualRoughness, NoV);
    #else
        #if 0
        // Karis' approximation based on Lazarov's
        const half4 c0 = half4(-1.0, -0.0275, -0.572,  0.022);
        const half4 c1 = half4( 1.0,  0.0425,  1.040, -0.040);
        half4 r = perceptualRoughness * c0 + c1;
        half a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
        return (half3(half2(-1.04, 1.04) * a004 + r.zw, 0.0));
        #endif
        #if 0
        // Zioma's approximation based on Karis
        return half3(half2(1.0, pow(1.0 - max(perceptualRoughness, NoV), 3.0)), 0.0);
        #endif
        return half3(0, 1, 1);
    #endif
}

//------------------------------------------------------------------------------
// IBL irradiance implementations
//------------------------------------------------------------------------------

half3 Irradiance_SphericalHarmonics(const half3 n, const bool useL2) {
    // Uses Unity's functions for reading SH.
    half3 finalSH = half3(0,0,0);

    #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_DEFAULT)
        finalSH = SHEvalLinearL0L1(half4(n, 1.0));
    #endif

    #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_GEOMETRICS)
        half3 L0 = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
        half3 L0L2 = half3(unity_SHBr.z, unity_SHBg.z, unity_SHBb.z) / 3.0;
        L0 = (useL2) ? L0+L0L2 : L0-L0L2;
        finalSH.r = shEvaluateDiffuseL1Geomerics_local(L0.r, unity_SHAr.xyz, n);
        finalSH.g = shEvaluateDiffuseL1Geomerics_local(L0.g, unity_SHAg.xyz, n);
        finalSH.b = shEvaluateDiffuseL1Geomerics_local(L0.b, unity_SHAb.xyz, n);
        // Quadratic polynomials
    #endif

    #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_ZH3)
        finalSH = SHEvalLinearL0L1_ZH3Hallucinate(half4(n, 1.0));
    #endif

    // L2 contribution.
    // Note that if UNITY_SAMPLE_FULL_SH_PER_PIXEL is not set, L2 will not be added here!
    #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_DEFAULT)
        if (useL2) finalSH += SHEvalLinearL2(half4(n, 1.0));
    #endif

    return finalSH;
}

half3 Irradiance_SphericalHarmonics(const float3 n) {
    // Assume L2 is wanted
    return Irradiance_SphericalHarmonics(n, true);
}

#if UNITY_LIGHT_PROBE_PROXY_VOLUME
// normal should be normalized, w=1.0
half3 Irradiance_SampleProbeVolume (half4 normal, float3 worldPos)
{
    const float transformToLocal = unity_ProbeVolumeParams.y;
    const float texelSizeX = unity_ProbeVolumeParams.z;

    //The SH coefficients textures and probe occlusion are packed into 1 atlas.
    //-------------------------
    //| ShR | ShG | ShB | Occ |
    //-------------------------

    float3 position = (transformToLocal == 1.0f) ? mul(unity_ProbeVolumeWorldToObject, float4(worldPos, 1.0)).xyz : worldPos;
    float3 texCoord = (position - unity_ProbeVolumeMin.xyz) * unity_ProbeVolumeSizeInv.xyz;
    texCoord.x = texCoord.x * 0.25f;

    // We need to compute proper X coordinate to sample.
    // Clamp the coordinate otherwize we'll have leaking between RGB coefficients
    float texCoordX = clamp(texCoord.x, 0.5f * texelSizeX, 0.25f - 0.5f * texelSizeX);

    // sampler state comes from SHr (all SH textures share the same sampler)
    texCoord.x = texCoordX;
    half4 SHAr = UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);

    texCoord.x = texCoordX + 0.25f;
    half4 SHAg = UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);

    texCoord.x = texCoordX + 0.5f;
    half4 SHAb = UNITY_SAMPLE_TEX3D_SAMPLER(unity_ProbeVolumeSH, unity_ProbeVolumeSH, texCoord);

    // Linear + constant polynomial terms
    half3 x1;

    #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_DEFAULT)
        x1.r = dot(SHAr, normal);
        x1.g = dot(SHAg, normal);
        x1.b = dot(SHAb, normal);
    #endif

    #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_GEOMETRICS)
        x1.r = shEvaluateDiffuseL1Geomerics_local(SHAr.w, SHAr.rgb, normal);
        x1.g = shEvaluateDiffuseL1Geomerics_local(SHAg.w, SHAg.rgb, normal);
        x1.b = shEvaluateDiffuseL1Geomerics_local(SHAb.w, SHAb.rgb, normal);
    #endif

    #if (SPHERICAL_HARMONICS == SPHERICAL_HARMONICS_ZH3)
        x1.r = SHEvalLinearL0L1_ZH3Hallucinate(float4(SHAr.w, SHAr.rgb), normal);
        x1.g = SHEvalLinearL0L1_ZH3Hallucinate(float4(SHAg.w, SHAg.rgb), normal);
        x1.b = SHEvalLinearL0L1_ZH3Hallucinate(float4(SHAb.w, SHAb.rgb), normal);
    #endif

    return x1;
}
#endif


#if defined(_VRCLV)
half3 Irradiance_SampleVRCLightVolume(half3 normal, float3 worldPos, out Light derivedLight)
{
    derivedLight = (Light)0;

    // Bias sampling by surface normal to avoid artifacts
    // Fetch Spherical Harmonics (SH) components from the VRC Light Volume
    float3 L0, L1r, L1g, L1b;
    LightVolumeSH(worldPos, L0, L1r, L1g, L1b, normal * getLightVolumeSurfaceBias());

    // Compute irradiance using the SH components
    half3 irradiance = 0.0;

    #if (SPHERICAL_HARMONICS_VRCLV == SPHERICAL_HARMONICS_DEFAULT)
        irradiance.r = dot(L1r, normal.xyz) + L0.r;
        irradiance.g = dot(L1g, normal.xyz) + L0.g;
        irradiance.b = dot(L1b, normal.xyz) + L0.b;
    #endif

    #if (SPHERICAL_HARMONICS_VRCLV == SPHERICAL_HARMONICS_GEOMETRICS)
        irradiance.r = shEvaluateDiffuseL1Geomerics_local(L0.r, L1r, normal.xyz);
        irradiance.g = shEvaluateDiffuseL1Geomerics_local(L0.g, L1g, normal.xyz);
        irradiance.b = shEvaluateDiffuseL1Geomerics_local(L0.b, L1b, normal.xyz);
    #endif

    #if (SPHERICAL_HARMONICS_VRCLV == SPHERICAL_HARMONICS_ZH3)
        irradiance = SHEvalLinearL0L1_ZH3Hallucinate(normal.xyz, L0, L1r, L1g, L1b);
    #endif

    #if defined(LIGHTMAP_SPECULAR)
    half3 nL1x; half3 nL1y; half3 nL1z;
    nL1x = half3(L1r[0], L1g[0], L1b[0]);
    nL1y = half3(L1r[1], L1g[1], L1b[1]);
    nL1z = half3(L1r[2], L1g[2], L1b[2]);
    half3 dominantDir = half3(luminance(nL1x), luminance(nL1y), luminance(nL1z));

    // Determine the light's direction and directionality
    half L0_lum = max(FLT_EPS, luminance(L0));
    half L1_mag = length(dominantDir);
    half directionality = saturate(L1_mag / L0_lum);
    derivedLight.l = dominantDir / L1_mag;

    half3 directionalColor = half3(dot(L1r, derivedLight.l), dot(L1g, derivedLight.l), dot(L1b, derivedLight.l));
    half3 Li = L0 + max(0, directionalColor);

    derivedLight.colorIntensity = half4(Li, 1.0);
    derivedLight.attenuation = directionality;
    derivedLight.NoL = saturate(dot(normal, derivedLight.l));
    #endif

    return irradiance;
}

half3 Irradiance_SampleVRCLightVolumeAdditive(half3 normal, float3 worldPos, out Light derivedLight)
{
    derivedLight = (Light)0;

    // Fetch Spherical Harmonics (SH) components from the VRC Light Volume
    half3 L0, L1r, L1g, L1b;
    LightVolumeAdditiveSH(worldPos, L0, L1r, L1g, L1b, normal * getLightVolumeSurfaceBias());

    // Compute irradiance using the SH components
    half3 irradiance = 0.0;

    // Doesn't support non-linear evaluation, so just evaluate normally.
    irradiance.r = dot(L1r, normal.xyz) + L0.r;
    irradiance.g = dot(L1g, normal.xyz) + L0.g;
    irradiance.b = dot(L1b, normal.xyz) + L0.b;

    // Add derived light to existing derived light
    #if defined(LIGHTMAP_SPECULAR)
    half3 nL1x; half3 nL1y; half3 nL1z;
    nL1x = half3(L1r[0], L1g[0], L1b[0]);
    nL1y = half3(L1r[1], L1g[1], L1b[1]);
    nL1z = half3(L1r[2], L1g[2], L1b[2]);
    half3 dominantDir = half3(luminance(nL1x), luminance(nL1y), luminance(nL1z));

    // Determine the light's direction and directionality
    half L0_lum = max(FLT_EPS, luminance(L0));
    half L1_mag = length(dominantDir);
    half directionality = saturate(L1_mag / L0_lum);
    derivedLight.l = dominantDir / L1_mag;

    half3 directionalColor = half3(dot(L1r, derivedLight.l), dot(L1g, derivedLight.l), dot(L1b, derivedLight.l));
    half3 Li = L0 + max(0, directionalColor);

    derivedLight.colorIntensity = half4(Li, 1.0);
    derivedLight.attenuation = directionality;
    derivedLight.NoL = saturate(dot(normal, derivedLight.l));
    #endif

    return irradiance;
}
#endif

half3 Irradiance_SphericalHarmonicsUnity (half3 normal, half3 ambient, float3 worldPos, out Light derivedLight)
{
    half3 ambient_contrib = 0.0;
    derivedLight = (Light)0;

    // Gather VRC Light Volumes data, if present.
    // This replaces the result of light probes.
#if defined(_VRCLV)
    #if UNITY_LIGHT_PROBE_PROXY_VOLUME // I feel like this is an insane edge case
        if (unity_ProbeVolumeParams.x == 1.0)
            ambient_contrib = Irradiance_SampleProbeVolume(half4(normal, 1.0), worldPos);
        else
            ambient_contrib = Irradiance_SampleVRCLightVolume(normal, worldPos, derivedLight);
    #else
        ambient_contrib = Irradiance_SampleVRCLightVolume(normal, worldPos, derivedLight);
    #endif

    ambient += max(half3(0, 0, 0), ambient_contrib);

    #ifdef UNITY_COLORSPACE_GAMMA
        ambient = LinearToGammaSpace (ambient);
    #endif

    return ambient;
#else

    #if UNITY_SAMPLE_FULL_SH_PER_PIXEL
        // Completely per-pixel
        #if UNITY_LIGHT_PROBE_PROXY_VOLUME
            if (unity_ProbeVolumeParams.x == 1.0)
                ambient_contrib = Irradiance_SampleProbeVolume(half4(normal, 1.0), worldPos);
            else
                ambient_contrib = Irradiance_SphericalHarmonics(normal, true);
        #else
            ambient_contrib = Irradiance_SphericalHarmonics(normal, true);
        #endif

            ambient += max(half3(0, 0, 0), ambient_contrib);

        #ifdef UNITY_COLORSPACE_GAMMA
            ambient = LinearToGammaSpace(ambient);
        #endif
    #elif (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
        // Completely per-vertex
        // nothing to do here. Gamma conversion on ambient from SH takes place in the vertex shader, see ShadeSHPerVertex.
    #else
        // L2 per-vertex, L0..L1 & gamma-correction per-pixel
        // Ambient in this case is expected to be always Linear, see ShadeSHPerVertex()
        #if UNITY_LIGHT_PROBE_PROXY_VOLUME
            if (unity_ProbeVolumeParams.x == 1.0)
                ambient_contrib = Irradiance_SampleProbeVolume (half4(normal, 1.0), worldPos);
            else
                ambient_contrib = Irradiance_SphericalHarmonics(normal, false);
        #else
            ambient_contrib = Irradiance_SphericalHarmonics(normal, false);
        #endif

        ambient = max(half3(0, 0, 0), ambient+ambient_contrib);     // include L2 contribution in vertex shader before clamp.
        #ifdef UNITY_COLORSPACE_GAMMA
            ambient = LinearToGammaSpace (ambient);
        #endif
    #endif

    return ambient;
#endif
}

/*
half3 Irradiance_RoughnessOne(const half3 n) {
    // note: lod used is always integer, hopefully the hardware skips tri-linear filtering
    return decodeDataForIBL(textureLod(light_iblSpecular, n, frameUniforms.iblRoughnessOneLevel));
}
*/

half IrradianceToExposureOcclusion(half3 irradiance)
{
    return saturate(length(irradiance + FLT_EPS) * getExposureOcclusionBias());
}

// Return light probes or lightmap.
float3 UnityGI_Irradiance(ShadingParams shading, float3 tangentNormal, out half occlusion, out Light derivedLight)
{
    float3 irradiance = shading.ambient;
    // In order for the exposure occlusion to handle mixed lightmaps and etc well, we accumulate
    // irradiance seperately, and calculate the exposure occlusion from that to avoid having directionality influence it.
    float3 irradianceForAO;
    occlusion = 1.0;
    derivedLight = (Light)0;

    #if UNITY_SHOULD_SAMPLE_SH
        irradiance += Irradiance_SphericalHarmonicsUnity(shading.normal, shading.ambient, shading.position, derivedLight);
    #endif

    irradianceForAO = irradiance;

    // Should be stripped out at compile time if vertex LM mode is disabled.
    if (getIsBakeryVertexMode() == false)
    {
    #if defined(LIGHTMAP_ON)
        // Baked lightmaps
        half4 bakedColorTex = SampleLightmapBicubic(shading.lightmapUV.xy);
        half3 bakedColor = DecodeLightmap(bakedColorTex);

        #ifdef DIRLIGHTMAP_COMBINED
            fixed4 bakedDirTex = SampleLightmapDirBicubic (shading.lightmapUV.xy);

            // Bakery's MonoSH mode replaces the regular directional lightmap
            #if defined(_BAKERY_MONOSH)
                irradiance = DecodeMonoSHLightmap (bakedColor, bakedDirTex, shading.normal, derivedLight);

                irradianceForAO = irradiance;

                #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                    irradiance = SubtractMainLightWithRealtimeAttenuationFromLightmap (irradiance, shading.attenuation, bakedColorTex, shading.normal);
                #endif
            #else
                irradiance = DecodeDirectionalLightmap (bakedColor, bakedDirTex, shading.normal);

                irradianceForAO = irradiance;

                #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                    irradiance = SubtractMainLightWithRealtimeAttenuationFromLightmap (irradiance, shading.attenuation, bakedColorTex, shading.normal);
                #endif

                #if defined(LIGHTMAP_SPECULAR)
                    irradiance = DecodeDirectionalLightmapSpecular(bakedColor, bakedDirTex, shading.normal, false, 0, derivedLight);
                #endif
            #endif

        #else // not directional lightmap

            #if defined(USING_BAKERY)
                #if defined(_BAKERY_RNM)
                // bakery rnm mode
                irradiance = DecodeRNMLightmap(bakedColor, shading.lightmapUV.xy, tangentNormal, shading.tangentToWorld, derivedLight);
                #endif

                #if defined(_BAKERY_SH)
                // bakery sh mode
                irradiance = DecodeSHLightmap(bakedColor, shading.lightmapUV.xy, shading.normal, derivedLight);
                #endif

                irradianceForAO = irradiance;

                #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                    irradiance = SubtractMainLightWithRealtimeAttenuationFromLightmap(irradiance, shading.attenuation, bakedColorTex, shading.normal);
                #endif

            #else

                irradiance += bakedColor;

                irradianceForAO = irradiance;

                #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                    irradiance = SubtractMainLightWithRealtimeAttenuationFromLightmap(irradiance, shading.attenuation, bakedColorTex, shading.normal);
                #endif
            #endif

        #endif
    #endif
    }
    #if defined(USING_BAKERY_VERTEXLM)
    if (getIsBakeryVertexMode() == true)
    {
        // Lightmap colour is already stored in shading.ambient.
        // If directionality is on, then ambientDir contains directionality.
        // If SH is on, then ambientSH[3] contains the SH data.
        half4 bakedColorTex = float4(shading.ambient, 1.0);

        #if defined(USING_BAKERY_VERTEXLMSH)
            irradiance = DecodeSHLightmapVertex(shading.ambient, shading.ambientSH, shading.normal, derivedLight);
            irradianceForAO = irradiance;
            #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                irradiance = SubtractMainLightWithRealtimeAttenuationFromLightmap (irradiance, shading.attenuation, bakedColorTex, shading.normal);
            #endif
        #else
            #if defined(USING_BAKERY_VERTEXLMDIR)
                #if defined(_BAKERY_MONOSH)
                    irradiance = DecodeMonoSHLightmap (shading.ambient, shading.ambientDir, shading.normal, derivedLight, false);
                    irradianceForAO = irradiance;
                    #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                        irradiance = SubtractMainLightWithRealtimeAttenuationFromLightmap (irradiance, shading.attenuation, bakedColorTex, shading.normal);
                    #endif
                #else
                    irradiance = DecodeDirectionalLightmap (shading.ambient, shading.ambientDir, shading.normal);
                    irradianceForAO = irradiance;
                    #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                        irradiance = SubtractMainLightWithRealtimeAttenuationFromLightmap (irradiance, shading.attenuation, bakedColorTex, shading.normal);
                    #endif
                    #if defined(LIGHTMAP_SPECULAR)
                        irradiance = DecodeDirectionalLightmapSpecular(shading.ambient, shading.ambientDir, shading.normal, false, 0, derivedLight);
                    #endif
                #endif
            #else
                // No directionality, just light colour.
                // Irradiance and IrradianceForAO already contain the irradiance, so just handle subtractive lighting.
                #if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
                    irradiance = SubtractMainLightWithRealtimeAttenuationFromLightmap(irradiance, shading.attenuation, bakedColorTex, shading.normal);
                #endif
            #endif
        #endif
    }
    #endif

    #if defined(DYNAMICLIGHTMAP_ON)
        // Dynamic lightmaps
        fixed4 realtimeColorTex = SampleDynamicLightmapBicubic(shading.lightmapUV.zw);
        half3 realtimeColor = DecodeRealtimeLightmap (realtimeColorTex);

        irradianceForAO += realtimeColor;

        #ifdef DIRLIGHTMAP_COMBINED
            half4 realtimeDirTex = SampleDynamicLightmapDirBicubic(shading.lightmapUV.zw);
            irradiance += DecodeDirectionalLightmap (realtimeColor, realtimeDirTex, shading.normal);
        #else
            irradiance += realtimeColor;
        #endif
    #endif

    occlusion = IrradianceToExposureOcclusion(irradianceForAO);

    return irradiance;
}

//------------------------------------------------------------------------------
// IBL irradiance dispatch
//------------------------------------------------------------------------------

half3 get_diffuseIrradiance_notUsed(const half3 n) {
        return Irradiance_SphericalHarmonics(n);
}
//------------------------------------------------------------------------------
// IBL specular
//------------------------------------------------------------------------------

UnityGIInput InitialiseUnityGIInput(const ShadingParams shading, const PixelParams pixel)
{
    UnityGIInput d;
    d.worldPos = shading.position;
    d.worldViewDir = -shading.view;
    d.probeHDR[0] = unity_SpecCube0_HDR;
    d.probeHDR[1] = unity_SpecCube1_HDR;
    #if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECCUBE_BOX_PROJECTION)
      d.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
    #endif
    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
      d.boxMax[0] = unity_SpecCube0_BoxMax;
      d.probePosition[0] = unity_SpecCube0_ProbePosition;
      d.boxMax[1] = unity_SpecCube1_BoxMax;
      d.boxMin[1] = unity_SpecCube1_BoxMin;
      d.probePosition[1] = unity_SpecCube1_ProbePosition;
    #endif
    return d;
}

half perceptualRoughnessToLod(half perceptualRoughness) {
    const half iblRoughnessOneLevel = 1.0/UNITY_SPECCUBE_LOD_STEPS;
    // The mapping below is a quadratic fit for log2(perceptualRoughness)+iblRoughnessOneLevel when
    // iblRoughnessOneLevel is 4. We found empirically that this mapping works very well for
    // a 256 cubemap with 5 levels used. But also scales well for other iblRoughnessOneLevel values.
    //return iblRoughnessOneLevel * perceptualRoughness * (2.0 - perceptualRoughness);

    // Unity's remapping (UNITY_SPECCUBE_LOD_STEPS is 6, not 4)
    return iblRoughnessOneLevel * perceptualRoughness * (1.7 - 0.7 * perceptualRoughness);
}

half3 prefilteredRadiance(const half3 r, half perceptualRoughness) {
    half lod = perceptualRoughnessToLod(perceptualRoughness);
    return DecodeHDR(UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, r, lod), unity_SpecCube0_HDR);
}

half3 prefilteredRadiance(const half3 r, half roughness, half offset) {
    const half iblRoughnessOneLevel = 1.0/UNITY_SPECCUBE_LOD_STEPS;
    half lod = iblRoughnessOneLevel * roughness;
    return DecodeHDR(UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, r, lod + offset), unity_SpecCube0_HDR);
}

half3 Unity_GlossyEnvironment_local (UNITY_ARGS_TEXCUBE(tex), half4 hdr, Unity_GlossyEnvironmentData glossIn)
{
    half perceptualRoughness = glossIn.roughness /* perceptualRoughness */ ;

    // Workaround for issue where objects are blurrier than they should be
    // due to specular AA.
    #if defined(GEOMETRIC_SPECULAR_AA)
    half roughnessAdjustment = 1-perceptualRoughness;
    roughnessAdjustment = MIN_PERCEPTUAL_ROUGHNESS * roughnessAdjustment * roughnessAdjustment;
    perceptualRoughness = perceptualRoughness - roughnessAdjustment;
    #endif

    // Unity derivation
    perceptualRoughness = perceptualRoughness*(1.7 - 0.7 * perceptualRoughness);
    // Filament derivation
    // perceptualRoughness = perceptualRoughness * (2.0 - perceptualRoughness);
    half mip = perceptualRoughnessToMipmapLevel(perceptualRoughness);
    half3 R = glossIn.reflUVW;
    half4 rgbm = UNITY_SAMPLE_TEXCUBE_LOD(tex, R, mip);

    return DecodeHDR(rgbm, hdr);
}

// Workaround: Construct the correct Unity variables and get the correct Unity spec values

inline half3 UnityGI_prefilteredRadiance(const UnityGIInput data, const half perceptualRoughness, const float3 r)
{
    half3 specular;

    Unity_GlossyEnvironmentData glossIn = (Unity_GlossyEnvironmentData)0;
    glossIn.roughness = perceptualRoughness;
    glossIn.reflUVW = r;

    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
        // we will tweak reflUVW in glossIn directly (as we pass it to Unity_GlossyEnvironment twice for probe0 and probe1), so keep original to pass into BoxProjectedCubemapDirection
        half3 originalReflUVW = glossIn.reflUVW;
        glossIn.reflUVW = BoxProjectedCubemapDirection (originalReflUVW, data.worldPos, data.probePosition[0], data.boxMin[0], data.boxMax[0]);
    #endif

    #ifdef _GLOSSYREFLECTIONS_OFF
        specular = unity_IndirectSpecColor.rgb;
    #else
        half3 env0 = Unity_GlossyEnvironment_local (UNITY_PASS_TEXCUBE(unity_SpecCube0), data.probeHDR[0], glossIn);
        #ifdef UNITY_SPECCUBE_BLENDING
            const float kBlendFactor = 0.99999;
            float blendLerp = data.boxMin[0].w;
            UNITY_BRANCH
            if (blendLerp < kBlendFactor)
            {
                #ifdef UNITY_SPECCUBE_BOX_PROJECTION
                    glossIn.reflUVW = BoxProjectedCubemapDirection (originalReflUVW, data.worldPos, data.probePosition[1], data.boxMin[1], data.boxMax[1]);
                #endif

                half3 env1 = Unity_GlossyEnvironment_local (UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1,unity_SpecCube0), data.probeHDR[1], glossIn);
                specular = lerp(env1, env0, blendLerp);
            }
            else
            {
                specular = env0;
            }
        #else
            specular = env0;
        #endif
    #endif

    return specular;
}

half3 getSpecularDominantDirection(const half3 n, const half3 r, half roughness) {
    return lerp(r, n, roughness * roughness);
}

half3 specularDFG(const PixelParams pixel) {
#if defined(SHADING_MODEL_CLOTH)
    return pixel.f0 * pixel.dfg.z;
#else
    return lerp(pixel.dfg.xxx, pixel.dfg.yyy, pixel.f0);
#endif
}

/**
 * Returns the reflected vector at the current shading point. The reflected vector
 * return by this function might be different from shading.reflected:
 * - For anisotropic material, we bend the reflection vector to simulate
 *   anisotropic indirect lighting
 * - The reflected vector may be modified to point towards the dominant specular
 *   direction to match reference renderings when the roughness increases
 */

half3 getReflectedVector(const PixelParams pixel, const half3 v, const half3 n) {
#if defined(MATERIAL_HAS_ANISOTROPY)
    half3  anisotropyDirection = pixel.anisotropy >= 0.0 ? pixel.anisotropicB : pixel.anisotropicT;
    half3  anisotropicTangent  = cross(anisotropyDirection, v);
    half3  anisotropicNormal   = cross(anisotropicTangent, anisotropyDirection);
    half bendFactor          = abs(pixel.anisotropy) * saturate(5.0 * pixel.perceptualRoughness);
    half3  bentNormal          = normalize(lerp(n, anisotropicNormal, bendFactor));

    half3 r = reflect(-v, bentNormal);
#else
    half3 r = reflect(-v, n);
#endif
    return r;
}

half3 getReflectedVector(const ShadingParams shading, const PixelParams pixel, const half3 n) {
#if defined(MATERIAL_HAS_ANISOTROPY)
    half3 r = getReflectedVector(pixel, shading.view, n);
#else
    half3 r = shading.reflected;
#endif
    return getSpecularDominantDirection(n, r, pixel.roughness);
}

//------------------------------------------------------------------------------
// Prefiltered importance sampling
//------------------------------------------------------------------------------

#if IBL_INTEGRATION == IBL_INTEGRATION_IMPORTANCE_SAMPLING

void isEvaluateClearCoatIBL(const ShadingParams shading, const PixelParams pixel,
    half specularAO, inout half3 Fd, inout half3 Fr) {
#if defined(MATERIAL_HAS_CLEAR_COAT)
#if defined(MATERIAL_HAS_NORMAL) || defined(MATERIAL_HAS_CLEAR_COAT_NORMAL)
    // We want to use the geometric normal for the clear coat layer
    half clearCoatNoV = clampNoV(dot(shading.clearCoatNormal, shading.view));
    half3 clearCoatNormal = shading.clearCoatNormal;
#else
    half clearCoatNoV = shading.NoV;
    half3 clearCoatNormal = shading.normal;
#endif
    // The clear coat layer assumes an IOR of 1.5 (4% reflectance)
    half Fc = F_Schlick(0.04, 1.0, clearCoatNoV) * pixel.clearCoat;
    half attenuation = 1.0 - Fc;
    Fd *= attenuation;
    Fr *= attenuation;

    PixelParams p;
    p.perceptualRoughness = pixel.clearCoatPerceptualRoughness;
    p.f0 = 0.04;
    p.roughness = perceptualRoughnessToRoughness(p.perceptualRoughness);
#if defined(MATERIAL_HAS_ANISOTROPY)
    p.anisotropy = 0.0;
#endif

    half3 clearCoatLobe = isEvaluateSpecularIBL(p, clearCoatNormal, shading.view, clearCoatNoV);
    Fr += clearCoatLobe * (specularAO * pixel.clearCoat);
#endif
}
#endif


//------------------------------------------------------------------------------
// IBL evaluation
//------------------------------------------------------------------------------

void evaluateClothIndirectDiffuseBRDF(const ShadingParams shading, const PixelParams pixel,
    inout half diffuse) {
#if defined(SHADING_MODEL_CLOTH)
#if defined(MATERIAL_HAS_SUBSURFACE_COLOR)
    // Simulate subsurface scattering with a wrap diffuse term
    diffuse *= Fd_Wrap(shading.NoV, 0.5);
#endif
#endif
}

void evaluateSheenIBL(const ShadingParams shading, const PixelParams pixel,
    half diffuseAO, inout half3 Fd, inout half3 Fr) {
#if !defined(SHADING_MODEL_CLOTH) && !defined(SHADING_MODEL_SUBSURFACE)
#if defined(MATERIAL_HAS_SHEEN_COLOR)
    // Albedo scaling of the base layer before we layer sheen on top
    Fd *= pixel.sheenScaling;
    Fr *= pixel.sheenScaling;

    half3 reflectance = pixel.sheenDFG * pixel.sheenColor;
    reflectance *= computeSpecularAO(shading.NoV, diffuseAO, pixel.sheenRoughness);

    Fr += reflectance * prefilteredRadiance(shading.reflected, pixel.sheenPerceptualRoughness);
#endif
#endif
}

void evaluateClearCoatIBL(const ShadingParams shading, const PixelParams pixel,
    half diffuseAO, inout half3 Fd, inout half3 Fr) {
#if IBL_INTEGRATION == IBL_INTEGRATION_IMPORTANCE_SAMPLING
    half specularAO = computeSpecularAO(shading.NoV, diffuseAO, pixel.clearCoatRoughness);
    isEvaluateClearCoatIBL(pixel, specularAO, Fd, Fr);
    return;
#endif

#if defined(MATERIAL_HAS_CLEAR_COAT)
#if defined(MATERIAL_HAS_NORMAL) || defined(MATERIAL_HAS_CLEAR_COAT_NORMAL)
    // We want to use the geometric normal for the clear coat layer
    half clearCoatNoV = clampNoV(dot(shading.clearCoatNormal, shading.view));
    half3 clearCoatR = reflect(-shading.view, shading.clearCoatNormal);
#else
    half clearCoatNoV = shading.NoV;
    half3 clearCoatR = shading.reflected;
#endif
    // The clear coat layer assumes an IOR of 1.5 (4% reflectance)
    half Fc = F_Schlick(0.04, 1.0, clearCoatNoV) * pixel.clearCoat;
    half attenuation = 1.0 - Fc;
    Fd *= attenuation;
    Fr *= attenuation;

    // TODO: Should we apply specularAO to the attenuation as well?
    half specularAO = computeSpecularAO(clearCoatNoV, diffuseAO, pixel.clearCoatRoughness);
    Fr += prefilteredRadiance(clearCoatR, pixel.clearCoatPerceptualRoughness) * (specularAO * Fc);
#endif
}

void evaluateSubsurfaceIBL(const ShadingParams shading, const PixelParams pixel,
    const float3 diffuseIrradiance, inout float3 Fd, inout float3 Fr) {
#if defined(SHADING_MODEL_SUBSURFACE)
    float3 viewIndependent = diffuseIrradiance;
    float3 viewDependent = prefilteredRadiance(-shading.view, pixel.roughness, 1.0 + pixel.thickness);
    float attenuation = (1.0 - pixel.thickness) / (2.0 * PI);
    Fd += pixel.subsurfaceColor * (viewIndependent + viewDependent) * attenuation;
#elif defined(SHADING_MODEL_CLOTH) && defined(MATERIAL_HAS_SUBSURFACE_COLOR)
    Fd *= saturate(pixel.subsurfaceColor + shading.NoV);
#endif
}

#if defined(HAS_REFRACTION)

struct Refraction {
    half3 position;
    half3 direction;
    half d;
};

void refractionSolidSphere(const ShadingParams shading, const PixelParams pixel,
    const half3 n, half3 r, out Refraction ray) {
    r = refract(r, n, pixel.etaIR);
    half NoR = dot(n, r);
    half d = pixel.thickness * -NoR;
    ray.position = half3(shading.position + r * d);
    ray.d = d;
    half3 n1 = normalize(NoR * r - n * 0.5);
    ray.direction = refract(r, n1,  pixel.etaRI);
}

void refractionSolidBox(const ShadingParams shading, const PixelParams pixel,
    const half3 n, half3 r, out Refraction ray) {
    half3 rr = refract(r, n, pixel.etaIR);
    half NoR = dot(n, rr);
    half d = pixel.thickness / max(-NoR, 0.001);
    ray.position = half3(shading.position + rr * d);
    ray.direction = r;
    ray.d = d;
#if REFRACTION_MODE == REFRACTION_MODE_CUBEMAP
    // fudge direction vector, so we see the offset due to the thickness of the object
    half envDistance = 10.0; // this should come from a ubo
    ray.direction = normalize((ray.position - shading.position) + ray.direction * envDistance);
#endif
}

void refractionThinSphere(const ShadingParams shading, const PixelParams pixel,
    const half3 n, half3 r, out Refraction ray) {
    half d = 0.0;
#if defined(MATERIAL_HAS_MICRO_THICKNESS)
    // note: we need the refracted ray to calculate the distance traveled
    // we could use shading.NoV, but we would lose the dependency on ior.
    half3 rr = refract(r, n, pixel.etaIR);
    half NoR = dot(n, rr);
    d = pixel.uThickness / max(-NoR, 0.001);
    ray.position = half3(shading.position + rr * d);
#else
    ray.position = half3(shading.position);
#endif
    ray.direction = r;
    ray.d = d;
}

void applyRefraction(
    const ShadingParams shading,
    const PixelParams pixel,
    half3 E, half3 Fd, half3 Fr,
    inout half3 color) {

    Refraction ray;
    half iblLuminance = 1.0; // unused
    half refractionLodOffset = 0.0; // unused

#if REFRACTION_TYPE == REFRACTION_TYPE_SOLID
    refractionSolidSphere(shading, pixel, shading.normal, -shading.view, ray);
#elif REFRACTION_TYPE == REFRACTION_TYPE_THIN
    refractionThinSphere(shading, pixel, shading.normal, -shading.view, ray);
#else
#error invalid REFRACTION_TYPE
#endif

    // compute transmission T
#if defined(MATERIAL_HAS_ABSORPTION)
#if defined(MATERIAL_HAS_THICKNESS) || defined(MATERIAL_HAS_MICRO_THICKNESS)
    half3 T = min(1.0, exp(-pixel.absorption * ray.d));
#else
    half3 T = 1.0 - pixel.absorption;
#endif
#endif

    // Roughness remapping so that an IOR of 1.0 means no microfacet refraction and an IOR
    // of 1.5 has full microfacet refraction
    half perceptualRoughness = lerp(pixel.perceptualRoughnessUnclamped, 0.0,
            saturate(pixel.etaIR * 3.0 - 2.0));
#if REFRACTION_TYPE == REFRACTION_TYPE_THIN
    // For thin surfaces, the light will bounce off at the second interface in the direction of
    // the reflection, effectively adding to the specular, but this process will repeat itself.
    // Each time the ray exits the surface on the front side after the first bounce,
    // it's multiplied by E^2, and we get: E + E(1-E)^2 + E^3(1-E)^2 + ...
    // This infinite series converges and is easy to simplify.
    // Note: we calculate these bounces only on a single component,
    // since it's a fairly subtle effect.
    E *= 1.0 + pixel.transmission * (1.0 - E.g) / (1.0 + E.g);
#endif

    /* sample the cubemap or screen-space */
#if REFRACTION_MODE == REFRACTION_MODE_CUBEMAP
    // when reading from the cubemap, we are not pre-exposed so we apply iblLuminance
    // which is not the case when we'll read from the screen-space buffer

    // Gather Unity GI data
    UnityGIInput unityData = InitialiseUnityGIInput(shading, pixel);
    half3 Ft = UnityGI_prefilteredRadiance(unityData, perceptualRoughness, ray.direction) * iblLuminance;
#else
    // compute the point where the ray exits the medium, if needed
    //half4 p = half4(frameUniforms.clipFromWorldMatrix * half4(ray.position, 1.0));
    //p.xy = uvToRenderTargetUV(p.xy * (0.5 / p.w) + 0.5);
    half4 p = UnityWorldToClipPos(half4(ray.position, 1.0));
    p.w =  (0.5 / p.w);
    p.xy = ComputeGrabScreenPos(p);

    // perceptualRoughness to LOD
    // Empirical factor to compensate for the gaussian approximation of Dggx, chosen so
    // cubemap and screen-space modes match at perceptualRoughness 0.125
    // TODO: Remove this factor temporarily until we find a better solution
    //       This overblurs many scenes and needs a more principled approach
    // half tweakedPerceptualRoughness = perceptualRoughness * 1.74;
    half tweakedPerceptualRoughness = perceptualRoughness;
    half lod = max(0.0, 2.0 * log2(tweakedPerceptualRoughness) + refractionLodOffset);

    half3 Ft = UNITY_SAMPLE_TEX2D_LOD(REFRACTION_SOURCE, p.xy, lod).rgb * REFRACTION_MULTIPLIER;
#endif

    // base color changes the amount of light passing through the boundary
    Ft *= pixel.diffuseColor;

    // fresnel from the first interface
    Ft *= 1.0 - E;

    // apply absorption
#if defined(MATERIAL_HAS_ABSORPTION)
    Ft *= T;
#endif

    Fr *= iblLuminance;
    Fd *= iblLuminance;
    color.rgb += Fr + lerp(Fd, Ft, pixel.transmission);
}
#endif

void combineDiffuseAndSpecular(const ShadingParams shading, const PixelParams pixel,
        const half3 E, const half3 Fd, const half3 Fr,
        inout half3 color) {
    const half iblLuminance = 1.0; // Unknown
#if defined(HAS_REFRACTION)
    applyRefraction(shading, pixel, E, Fd, Fr, color);
#else
    color.rgb += (Fd + Fr) * iblLuminance;
#endif
}

void evaluateIBL(const ShadingParams shading, const MaterialInputs material, const PixelParams pixel,
    inout half3 color) {
    half ssao = 1.0; // Not implemented
    half lightmapAO = 1.0; // Specular-only AO derived from baked lighting and exposure occlusion setting
    half3 tangentNormal = half3(0, 0, 1);
#if defined(MATERIAL_HAS_NORMAL)
    tangentNormal = material.normal;
#endif

    Light derivedLight = (Light)0;

    // Gather Unity GI data
    UnityGIInput unityData = InitialiseUnityGIInput(shading, pixel);

    half3 unityIrradiance = UnityGI_Irradiance(shading, tangentNormal,
        /*out*/ lightmapAO, /*out*/ derivedLight);

    // specular layer
    half3 Fr;
#if IBL_INTEGRATION == IBL_INTEGRATION_PREFILTERED_CUBEMAP
    half3 E = specularDFG(pixel);
    half3 r = getReflectedVector(shading, pixel, shading.normal);
    Fr = E * UnityGI_prefilteredRadiance(unityData, pixel.perceptualRoughness, r);
#elif IBL_INTEGRATION == IBL_INTEGRATION_IMPORTANCE_SAMPLING
    // Not supported
    half3 E = half3(0.0); // TODO: fix for importance sampling
    Fr = isEvaluateSpecularIBL(pixel, shading.normal, shading.view, shading.NoV);
#endif

    // Ambient occlusion
    half diffuseAO = min(material.ambientOcclusion, ssao);
    half specularAO = computeSpecularAO(shading.NoV, diffuseAO*lightmapAO, pixel.roughness);

    half3 specularSingleBounceAO = singleBounceAO(specularAO) * pixel.energyCompensation;
    Fr *= specularSingleBounceAO;

    // Gather LTCGI data, if present.
#if defined(_LTCGI)
    accumulator_struct acc = (accumulator_struct)0;

    LTCGI_Contribution(
        acc,
        shading.position,
        shading.normal,
        shading.view,
        pixel.perceptualRoughness,
        (shading.lightmapUV.xy - unity_LightmapST.zw) / unity_LightmapST.xy
    );

    // Apply specular AO seperately for LTCGI pass, as it is a seperate set of lights.
    half ltc_specularAO = computeSpecularAO(shading.NoV, diffuseAO, pixel.roughness);
    half3 ltc_Fr =  E * acc.specular;

    ltc_Fr *= singleBounceAO(ltc_specularAO) * pixel.energyCompensation;
    specularAO = lerp(specularAO, ltc_specularAO, saturate(acc.specularIntensity));

    Fr = lerp(Fr, ltc_Fr, saturate(acc.specularIntensity));
#endif

    // diffuse layer
    half diffuseBRDF = singleBounceAO(diffuseAO); // Fd_Lambert() is baked in the SH below

    evaluateClothIndirectDiffuseBRDF(shading, pixel, diffuseBRDF);

#if defined(MATERIAL_HAS_BENT_NORMAL)
    half3 diffuseNormal = shading.bentNormal;
#else
    half3 diffuseNormal = shading.normal;
#endif

#if IBL_INTEGRATION == IBL_INTEGRATION_PREFILTERED_CUBEMAP
    //half3 diffuseIrradiance = get_diffuseIrradiance(diffuseNormal);
    half3 diffuseIrradiance = unityIrradiance;
#elif IBL_INTEGRATION == IBL_INTEGRATION_IMPORTANCE_SAMPLING
    half3 diffuseIrradiance = isEvaluateDiffuseIBL(pixel, diffuseNormal, shading.view);
#endif

#if defined(_LTCGI)
    diffuseIrradiance += acc.diffuse;
#endif

    // VRC Light Volumes also have an additive component which can be added over lightmapping.
    #if defined(_VRCLV) && !UNITY_SHOULD_SAMPLE_SH
        Light volumeLight = (Light)0;
        diffuseIrradiance += Irradiance_SampleVRCLightVolumeAdditive(shading.normal, shading.position, volumeLight);
    #endif

    half3 Fd = pixel.diffuseColor * diffuseIrradiance * (1.0 - E) * diffuseBRDF;

    // subsurface layer
    evaluateSubsurfaceIBL(shading, pixel, diffuseIrradiance, Fd, Fr);

    // extra ambient occlusion term for the base and subsurface layers
    multiBounceAO(diffuseAO, pixel.diffuseColor, Fd);
    multiBounceSpecularAO(specularAO, pixel.f0, Fr);

    // sheen layer
    evaluateSheenIBL(shading, pixel, diffuseAO, Fd, Fr);

    // clear coat layer
    evaluateClearCoatIBL(shading, pixel, diffuseAO, Fd, Fr);

    // Note: iblLuminance is already premultiplied by the exposure
    combineDiffuseAndSpecular(shading, pixel, E, Fd, Fr, color);

    #if defined(LIGHTMAP_SPECULAR)
    PixelParams pixelForBakedSpecular = pixel;

    // Remap roughness to clamp at max roughness without a hard clamp
    pixelForBakedSpecular.roughness = remap_almostIdentity(pixelForBakedSpecular.roughness,
        1-getLightmapSpecularMaxSmoothness(), 1-getLightmapSpecularMaxSmoothness()+MIN_ROUGHNESS);

    // Remove diffuse component
    pixelForBakedSpecular.diffuseColor = 0;

    if (derivedLight.NoL >= 0.0)
    {
        // derived light contribution from lightmap
        half diffuseAOForLightmap = min(material.ambientOcclusion * 0.8 + 0.3, 1.0);
        diffuseAOForLightmap = computeMicroShadowing(derivedLight.NoL, diffuseAOForLightmap);
        color += max(0, surfaceShading(shading, pixelForBakedSpecular, derivedLight, diffuseAOForLightmap));
    };
    #if defined(_VRCLV) && !UNITY_SHOULD_SAMPLE_SH
    if (volumeLight.NoL >= 0.0)
    {
        // derived light contribution from lightmap
        half diffuseAOForLightmap = min(material.ambientOcclusion * 0.8 + 0.3, 1.0);
        diffuseAOForLightmap = computeMicroShadowing(volumeLight.NoL, diffuseAOForLightmap);
        color += max(0, surfaceShading(shading, pixelForBakedSpecular, volumeLight, diffuseAOForLightmap));
    };
    #endif
    #endif
}

#endif // FILAMENT_LIGHT_INDIRECT
