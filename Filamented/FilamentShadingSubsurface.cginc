#ifndef FILAMENT_SHADING_SUBSURFACE_INCLUDED
#define FILAMENT_SHADING_SUBSURFACE_INCLUDED

#include "FilamentBRDF.cginc"
/**
 * Evalutes lit materials with the subsurface shading model. This model is a
 * combination of a BRDF (the same used in shading_model_standard.fs, refer to that
 * file for more information) and of an approximated BTDF to simulate subsurface
 * scattering. The BTDF itself is not physically based and does not represent a
 * correct interpretation of transmission events.
 */
half3 surfaceShading(const ShadingParams shading, const PixelParams pixel, const Light light, half occlusion) {
    half3 h = normalize(shading.view + light.l);

    half NoL = light.NoL;
    half NoH = saturate(dot(shading.normal, h));
    half LoH = saturate(dot(light.l, h));
    half3 NxH = cross(shading.normal, h);

    half3 Fr = 0.0;
    if (NoL > 0.0) {
        // specular BRDF
        half D = distribution(pixel.roughness, NoH, NxH, h);
        half V = visibility(pixel.roughness, shading.NoV, NoL);
        half3  F = fresnel(pixel.f0, LoH);
        Fr = (D * V) * F * pixel.energyCompensation;
    }

    // diffuse BRDF
    half3 Fd = pixel.diffuseColor * diffuse(pixel.roughness, shading.NoV, NoL, LoH);

    // NoL does not apply to transmitted light
    half3 color = (Fd + Fr) * (NoL * occlusion);

    // subsurface scattering
    // Use a spherical gaussian approximation of pow() for forwardScattering
    // We could include distortion by adding shading.normal * distortion to light.l
    half scatterVoH = saturate(dot(shading.view, -light.l));
    half forwardScatter = exp2(scatterVoH * pixel.subsurfacePower - pixel.subsurfacePower);
    half backScatter = saturate(NoL * pixel.thickness + (1.0 - pixel.thickness)) * 0.5;
    half subsurface = lerp(backScatter, 1.0, forwardScatter) * (1.0 - pixel.thickness);
    color += pixel.subsurfaceColor * (subsurface * Fd_Lambert());

    // TODO: apply occlusion to the transmitted light
    return (color * light.colorIntensity.rgb) * (light.colorIntensity.w * light.attenuation);
}

#endif // FILAMENT_SHADING_SUBSURFACE_INCLUDED
