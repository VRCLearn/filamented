Shader "Silent/Filamented Extras/Simple Rotate Filamented"
{
    Properties
    {
        [CheckDFGTexture]
        [BlendModeSelector(_SrcBlend, _DstBlend, _CustomRenderQueue, _ZWrite, _AtoCmode)] _Mode ("__mode", Float) = 0.0
        [HeaderEx(Base Material)]
        [ScaleOffset][SingleLine(_Color)]_MainTex("Albedo", 2D) = "white" {}
        [HideInInspector]_Color("Color", Color) = (1,1,1,1)
        [SingleLine(_BumpScale)][Normal] _BumpMap("Normal", 2D) = "bump" {}
        [HideInInspector]_BumpScale("Normal Scale", Float) = 1
        [SingleLine]_MOESMap("MOES Map", 2D) = "white" {}
        [Space]
        _MetallicScale("Metallic", Range( 0 , 1)) = 0
        _OcclusionScale("Occlusion", Range( 0 , 1)) = 0
        _Emission("Emission Power", Float) = 0
        _SmoothnessScale("Smoothness", Range( 0 , 1)) = 0
        [Space]
        _EmissionColor("Emission Color", Color) = (1,1,1,1)
        [HeaderEx(Rotation Properties)]
        [ToggleUI]_MaskRotationByUV("Limit Rotation to Positive UV", Float) = 0
        _RotateSpeed("Rotation Speed", Float) = 0
        _RotationAxis("Rotation Axis", Vector) = (0, 0, 1, 0)
        _RotationOffset("Rotation Offset", Vector) = (0, 0, 0, 0)
        [ToggleUI]_RotationOffsetByWorldPos("Add Random Offset by World Position", Float) = 0
        [Space]
        [HeaderEx(System)]
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
        [Space]
        [Enum(UnityEngine.Rendering.CullMode)]_CullMode("Cull Mode", Int) = 2

        [NonModifiableTextureData][HideInInspector] _DFG("DFG", 2D) = "white" {}
        // Blending state
        [HideInInspector] _SrcBlend ("__src", Float) = 1.0
        [HideInInspector] _DstBlend ("__dst", Float) = 0.0
        [HideInInspector] _CustomRenderQueue ("__rq", Float) = 1.0
        [HideInInspector] _ZWrite ("__zw", Float) = 1.0
        [HideInInspector] _AtoCmode("__atoc", Float) = 0
    }

    CustomEditor "Silent.FilamentedExtras.Unity.FilamentedExtrasInspector"

    CGINCLUDE
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

    	// MATERIAL_HAS_CLEAR_COAT 
    	// If this is set, the material will support clear coat.

        // HAS_ATTRIBUTE_COLOR
        // If this is not defined, vertex colour will not be available.

        #define USE_DFG_LUT
        // Whether to use the lookup texture for specular reflection calculation.
        // Requires a shader property _DFG to be present and filled.
    ENDCG

    CGINCLUDE
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
    #else
    #include "Packages/s-ilent.filamented/Filamented/UnityStandardShadow.cginc"
    #endif

    uniform half _RotateSpeed;
    uniform half3 _RotationAxis;
    uniform half3 _RotationOffset;
    uniform float _MaskRotationByUV;
    uniform float _RotationOffsetByWorldPos;

	// Vertex functions are called from UnityStandardCore/Shadow.
	// You can alter values here, or copy the function in and modify it.
    
float3x3 AngleAxis3x3(float angle, float3 axis)
{
    float c, s;
    sincos(angle, s, c);

    float t = 1 - c;
    float x = axis.x;
    float y = axis.y;
    float z = axis.z;

    return float3x3(
        t * x * x + c,      t * x * y - s * z,  t * x * z + s * y,
        t * x * y + s * z,  t * y * y + c,      t * y * z - s * x,
        t * x * z - s * y,  t * y * z + s * x,  t * z * z + c
    );
}

inline float hash13(float3 p3)
{
	p3 = frac(p3 * 443.8975);
	p3 += dot(p3, p3.yzx + 19.19);
	return frac((p3.x + p3.y) * p3.z);
}

inline void VertexCommon(inout VertexInput v)
{
    bool shouldRotate = (!_MaskRotationByUV || v.uv0.x > 0);
    float rotateOffset = _RotationOffsetByWorldPos * hash13(mul(unity_ObjectToWorld, float4(0, 0, 0, 1.0)));
    
    if (shouldRotate)
    {
        float rotateFactor = frac(_RotateSpeed * _Time.y + rotateOffset) * UNITY_PI * 2.0;
        v.vertex.xyz = mul(v.vertex.xyz - _RotationOffset, AngleAxis3x3(rotateFactor, _RotationAxis)) + _RotationOffset;
        v.normal.xyz = mul(v.normal.xyz, AngleAxis3x3(rotateFactor, _RotationAxis));
    #ifdef _TANGENT_TO_WORLD
        v.tangent.xyz = mul(v.tangent.xyz, AngleAxis3x3(rotateFactor, _RotationAxis));
    #endif
    }
}

#ifndef UNITY_PASS_SHADOWCASTER

    // uniform sampler2D _MainTex;
    // uniform sampler2D _BumpMap;
    uniform sampler2D _MOESMap;
	// uniform half _BumpScale;
	uniform half _MetallicScale;
	uniform half _OcclusionScale;
	uniform half _SmoothnessScale;
	uniform half _Emission;
	// uniform half3 _EmissionColor;

	VertexOutputForwardBase vertBase (VertexInput v) { VertexCommon(v); return vertForwardBase(v); }
	VertexOutputForwardAdd vertAdd (VertexInput v) { VertexCommon(v); return vertForwardAdd(v); }

	// The material function itself!  You can alter the code below to add extra properties. 
inline MaterialInputs MyMaterialSetup (inout float4 i_tex, float3 i_eyeVec, half3 i_viewDirForParallax, float4 tangentToWorld[3], float3 i_posWorld)
{   
    half4 baseColor = tex2D (_MainTex, i_tex.xy) * _Color;
    half4 packedMap = tex2D (_MOESMap, i_tex.xy);
    half3 normalTangent = UnpackScaleNormal(tex2D (_BumpMap, i_tex.xy), _BumpScale);

    half metallic = packedMap.x * _MetallicScale;
    half occlusion = lerp(1, packedMap.y, _OcclusionScale);
    half emissionMask = packedMap.z;
    half smoothness = packedMap.w * _SmoothnessScale; 

    MaterialInputs material = (MaterialInputs)0;
    initMaterial(material);
    material.baseColor = baseColor;
    material.metallic = metallic;
    material.roughness = computeRoughnessFromGlossiness(smoothness);
    material.normal = normalTangent;
    material.emissive.rgb = baseColor.rgb * emissionMask * _Emission * _EmissionColor;
    material.emissive.a = 1.0;
    material.ambientOcclusion = occlusion;
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

    ENDCG

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
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]

            CGPROGRAM
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

            ENDCG
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
            Blend One [_DstBlend]
            ZWrite [_ZWrite]

            CGPROGRAM
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

            ENDCG
        }
        
        // ------------------------------------------------------------------
        //  Shadow rendering pass
        Pass {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On ZTest LEqual
            Cull [_CullMode]
            AlphaToMask Off

            CGPROGRAM
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

            #pragma vertex vertShadowCasterLocal
            #pragma fragment fragShadowCaster

            #include "Packages/s-ilent.filamented/Filamented/UnityStandardShadow.cginc"

            // We use Unity's shadowcaster as a base, but unfortunately it's complicated to work with.
            void vertShadowCasterLocal (VertexInput v
                , out float4 opos : SV_POSITION
                #ifdef UNITY_STANDARD_USE_SHADOW_OUTPUT_STRUCT
                , out VertexOutputShadowCaster o
                #endif
                #ifdef UNITY_STANDARD_USE_STEREO_SHADOW_OUTPUT_STRUCT
                , out VertexOutputStereoShadowCaster os
                #endif
            )
            {
                UNITY_SETUP_INSTANCE_ID(v);
                #ifdef UNITY_STANDARD_USE_STEREO_SHADOW_OUTPUT_STRUCT
                    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(os);
                #endif
                VertexCommon(v);
                TRANSFER_SHADOW_CASTER_NOPOS(o,opos)
                #if defined(UNITY_STANDARD_USE_SHADOW_UVS)
                    o.tex = TRANSFORM_TEX(v.uv0, _MainTex);

                    #ifdef _PARALLAXMAP
                        TANGENT_SPACE_ROTATION;
                        o.viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
                    #endif
                #endif
            }

            ENDCG
        }
        

        // Deferred not implemented
        UsePass "Standard/DEFERRED"

        // Meta not implemented
        UsePass "Standard/META"

    }

    FallBack "VertexLit"
}
