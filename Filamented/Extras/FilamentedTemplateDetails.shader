/*
Filamented example template.
*/ 
Shader "Silent/Filamented Extras/Filamented Details Template"
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
        _EmissionColor("Emission Tint", Color) = (1,1,1,1)
        [Space]
        [HeaderEx(Details)]
        _DetailBlendWeight("Blend Weight", Range(0, 1)) = 1
        [HideInInspector][Enum(Multiply2x, 0, Multiply, 1, Additive, 2, AlphaBlend, 3)]_DetailBlendMode("Blend Mode", Float) = 0.0
        [ScaleOffset][SingleLine(_DetailBlendMode)]_MainTexDetail("Albedo Detail", 2D) = "gray" {}
        [SingleLine(_BumpScaleDetail)][Normal] _BumpMapDetail("Normal Detail", 2D) = "bump" {}
        [HideInInspector]_BumpScaleDetail("Normal Detail Scale", Float) = 1
        [SingleLine]_MOESMapDetail("MOES Map Detail", 2D) = "white" {}
        [Space]
        [Toggle(_DTRIPLANAR)]_UseDTriplanar("Triplanar Detail", Float) = 0.0
        _TriplanarSharp("Blending Sharpness", Range(1, 10)) = 3
		[IfDef(_DTRIPLANAR)]_TriplanarTiles0x ("X Axis Tiling", float) = 1
		[IfDef(_DTRIPLANAR)]_TriplanarTiles0y ("Y Axis Tiling", float) = 1
		[IfDef(_DTRIPLANAR)]_TriplanarTiles0z ("X Axis Tiling", float) = 1
		[IfDef(_DTRIPLANAR)]_TriplanarOffset0x ("X Axis Offset", float) = 0
		[IfDef(_DTRIPLANAR)]_TriplanarOffset0y ("Y Axis Offset", float) = 0
		[IfDef(_DTRIPLANAR)]_TriplanarOffset0z ("X Axis Offset", float) = 0
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
        [IfDef(_VRCLV)] _VRCLVSurfaceBias("Light Volume Surface Bias", Range(0, 0.5)) = 0.05
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
        #pragma multi_compile_local _ _DTRIPLANAR
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

    // uniform sampler2D _MainTex;
    // uniform sampler2D _BumpMap;
    uniform sampler2D _MOESMap;
	// uniform half _BumpScale;
	uniform half _MetallicScale;
	uniform half _OcclusionScale;
	uniform half _SmoothnessScale;
	uniform half _Emission;
	// uniform half3 _EmissionColor;

    uniform sampler2D _MainTexDetail;
    uniform sampler2D _MOESMapDetail;
    uniform sampler2D _BumpMapDetail;
	uniform half _BumpScaleDetail;
	uniform half _DetailBlendMode;
	uniform half _DetailBlendWeight;
    uniform half4 _MainTexDetail_ST;

    #ifdef _DTRIPLANAR
    uniform half _TriplanarTiles0x;
    uniform half _TriplanarTiles0y;
    uniform half _TriplanarTiles0z;
    uniform half _TriplanarOffset0x;
    uniform half _TriplanarOffset0y;
    uniform half _TriplanarOffset0z;
    uniform half _TriplanarSharp;
    #endif

	// Vertex functions are called from UnityStandardCore.
	// You can alter values here, or copy the function in and modify it.
	VertexOutputForwardBase vertBase (VertexInput v) { return vertForwardBase(v); }
	VertexOutputForwardAdd vertAdd (VertexInput v) { return vertForwardAdd(v); }

float4 boxmap(sampler2D tex, float3 p, float3 n, float k )
{
    // grab coord derivatives for texturing
    float3 dpdx = ddx(p);
    float3 dpdy = ddy(p);

    float3 m = pow( abs(n), k );

    // project+fetch
    float4 x = 0.0;
    if (m.x > 0) x = tex2Dgrad( tex, p.zy, dpdx.zy, dpdy.zy );
    float4 y = 0.0;
    if (m.y > 0) y = tex2Dgrad( tex, p.zx, dpdx.zx, dpdy.zx );
    float4 z = 0.0;
    if (m.z > 0) z = tex2Dgrad( tex, p.xy, dpdx.xy, dpdy.xy );
    
    // and blend
    return (x*m.x + y*m.y + z*m.z) / (m.x + m.y + m.z);
}

float3 applyDetailBlendMode(int blendOp, half3 a, half3 b, half t)
{
    switch(blendOp)
    {
        default:
        case 0: // Multiply 2x
            return a * LerpWhiteTo (b * unity_ColorSpaceDouble.rgb, t);
        case 1: // Multiply
            return a * LerpWhiteTo (b, t);
        case 2: // Additive
            return a + b * t;
        case 3: // Alpha Blend
            return lerp(a, b, t);
    }
}

float3 RNMBlendUnpacked(float3 n1, float3 n2)
{
    n1 += float3( 0,  0, 1);
    n2 *= float3(-1, -1, 1);
    return n1*dot(n1, n2)/n1.z - n2;
}

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

    #if defined(_DTRIPLANAR)
    float triSharp = _TriplanarSharp;
    float3 triPosition = i_posWorld * float3(_TriplanarTiles0x, _TriplanarTiles0y, _TriplanarTiles0z)
        + float3(_TriplanarOffset0x, _TriplanarOffset0y, _TriplanarOffset0z);
    half4 baseColorDetail = boxmap (_MainTexDetail, triPosition, tangentToWorld[2], triSharp);
    half4 packedMapDetail = boxmap (_MOESMapDetail, triPosition, tangentToWorld[2], triSharp);
    half3 normalTangentDetail = UnpackScaleNormal(boxmap (_BumpMapDetail, triPosition, tangentToWorld[2], triSharp), _BumpScaleDetail);
    #else
    float2 dUV = i_tex.xy * _MainTexDetail_ST.xy + _MainTexDetail_ST.zw;
    half4 baseColorDetail = tex2D (_MainTexDetail, dUV);
    half4 packedMapDetail = tex2D (_MOESMapDetail, dUV);
    half3 normalTangentDetail = UnpackScaleNormal(tex2D (_BumpMapDetail, dUV), _BumpScaleDetail);
    #endif

    baseColor.rgb = applyDetailBlendMode(_DetailBlendMode, baseColor, baseColorDetail, _DetailBlendWeight);

    normalTangent = lerp(normalTangent, RNMBlendUnpacked(normalTangent, normalTangentDetail), _DetailBlendWeight);

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
            #pragma shader_feature_local _LIGHTMAPSPECULAR

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

            #pragma vertex vertShadowCaster
            #pragma fragment fragShadowCaster

            #include "Packages/s-ilent.filamented/Filamented/UnityStandardShadow.cginc"

            ENDCG
        }
        
        Pass
        {
            Name "META"
            Tags {"LightMode"="Meta"}
            Cull Off
            CGPROGRAM
            
            #define REQUIRE_META_WORLDPOS

            #include "Packages/s-ilent.filamented/Filamented/UnityStandardMeta.cginc"

            #define META_PASS

            float4 frag_meta2 (v2f_meta i): SV_Target
            {
                MaterialInputs material = SETUP_BRDF_INPUT (i.uv);
                float4 dummy[3]; dummy[0] = 1; dummy[1] = 0; dummy[2] = 0;
                material = MyMaterialSetup (i.uv, 0, 0, dummy, i.worldPos);
                
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
            ENDCG
        }

    }

    FallBack "VertexLit"
}
