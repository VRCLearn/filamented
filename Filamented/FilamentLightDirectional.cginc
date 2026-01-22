#ifndef FILAMENT_LIGHT_DIRECTIONAL
#define FILAMENT_LIGHT_DIRECTIONAL

#include "UnityLightingCommon.cginc"
//------------------------------------------------------------------------------
// Directional light evaluation
//------------------------------------------------------------------------------

#if FILAMENT_QUALITY < FILAMENT_QUALITY_HIGH
//#define SUN_AS_AREA_LIGHT
#endif

half3 sampleSunAreaLight(const half3 lightDirection, const ShadingParams shading) {
    // Replaced frameUniforms.sun
#if defined(SUN_AS_AREA_LIGHT)
    // cos(sunAngle), sin(sunAngle), 1/(sunAngle*HALO_SIZE-sunAngle), HALO_EXP
    static const half sunAngle = 0.00951f;
    static const half sunHaloSize = 10.0f;
    static const half sunHaloFalloff = 80.0f;
    static const half4 sunParameters = half4(cos(sunAngle), sin(sunAngle), 1/(sunAngle*sunHaloSize-sunAngle), sunHaloFalloff);
    if (sunParameters.w >= 0.0) {
        // simulate sun as disc area light
        half LoR = dot(lightDirection, shading.reflected);
        half d = sunParameters.x;
        float3 s = shading.reflected - LoR * lightDirection;
        return LoR < d ?
                normalize(lightDirection * d + normalize(s) * sunParameters.y) : shading.reflected;
    }
#endif
    return lightDirection;
}

half4 UnityLight_ColorIntensitySeperated() {
    return half4(_LightColor0.xyz, 1.0);

    if (_LightColor0.w <= 0) return 0.0;
    _LightColor0 += 0.000001;
    return half4(_LightColor0.xyz / _LightColor0.w, _LightColor0.w);
}

Light getDirectionalLight(ShadingParams shading) {
    Light light;
    // note: lightColorIntensity.w is always premultiplied by the exposure
    light.colorIntensity = UnityLight_ColorIntensitySeperated();
    light.l = sampleSunAreaLight(_WorldSpaceLightPos0.xyz, shading);
    light.attenuation = 1.0;
    light.NoL = saturate(dot(shading.normal, light.l));
    return light;
}

// Much of this function has changed from the original because we still use
// Unity's BIRP shadow handling. Sorry!
void evaluateDirectionalLight(const ShadingParams shading, const MaterialInputs material,
        const PixelParams pixel, inout half3 color) {

    Light light = getDirectionalLight(shading);

    half visibility = 1.0;
#if defined(HAS_SHADOWING)
    if (light.NoL > 0.0) {
        half ssContactShadowOcclusion = 0.0;

        // hasDirectionalShadows && cascadeHasVisibleShadows
        if (1) {
            visibility*=shading.attenuation;
            // apply directional shadows to visibility here
        }
        // if contact shadows are enabled
        if (true && visibility > 0.0) {
            // ssContactShadowOcclusion = screenSpaceContactShadow(light.l);
        }

        visibility *= 1.0 - ssContactShadowOcclusion;

        #if defined(MATERIAL_HAS_AMBIENT_OCCLUSION)
        visibility *= computeMicroShadowing(light.NoL, material.ambientOcclusion * 1.6 + 0.2);
        #endif
    } else {
#if defined(MATERIAL_CAN_SKIP_LIGHTING)
        return;
#endif
    }
#elif defined(MATERIAL_CAN_SKIP_LIGHTING)
    if (light.NoL <= 0.0) return;
#endif

    color.rgb += surfaceShading(shading, pixel, light, visibility);
}

#endif // FILAMENT_LIGHT_DIRECTIONAL
