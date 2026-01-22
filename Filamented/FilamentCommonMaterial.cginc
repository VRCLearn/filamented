#ifndef FILAMENT_COMMON_MATERIAL
#define FILAMENT_COMMON_MATERIAL

#if defined(TARGET_MOBILE)
    // min roughness such that (MIN_PERCEPTUAL_ROUGHNESS^4) > 0 in fp16 (i.e. 2^(-14/4), rounded up)
    #define MIN_PERCEPTUAL_ROUGHNESS 0.089
    #define MIN_ROUGHNESS            0.007921
#else
    #define MIN_PERCEPTUAL_ROUGHNESS 0.045
    #define MIN_ROUGHNESS            0.002025
#endif

#define MIN_N_DOT_V 1e-4

half clampNoV(half NoV) {
    // Neubelt and Pettineo 2013, "Crafting a Next-gen Material Pipeline for The Order: 1886"
    return max(NoV, MIN_N_DOT_V);
}

half3 computeDiffuseColor(const half4 baseColor, half metallic) {
    return baseColor.rgb * (1.0 - metallic);
}

half3 computeF0(const half4 baseColor, half metallic, half reflectance) {
    return baseColor.rgb * metallic + (reflectance * (1.0 - metallic));
}

half computeDielectricF0(half reflectance) {
    return 0.16 * reflectance * reflectance;
}

half computeMetallicFromSpecularColor(const half3 specularColor) {
    return max3(specularColor);
}

half computeRoughnessFromGlossiness(half glossiness) {
    return 1.0 - glossiness;
}

half perceptualRoughnessToRoughness(half perceptualRoughness) {
    return perceptualRoughness * perceptualRoughness;
}

half roughnessToPerceptualRoughness(half roughness) {
    return sqrt(roughness);
}

half iorToF0(half transmittedIor, half incidentIor) {
    return sq((transmittedIor - incidentIor) / (transmittedIor + incidentIor));
}

half f0ToIor(half f0) {
    half r = sqrt(f0);
    return (1.0 + r) / (1.0 - r);
}

half3 f0ClearCoatToSurface(const half3 f0) {
    // Approximation of iorTof0(f0ToIor(f0), 1.5)
    // This assumes that the clear coat layer has an IOR of 1.5
#if FILAMENT_QUALITY == FILAMENT_QUALITY_LOW
    return saturate(f0 * (f0 * 0.526868 + 0.529324) - 0.0482256);
#else
    return saturate(f0 * (f0 * (0.941892 - 0.263008 * f0) + 0.346479) - 0.0285998);
#endif
}
#endif // FILAMENT_COMMON_MATERIAL
