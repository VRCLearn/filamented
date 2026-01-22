#ifndef FILAMENT_MATERIAL_INPUTS
#define FILAMENT_MATERIAL_INPUTS

// Decide if we can skip lighting when dot(n, l) <= 0.0
#if defined(SHADING_MODEL_CLOTH)
#if !defined(MATERIAL_HAS_SUBSURFACE_COLOR)
    #define MATERIAL_CAN_SKIP_LIGHTING
#endif
#elif defined(SHADING_MODEL_SUBSURFACE)
    // Cannot skip lighting
#else
    #define MATERIAL_CAN_SKIP_LIGHTING
#endif

struct MaterialInputs {
    half4  baseColor;
#if !defined(SHADING_MODEL_UNLIT)
#if !defined(SHADING_MODEL_SPECULAR_GLOSSINESS)
    half roughness;
#endif
#if !defined(SHADING_MODEL_CLOTH) && !defined(SHADING_MODEL_SPECULAR_GLOSSINESS)
    half metallic;
    half reflectance;
#endif
    half ambientOcclusion;
#endif
    half4  emissive;

#if !defined(SHADING_MODEL_CLOTH) && !defined(SHADING_MODEL_SUBSURFACE) && !defined(SHADING_MODEL_UNLIT)
    half3 sheenColor;
    half sheenRoughness;
#endif

    half clearCoat;
    half clearCoatRoughness;

    half anisotropy;
    half3  anisotropyDirection;

#if defined(SHADING_MODEL_SUBSURFACE) || defined(HAS_REFRACTION)
    half thickness;
#endif
#if defined(SHADING_MODEL_SUBSURFACE)
    half subsurfacePower;
    half3  subsurfaceColor;
#endif

#if defined(SHADING_MODEL_CLOTH)
    half3  sheenColor;
#if defined(MATERIAL_HAS_SUBSURFACE_COLOR)
    half3  subsurfaceColor;
#endif
#endif

#if defined(SHADING_MODEL_SPECULAR_GLOSSINESS)
    half3  specularColor;
    half glossiness;
#endif

#if defined(MATERIAL_HAS_NORMAL)
    half3  normal;
#endif
#if defined(MATERIAL_HAS_BENT_NORMAL)
    half3  bentNormal;
#endif
#if defined(MATERIAL_HAS_CLEAR_COAT) && defined(MATERIAL_HAS_CLEAR_COAT_NORMAL)
    half3  clearCoatNormal;
#endif

#if defined(MATERIAL_HAS_POST_LIGHTING_COLOR)
    half4  postLightingColor;
#endif

#if !defined(SHADING_MODEL_CLOTH) && !defined(SHADING_MODEL_SUBSURFACE) && !defined(SHADING_MODEL_UNLIT)
#if defined(HAS_REFRACTION)
#if defined(MATERIAL_HAS_ABSORPTION)
    half3 absorption;
#endif
#if defined(MATERIAL_HAS_TRANSMISSION)
    half transmission;
#endif
#if defined(MATERIAL_HAS_IOR)
    half ior;
#endif
#if defined(MATERIAL_HAS_MICRO_THICKNESS) && (REFRACTION_TYPE == REFRACTION_TYPE_THIN)
    half microThickness;
#endif
#elif !defined(SHADING_MODEL_SPECULAR_GLOSSINESS)
#if defined(MATERIAL_HAS_IOR)
    half ior;
#endif
#endif
#endif
};

void initMaterial(out MaterialInputs material) {
    material = (MaterialInputs)0;

    material.baseColor = 1.0;
#if !defined(SHADING_MODEL_UNLIT)
#if !defined(SHADING_MODEL_SPECULAR_GLOSSINESS)
    material.roughness = 1.0;
#endif
#if !defined(SHADING_MODEL_CLOTH) && !defined(SHADING_MODEL_SPECULAR_GLOSSINESS)
    material.metallic = 0.0;
    material.reflectance = 0.5;
#endif
    material.ambientOcclusion = 1.0;
#endif
    material.emissive = half4(half3(0.0.xxx), 1.0);

#if !defined(SHADING_MODEL_CLOTH) && !defined(SHADING_MODEL_SUBSURFACE) && !defined(SHADING_MODEL_UNLIT)
#if defined(MATERIAL_HAS_SHEEN_COLOR)
    material.sheenColor = half3(0.0.xxx);
    material.sheenRoughness = 0.0;
#endif
#endif

#if defined(MATERIAL_HAS_CLEAR_COAT)
    material.clearCoat = 1.0;
    material.clearCoatRoughness = 0.0;
#endif

#if defined(MATERIAL_HAS_ANISOTROPY)
    material.anisotropy = 0.0;
    material.anisotropyDirection = half3(1.0, 0.0, 0.0);
#endif

#if defined(SHADING_MODEL_SUBSURFACE) || defined(HAS_REFRACTION)
    material.thickness = 0.5;
#endif
#if defined(SHADING_MODEL_SUBSURFACE)
    material.subsurfacePower = 12.234;
    material.subsurfaceColor = half3(1.0.xxx);
#endif

#if defined(SHADING_MODEL_CLOTH)
    material.sheenColor = sqrt(material.baseColor.rgb);
#if defined(MATERIAL_HAS_SUBSURFACE_COLOR)
    material.subsurfaceColor = half3(0.0.xxx);
#endif
#endif

#if defined(SHADING_MODEL_SPECULAR_GLOSSINESS)
    material.glossiness = 0.0;
    material.specularColor = half3(0.0.xxx);
#endif

#if defined(MATERIAL_HAS_NORMAL)
    material.normal = half3(0.0, 0.0, 1.0);
#endif
#if defined(MATERIAL_HAS_BENT_NORMAL)
    material.bentNormal = half3(0.0, 0.0, 1.0);
#endif
#if defined(MATERIAL_HAS_CLEAR_COAT) && defined(MATERIAL_HAS_CLEAR_COAT_NORMAL)
    material.clearCoatNormal = half3(0.0, 0.0, 1.0);
#endif

#if defined(MATERIAL_HAS_POST_LIGHTING_COLOR)
    material.postLightingColor = half4(0.0.xxx);
#endif

#if !defined(SHADING_MODEL_CLOTH) && !defined(SHADING_MODEL_SUBSURFACE) && !defined(SHADING_MODEL_UNLIT)
#if defined(HAS_REFRACTION)
#if defined(MATERIAL_HAS_ABSORPTION)
    material.absorption = half3(0.0.xxx);
#endif
#if defined(MATERIAL_HAS_TRANSMISSION)
    material.transmission = 1.0;
#endif
#if defined(MATERIAL_HAS_IOR)
    material.ior = 1.5;
#endif
#if defined(MATERIAL_HAS_MICRO_THICKNESS) && (REFRACTION_TYPE == REFRACTION_TYPE_THIN)
    material.microThickness = 0.0;
#endif
#elif !defined(SHADING_MODEL_SPECULAR_GLOSSINESS)
#if defined(MATERIAL_HAS_IOR)
    material.ior = 1.5;
#endif
#endif
#endif
}

#if defined(MATERIAL_HAS_CUSTOM_SURFACE_SHADING)
/** @public-api */
struct LightData {
    half4  colorIntensity;
    half3  l;
    half NdotL;
    half3  worldPosition;
    half attenuation;
    half visibility;
};

/** @public-api */
struct ShadingData {
    half3  diffuseColor;
    half perceptualRoughness;
    half3  f0;
    half roughness;
};
#endif

#endif // FILAMENT_MATERIAL_INPUTS
