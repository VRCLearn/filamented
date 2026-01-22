#ifndef FILAMENT_LIGHT_DYNAMIC
#define FILAMENT_LIGHT_DYNAMIC

#include "UnityLightingCommon.cginc"
//------------------------------------------------------------------------------
// Punctual lights evaluation
//------------------------------------------------------------------------------

// This is based off light_directional, not light_punctual, because of Unity's
// light model.

half4 UnityLight_ColorIntensitySeperated_Punctual() {
    return half4(_LightColor0.xyz, 1.0);

    if (_LightColor0.w <= 0) return 0.0;
    return half4(_LightColor0.xyz / _LightColor0.w, _LightColor0.w);
}

half getSquareFalloffAttenuation(half distanceSquare, half falloff) {
    half factor = distanceSquare * falloff;
    half smoothFactor = saturate(1.0 - factor * factor);
    // We would normally divide by the square distance here
    // but we do it at the call site
    return smoothFactor * smoothFactor;
}

half getDistanceAttenuation(const half3 posToLight, half falloff) {
    half distanceSquare = dot(posToLight, posToLight);
    half attenuation = getSquareFalloffAttenuation(distanceSquare, falloff);
    // Assume a punctual light occupies a volume of 1cm to avoid a division by 0
    return attenuation * 1.0 / max(distanceSquare, 1e-4);
}

half getAngleAttenuation(const half3 lightDir, const half3 l, const half2 scaleOffset) {
    half cd = dot(lightDir, l);
    half attenuation = saturate(cd * scaleOffset.x + scaleOffset.y);
    return attenuation * attenuation;
}

Light getLight(ShadingParams shading) {
    Light light;

    // position-to-light vector
    float3 posToLight = _WorldSpaceLightPos0.xyz - shading.position;

    // note: lightColorIntensity.w is always premultiplied by the exposure
    light.colorIntensity = UnityLight_ColorIntensitySeperated_Punctual();
    light.l = normalize(posToLight);
    light.attenuation = shading.attenuation; //getDistanceAttenuation(posToLight, _WorldSpaceLightPos0.w);
    light.NoL = saturate(dot(shading.normal, light.l));
    light.worldPosition = _WorldSpaceLightPos0.xyz;
    return light;
}

// Much of this function has changed from the original because we still use
// Unity's BIRP shadow handling. Sorry!
void evaluatePunctualLights(const ShadingParams shading, const PixelParams pixel, inout half3 color) {

    Light light = getLight(shading);

    half visibility = 1.0;
#if defined(HAS_SHADOWING)
    if (light.NoL > 0.0) {
        float ssContactShadowOcclusion = 0.0;

        // hasDirectionalShadows && cascadeHasVisibleShadows
        if (1) {
            //visibility*=shading.attenuation;
            // apply directional shadows to visibility here
        }
        // if contact shadows are enabled
        if (true && visibility > 0.0) {
            // ssContactShadowOcclusion = screenSpaceContactShadow(light.l);
        }

        visibility *= 1.0 - ssContactShadowOcclusion;
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

#endif // FILAMENT_LIGHT_DYNAMIC
