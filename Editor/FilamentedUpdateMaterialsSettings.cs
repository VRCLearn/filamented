using System.Collections.Generic;
using System.Linq;
using System.Text;
using UnityEditor;
using UnityEngine;
using System.IO;

#if UNITY_2022_3_OR_NEWER
namespace SilentTools
{
    public class FilamentedUpdateMaterialSettings : EditorWindow
    {
        public enum FeatureOnOffMode { NoChange = 0, On = 1, Off = 2 }
        public enum BakeryRenderDirMode { NoChange = -1, None = 0, RNM = 3, SH = 4, MonoSH = 6 }
        public enum TargetScope { CurrentScene, ProjectBrowser }

        private static class Styles
        {
            public static readonly GUIContent TargetScopeLabel = new("Target", "Whether to use the current scene or the selected material's folder for material updates.");
            public static readonly GUIContent BakerySettingsHeader = new("Bakery Settings");
            public static readonly GUIContent AdditionalSettingsHeader = new("Feature Settings");
            public static readonly GUIContent UpdateMaterialsButton = new("Apply");

            // User-friendly messages
            public static readonly GUIContent InfoHelpBox_SelectOperation = new("Select one or more features to change on materials.");
            public static readonly GUIContent InfoHelpBox_ProjectBrowser_NoFolder = new("Select a folder in the Project Browser window to target its materials, or select a material to use the folder it resides in.");
            public static readonly GUIContent InfoHelpBox_ProjectBrowser_NoMaterialsInFolder = new("The selected folder contains no materials to update.");
            public static readonly GUIContent InfoHelpBox_NoMaterialsInScene = new("No materials were found to update in the current scene.");

            public static readonly GUIContent CopyListButton = new("Copy List");
            public static readonly string LabelNone = " (None)";

            public static readonly GUIContent BakeryDirModeLabel = new("Bakery Mode", "Sets the Bakery directional lightmap rendering mode.");
            public static readonly GUIContent BakeryVertexLMLabel = new("Vertex Lightmaps", "Enable or disable Bakery vertex lightmap support.");
            public static readonly GUIContent LtcgiLabel = new("LTCGI", "Enable or disable LTCGI.");
            public static readonly GUIContent VrclvLabel = new("VRC Light Volumes", "Enable or disable support for VRC Light Volumes.");
            public static readonly GUIContent LightmapSpecularLabel = new("Lightmap Specular", "Enable or disable specular highlights from lightmaps.");

            public static string TotalMaterialsLabel(int count, TargetScope scope, string folderName) =>
                scope == TargetScope.ProjectBrowser
                    ? $"Total materials in folder '{folderName}': {count}"
                    : $"Total materials in current scene: {count}";

            public static string FoldoutMaterialsToUpdate(int count) => $"Will be updated ({count})";
            public static string FoldoutSkippedMaterials(int count) => $"Will be skipped ({count})";
        }

        // --- Settings ---
        private TargetScope _targetScope = TargetScope.CurrentScene;
        private BakeryRenderDirMode _bakeryDirectionalMode = BakeryRenderDirMode.NoChange;
        private FeatureOnOffMode _bakeryVertexMode = FeatureOnOffMode.NoChange;
        private FeatureOnOffMode _ltcgiMode = FeatureOnOffMode.NoChange;
        private FeatureOnOffMode _vrclvMode = FeatureOnOffMode.NoChange;
        private FeatureOnOffMode _lightmapSpecularMode = FeatureOnOffMode.NoChange;

        // --- Property and Keyword Constants (Internal) ---
        private const string BAKERY_DIR_PROP = "_Bakery";
        private const string BAKERY_RNM_KEY = "_BAKERY_RNM";
        private const string BAKERY_SH_KEY = "_BAKERY_SH";
        private const string BAKERY_MONOSH_KEY = "_BAKERY_MONOSH";

        private const string BAKERY_VERTEX_PROP = "_BakeryVertexLM";
        private const string BAKERY_VERTEX_KEY = "_BAKERY_VERTEXLM";

        private const string LTCGI_PROP = "_LTCGI";
        private const string LTCGI_KEY = "_LTCGI";

        private const string VRCLV_PROP = "_VRCLV";
        private const string VRCLV_KEY = "_VRCLV";

        private const string LIGHTMAP_SPEC_PROP = "_LightmapSpecular";
        private const string LIGHTMAP_SPEC_KEY = "_LIGHTMAPSPECULAR";

        // --- UI State ---
        private int _totalUniqueMaterialsFound;
        private readonly List<Material> _materialsToModify = new();
        private readonly List<string> _materialsToModifyNames = new();
        private readonly List<Material> _materialsSkippedMissingProperty = new();
        private readonly List<string> _materialsSkippedMissingPropertyNames = new();
        private bool _showMaterialsToModify, _showSkippedMaterialsMissingProperty;
        private Vector2 _scrollPosModify, _scrollPosSkippedMissing;
        private bool _forceUiRefreshAndRecalculate = true;
        private string _currentProjectBrowserFolderPath = string.Empty;
        private string _currentProjectBrowserFolderName = "N/A";

        [MenuItem("Tools/Silent/Filamented Batch Material Updater")]
        public static void ShowWindow() =>
            GetWindow<FilamentedUpdateMaterialSettings>("Material Updater");

        private void OnFocus() => _forceUiRefreshAndRecalculate = true;
        private void OnProjectChange() => _forceUiRefreshAndRecalculate = true;
        private void OnHierarchyChange() { if (_targetScope == TargetScope.CurrentScene) _forceUiRefreshAndRecalculate = true; }
        private void OnSelectionChange() { if (_targetScope == TargetScope.ProjectBrowser) _forceUiRefreshAndRecalculate = true; }

        private void OnGUI()
        {
            EditorGUI.BeginChangeCheck();

            // Display settings
            _targetScope = (TargetScope)EditorGUILayout.EnumPopup(Styles.TargetScopeLabel, _targetScope);

            EditorGUILayout.Space();
            EditorGUILayout.BeginVertical();
            EditorGUILayout.LabelField(Styles.BakerySettingsHeader, EditorStyles.boldLabel);
            _bakeryDirectionalMode = (BakeryRenderDirMode)EditorGUILayout.EnumPopup(Styles.BakeryDirModeLabel, _bakeryDirectionalMode);
            _bakeryVertexMode = (FeatureOnOffMode)EditorGUILayout.EnumPopup(Styles.BakeryVertexLMLabel, _bakeryVertexMode);

            EditorGUILayout.Space();
            EditorGUILayout.LabelField(Styles.AdditionalSettingsHeader, EditorStyles.boldLabel);
            _ltcgiMode = (FeatureOnOffMode)EditorGUILayout.EnumPopup(Styles.LtcgiLabel, _ltcgiMode);
            _vrclvMode = (FeatureOnOffMode)EditorGUILayout.EnumPopup(Styles.VrclvLabel, _vrclvMode);
            _lightmapSpecularMode = (FeatureOnOffMode)EditorGUILayout.EnumPopup(Styles.LightmapSpecularLabel, _lightmapSpecularMode);
            EditorGUILayout.EndVertical();

            if (EditorGUI.EndChangeCheck())
                _forceUiRefreshAndRecalculate = true;

            if (_forceUiRefreshAndRecalculate)
            {
                UpdateMaterialListsAndCounts();
                _forceUiRefreshAndRecalculate = false;
            }

            DisplayActionArea();
            DisplaySummaryAndLists();
        }

        private void DisplayActionArea()
        {
            EditorGUILayout.Space(20);
            bool anyOpSelected = IsAnyOperationSelected();

            if (_targetScope == TargetScope.ProjectBrowser && string.IsNullOrEmpty(_currentProjectBrowserFolderPath))
            {
                EditorGUILayout.HelpBox(Styles.InfoHelpBox_ProjectBrowser_NoFolder.text, MessageType.Warning);
            }
            else if (_totalUniqueMaterialsFound == 0)
            {
                string message = _targetScope == TargetScope.ProjectBrowser
                    ? Styles.InfoHelpBox_ProjectBrowser_NoMaterialsInFolder.text
                    : Styles.InfoHelpBox_NoMaterialsInScene.text;
                EditorGUILayout.HelpBox(message, MessageType.Info);
            }
            else if (!anyOpSelected)
            {
                EditorGUILayout.HelpBox(Styles.InfoHelpBox_SelectOperation.text, MessageType.Info);
            }
            else
            {
                if (GUILayout.Button(Styles.UpdateMaterialsButton, GUILayout.Height(30)))
                {
                    ApplyChanges();
                    _forceUiRefreshAndRecalculate = true;
                }
            }
        }

        private void DisplaySummaryAndLists()
        {
            EditorGUILayout.Space();
            EditorGUILayout.LabelField(Styles.TotalMaterialsLabel(_totalUniqueMaterialsFound, _targetScope, _currentProjectBrowserFolderName), EditorStyles.label);

            _showMaterialsToModify = EditorGUILayout.Foldout(_showMaterialsToModify, Styles.FoldoutMaterialsToUpdate(_materialsToModifyNames.Count), true);
            if (_showMaterialsToModify)
                DrawMaterialList(_materialsToModifyNames, ref _scrollPosModify);

            _showSkippedMaterialsMissingProperty = EditorGUILayout.Foldout(_showSkippedMaterialsMissingProperty, Styles.FoldoutSkippedMaterials(_materialsSkippedMissingPropertyNames.Count), true);
            if (_showSkippedMaterialsMissingProperty)
                DrawMaterialList(_materialsSkippedMissingPropertyNames, ref _scrollPosSkippedMissing);
        }

        private void DrawMaterialList(IReadOnlyList<string> materialNames, ref Vector2 scrollPosition)
        {
            if (!materialNames.Any())
            {
                EditorGUILayout.LabelField(Styles.LabelNone, EditorStyles.miniLabel);
                return;
            }

            using (new EditorGUI.IndentLevelScope())
            {
                scrollPosition = EditorGUILayout.BeginScrollView(scrollPosition, GUILayout.MaxHeight(150));
                foreach (var name in materialNames)
                    EditorGUILayout.LabelField($"- {name}", EditorStyles.miniLabel);
                EditorGUILayout.EndScrollView();

                if (GUILayout.Button(Styles.CopyListButton, GUILayout.Width(200)))
                {
                    EditorGUIUtility.systemCopyBuffer = string.Join("\n", materialNames);
                    Debug.Log($"{Styles.CopyListButton.text}: Copied {materialNames.Count} material names to clipboard.");
                }
            }
        }

        private bool IsAnyOperationSelected() =>
            _bakeryDirectionalMode != BakeryRenderDirMode.NoChange ||
            _bakeryVertexMode != FeatureOnOffMode.NoChange ||
            _ltcgiMode != FeatureOnOffMode.NoChange ||
            _vrclvMode != FeatureOnOffMode.NoChange ||
            _lightmapSpecularMode != FeatureOnOffMode.NoChange;

        // --- Second Part Refactored ---

        private string GetActiveProjectBrowserFolderPath()
        {
            _currentProjectBrowserFolderPath = string.Empty;
            _currentProjectBrowserFolderName = "N/A";

            if (Selection.activeObject == null)
                return string.Empty;

            string path = AssetDatabase.GetAssetPath(Selection.activeObject);
            if (string.IsNullOrEmpty(path))
                return string.Empty;

            if (AssetDatabase.IsValidFolder(path))
            {
                _currentProjectBrowserFolderPath = path;
                _currentProjectBrowserFolderName = Path.GetFileName(path);
                return path;
            }

            string directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory) && AssetDatabase.IsValidFolder(directory))
            {
                _currentProjectBrowserFolderPath = directory.Replace("\\", "/");
                _currentProjectBrowserFolderName = Path.GetFileName(_currentProjectBrowserFolderPath);
                return _currentProjectBrowserFolderPath;
            }

            if (Path.GetDirectoryName(path)?.Replace("\\", "/") == "Assets")
            {
                _currentProjectBrowserFolderPath = "Assets";
                _currentProjectBrowserFolderName = "Assets";
                return "Assets";
            }

            return string.Empty;
        }

        private HashSet<Material> GetTargetMaterials()
        {
            var uniqueMaterials = new HashSet<Material>();
            _currentProjectBrowserFolderPath = string.Empty;
            _currentProjectBrowserFolderName = "N/A";

            if (_targetScope == TargetScope.CurrentScene)
            {
                var renderers = FindObjectsOfType<Renderer>(true);
                foreach (var renderer in renderers)
                {
                    foreach (var mat in renderer.sharedMaterials)
                    {
                        if (mat != null)
                            uniqueMaterials.Add(mat);
                    }
                }
            }
            else
            {
                string folderPath = GetActiveProjectBrowserFolderPath(); // Sets folder path and name
                if (!string.IsNullOrEmpty(folderPath))
                {
                    var materialGUIDs = AssetDatabase.FindAssets("t:Material", new[] { folderPath });
                    string normalizedFolderPath = folderPath.TrimEnd('/');
                    foreach (var guid in materialGUIDs)
                    {
                        string matPath = AssetDatabase.GUIDToAssetPath(guid);
                        if (Path.GetDirectoryName(matPath)?.Replace("\\", "/") == normalizedFolderPath)
                        {
                            var mat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
                            if (mat != null)
                                uniqueMaterials.Add(mat);
                        }
                    }
                }
            }

            return uniqueMaterials;
        }

        private void UpdateMaterialListsAndCounts()
        {
            var targetMaterials = GetTargetMaterials();
            _totalUniqueMaterialsFound = targetMaterials.Count;
            _materialsToModify.Clear();
            _materialsSkippedMissingProperty.Clear();

            if (_totalUniqueMaterialsFound == 0 || !IsAnyOperationSelected())
            {
                _materialsToModifyNames.Clear();
                _materialsSkippedMissingPropertyNames.Clear();
                return;
            }

            foreach (var material in targetMaterials)
            {
                if (material == null)
                    continue;

                bool willBeModified = false;
                bool lacksProperty = false;

                void CheckOnOffFeature(FeatureOnOffMode mode, string prop, string key)
                {
                    if (mode == FeatureOnOffMode.NoChange)
                        return;

                    if (material.HasProperty(prop))
                    {
                        if (!IsFeatureStateCorrect(material, prop, key, mode == FeatureOnOffMode.On))
                            willBeModified = true;
                    }
                    else
                    {
                        lacksProperty = true;
                    }
                }

                CheckOnOffFeature(_bakeryVertexMode, BAKERY_VERTEX_PROP, BAKERY_VERTEX_KEY);
                CheckOnOffFeature(_ltcgiMode, LTCGI_PROP, LTCGI_KEY);
                CheckOnOffFeature(_vrclvMode, VRCLV_PROP, VRCLV_KEY);
                CheckOnOffFeature(_lightmapSpecularMode, LIGHTMAP_SPEC_PROP, LIGHTMAP_SPEC_KEY);

                if (_bakeryDirectionalMode != BakeryRenderDirMode.NoChange)
                {
                    if (material.HasProperty(BAKERY_DIR_PROP))
                    {
                        if (!IsBakeryDirectionalModeCorrect(material, _bakeryDirectionalMode))
                            willBeModified = true;
                    }
                    else
                    {
                        lacksProperty = true;
                    }
                }

                if (willBeModified)
                {
                    if (!_materialsToModify.Contains(material))
                        _materialsToModify.Add(material);
                }
                else if (lacksProperty)
                {
                    if (!_materialsSkippedMissingProperty.Contains(material))
                        _materialsSkippedMissingProperty.Add(material);
                }
            }

            _materialsSkippedMissingProperty.RemoveAll(_materialsToModify.Contains);

            _materialsToModifyNames.Clear();
            _materialsToModifyNames.AddRange(
                _materialsToModify.Select(m => m.name)
                                  .Distinct()
                                  .OrderBy(name => name));

            _materialsSkippedMissingPropertyNames.Clear();
            _materialsSkippedMissingPropertyNames.AddRange(
                _materialsSkippedMissingProperty.Select(m => m.name)
                                                .Distinct()
                                                .OrderBy(name => name));
        }

        private static bool IsFeatureStateCorrect(Material mat, string propertyName, string keywordName, bool expectedStateIsOn)
        {
            bool currentKeywordState = mat.IsKeywordEnabled(keywordName);
            bool hasProperty = mat.HasProperty(propertyName);
            float currentValue = hasProperty ? mat.GetFloat(propertyName) : 0f;

            return expectedStateIsOn
                ? currentKeywordState && (!hasProperty || currentValue > 0.5f)
                : !currentKeywordState && (!hasProperty || currentValue < 0.5f);
        }

        private static bool IsBakeryDirectionalModeCorrect(Material mat, BakeryRenderDirMode targetMode)
        {
            float currentFloat = mat.GetFloat(BAKERY_DIR_PROP);
            bool rnm = mat.IsKeywordEnabled(BAKERY_RNM_KEY);
            bool sh = mat.IsKeywordEnabled(BAKERY_SH_KEY);
            bool mono = mat.IsKeywordEnabled(BAKERY_MONOSH_KEY);

            return targetMode switch
            {
                BakeryRenderDirMode.None => Mathf.Approximately(currentFloat, 0f) && !rnm && !sh && !mono,
                BakeryRenderDirMode.RNM => rnm && !sh && !mono && Mathf.Approximately(currentFloat, 2f),
                BakeryRenderDirMode.SH => sh && !rnm && !mono && Mathf.Approximately(currentFloat, 1f),
                BakeryRenderDirMode.MonoSH => mono && !rnm && !sh && Mathf.Approximately(currentFloat, 3f),
                _ => true,
            };
        }

        private static void ClearBakeryDirectionalKeywords(Material m)
        {
            m.DisableKeyword(BAKERY_RNM_KEY);
            m.DisableKeyword(BAKERY_SH_KEY);
            m.DisableKeyword(BAKERY_MONOSH_KEY);
        }

        private void ApplyChanges()
        {
            if (!_materialsToModify.Any())
            {
                Debug.Log("No materials to modify.");
                return;
            }

            Undo.RecordObjects(_materialsToModify.ToArray(), "Batch Update Material Features");
            int changedCount = 0;

            foreach (var material in _materialsToModify)
            {
                if (material == null)
                    continue;

                bool propertyChanged = false;

                void ApplyOnOffFeature(FeatureOnOffMode mode, string prop, string key)
                {
                    if (mode == FeatureOnOffMode.NoChange || !material.HasProperty(prop))
                        return;

                    bool targetOn = mode == FeatureOnOffMode.On;
                    if (!IsFeatureStateCorrect(material, prop, key, targetOn))
                    {
                        SetFeatureState(material, prop, key, targetOn);
                        propertyChanged = true;
                    }
                }

                ApplyOnOffFeature(_bakeryVertexMode, BAKERY_VERTEX_PROP, BAKERY_VERTEX_KEY);
                ApplyOnOffFeature(_ltcgiMode, LTCGI_PROP, LTCGI_KEY);
                ApplyOnOffFeature(_vrclvMode, VRCLV_PROP, VRCLV_KEY);
                ApplyOnOffFeature(_lightmapSpecularMode, LIGHTMAP_SPEC_PROP, LIGHTMAP_SPEC_KEY);

                if (_bakeryDirectionalMode != BakeryRenderDirMode.NoChange && material.HasProperty(BAKERY_DIR_PROP))
                {
                    if (!IsBakeryDirectionalModeCorrect(material, _bakeryDirectionalMode))
                    {
                        ClearBakeryDirectionalKeywords(material);
                        switch (_bakeryDirectionalMode)
                        {
                            case BakeryRenderDirMode.None:
                                material.SetFloat(BAKERY_DIR_PROP, 0f);
                                break;
                            case BakeryRenderDirMode.RNM:
                                material.EnableKeyword(BAKERY_RNM_KEY);
                                material.SetFloat(BAKERY_DIR_PROP, 2f);
                                break;
                            case BakeryRenderDirMode.SH:
                                material.EnableKeyword(BAKERY_SH_KEY);
                                material.SetFloat(BAKERY_DIR_PROP, 1f);
                                break;
                            case BakeryRenderDirMode.MonoSH:
                                material.EnableKeyword(BAKERY_MONOSH_KEY);
                                material.SetFloat(BAKERY_DIR_PROP, 3f);
                                break;
                        }
                        propertyChanged = true;
                    }
                }

                if (propertyChanged)
                {
                    changedCount++;
                    EditorUtility.SetDirty(material);
                }
            }

            if (changedCount > 0)
                AssetDatabase.SaveAssets();

            Debug.Log($"{changedCount} material(s) modified. " +
                      $"{_materialsToModify.Count} targeted. " +
                      $"{_totalUniqueMaterialsFound} in {(_targetScope == TargetScope.CurrentScene ? "scene" : $"folder '{_currentProjectBrowserFolderName}'")}.");
            _forceUiRefreshAndRecalculate = true;
            Repaint();
        }

        private static void SetFeatureState(Material m, string propertyName, string keywordName, bool enable)
        {
            if (enable)
            {
                m.EnableKeyword(keywordName);
                if (m.HasProperty(propertyName))
                    m.SetFloat(propertyName, 1.0f);
            }
            else
            {
                m.DisableKeyword(keywordName);
                if (m.HasProperty(propertyName))
                    m.SetFloat(propertyName, 0.0f);
            }
        }
    }
}
#endif // UNITY_2022_3_OR_NEWER