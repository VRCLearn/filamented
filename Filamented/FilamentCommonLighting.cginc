#ifndef FILAMENT_COMMON_LIGHTING
#define FILAMENT_COMMON_LIGHTING

struct Light {
    float4 colorIntensity;  // rgb, pre-exposed intensity
    float3 l;
    half attenuation;
    half NoL;
    float3 worldPosition;
};

struct PixelParams {
    half3  diffuseColor;
    half perceptualRoughness;
    half perceptualRoughnessUnclamped;
    half3  f0;
    half roughness;
    half3  dfg;
    half3  energyCompensation;

#if defined(MATERIAL_HAS_CLEAR_COAT)
    half clearCoat;
    half clearCoatPerceptualRoughness;
    half clearCoatRoughness;
#endif

#if defined(MATERIAL_HAS_SHEEN_COLOR)
    half3  sheenColor;
#if !defined(SHADING_MODEL_CLOTH)
    half sheenRoughness;
    half sheenPerceptualRoughness;
    half sheenScaling;
    half sheenDFG;
#endif
#endif

#if defined(MATERIAL_HAS_ANISOTROPY)
    half3  anisotropicT;
    half3  anisotropicB;
    half anisotropy;
#endif

#if defined(SHADING_MODEL_SUBSURFACE) || defined(HAS_REFRACTION)
    half thickness;
#endif
#if defined(SHADING_MODEL_SUBSURFACE)
    half3  subsurfaceColor;
    half subsurfacePower;
#endif

#if defined(SHADING_MODEL_CLOTH) && defined(MATERIAL_HAS_SUBSURFACE_COLOR)
    half3  subsurfaceColor;
#endif

#if defined(HAS_REFRACTION)
    half etaRI;
    half etaIR;
    half transmission;
    half uThickness;
    half3 absorption;
#endif
};

half computeMicroShadowing(half NoL, half visibility) {
    // Chan 2018, "Material Advances in Call of Duty: WWII"
    half aperture = rsqrt(1.0 - visibility);
    half microShadow = saturate(NoL * aperture);
    return microShadow * microShadow;
};

#endif // FILAMENT_COMMON_LIGHTING
