// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)
using System;
using UnityEngine;
using UnityEditor;
using System.Collections.Generic;
using System.Reflection;

namespace SilentTools
{
    [AttributeUsage(AttributeTargets.Field, AllowMultiple = false)]
    public class MaterialPropertyAttribute : Attribute
    {
        public string PropertyName { get; }

        public MaterialPropertyAttribute(string propertyName)
        {
            PropertyName = propertyName;
        }
    }

    [AttributeUsage(AttributeTargets.Field, AllowMultiple = false)]
    public class GUIContentAttribute : Attribute
    {
        public string Text { get; }
        public string Tooltip { get; }

        public GUIContentAttribute(string text, string tooltip)
        {
            Text = text;
            Tooltip = tooltip;
        }
    }

    class FilamentedStandardShaderGUI : ShaderGUI
    {
        private enum WorkflowMode
        {
            Specular,
            Metallic,
            Dielectric,
            Roughness,
            Cloth
        }

        public enum BlendMode
        {
            Opaque,
            Cutout,
            Fade,   // Old school alpha-blending mode, fresnel does not affect amount of transparency
            Transparent // Physically plausible transparency mode, implemented as alpha pre-multiply
        }

        public enum SmoothnessMapChannel
        {
            SpecularMetallicAlpha,
            AlbedoAlpha,
        }

        private enum SettingsMode
        {
            Basic,
            Full,
        }

        private static class Styles
        {
            public static string primaryMapsText = "Main Maps";
            public static string secondaryMapsText = "Secondary Maps";
            public static string forwardText = "Forward Rendering Options";
            public static string renderingMode = "Rendering Mode";
            public static string settingsMode = "Settings Mode";
            public static string advancedText = "Advanced Options";
            public static GUIContent filamentedOptionsLabel = EditorGUIUtility.TrTextContent("Filamented Options", "Settings which control functionality specific to Filamented.");
            public static GUIContent specularAALabel = EditorGUIUtility.TrTextContent("Specular Anti-Aliasing", "Reduces specular aliasing and preserves the shape of specular highlights as an object moves away from the camera.");
            public static GUIContent lightmapOptionsLabel = EditorGUIUtility.TrTextContent("Lightmap Options", "Settings which only affect the object when it is affected by baked GI lightmapping.");
            
            public static readonly string[] blendNames = Enum.GetNames(typeof(BlendMode));
            public static readonly string[] settingNames = Enum.GetNames(typeof(SettingsMode));
        }

        MaterialProperty blendMode = null;

        [MaterialProperty("_MainTex")]
        [GUIContent("Albedo", "Albedo (RGB) and Transparency (A)")]
        private MaterialProperty albedoMap = null;

        [MaterialProperty("_Cutoff")]
        [GUIContent("Alpha Cutoff", "Threshold for alpha cutoff")]
        private MaterialProperty alphaCutoff = null;

        [MaterialProperty("_SpecGlossMap")]
        [GUIContent("Specular", "Specular (RGB) and Smoothness (A)")]
        private MaterialProperty specularMap = null;

        [MaterialProperty("_SpecColor")]
        [GUIContent("Specular Color", "Specular color")]
        private MaterialProperty specularColor = null;

        [MaterialProperty("_MetallicGlossMap")]
        [GUIContent("Metallic", "Metallic (R) and Smoothness (A)")]
        private MaterialProperty metallicMap = null;

        [MaterialProperty("_Metallic")]
        [GUIContent("Metallic", "Metallic value")]
        private MaterialProperty metallic = null;

        [MaterialProperty("_Glossiness")]
        [GUIContent("Roughness", "Roughness value")]
        private MaterialProperty roughness = null;

        [MaterialProperty("_GlossMapScale")]
        [GUIContent("Smoothness", "Smoothness scale factor")]
        private MaterialProperty smoothnessScale = null;

        [MaterialProperty("_SmoothnessTextureChannel")]
        [GUIContent("Source", "Smoothness texture and channel")]
        private MaterialProperty smoothnessMapChannel = null;

        [MaterialProperty("_SpecularHighlights")]
        [GUIContent("Specular Highlights", "Specular Highlights")]
        private MaterialProperty highlights = null;

        [MaterialProperty("_GlossyReflections")]
        [GUIContent("Reflections", "Glossy Reflections")]
        private MaterialProperty reflections = null;

        [MaterialProperty("_BumpScale")]
        [GUIContent("Normal Map", "Normal Map")]
        private MaterialProperty bumpScale = null;

        [MaterialProperty("_BumpMap")]
        [GUIContent("Normal Map", "Normal Map")]
        private MaterialProperty bumpMap = null;

        [MaterialProperty("_Parallax")]
        [GUIContent("Height Map", "Height Map (G)")]
        private MaterialProperty heigtMapScale = null;

        [MaterialProperty("_ParallaxMap")]
        [GUIContent("Height Map", "Height Map (G)")]
        private MaterialProperty heightMap = null;

        [MaterialProperty("_OcclusionStrength")]
        [GUIContent("Occlusion", "Occlusion (G)")]
        private MaterialProperty occlusionStrength = null;

        [MaterialProperty("_OcclusionMap")]
        [GUIContent("Occlusion", "Occlusion (G)")]
        private MaterialProperty occlusionMap = null;

        [MaterialProperty("_EmissionColor")]
        [GUIContent("Color", "Emission (RGB)")]
        private MaterialProperty emissionColorForRendering = null;

        [MaterialProperty("_EmissionMap")]
        [GUIContent("Color", "Emission (RGB)")]
        private MaterialProperty emissionMap = null;

        [MaterialProperty("_DetailMask")]
        [GUIContent("Detail Mask", "Mask for Secondary Maps (A)")]
        private MaterialProperty detailMask = null;

        [MaterialProperty("_DetailAlbedoMap")]
        [GUIContent("Detail Albedo x2", "Albedo (RGB) multiplied by 2")]
        private MaterialProperty detailAlbedoMap = null;

        [MaterialProperty("_DetailNormalMapScale")]
        [GUIContent("Normal Map", "Normal Map")]
        private MaterialProperty detailNormalMapScale = null;

        [MaterialProperty("_DetailNormalMap")]
        [GUIContent("Normal Map", "Normal Map")]
        private MaterialProperty detailNormalMap = null;

        [MaterialProperty("_UVSec")]
        [GUIContent("UV Set", "UV Set")]
        private MaterialProperty uvSetSecondary = null;

        [MaterialProperty("_CullMode")]
        [GUIContent("Cull Mode", "Which face of the polygon should be culled from rendering")]
        private MaterialProperty cullMode = null;

        [MaterialProperty("_AlphaToMaskMode")]
        [GUIContent("Alpha to Coverage Mode", "Whether to use alpha-to-coverage on the edges of cutout materials to anti-alias them")]
        private MaterialProperty alphaCoverageMode = null;

        [MaterialProperty("_specularAntiAliasingVariance")]
        [GUIContent("Variance", "Sets the screen space variance of the filter kernel used when applying specular anti-aliasing. Higher values will increase the effect of the filter but may increase roughness in unwanted areas.")]
        private MaterialProperty specularAAVariance = null;

        [MaterialProperty("_specularAntiAliasingThreshold")]
        [GUIContent("Threshold", "Sets the clamping threshold used to suppress estimation errors when applying specular anti-aliasing. When set to 0, specular anti-aliasing is disabled.")]
        private MaterialProperty specularAAThreshold = null;

        [MaterialProperty("_ExposureOcclusion")]
        [GUIContent("Exposure Occlusion", "Controls occlusion of specular lighting by the lightmap and light probes.")]
        private MaterialProperty exposureOcclusion = null;

        [MaterialProperty("_LightmapSpecular")]
        [GUIContent("Lightmap Specular", "Allows the material to derive specular lighting from the lightmap directionality.")]
        private MaterialProperty lightmapSpecular = null;

        [MaterialProperty("_LightmapSpecularMaxSmoothness")]
        [GUIContent("Max Smoothness", "Adjusts the maximum smoothness of the material for lightmap specular to avoid artifacts from imprecise directionality.")]
        private MaterialProperty lmSpecMaxSmoothness = null;

        [MaterialProperty("_NormalMapShadows")]
        [GUIContent("Normal Map Shadows", "Additional shadows produced by marching along the material's normal map.")]
        private MaterialProperty normalMapShadows = null;

        [MaterialProperty("_BumpShadowHeightScale")]
        [GUIContent("Height Scale", "Controls the length of normal map shadows.")]
        private MaterialProperty normalMapShadowsScale = null;

        [MaterialProperty("_BumpShadowHardness")]
        [GUIContent("Hardness", "Controls the hardness of normal map shadows, which are dithered to avoid jagged artifacts.")]
        private MaterialProperty normalMapShadowsHardness = null;

        [MaterialProperty("_Bakery")]
        [GUIContent("Bakery Mode", "Sets the material to use one of Bakery's directionality map modes.")]
        private MaterialProperty bakeryMode = null;

        [MaterialProperty("_BakeryVertexLM")]
        [GUIContent("Bakery Vertex Lightmaps", "Sets the material to allow using Bakery's vertex lightmap baking.")]
        private MaterialProperty bakeryVertexMode = null;

        [MaterialProperty("_RNM0")]
        [GUIContent("Bakery Lightmap", "This texture is applied either by the Bakery runtime script or an external script according to the mesh renderer and can not be modified.")]
        private MaterialProperty bakeryRNM0 = null;

        [MaterialProperty("_RNM1")]
        [GUIContent("Bakery Lightmap", "This texture is applied either by the Bakery runtime script or an external script according to the mesh renderer and can not be modified.")]
        private MaterialProperty bakeryRNM1 = null;

        [MaterialProperty("_RNM2")]
        [GUIContent("Bakery Lightmap", "This texture is applied either by the Bakery runtime script or an external script according to the mesh renderer and can not be modified.")]
        private MaterialProperty bakeryRNM2 = null;

        [MaterialProperty("_LTCGI")]
        [GUIContent("LTCGI Support", "Sets whether the material can receive lights from LTCGI sources in the scene.")]
        private MaterialProperty ltcgiMode = null;

        [MaterialProperty("_VRCLV")]
        [GUIContent("VRC Light Volumes Support", "Sets whether the material can receive indirect light from Light Volumes in the scene.")]
        private MaterialProperty vrclvMode = null;

        [MaterialProperty("_ShaderType_Cloth")]
        [GUIContent("Sheen", "Sheen colour (RGB) and glossiness (A) for cloth")]
        private MaterialProperty isCloth = null;

        [MaterialProperty("_DFG")]
        private MaterialProperty dfgLUT = null;

        [MaterialProperty("_Color")]
        MaterialProperty albedoColor = null;
        [MaterialProperty("_SpecGlossMap")]
        MaterialProperty roughnessMap = null;
        [MaterialProperty("_Glossiness")]
        MaterialProperty smoothness = null;

        MaterialEditor m_MaterialEditor;
        WorkflowMode m_WorkflowMode = WorkflowMode.Specular;

        bool m_FirstTimeApply = true;

        int m_SettingsMode = (int)SettingsMode.Basic;

        private static Dictionary<string, MaterialPropertyAttribute> materialPropertyCache = new Dictionary<string, MaterialPropertyAttribute>();
        private static Dictionary<string, GUIContent> guiContentCache = new Dictionary<string, GUIContent>();
        private static bool isCacheInitialized = false;

        private void InitializeCache()
        {
            if (isCacheInitialized) return;

            var fields = this.GetType().GetFields(BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Public);
            foreach (var field in fields)
            {
                var materialPropertyAttribute = (MaterialPropertyAttribute)Attribute.GetCustomAttribute(field, typeof(MaterialPropertyAttribute));
                if (materialPropertyAttribute != null)
                {
                    materialPropertyCache[field.Name] = materialPropertyAttribute;
                }

                var guiContentAttribute = (GUIContentAttribute)Attribute.GetCustomAttribute(field, typeof(GUIContentAttribute));
                if (guiContentAttribute != null)
                {
                    var content = new GUIContent(guiContentAttribute.Text, guiContentAttribute.Tooltip);
                    guiContentCache[field.Name] = content;
                }
            }

            isCacheInitialized = true;
        }

        public void FindProperties(MaterialProperty[] props)
        {
            InitializeCache();

            foreach (var kvp in materialPropertyCache)
            {
                var field = this.GetType().GetField(kvp.Key, BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Public);
                var property = FindProperty(kvp.Value.PropertyName, props, false);
                field.SetValue(this, property);
            }

            blendMode = FindProperty("_Mode", props);
            isCloth = FindProperty("_ShaderType_Cloth", props, false);
            // todo: find a better way to handle this
            if (isCloth != null)
                m_WorkflowMode = WorkflowMode.Cloth;
            else if (specularMap != null && specularMap.displayName == "Roughness Map") 
                m_WorkflowMode = WorkflowMode.Roughness;
            else if (specularMap != null && specularColor != null)
                m_WorkflowMode = WorkflowMode.Specular;
            else if (metallicMap != null && metallic != null)
                m_WorkflowMode = WorkflowMode.Metallic;
            else
                m_WorkflowMode = WorkflowMode.Dielectric;
        }

        internal void DetermineWorkflow(MaterialProperty[] props)
        {
            if (FindProperty("_ShaderType_Cloth", props, false) != null)
                m_WorkflowMode = WorkflowMode.Cloth;
            else if (FindProperty("_SpecGlossMap", props, false) != null && FindProperty("_SpecColor", props, false) != null)
                m_WorkflowMode = WorkflowMode.Specular;
                if (FindProperty("_SpecGlossMap", props, false).displayName == "Roughness Map") 
                    m_WorkflowMode = WorkflowMode.Roughness; 
            else if (FindProperty("_MetallicGlossMap", props, false) != null && FindProperty("_Metallic", props, false) != null)
                m_WorkflowMode = WorkflowMode.Metallic;
            else
                m_WorkflowMode = WorkflowMode.Dielectric;
        }

        public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] props)
        {
            FindProperties(props); // MaterialProperties can be animated so we do not cache them but fetch them every event to ensure animated values are updated correctly
            m_MaterialEditor = materialEditor;
            Material material = materialEditor.target as Material;

            // Make sure that needed setup (ie keywords/renderqueue) are set up if we're switching some existing
            // material to a standard shader.
            // Do this before any GUI code has been issued to prevent layout issues in subsequent GUILayout statements (case 780071)
            if (m_FirstTimeApply)
            {
                if (!Int32.TryParse(EditorUserSettings.GetConfigValue("filamented_settings_mode"), out m_SettingsMode))
                {
                    Debug.Log(m_SettingsMode);
                    Debug.Log(EditorUserSettings.GetConfigValue("filamented_settings_mode"));
                    m_SettingsMode = (int)SettingsMode.Basic;
                }
                MaterialChanged(material, m_WorkflowMode, false);
                m_FirstTimeApply = false;
            }

            ShaderPropertiesGUI(material);
        }

        public void ShaderPropertiesGUI(Material material)
        {
            // Use default labelWidth
            EditorGUIUtility.labelWidth = 0f;

            bool blendModeChanged = false;

            // Detect any changes to the material
            EditorGUI.BeginChangeCheck();
            {
                blendModeChanged = BlendModePopup();

                if (dfgLUT.textureValue == null)
                {
                    EditorGUILayout.HelpBox("No texture is assigned to the DFG slot in the shader. This will cause the shader to render incorrecty. Please assign one of the DFG textures to the DFG slot in the shader.", MessageType.Error);
                }

                // Primary properties
                GUILayout.Label(Styles.primaryMapsText, EditorStyles.boldLabel);
                DoAlbedoArea(material);
                DoSpecularMetallicArea();
                DoNormalArea();
                DoHeightMapArea();
                DoOcclusionMapArea();
                DoDetailMaskArea();
                DoEmissionArea(material);
                EditorGUI.BeginChangeCheck();
                m_MaterialEditor.TextureScaleOffsetProperty(albedoMap);
                if (EditorGUI.EndChangeCheck())
                    emissionMap.textureScaleAndOffset = albedoMap.textureScaleAndOffset; // Apply the main texture scale and offset to the emission texture as well, for Enlighten's sake

                EditorGUILayout.Space();

                // Secondary properties
                GUILayout.Label(Styles.secondaryMapsText, EditorStyles.boldLabel);
                DoDetailAlbedoMapArea();
                DoDetailNormalMapArea();
                m_MaterialEditor.TextureScaleOffsetProperty(detailAlbedoMap);
                DoUVSetSecondaryArea();

                EditorGUILayout.Space();

                SettingsModePopup();

                if(m_SettingsMode > (int)SettingsMode.Basic)
                {
                    // Third properties
                    EditorGUILayout.Space();
                    GUILayout.Label(Styles.filamentedOptionsLabel, EditorStyles.boldLabel);

                    // Added properties
                    DoSpecularAAArea();
                    EditorGUILayout.Space();
                    DoExposureOcclusionArea();
                    EditorGUILayout.Space();
                    DoNormalMapShadowsArea(material);
                    EditorGUILayout.Space();
                    DoLightmapSpecularArea(material);
                    EditorGUILayout.Space();
                    DoBakeryArea(material);
                    EditorGUILayout.Space();
                    DoLTCGIArea(material);
                    DoVRCLVArea(material);

                    EditorGUILayout.Space();
                }

                DoForwardArea();
                EditorGUILayout.Space();
                DoAdvancedArea();
            }
            if (EditorGUI.EndChangeCheck())
            {
                foreach (var obj in blendMode.targets)
                    MaterialChanged((Material)obj, m_WorkflowMode, blendModeChanged);
            }

            DoCullModeArea(material);
            DoInstancingAndGIFields();
        }

        public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader)
        {
            // _Emission property is lost after assigning Standard shader to the material
            // thus transfer it before assigning the new shader
            if (material.HasProperty("_Emission"))
            {
                material.SetColor("_EmissionColor", material.GetColor("_Emission"));
            }

            base.AssignNewShaderToMaterial(material, oldShader, newShader);

            if (oldShader == null || !oldShader.name.Contains("Legacy Shaders/"))
            {
                SetupMaterialWithBlendMode(material, (BlendMode)material.GetFloat("_Mode"), true);
                return;
            }

            BlendMode blendMode = BlendMode.Opaque;
            if (oldShader.name.Contains("/Transparent/Cutout/"))
            {
                blendMode = BlendMode.Cutout;
            }
            else if (oldShader.name.Contains("/Transparent/"))
            {
                // NOTE: legacy shaders did not provide physically based transparency
                // therefore Fade mode
                blendMode = BlendMode.Fade;
            }
            material.SetFloat("_Mode", (float)blendMode);

            DetermineWorkflow(MaterialEditor.GetMaterialProperties(new Material[] { material }));
            MaterialChanged(material, m_WorkflowMode, true);
        }

        bool BlendModePopup()
        {
            EditorGUI.showMixedValue = blendMode.hasMixedValue;
            var mode = (BlendMode)blendMode.floatValue;

            EditorGUI.BeginChangeCheck();
            mode = (BlendMode)EditorGUILayout.Popup(Styles.renderingMode, (int)mode, Styles.blendNames);
            bool result = EditorGUI.EndChangeCheck();
            if (result)
            {
                m_MaterialEditor.RegisterPropertyChangeUndo("Rendering Mode");
                blendMode.floatValue = (float)mode;
            }

            EditorGUI.showMixedValue = false;

            return result;
        }

        bool SettingsModePopup()
        {
            EditorGUI.showMixedValue = blendMode.hasMixedValue;
            var mode = (int)m_SettingsMode;
            
            //First time
            //When filamented_settings_mode is not set, GetConfigValue is not possible, so store the current value.
            if (string.IsNullOrEmpty(EditorUserSettings.GetConfigValue("filamented_settings_mode")))
            {
                EditorUserSettings.SetConfigValue("filamented_settings_mode", mode.ToString());
                return true;
            }

            EditorGUI.BeginChangeCheck();
            mode = EditorGUILayout.Popup(Styles.settingsMode, mode, Styles.settingNames);
            bool result = EditorGUI.EndChangeCheck();
            if (result)
            {
                EditorUserSettings.SetConfigValue("filamented_settings_mode", mode.ToString());
                m_SettingsMode = mode;
            }

            EditorGUI.showMixedValue = false;

            return result;
        }

        void DoNormalArea()
        {
            m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(bumpMap)], bumpMap, bumpMap.textureValue != null ? bumpScale : null);
            if (bumpScale.floatValue != 1
                && UnityEditorInternal.InternalEditorUtility.IsMobilePlatform(EditorUserBuildSettings.activeBuildTarget))
                if (m_MaterialEditor.HelpBoxWithButton(
                    EditorGUIUtility.TrTextContent("Bump scale is not supported on mobile platforms"),
                    EditorGUIUtility.TrTextContent("Fix Now")))
                {
                    bumpScale.floatValue = 1;
                }
        }

        void DoAlbedoArea(Material material)
        {
            m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(albedoMap)], albedoMap, albedoColor);
            if (((BlendMode)material.GetFloat("_Mode") == BlendMode.Cutout))
            {
                m_MaterialEditor.ShaderProperty(alphaCutoff, guiContentCache[nameof(alphaCutoff)], MaterialEditor.kMiniTextureFieldLabelIndentLevel + 1);
            }
        }

        void DoEmissionArea(Material material)
        {
            // Emission for GI?
            if (m_MaterialEditor.EmissionEnabledProperty())
            {
                bool hadEmissionTexture = emissionMap.textureValue != null;

                // Texture and HDR color controls
                m_MaterialEditor.TexturePropertyWithHDRColor(guiContentCache[nameof(emissionMap)], emissionMap, emissionColorForRendering, false);

                // If texture was assigned and color was black set color to white
                float brightness = emissionColorForRendering.colorValue.maxColorComponent;
                if (emissionMap.textureValue != null && !hadEmissionTexture && brightness <= 0f)
                    emissionColorForRendering.colorValue = Color.white;

                // change the GI flag and fix it up with emissive as black if necessary
                m_MaterialEditor.LightmapEmissionFlagsProperty(MaterialEditor.kMiniTextureFieldLabelIndentLevel, true);
            }
        }

        void DoSpecularMetallicArea()
        {
            if (m_WorkflowMode == WorkflowMode.Roughness)
            {
                m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(metallicMap)], metallicMap, metallicMap.textureValue != null ? null : metallic);
                m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(roughness)], roughnessMap, roughnessMap.textureValue != null ? null : roughness);
                return;
            }
            bool hasGlossMap = false;
            if (m_WorkflowMode == WorkflowMode.Specular)
            {
                hasGlossMap = specularMap.textureValue != null;
                m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(specularMap)], specularMap, hasGlossMap ? null : specularColor);
            }
            else if (m_WorkflowMode == WorkflowMode.Metallic)
            {
                hasGlossMap = metallicMap.textureValue != null;
                m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(metallicMap)], metallicMap, hasGlossMap ? null : metallic);
            }
            else if (m_WorkflowMode == WorkflowMode.Cloth)
            {
                hasGlossMap = specularMap.textureValue != null;
                // Always show colour for tinting
                m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(isCloth)], specularMap, specularColor);
            }

            bool showSmoothnessScale = hasGlossMap;
            if (smoothnessMapChannel != null)
            {
                int smoothnessChannel = (int)smoothnessMapChannel.floatValue;
                if (smoothnessChannel == (int)SmoothnessMapChannel.AlbedoAlpha)
                    showSmoothnessScale = true;
            }

            int indentation = 2; // align with labels of texture properties
            m_MaterialEditor.ShaderProperty(showSmoothnessScale ? smoothnessScale : smoothness, showSmoothnessScale ? guiContentCache[nameof(smoothnessScale)] : guiContentCache[nameof(smoothnessScale)], indentation);

            ++indentation;
            if (smoothnessMapChannel != null)
                m_MaterialEditor.ShaderProperty(smoothnessMapChannel, guiContentCache[nameof(smoothnessMapChannel)], indentation);
        }

        void DoHeightMapArea()
        {
            m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(heightMap)], heightMap, heightMap.textureValue != null ? heigtMapScale : null);
        }

        void DoOcclusionMapArea()
        {
            m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(occlusionMap)], occlusionMap, occlusionMap.textureValue != null ? occlusionStrength : null);
        }

        void DoDetailMaskArea()
        {
            m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(detailMask)], detailMask);
        }

        void DoDetailAlbedoMapArea()
        {
            m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(detailAlbedoMap)], detailAlbedoMap);
        }

        void DoDetailNormalMapArea()
        {
            m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(detailNormalMap)], detailNormalMap, detailNormalMapScale);
        }

        void DoUVSetSecondaryArea()
        {
            m_MaterialEditor.ShaderProperty(uvSetSecondary, guiContentCache[nameof(uvSetSecondary)]);
        }

        void DoSpecularAAArea()
        {
            GUILayout.Label(Styles.specularAALabel, EditorStyles.label);
            if (specularAAVariance != null)
                m_MaterialEditor.ShaderProperty(specularAAVariance, guiContentCache[nameof(specularAAVariance)], 2);
            if (specularAAThreshold != null)
                m_MaterialEditor.ShaderProperty(specularAAThreshold, guiContentCache[nameof(specularAAThreshold)], 2);
        }

        void DoExposureOcclusionArea()
        {
            if (exposureOcclusion != null)
                m_MaterialEditor.ShaderProperty(exposureOcclusion, guiContentCache[nameof(exposureOcclusion)]);
        }

        void DoNormalMapShadowsArea(Material material)
        {
            if (normalMapShadows != null)
                m_MaterialEditor.ShaderProperty(normalMapShadows, guiContentCache[nameof(normalMapShadows)]);
            if (material.GetFloat("_NormalMapShadows") != 0)
            {
                if (normalMapShadowsScale != null)
                    m_MaterialEditor.ShaderProperty(normalMapShadowsScale, guiContentCache[nameof(normalMapShadowsScale)], 2);
                if (normalMapShadowsHardness != null)
                    m_MaterialEditor.ShaderProperty(normalMapShadowsHardness, guiContentCache[nameof(normalMapShadowsHardness)], 2);
            }
        }

        void DoLightmapSpecularArea(Material material)
        {
            if (lightmapSpecular != null)
                m_MaterialEditor.ShaderProperty(lightmapSpecular, guiContentCache[nameof(lightmapSpecular)]);
            if (lmSpecMaxSmoothness != null && material.GetFloat("_LightmapSpecular") != 0)
                m_MaterialEditor.ShaderProperty(lmSpecMaxSmoothness, guiContentCache[nameof(lmSpecMaxSmoothness)], 2);
        }

        void DoBakeryArea(Material material)
        {
        #if BAKERY_INCLUDED
            if (bakeryMode != null)
                m_MaterialEditor.ShaderProperty(bakeryMode, guiContentCache[nameof(bakeryMode)]);
                m_MaterialEditor.ShaderProperty(bakeryVertexMode, guiContentCache[nameof(bakeryVertexMode)]);

                bool isBakeryRNM = material.GetFloat("_Bakery") == 1;
                bool isBakeryFullSH = material.GetFloat("_Bakery") == 2;
            if (isBakeryRNM || isBakeryFullSH)
            {
                EditorGUI.BeginDisabledGroup(true);

                EditorGUI.indentLevel += 2;
                m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(bakeryRNM0)], bakeryRNM0);
                m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(bakeryRNM0)], bakeryRNM1);
                m_MaterialEditor.TexturePropertySingleLine(guiContentCache[nameof(bakeryRNM0)], bakeryRNM2);
                EditorGUI.indentLevel -= 2;
                EditorGUI.EndDisabledGroup();
            }
        #endif
        }

        void DoLTCGIArea(Material material)
        {
        #if LTCGI_INCLUDED
            if (ltcgiMode != null)
                m_MaterialEditor.ShaderProperty(ltcgiMode, guiContentCache[nameof(ltcgiMode)]);
        #else
            // Force disabled when script isn't active to protect against compile failures.
            material.SetFloat("_LTCGI", 0.0f);
            material.DisableKeyword("_LTCGI");
        #endif
        }

        void DoVRCLVArea(Material material)
        {
        #if true
            if (vrclvMode != null)
                m_MaterialEditor.ShaderProperty(vrclvMode, guiContentCache[nameof(vrclvMode)]);
        #else
            // Force disabled when script isn't active to protect against compile failures.
            material.SetFloat("_VRCLV", 0.0f);
            material.DisableKeyword("_VRCLV");
        #endif
        }

        void DoForwardArea()
        {
            GUILayout.Label(Styles.forwardText, EditorStyles.boldLabel);
            if (highlights != null)
                m_MaterialEditor.ShaderProperty(highlights, guiContentCache[nameof(highlights)]);
            if (reflections != null)
                m_MaterialEditor.ShaderProperty(reflections, guiContentCache[nameof(reflections)]);
        }

        void DoAdvancedArea()
        {
            GUILayout.Label(Styles.advancedText, EditorStyles.boldLabel);
            m_MaterialEditor.RenderQueueField();
        }

        void DoCullModeArea(Material material)
        {
            m_MaterialEditor.ShaderProperty(cullMode, guiContentCache[nameof(cullMode)].text);
            if (((BlendMode)material.GetFloat("_Mode") == BlendMode.Cutout))
            {
                m_MaterialEditor.ShaderProperty(alphaCoverageMode, guiContentCache[nameof(alphaCoverageMode)].text);
            }
        }

        void DoInstancingAndGIFields()
        {
            m_MaterialEditor.EnableInstancingField();
            m_MaterialEditor.DoubleSidedGIField();
        }


        public static void SetupMaterialWithBlendMode(Material material, BlendMode blendMode, bool overrideRenderQueue)
        {
            int minRenderQueue = -1;
            int maxRenderQueue = 5000;
            int defaultRenderQueue = -1;
            switch (blendMode)
            {
                case BlendMode.Opaque:
                    material.SetOverrideTag("RenderType", "");
                    material.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.One);
                    material.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.Zero);
                    material.SetFloat("_ZWrite", 1.0f);
                    material.SetFloat("_AlphaToMaskMode", 0.0f);
                    material.DisableKeyword("_ALPHATEST_ON");
                    material.DisableKeyword("_ALPHABLEND_ON");
                    material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                    minRenderQueue = -1;
                    maxRenderQueue = (int)UnityEngine.Rendering.RenderQueue.AlphaTest - 1;
                    defaultRenderQueue = -1;
                    break;
                case BlendMode.Cutout:
                    material.SetOverrideTag("RenderType", "TransparentCutout");
                    material.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.One);
                    material.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.Zero);
                    material.SetFloat("_ZWrite", 1.0f);
                    material.SetFloat("_AlphaToMaskMode", 1.0f);
                    material.EnableKeyword("_ALPHATEST_ON");
                    material.DisableKeyword("_ALPHABLEND_ON");
                    material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                    minRenderQueue = (int)UnityEngine.Rendering.RenderQueue.AlphaTest;
                    maxRenderQueue = (int)UnityEngine.Rendering.RenderQueue.GeometryLast;
                    defaultRenderQueue = (int)UnityEngine.Rendering.RenderQueue.AlphaTest;
                    break;
                case BlendMode.Fade:
                    material.SetOverrideTag("RenderType", "Transparent");
                    material.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
                    material.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                    material.SetFloat("_ZWrite", 0.0f);
                    material.SetFloat("_AlphaToMaskMode", 0.0f);
                    material.DisableKeyword("_ALPHATEST_ON");
                    material.EnableKeyword("_ALPHABLEND_ON");
                    material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                    minRenderQueue = (int)UnityEngine.Rendering.RenderQueue.GeometryLast + 1;
                    maxRenderQueue = (int)UnityEngine.Rendering.RenderQueue.Overlay - 1;
                    defaultRenderQueue = (int)UnityEngine.Rendering.RenderQueue.Transparent;
                    break;
                case BlendMode.Transparent:
                    material.SetOverrideTag("RenderType", "Transparent");
                    material.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.One);
                    material.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                    material.SetFloat("_ZWrite", 0.0f);
                    material.SetFloat("_AlphaToMaskMode", 0.0f);
                    material.DisableKeyword("_ALPHATEST_ON");
                    material.DisableKeyword("_ALPHABLEND_ON");
                    material.EnableKeyword("_ALPHAPREMULTIPLY_ON");
                    minRenderQueue = (int)UnityEngine.Rendering.RenderQueue.GeometryLast + 1;
                    maxRenderQueue = (int)UnityEngine.Rendering.RenderQueue.Overlay - 1;
                    defaultRenderQueue = (int)UnityEngine.Rendering.RenderQueue.Transparent;
                    break;
            }

            if (overrideRenderQueue)
            {
                if (!overrideRenderQueue)
                    Debug.LogFormat("Render queue value outside of the allowed range ({0} - {1}) for selected Blend mode, resetting render queue to default", minRenderQueue, maxRenderQueue);
                material.renderQueue = defaultRenderQueue;
            }
        }

        static SmoothnessMapChannel GetSmoothnessMapChannel(Material material)
        {
            int ch = (int)material.GetFloat("_SmoothnessTextureChannel");
            if (ch == (int)SmoothnessMapChannel.AlbedoAlpha)
                return SmoothnessMapChannel.AlbedoAlpha;
            else
                return SmoothnessMapChannel.SpecularMetallicAlpha;
        }

        static void SetMaterialKeywords(Material material, WorkflowMode workflowMode)
        {
            // Note: keywords must be based on Material value not on MaterialProperty due to multi-edit & material animation
            // (MaterialProperty value might come from renderer material property block)
            SetKeyword(material, "_NORMALMAP", material.GetTexture("_BumpMap") || material.GetTexture("_DetailNormalMap"));
            if (workflowMode == WorkflowMode.Roughness)
            {
                SetKeyword(material, "_SPECGLOSSMAP", material.GetTexture("_SpecGlossMap"));
                SetKeyword(material, "_METALLICGLOSSMAP", material.GetTexture("_MetallicGlossMap"));
            } 
            else 
            {
                if (workflowMode == WorkflowMode.Specular || workflowMode == WorkflowMode.Cloth)
                    SetKeyword(material, "_SPECGLOSSMAP", material.GetTexture("_SpecGlossMap"));
                else if (workflowMode == WorkflowMode.Metallic)
                    SetKeyword(material, "_METALLICGLOSSMAP", material.GetTexture("_MetallicGlossMap"));
            }
            SetKeyword(material, "_PARALLAXMAP", material.GetTexture("_ParallaxMap"));
            SetKeyword(material, "_DETAIL_MULX2", material.GetTexture("_DetailAlbedoMap") || material.GetTexture("_DetailNormalMap"));

            // A material's GI flag internally keeps track of whether emission is enabled at all, it's enabled but has no effect
            // or is enabled and may be modified at runtime. This state depends on the values of the current flag and emissive color.
            // The fixup routine makes sure that the material is in the correct state if/when changes are made to the mode or color.
            MaterialEditor.FixupEmissiveFlag(material);
            bool shouldEmissionBeEnabled = (material.globalIlluminationFlags & MaterialGlobalIlluminationFlags.EmissiveIsBlack) == 0;
            SetKeyword(material, "_EMISSION", shouldEmissionBeEnabled);

            if (material.HasProperty("_SmoothnessTextureChannel"))
            {
                SetKeyword(material, "_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A", GetSmoothnessMapChannel(material) == SmoothnessMapChannel.AlbedoAlpha);
            }

            // New properties

            SetKeyword(material, "_LIGHTMAPSPECULAR", material.GetFloat("_LightmapSpecular") == 1? true : false);
            SetKeyword(material, "_NORMALMAP_SHADOW", material.GetFloat("_NormalMapShadows") == 1? true : false);
        }

        static void MaterialChanged(Material material, WorkflowMode workflowMode, bool overrideRenderQueue)
        {
            SetupMaterialWithBlendMode(material, (BlendMode)material.GetFloat("_Mode"), overrideRenderQueue);

            SetMaterialKeywords(material, workflowMode);
        }

        static void SetKeyword(Material m, string keyword, bool state)
        {
            if (state)
                m.EnableKeyword(keyword);
            else
                m.DisableKeyword(keyword);
        }
    }
} // namespace SilentTools