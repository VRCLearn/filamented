#ifndef FILAMENT_BRDF_INCLUDED
#define FILAMENT_BRDF_INCLUDED

//------------------------------------------------------------------------------
// BRDF configuration
//------------------------------------------------------------------------------

// Diffuse BRDFs
#define DIFFUSE_LAMBERT             0
#define DIFFUSE_BURLEY              1

// Specular BRDF
// Normal distribution functions
#define SPECULAR_D_GGX              0

// Anisotropic NDFs
#define SPECULAR_D_GGX_ANISOTROPIC  0

// Cloth NDFs
#define SPECULAR_D_CHARLIE          0

// Visibility functions
#define SPECULAR_V_SMITH_GGX        0
#define SPECULAR_V_SMITH_GGX_FAST   1
#define SPECULAR_V_GGX_ANISOTROPIC  2
#define SPECULAR_V_KELEMEN          3
#define SPECULAR_V_NEUBELT          4

// Fresnel functions
#define SPECULAR_F_SCHLICK          0

#define BRDF_DIFFUSE                DIFFUSE_BURLEY

#if FILAMENT_QUALITY < FILAMENT_QUALITY_HIGH
#define BRDF_SPECULAR_D             SPECULAR_D_GGX
#define BRDF_SPECULAR_V             SPECULAR_V_SMITH_GGX_FAST
#define BRDF_SPECULAR_F             SPECULAR_F_SCHLICK
#else
#define BRDF_SPECULAR_D             SPECULAR_D_GGX
#define BRDF_SPECULAR_V             SPECULAR_V_SMITH_GGX
#define BRDF_SPECULAR_F             SPECULAR_F_SCHLICK
#endif

#define BRDF_CLEAR_COAT_D           SPECULAR_D_GGX
#define BRDF_CLEAR_COAT_V           SPECULAR_V_KELEMEN

#define BRDF_ANISOTROPIC_D          SPECULAR_D_GGX_ANISOTROPIC
#define BRDF_ANISOTROPIC_V          SPECULAR_V_GGX_ANISOTROPIC

#define BRDF_CLOTH_D                SPECULAR_D_CHARLIE
#define BRDF_CLOTH_V                SPECULAR_V_NEUBELT

//------------------------------------------------------------------------------
// Specular BRDF implementations
//------------------------------------------------------------------------------

half D_GGX(half roughness, half NoH, half3 NxH, const half3 h) {
    // Walter et al. 2007, "Microfacet Models for Refraction through Rough Surfaces"

    // In mediump, there are two problems computing 1.0 - NoH^2
    // 1) 1.0 - NoH^2 suffers floating point cancellation when NoH^2 is close to 1 (highlights)
    // 2) NoH doesn't have enough precision around 1.0
    // Both problem can be fixed by computing 1-NoH^2 in highp and providing NoH in highp as well

    // However, we can do better using Lagrange's identity:
    //      ||a x b||^2 = ||a||^2 ||b||^2 - (a . b)^2
    // since N and H are unit vectors: ||N x H||^2 = 1.0 - NoH^2
    // This computes 1.0 - NoH^2 directly (which is close to zero in the highlights and has
    // enough precision).
    // Overall this yields better performance, keeping all computations in mediump
#if defined(TARGET_MOBILE)
    half oneMinusNoHSquared = dot(NxH, NxH);
#else
    half oneMinusNoHSquared = 1.0 - NoH * NoH;
#endif

    half a = NoH * roughness;
    half k = min(roughness / (oneMinusNoHSquared + a * a), 453.5); // 453.5 prevents fp16 overflow
    half d = k * (k * (1.0 / PI));
    return d;
}

half D_GGX_Anisotropic(half at, half ab, half ToH, half BoH, half NoH) {
    // Burley 2012, "Physically-Based Shading at Disney"

    // The values at and ab are perceptualRoughness^2, a2 is therefore perceptualRoughness^4
    // The dot product below computes perceptualRoughness^8. We cannot fit in fp16 without clamping
    // the roughness to too high values so we perform the dot product and the division in fp32
    half a2 = at * ab;
    float3 d = float3(ab * ToH, at * BoH, a2 * NoH);
    float d2 = dot(d, d);
    half b2 = a2 / d2;
    return a2 * b2 * b2 * (1.0 / PI);
}

half D_Charlie(half roughness, half NoH) {
    // Estevez and Kulla 2017, "Production Friendly Microfacet Sheen BRDF"
    half invAlpha  = 1.0 / roughness;
    half cos2h = NoH * NoH;
    half sin2h = max(1.0 - cos2h, 0.0078125); // 2^(-14/2), so sin2h^2 > 0 in fp16
    return (2.0 + invAlpha) * pow(sin2h, invAlpha * 0.5) / (2.0 * PI);
}

half V_SmithGGXCorrelated(half roughness, half NoV, half NoL) {
    // Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"
    half a2 = roughness * roughness;
    // TODO: lambdaV can be pre-computed for all the lights, it should be moved out of this function
    half lambdaV = NoL * sqrt((NoV - a2 * NoV) * NoV + a2);
    half lambdaL = NoV * sqrt((NoL - a2 * NoL) * NoL + a2);
    // 0.0000077 = nextafter(0.5 / MEDIUMP_FLT_MAX, 1.0) in fp16, so we don't overflow
    half v = PREVENT_DIV0(0.5, lambdaV + lambdaL, 0.0000077);
    // a2=0 => v = 1 / 4*NoL*NoV   => min=1/4, max=+inf
    // a2=1 => v = 1 / 2*(NoL+NoV) => min=1/4, max=+inf
    return v;
}

half V_SmithGGXCorrelated_Fast(half roughness, half NoV, half NoL) {
    // Hammon 2017, "PBR Diffuse Lighting for GGX+Smith Microsurfaces"
    // 0.0000077 = nextafter(0.5 / MEDIUMP_FLT_MAX, 1.0) in fp16, so we don't overflow
    half v = PREVENT_DIV0(0.5, lerp(2.0 * NoL * NoV, NoL + NoV, roughness), 0.0000077);
    return v;
}

half V_SmithGGXCorrelated_Anisotropic(half at, half ab, half ToV, half BoV,
        half ToL, half BoL, half NoV, half NoL) {
    // Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"
    // TODO: lambdaV can be pre-computed for all the lights, it should be moved out of this function
    half lambdaV = NoL * length(half3(at * ToV, ab * BoV, NoV));
    half lambdaL = NoV * length(half3(at * ToL, ab * BoL, NoL));
    // 0.0000077 = nextafter(0.5 / MEDIUMP_FLT_MAX, 1.0) in fp16, so we don't overflow
    half v = PREVENT_DIV0(0.5, lambdaV + lambdaL, 0.0000077);
    return v;
}

half V_Kelemen(half LoH) {
    // Kelemen 2001, "A Microfacet Based Coupled Specular-Matte BRDF Model with Importance Sampling"
    // 0.0000039 = nextafter(0.25 / MEDIUMP_FLT_MAX, 1.0) in fp16, so we don't overflow
    return PREVENT_DIV0(0.25, LoH * LoH, 0.0000039);
}

half V_Neubelt(half NoV, half NoL) {
    // Neubelt and Pettineo 2013, "Crafting a Next-gen Material Pipeline for The Order: 1886"
    // 0.00001532 = nextafter(1.0 / MEDIUMP_FLT_MAX, 1.0) in fp16, so we don't overflow
    return PREVENT_DIV0(1.0, 4.0 * (NoL + NoV - NoL * NoV), 0.00001532);
}

half3 F_Schlick(const half3 f0, half f90, half VoH) {
    // Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"
    return f0 + (f90 - f0) * pow5(1.0 - VoH);
}

half3 F_Schlick(const half3 f0, half VoH) {
    half f = pow(1.0 - VoH, 5.0);
    return f + f0 * (1.0 - f);
}

half F_Schlick(half f0, half f90, half VoH) {
    return f0 + (f90 - f0) * pow5(1.0 - VoH);
}

//------------------------------------------------------------------------------
// Specular BRDF dispatch
//------------------------------------------------------------------------------

half distribution(half roughness, half NoH, half3 NxH, const half3 h) {
#if BRDF_SPECULAR_D == SPECULAR_D_GGX
    return D_GGX(roughness, NoH, NxH, h);
#endif
}

half visibility(half roughness, half NoV, half NoL) {
#if BRDF_SPECULAR_V == SPECULAR_V_SMITH_GGX
    return V_SmithGGXCorrelated(roughness, NoV, NoL);
#elif BRDF_SPECULAR_V == SPECULAR_V_SMITH_GGX_FAST
    return V_SmithGGXCorrelated_Fast(roughness, NoV, NoL);
#endif
}

half3 fresnel(const half3 f0, half LoH) {
#if BRDF_SPECULAR_F == SPECULAR_F_SCHLICK
#if FILAMENT_QUALITY == FILAMENT_QUALITY_LOW
    return F_Schlick(f0, LoH); // f90 = 1.0
#else
    half f90 = saturate(dot(f0, (50.0 * 0.33)));
    return F_Schlick(f0, f90, LoH);
#endif
#endif
}

half3 fresnel(const half3 f0, const half f90, half LoH) {
#if BRDF_SPECULAR_F == SPECULAR_F_SCHLICK
    return F_Schlick(f0, f90, LoH);
#endif
}

half distributionAnisotropic(half at, half ab, half ToH, half BoH, half NoH) {
#if BRDF_ANISOTROPIC_D == SPECULAR_D_GGX_ANISOTROPIC
    return D_GGX_Anisotropic(at, ab, ToH, BoH, NoH);
#endif
}

half visibilityAnisotropic(half roughness, half at, half ab,
        half ToV, half BoV, half ToL, half BoL, half NoV, half NoL) {
#if BRDF_ANISOTROPIC_V == SPECULAR_V_SMITH_GGX
    return V_SmithGGXCorrelated(roughness, NoV, NoL);
#elif BRDF_ANISOTROPIC_V == SPECULAR_V_GGX_ANISOTROPIC
    return V_SmithGGXCorrelated_Anisotropic(at, ab, ToV, BoV, ToL, BoL, NoV, NoL);
#endif
}

half distributionClearCoat(half roughness, half NoH, half3 NxH, const half3 h) {
#if BRDF_CLEAR_COAT_D == SPECULAR_D_GGX
    return D_GGX(roughness, NoH, NxH, h);
#endif
}

half visibilityClearCoat(half LoH) {
#if BRDF_CLEAR_COAT_V == SPECULAR_V_KELEMEN
    return V_Kelemen(LoH);
#endif
}

half distributionCloth(half roughness, half NoH) {
#if BRDF_CLOTH_D == SPECULAR_D_CHARLIE
    return D_Charlie(roughness, NoH);
#endif
}

half visibilityCloth(half NoV, half NoL) {
#if BRDF_CLOTH_V == SPECULAR_V_NEUBELT
    return V_Neubelt(NoV, NoL);
#endif
}

//------------------------------------------------------------------------------
// Diffuse BRDF implementations
//------------------------------------------------------------------------------

half Fd_Lambert() {
    return 1.0 / PI;
}

half Fd_Burley(half roughness, half NoV, half NoL, half LoH) {
    // Burley 2012, "Physically-Based Shading at Disney"
    half f90 = 0.5 + 2.0 * roughness * LoH * LoH;
    half lightScatter = F_Schlick(1.0, f90, NoL);
    half viewScatter  = F_Schlick(1.0, f90, NoV);
    return lightScatter * viewScatter * (1.0 / PI);
}

// Energy conserving wrap diffuse term, does *not* include the divide by pi
half Fd_Wrap(half NoL, half w) {
    return saturate((NoL + w) / sq(1.0 + w));
}

//------------------------------------------------------------------------------
// Diffuse BRDF dispatch
//------------------------------------------------------------------------------

half diffuse(half roughness, half NoV, half NoL, half LoH) {
#if BRDF_DIFFUSE == DIFFUSE_LAMBERT
    return Fd_Lambert();
#elif BRDF_DIFFUSE == DIFFUSE_BURLEY
    return Fd_Burley(roughness, NoV, NoL, LoH);
#endif
}

#endif // FILAMENT_BRDF_INCLUDED
