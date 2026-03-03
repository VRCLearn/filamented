Shader "Silent/Filamented Extras/Filamented Glinty"
{
    Properties
    {
        [CheckDFGTexture]
        [ScaleOffset][SingleLine(_Color)]_MainTex("Albedo", 2D) = "white" {}
        [HideInInspector]_Color("Color", Color) = (1,1,1,1)
        [Space]
        [SingleLine(_BumpScale)][Normal] _BumpMap("Normal", 2D) = "bump" {}
        [HideInInspector]_BumpScale("Normal Scale", Float) = 1
        [Space]
        [SingleLine]_MOESMap("MOES Map", 2D) = "white" {}
        [Space]
        _MetallicScale("Metallic", Range( 0 , 1)) = 0
        _OcclusionScale("Occlusion", Range( 0 , 1)) = 0
        _SmoothnessScale("Smoothness", Range( 0 , 1)) = 0
        [Space]
        _Emission("Emission Power", Float) = 0
        _EmissionColor("Emission Color", Color) = (1,1,1,1)
        [Header(Glint Properties)][Space]
        _SpecularGlintSize("Glint Size", Range(0, 1)) = 0.5
        _SpecularGlintDensity("Glint Density", Range(0, 1)) = 0.5
        [Header(Clear Coat Properties)][Space]
        [SingleLine]_ClearCoatMap("Clear Coat Map (R: Intensity, G: Roughness)", 2D) = "white" {}
        _ClearCoat("Clear Coat Intensity", Range(0, 1)) = 0.0
        _ClearCoatRoughness("Clear Coat Roughness", Range(0, 1)) = 0.0
        [Header(System Settings)][Space]
        [Toggle(_LIGHTMAPSPECULAR)]_LightmapSpecular("Lightmap Specular", Range(0, 1)) = 1
        _LightmapSpecularMaxSmoothness("Lightmap Specular Max Smoothness", Range(0, 1)) = 1
        _ExposureOcclusion("Lightmap Occlusion Sensitivity", Range(0, 1)) = 0.2
        [Space]
        [KeywordEnum(None, SH, RNM, MonoSH)] _Bakery ("Bakery Mode", Int) = 0
        [HideInInspector]_RNM0("RNM0", 2D) = "black" {}
        [HideInInspector]_RNM1("RNM1", 2D) = "black" {}
        [HideInInspector]_RNM2("RNM2", 2D) = "black" {}
        [Toggle(_LTCGI)] _LTCGI ("LTCGI", Int) = 0
        [Toggle(_VRCLV)] _VRCLV ("VRC Light Volumes", Int) = 0
        [IfDef(_VRCLV)] _VRCLVSurfaceBias("Light Volume Surface Bias", Range(0, 0.5)) = 0.05
        [Space]
        [Enum(UnityEngine.Rendering.CullMode)]_CullMode("Cull Mode", Int) = 2
        [Toggle(_ALPHATEST_ON)]_AtoCmode("Cutout Transparency", Float) = 0

        [NonModifiableTextureData][HideInInspector] _DFG("DFG", 2D) = "white" {}
    }

    HLSLINCLUDE
    #define fixed half
    #define fixed2 half2
    #define fixed3 half3
    #define fixed4 half4
    ENDHLSL

    HLSLINCLUDE
    	// First, setup what Filamented does.
    	// Filamented's behaviour is decided by the shading model and what material properties are defined.
    	// These are listed in FilamentMaterialInputs.
    	// You can set up and use anything in the initMaterials function.

		// SHADING_MODEL_CLOTH
		// SHADING_MODEL_SUBSURFACE
    	// These are *not* currently supported.

    	// SHADING_MODEL_SPECULAR_GLOSSINESS
    	// If this is not defined, the material will default to metallic/roughness workflow.

    	#define MATERIAL_HAS_NORMAL
    	// If this is not defined, normal maps won't be enabled.

    	#define MATERIAL_HAS_AMBIENT_OCCLUSION
    	// If this is not defined, occlusion won't be taken into account

    	#define MATERIAL_HAS_EMISSIVE
    	// If this is not defined, emission won't be taken into account

    	// MATERIAL_HAS_ANISOTROPY
    	// If this is set, the material will support anisotropy.

    	#define MATERIAL_HAS_CLEAR_COAT
    	// If this is set, the material will support clear coat.

        // HAS_ATTRIBUTE_COLOR
        // If this is not defined, vertex colour will not be available.

        #define MATERIAL_HAS_GLINT
    	// If this is set, the material will support glint specular.
        // Not compatible with cloth/anisotropy.

        #define USE_DFG_LUT
        // Whether to use the lookup texture for specular reflection calculation.
        // Requires a shader property _DFG to be present and filled.
    ENDHLSL

    HLSLINCLUDE
    #ifndef UNITY_PASS_SHADOWCASTER

    // Include common files. These will include the other files as needed.
    #include "Packages/s-ilent.filamented/Filamented/UnityLightingCommon.cginc"
    #include "Packages/s-ilent.filamented/Filamented/UnityStandardInput.cginc"
    #include "Packages/s-ilent.filamented/Filamented/UnityStandardConfig.cginc"
    #include "Packages/s-ilent.filamented/Filamented/UnityStandardCore.cginc"
	// Note: Unfortunately, Input is still needed due to some interdependancies with other Unity files.
	// This means that some properties will always be defined, even if they aren't used.
	// In practise, this won't affect the final compilation, but it means you'll need to watch out for the names
	// of some common parameters. In this case, only MOESMap and some other properties are defined here because
	// they are already defined in Input.

    // uniform sampler2D _MainTex;
    // uniform sampler2D _BumpMap;
    uniform sampler2D _MOESMap;
	// uniform half _BumpScale;
	uniform half _MetallicScale;
	uniform half _OcclusionScale;
	uniform half _SmoothnessScale;
	uniform half _Emission;
	// uniform half3 _EmissionColor;

    uniform half _SpecularGlintSize;
    uniform half _SpecularGlintDensity;

    uniform sampler2D _ClearCoatMap;
    uniform half _ClearCoat;
    uniform half _ClearCoatRoughness;

	// Vertex functions are called from UnityStandardCore.
	// You can alter values here, or copy the function in and modify it.
	VertexOutputForwardBase vertBase (VertexInput v) { return vertForwardBase(v); }
	VertexOutputForwardAdd vertAdd (VertexInput v) { return vertForwardAdd(v); }

	// The material function itself!  You can alter the code below to add extra properties.
inline MaterialInputs MyMaterialSetup (inout float4 i_tex, float3 i_eyeVec, half3 i_viewDirForParallax, float4 tangentToWorld[3], float3 i_posWorld)
{
    half4 baseColor = tex2D (_MainTex, i_tex.xy) * _Color;
    half4 packedMap = tex2D (_MOESMap, i_tex.xy);
    half3 normalTangent = UnpackScaleNormal(tex2D (_BumpMap, i_tex.xy), _BumpScale);
    half4 ccMap = tex2D(_ClearCoatMap, i_tex.xy);

    half metallic = packedMap.x * _MetallicScale;
    half occlusion = lerp(1, packedMap.y, _OcclusionScale);
    half emissionMask = packedMap.z;
    half smoothness = packedMap.w * _SmoothnessScale;

    half internal_glint_alpha = lerp(0.001, 0.1, _SpecularGlintSize * _SpecularGlintSize);
    half internal_density = pow(10.0, lerp(3.0, 9.0, _SpecularGlintDensity));

    MaterialInputs material = (MaterialInputs)0;
    initMaterial(material);
    material.baseColor = baseColor;
    material.metallic = metallic;
    material.roughness = computeRoughnessFromGlossiness(smoothness);
    material.normal = normalTangent;
    material.emissive.rgb = baseColor.rgb * emissionMask * _Emission * _EmissionColor;
    material.emissive.a = 1.0;
    material.ambientOcclusion = occlusion;

    material.uv = i_tex.xy;
    material.glintAlpha = internal_glint_alpha;
    material.glintDensity = internal_density;

    material.clearCoat = ccMap.r * _ClearCoat;
    material.clearCoatRoughness = ccMap.g * _ClearCoatRoughness;

    return material;
}

half4 fragForwardBaseTemplate (VertexOutputForwardBase i)
{
    UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);

    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

    ShadingParams shading = (ShadingParams)0;
    // Initialize shading with expected parameters
    computeShadingParamsForwardBase(shading, i);

    UNITY_LIGHT_ATTENUATION(atten, i, shading.position);

    #if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
    GetBakedAttenuation(atten, i.ambientOrLightmapUV.xy, shading.position);
    #endif

    // Your material setup goes here.
    MaterialInputs material =
    MyMaterialSetup(i.tex, i.eyeVec.xyz, IN_VIEWDIR4PARALLAX(i), i.tangentToWorldAndPackedData, IN_WORLDPOS(i));

    prepareMaterial(shading, material);

#if (defined(_NORMALMAP) && defined(NORMALMAP_SHADOW))
    float noise = noiseR2(i.pos.xy);
    float nmShade = NormalTangentShadow (i.tex, i.lightDirTS, noise);
    shading.attenuation = min(shading.attenuation, max(1-nmShade, 0));
#endif

    float4 c = evaluateMaterial (shading, material);

    UNITY_EXTRACT_FOG_FROM_EYE_VEC(i);
    UNITY_APPLY_FOG(_unity_fogCoord, c.rgb);
    return c;
}

half4 fragForwardAddTemplate (VertexOutputForwardAdd i)
{
    UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);

    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

    ShadingParams shading = (ShadingParams)0;
    // Initialize shading with expected parameters
    computeShadingParamsForwardAdd(shading, i);

    UNITY_LIGHT_ATTENUATION(atten, i, shading.position);

    // Your material setup goes here.
    MaterialInputs material =
    MyMaterialSetup(i.tex, i.eyeVec.xyz, IN_VIEWDIR4PARALLAX_FWDADD(i), i.tangentToWorldAndLightDir, IN_WORLDPOS_FWDADD(i));

    prepareMaterial(shading, material);

#if (defined(_NORMALMAP) && defined(NORMALMAP_SHADOW))
    float noise = noiseR2(i.pos.xy);
    float nmShade = NormalTangentShadow (i.tex, i.lightDirTS, noise);
    shading.attenuation = min(shading.attenuation, max(1-nmShade, 0));
#endif

    float4 c = evaluateMaterial (shading, material);

    UNITY_EXTRACT_FOG_FROM_EYE_VEC(i);
    UNITY_APPLY_FOG_COLOR(_unity_fogCoord, c.rgb, half4(0,0,0,0)); // fog towards black in additive pass
    return c;
}

half4 fragBase (VertexOutputForwardBase i) : SV_Target { return fragForwardBaseTemplate(i); }
half4 fragAdd (VertexOutputForwardAdd i) : SV_Target { return fragForwardAddTemplate(i); }
    #endif

    ENDHLSL

    SubShader
    {
        Tags { "RenderType"="Opaque" "PerformanceChecks"="False" "LTCGI" = "_LTCGI" }
        LOD 300

        // ------------------------------------------------------------------
        //  Base forward pass (directional light, emission, lightmaps, ...)
        Pass
        {
            Name "FORWARD"
            Tags { "LightMode" = "ForwardBase" }

            Cull [_CullMode]
            AlphaToMask [_AtoCmode]

            HLSLPROGRAM
            #pragma target 4.0

            // -------------------------------------

            #pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature_local _GLOSSYREFLECTIONS_OFF
            #pragma shader_feature_local _LIGHTMAPSPECULAR

            #pragma shader_feature_local _ _BAKERY_RNM _BAKERY_SH _BAKERY_MONOSH
            #pragma shader_feature_local _LTCGI
            #pragma shader_feature_local _VRCLV

            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            // Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
            //#pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma vertex vertBase
            #pragma fragment fragBase

            ENDHLSL
        }
        // ------------------------------------------------------------------
        //  Additive forward pass (one light per pass)
        Pass
        {
            Name "FORWARD_DELTA"
            Tags { "LightMode" = "ForwardAdd" }
            Blend One One
            Fog { Color (0,0,0,0) } // in additive pass fog should be black
            ZWrite Off
            ZTest Equal
            Cull [_CullMode]
            AlphaToMask [_AtoCmode]

            HLSLPROGRAM
            #pragma target 3.0

            // -------------------------------------


            #pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF

            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_fog
            // Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
            //#pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma vertex vertAdd
            #pragma fragment fragAdd

            ENDHLSL
        }

        // ------------------------------------------------------------------
        //  Shadow rendering pass
        Pass {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On ZTest LEqual
            Cull [_CullMode]

            HLSLPROGRAM
            #pragma target 3.0

            // -------------------------------------

            #ifndef UNITY_PASS_SHADOWCASTER
            #define UNITY_PASS_SHADOWCASTER
            #endif

            #pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma multi_compile_shadowcaster
            #pragma multi_compile_instancing
            // Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
            //#pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma vertex vertShadowCaster
            #pragma fragment fragShadowCaster

            #include "Packages/s-ilent.filamented/Filamented/UnityStandardShadow.cginc"

            ENDHLSL
        }


        // Deferred not implemented
        UsePass "Standard/DEFERRED"

        Pass
        {
            Name "META"
            Tags {"LightMode"="Meta"}
            Cull Off
            HLSLPROGRAM

            #include "Packages/s-ilent.filamented/Filamented/UnityStandardMeta.cginc"

            #define META_PASS

            float4 frag_meta2 (v2f_meta i): SV_Target
            {
                MaterialInputs material = SETUP_BRDF_INPUT (i.uv);
                // Note: If your MaterialSetup needs vertex normals, you might want to use a custom vert_meta which passes them through.
                float4 dummy[3]; dummy[0] = 1.0; dummy[1] = 0.0; dummy[2] = 0.0;
                material = MyMaterialSetup(i.uv, 0, 0, dummy, 0);

                PixelParams pixel = (PixelParams)0;
                getCommonPixelParams(material, pixel);

                UnityMetaInput o;
                UNITY_INITIALIZE_OUTPUT(UnityMetaInput, o);

            #ifdef EDITOR_VISUALIZATION
                o.Albedo = pixel.diffuseColor;
                o.VizUV = i.vizUV;
                o.LightCoord = i.lightCoord;
            #else
                o.Albedo = UnityLightmappingAlbedo (pixel.diffuseColor, pixel.f0, 1-pixel.perceptualRoughness);
            #endif
                o.SpecularColor = pixel.f0;
                o.Emission = material.emissive;

                return UnityMetaFragment(o);
            }

            #pragma vertex vert_meta
            #pragma fragment frag_meta2
            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICGLOSSMAP
            #pragma shader_feature ___ _DETAIL_MULX2
            ENDHLSL
        }

    }

    FallBack "VertexLit"
}
