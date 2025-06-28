using UnityEditor;
using UnityEngine;
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine.Rendering;
using Object = UnityEngine.Object;
using System.Linq;

namespace Silent.FilamentedExtras.Unity
{
	public partial class FilamentedExtrasInspector : ShaderGUI
	{

		sealed class DefaultStyles
		{
			public static GUIStyle scmStyle;
			public static GUIStyle sectionHeader;
			public static GUIStyle sectionHeaderBox;
            static DefaultStyles()
            {
				scmStyle = new GUIStyle("DropDownButton");
				sectionHeader = new GUIStyle(EditorStyles.miniBoldLabel);
				sectionHeader.padding.left = 24;
				sectionHeader.padding.right = -24;
				sectionHeaderBox = new GUIStyle( GUI.skin.box );
				sectionHeaderBox.alignment = TextAnchor.MiddleLeft;
				sectionHeaderBox.padding.left = 5;
				sectionHeaderBox.padding.right = -5;
				sectionHeaderBox.padding.top = 0;
				sectionHeaderBox.padding.bottom = 0;
			}
		}	

		sealed class HeaderExDecorator : MaterialPropertyDrawer
    	{
	        private readonly string header;

	        public HeaderExDecorator(string header)
	        {
	            this.header = header;
	        }

	        // so that we can accept Header(1) and display that as text
	        public HeaderExDecorator(float headerAsNumber)
	        {
	            this.header = headerAsNumber.ToString();
	        }

	        public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
	        {
	            return 24f;
	        }

	        public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
	        {
				/*
	            position.y += 8;
	            position = EditorGUI.IndentedRect(position);
	            GUI.Label(position, header, EditorStyles.boldLabel);
				*/
            Rect r = position;
				r.x -= 2.0f;
				r.y += 2.0f;
				r.height = 18.0f;
				r.width -= 0.0f;
			GUI.Box(r, EditorGUIUtility.IconContent("d_FilterByType"), DefaultStyles.sectionHeaderBox);
			position.y += 2;
			GUI.Label(position, header, DefaultStyles.sectionHeader);
	        }
    	}

	    sealed class SetKeywordDrawer : MaterialPropertyDrawer
	    {
	        static bool s_drawing;

	        readonly string _keyword;

	        public SetKeywordDrawer() : this(default) { }

	        public SetKeywordDrawer(string keyword)
	        {
	            _keyword = keyword;
	        }

	        public override void Apply(MaterialProperty prop)
	        {
	            if (!string.IsNullOrEmpty(_keyword))
	            {
	                foreach (Material mat in prop.targets)
	                {
	                    if (mat.GetTexture(prop.name) != null)
	                        mat.EnableKeyword(_keyword);
	                    else
	                        mat.DisableKeyword(_keyword);
	                }
	            }
	        }

	        public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
	            => 0;

	        public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
	        {
	            if (s_drawing)
	            {
	                editor.DefaultShaderProperty(position, prop, label.text);
	            }
	            else if (prop.type == MaterialProperty.PropType.Texture)
	            {
	                var oldLabelWidth = EditorGUIUtility.labelWidth;
	                EditorGUIUtility.labelWidth = 0f;
	                s_drawing = true;
	                try
	                {
	                    EditorGUI.BeginChangeCheck();
	                    {
	                        editor.TextureProperty(prop, label.text);
	                    }
	                    if (EditorGUI.EndChangeCheck())
	                    {
	                        if (!string.IsNullOrEmpty(_keyword))
	                        {
	                            var useTexture = prop.textureValue != null;
	                            foreach (Material mat in prop.targets)
	                            {
	                                if (useTexture)
	                                    mat.EnableKeyword(_keyword);
	                                else
	                                    mat.DisableKeyword(_keyword);
	                            }
	                        }
	                    }
	                }
	                finally
	                {
	                    s_drawing = false;
	                    EditorGUIUtility.labelWidth = oldLabelWidth;
	                }
	            }
	        }
	    }

	// Used for toggling GrabPass
	internal class SetShaderPassToggleDrawer : MaterialPropertyDrawer
	{
		readonly string _passName;
    	readonly string _keyword;

		public SetShaderPassToggleDrawer() : this("Always", default) { }

		public SetShaderPassToggleDrawer(string passName, string keyword)
		{
			_passName = passName;
        	_keyword = keyword;
		}

		static bool IsPropertyTypeSuitable(MaterialProperty prop)
		{
			return prop.type == MaterialProperty.PropType.Float || prop.type == MaterialProperty.PropType.Range;
			// Not present in 2019.4
            // || prop.type == MaterialProperty.PropType.Int;
		}

		public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
		{
			if (!IsPropertyTypeSuitable(prop))
			{
				return EditorGUIUtility.singleLineHeight * 2.5f;
			}
			return base.GetPropertyHeight(prop, label, editor);
		}

		public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
		{

			EditorGUI.BeginChangeCheck();

			bool value = (Math.Abs(prop.floatValue) > 0.001f);
			EditorGUI.showMixedValue = prop.hasMixedValue;
			value = EditorGUI.Toggle(position, label, value);
			EditorGUI.showMixedValue = false;
			if (EditorGUI.EndChangeCheck())
			{
				prop.floatValue = value ? 1.0f : 0.0f;
				SetShaderPassEnabled(prop, value);
			}
		}

		public override void Apply(MaterialProperty prop)
		{
			base.Apply(prop);
			if (!IsPropertyTypeSuitable(prop))
				return;

			if (prop.hasMixedValue)
				return;

			SetShaderPassEnabled(prop, (Math.Abs(prop.floatValue) > 0.001f));
		}

		protected virtual void SetShaderPassEnabled(MaterialProperty prop, bool on)
		{
			foreach (Material mat in prop.targets)
			{
				mat.SetShaderPassEnabled(_passName, on);
				if (on)
				{
					mat.EnableKeyword(_keyword);
				}
				else
				{
					mat.DisableKeyword(_keyword);
				}

			}
		}
	}



    	// From momoma's GeneLit, used with permission
    	// https://github.com/momoma-null/GeneLit
	sealed class SingleLineDrawer : MaterialPropertyDrawer
	{
		static bool s_drawing;

		readonly string _extraPropName;
		readonly string _additionalPropName;

		public SingleLineDrawer() : this(default, default) { }

		public SingleLineDrawer(string extraPropName) : this(extraPropName, default) { }

		public SingleLineDrawer(string extraPropName, string additionalPropName)
		{
			_extraPropName = extraPropName;
			_additionalPropName = additionalPropName;
		}

		public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
			=> 0;

		public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
		{
			if (s_drawing)
			{
				editor.DefaultShaderProperty(position, prop, label.text);
			}

			if (prop.type != MaterialProperty.PropType.Texture)
				return;
			
			var oldLabelWidth = EditorGUIUtility.labelWidth;
			EditorGUIUtility.labelWidth = 0f;
			s_drawing = true;
        try
        {
            EditorGUI.BeginChangeCheck();

            if (string.IsNullOrEmpty(_extraPropName))
            {
                editor.TexturePropertySingleLine(label, prop);
            }
            else
            {
                var extraProp = MaterialEditor.GetMaterialProperty(prop.targets, _extraPropName);

                if (extraProp != null && extraProp.type == MaterialProperty.PropType.Color && (extraProp.flags & MaterialProperty.PropFlags.HDR) > 0)
                {
                    editor.TexturePropertyWithHDRColor(label, prop, extraProp, false);
                }
                else if (string.IsNullOrEmpty(_additionalPropName))
                {
                    editor.TexturePropertySingleLine(label, prop, extraProp);
                }
                else
                {
                    var additionalProp = MaterialEditor.GetMaterialProperty(prop.targets, _additionalPropName);
                    editor.TexturePropertySingleLine(label, prop, extraProp, additionalProp);
                }
			}
			
            EditorGUI.EndChangeCheck();
            }
			finally
			{
				s_drawing = false;
				EditorGUIUtility.labelWidth = oldLabelWidth;
			}
			
		}
	}

	sealed class SetKeywordSingleLineDrawer : MaterialPropertyDrawer
	{
		static bool s_drawing;
		readonly string _keyword;
		readonly string _extraPropName;
		readonly string _additionalPropName;

		public SetKeywordSingleLineDrawer(string keyword) : this(keyword, null, null) { }

		public SetKeywordSingleLineDrawer(string keyword, string extraPropName) : this(keyword, extraPropName, null) { }

		public SetKeywordSingleLineDrawer(string keyword, string extraPropName, string additionalPropName)
		{
			_keyword = keyword;
			_extraPropName = extraPropName;
			_additionalPropName = additionalPropName;
		}

		public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
			=> 0;

		public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
		{
			if (s_drawing)
			{
				editor.DefaultShaderProperty(position, prop, label.text);
				return;
			}

			if (prop.type != MaterialProperty.PropType.Texture)
				return;

			var oldLabelWidth = EditorGUIUtility.labelWidth;
			EditorGUIUtility.labelWidth = 0f;
			s_drawing = true;
			
			try
			{
				EditorGUI.BeginChangeCheck();

				if (string.IsNullOrEmpty(_extraPropName))
				{
					editor.TexturePropertySingleLine(label, prop);
				}
				else
				{
					var extraProp = MaterialEditor.GetMaterialProperty(prop.targets, _extraPropName);

					if (extraProp != null && extraProp.type == MaterialProperty.PropType.Color && 
						(extraProp.flags & MaterialProperty.PropFlags.HDR) > 0)
					{
						editor.TexturePropertyWithHDRColor(label, prop, extraProp, false);
					}
					else if (string.IsNullOrEmpty(_additionalPropName))
					{
						editor.TexturePropertySingleLine(label, prop, extraProp);
					}
					else
					{
						var additionalProp = MaterialEditor.GetMaterialProperty(prop.targets, _additionalPropName);
						editor.TexturePropertySingleLine(label, prop, extraProp, additionalProp);
					}
				}

				if (EditorGUI.EndChangeCheck() && !string.IsNullOrEmpty(_keyword))
				{
					var useTexture = prop.textureValue != null;
					foreach (Material mat in prop.targets)
					{
						if (useTexture)
							mat.EnableKeyword(_keyword);
						else
							mat.DisableKeyword(_keyword);
					}
				}
			}
			finally
			{
				s_drawing = false;
				EditorGUIUtility.labelWidth = oldLabelWidth;
			}
		}

		public override void Apply(MaterialProperty prop)
		{
			if (!string.IsNullOrEmpty(_keyword))
			{
				foreach (Material mat in prop.targets)
				{
					if (mat.GetTexture(prop.name) != null)
						mat.EnableKeyword(_keyword);
					else
						mat.DisableKeyword(_keyword);
				}
			}
		}
	}

sealed class TexturePropertyTwoLines : MaterialPropertyDrawer
{
    static bool s_drawing;

    readonly string _extraPropName;
    readonly string _additionalPropName;

    public TexturePropertyTwoLines() : this(default, default) { }

    public TexturePropertyTwoLines(string extraPropName) : this(extraPropName, default) { }

    public TexturePropertyTwoLines(string extraPropName, string additionalPropName)
    {
        _extraPropName = extraPropName;
        _additionalPropName = additionalPropName;
    }

    public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
        => EditorGUIUtility.singleLineHeight * 2;

    public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
    {
        if (s_drawing)
        {
            editor.DefaultShaderProperty(position, prop, label.text);
        }

        if (prop.type != MaterialProperty.PropType.Texture)
            return;

        var oldLabelWidth = EditorGUIUtility.labelWidth;
        EditorGUIUtility.labelWidth = 0f;
        s_drawing = true;
        try
        {
            EditorGUI.BeginChangeCheck();
            var firstLinePosition = new Rect(position.x, position.y, position.width, EditorGUIUtility.singleLineHeight);
            var secondLinePosition = new Rect(position.x, position.y + EditorGUIUtility.singleLineHeight, position.width, EditorGUIUtility.singleLineHeight);

            if (string.IsNullOrEmpty(_extraPropName))
            {
                editor.TexturePropertySingleLine(label, prop);
            }
            else
            {
                var extraProp = MaterialEditor.GetMaterialProperty(prop.targets, _extraPropName);
                var additionalProp = MaterialEditor.GetMaterialProperty(prop.targets, _additionalPropName);
                var extraLabel = new GUIContent(extraProp.displayName);
                var additionalLabel = new GUIContent(additionalProp.displayName);

                if (extraProp.type == MaterialProperty.PropType.Color && (extraProp.flags & MaterialProperty.PropFlags.HDR) > 0)
                    editor.TexturePropertyWithHDRColor(label, prop, extraProp, false);
                else
                    editor.TexturePropertyTwoLines(label, prop, extraProp, additionalLabel, additionalProp);
            }
            EditorGUI.EndChangeCheck();
        }
        finally
        {
            s_drawing = false;
            EditorGUIUtility.labelWidth = oldLabelWidth;
        }
    }
}



    	sealed class ScaleOffsetDecorator : MaterialPropertyDrawer
    	{
    	    bool _initialized = false;
	
    	    public ScaleOffsetDecorator() { }
	
    	    public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
    	    {
    	        if (!_initialized)
    	        {
    	            prop.ReplacePostDecorator(this);
    	            _initialized = true;
    	        }
    	        return 2f * EditorGUIUtility.singleLineHeight + EditorGUIUtility.standardVerticalSpacing;
    	    }
	
    	    public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
    	    {
    	        position.xMin += 15f;
    	        position.y = position.yMax - (2f * EditorGUIUtility.singleLineHeight + 2.5f * EditorGUIUtility.standardVerticalSpacing);
    	        editor.TextureScaleOffsetProperty(position, prop);
    	    }
    	}
    	
	    sealed class IfDefDecorator : MaterialPropertyDrawer
	    {
	        readonly string _keyword;

	        public IfDefDecorator(string keyword)
	        {
	            _keyword = keyword;
	        }

	        public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
	        {
	            var materials = Array.ConvertAll(prop.targets, o => o as Material);
	            var enabled = materials[0].IsKeywordEnabled(_keyword);
	            if (!enabled)
	            {
	                prop.SkipRemainingDrawers(this);
	            }
	            else
	            {
	                for (var i = 1; i < materials.Length; ++i)
	                {
	                    if (materials[i].IsKeywordEnabled(_keyword) != enabled)
	                    {
	                        prop.SkipRemainingDrawers(this);
	                        break;
	                    }
	                }
	            }
	            return 0;
	        }

	        public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
	        {
	            var materials = Array.ConvertAll(prop.targets, o => o as Material);
	            var enabled = materials[0].IsKeywordEnabled(_keyword);
	            if (!enabled)
	            {
	                prop.SkipRemainingDrawers(this);
	            }
	            else
	            {
	                for (var i = 1; i < materials.Length; ++i)
	                {
	                    if (materials[i].IsKeywordEnabled(_keyword) != enabled)
	                    {
	                        prop.SkipRemainingDrawers(this);
	                        break;
	                    }
	                }
	            }
	        }
	    }

	    sealed class IfNDefDecorator : MaterialPropertyDrawer
	    {
	        static readonly float s_helpBoxHeight = EditorStyles.helpBox.CalcHeight(GUIContent.none, 0f);

	        readonly string _keyword;

	        public IfNDefDecorator(string keyword)
	        {
	            _keyword = keyword;
	        }

	        public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
	        {
	            var materials = Array.ConvertAll(prop.targets, o => o as Material);
	            var enabled = materials[0].IsKeywordEnabled(_keyword);
	            if (enabled)
	            {
	                prop.SkipRemainingDrawers(this);
	            }
	            else
	            {
	                for (var i = 1; i < materials.Length; ++i)
	                {
	                    if (materials[i].IsKeywordEnabled(_keyword) != enabled)
	                    {
	                        prop.SkipRemainingDrawers(this);
	                        break;
	                    }
	                }
	            }
	            return 0;
	        }

	        public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
	        {
	            var materials = Array.ConvertAll(prop.targets, o => o as Material);
	            var enabled = materials[0].IsKeywordEnabled(_keyword);
	            if (enabled)
	            {
	                prop.SkipRemainingDrawers(this);
	            }
	            else
	            {
	                for (var i = 1; i < materials.Length; ++i)
	                {
	                    if (materials[i].IsKeywordEnabled(_keyword) != enabled)
	                    {
	                        prop.SkipRemainingDrawers(this);
	                        break;
	                    }
	                }
	            }
	        }
	    }

		sealed class IfSetDecorator : MaterialPropertyDrawer
		{
			readonly string _propertyName;
			readonly float _value;

			public IfSetDecorator(string propertyName, float value)
			{
				_propertyName = propertyName;
				_value = value;
			}

			public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
			{
				var materials = Array.ConvertAll(prop.targets, o => o as Material);
				var enabled = Mathf.Approximately(materials[0].GetFloat(_propertyName), _value);
				if (!enabled)
				{
					prop.SkipRemainingDrawers(this);
				}
				else
				{
					for (var i = 1; i < materials.Length; ++i)
					{
						if (!Mathf.Approximately(materials[i].GetFloat(_propertyName), _value))
						{
							prop.SkipRemainingDrawers(this);
							break;
						}
					}
				}
				return 0;
			}

			public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
			{
				var materials = Array.ConvertAll(prop.targets, o => o as Material);
				var enabled = Mathf.Approximately(materials[0].GetFloat(_propertyName), _value);
				if (!enabled)
				{
					prop.SkipRemainingDrawers(this);
				}
				else
				{
					for (var i = 1; i < materials.Length; ++i)
					{
						if (!Mathf.Approximately(materials[i].GetFloat(_propertyName), _value))
						{
							prop.SkipRemainingDrawers(this);
							break;
						}
					}
				}
			}
		}

		sealed class GradientDisplayDecorator : MaterialPropertyDrawer
		{
			readonly Color[] _colors;

			public GradientDisplayDecorator(params string[] colors)
			{
				_colors = new Color[colors.Length];
				for (int i = 0; i < colors.Length; i++)
				{
					_colors[i] = ColorUtility.TryParseHtmlString(colors[i], out var col) ? col : Color.clear;
				}
			}

			public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
			{
				return 0.0f; // base.GetPropertyHeight(prop, label, editor) + EditorGUIUtility.singleLineHeight;
			}

			public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
			{
				var gradient = new Gradient();
				var colorKeys = new GradientColorKey[_colors.Length];
				for (int i = 0; i < _colors.Length; i++)
				{
					colorKeys[i] = new GradientColorKey(_colors[i], (float)i / (_colors.Length - 1));
				}
				gradient.colorKeys = colorKeys;

				EditorGUI.BeginDisabledGroup(true);
				var gradientRect = new Rect(position.x, position.y, position.width - 54.0f, 0);
				EditorGUI.GradientField(gradientRect, " ", gradient);
				EditorGUI.EndDisabledGroup();
			}
		}

		sealed class RGBSliderDecorator : MaterialPropertyDrawer
		{
			private float minRange;
			private float maxRange;
			private bool rgbEnabled = false;

			bool _initialized = false;

			public RGBSliderDecorator(float minRange, float maxRange)
			{
				this.minRange = minRange;
				this.maxRange = maxRange;
			}

			public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
			{
				if (prop.type == MaterialProperty.PropType.Color || prop.type == MaterialProperty.PropType.Vector)
				{
					bool isColor = prop.type == MaterialProperty.PropType.Color;
					Vector4 value = prop.vectorValue;

					if (isColor)
					{
						Color colorValue = prop.colorValue;
						value = new Vector4(colorValue.r, colorValue.g, colorValue.b, colorValue.a);
					}
					
					if (!_initialized)
					{
						// prop.ReplacePropertyDrawerWithDecorator(this);
						_initialized = true;
						bool allEqual = Mathf.Approximately(value.x, value.y) && Mathf.Approximately(value.y, value.z) && Mathf.Approximately(value.z, value.w);
						rgbEnabled = allEqual ? false : true;
					}

					GUILayout.Space( EditorGUIUtility.singleLineHeight * -3f); // Adjust the value to push elements up or down

					EditorGUI.BeginChangeCheck();

					Rect overallRect = EditorGUILayout.GetControlRect();
					Rect rRect = EditorGUILayout.GetControlRect();
					Rect gRect = EditorGUILayout.GetControlRect();
					Rect bRect = EditorGUILayout.GetControlRect();

					if (Event.current.type == EventType.MouseDown && Event.current.clickCount == 2)
					{
						if (overallRect.Contains(Event.current.mousePosition) || rRect.Contains(Event.current.mousePosition) || gRect.Contains(Event.current.mousePosition) || bRect.Contains(Event.current.mousePosition))
						{
							rgbEnabled = !rgbEnabled;
							Event.current.Use();
						}
					}

					float overallValueProxy = (value.x + value.y + value.z) / 3.0f;

					EditorGUI.BeginDisabledGroup(rgbEnabled);
					float overallValue = EditorGUI.Slider(overallRect, label, rgbEnabled ? overallValueProxy : value.x, minRange, maxRange);
					EditorGUI.EndDisabledGroup();

					EditorGUI.BeginDisabledGroup(!rgbEnabled);
					EditorGUI.indentLevel++;
					float r = EditorGUI.Slider(rRect, "R", value.x, minRange, maxRange);
					float g = EditorGUI.Slider(gRect, "G", value.y, minRange, maxRange);
					float b = EditorGUI.Slider(bRect, "B", value.z, minRange, maxRange);
					EditorGUI.indentLevel--;
					EditorGUI.EndDisabledGroup();

					if (EditorGUI.EndChangeCheck())
					{
						if (!rgbEnabled)
						{
							value = new Vector4(overallValue, overallValue, overallValue, overallValue);
						}
						else
						{
							value = new Vector4(r, g, b, 1.0f);
						}
					}

					prop.vectorValue = value;

					if (isColor) prop.colorValue = value;

					prop.SkipRemainingDrawers(this);
				}
				else
				{
					EditorGUI.LabelField(position, label, "Use with Color or Vector only.");
				}
			}
		}

		sealed class CheckDFGTextureDecorator : MaterialPropertyDrawer
		{
			public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
			{
				return 0; // Do not display the property field
			}

			public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
			{
				var materials = Array.ConvertAll(prop.targets, o => o as Material);
				bool textureSet = materials[0].GetTexture("_DFG") != null;

				for (int i = 1; i < materials.Length; ++i)
				{
					if ((materials[i].GetTexture("_DFG") != null) != textureSet)
					{
						textureSet = false;
						break;
					}
				}

				if (!textureSet)
				{
					EditorGUILayout.HelpBox("No texture is assigned to the DFG slot in the shader. This will cause the shader to render incorrecty. Please assign one of the DFG textures to the DFG slot in the shader.", MessageType.Error);
				}
			}
		}

		public class BlendModeSelectorDrawer : MaterialPropertyDrawer
		{
			private readonly string _srcBlend;
			private readonly string _dstBlend;
			private readonly string _customRenderQueue;
			private readonly string _zWrite;
			private readonly string _alphaToMask;
			
			public BlendModeSelectorDrawer(string srcBlend, string dstBlend, string customRenderQueue, string zWrite = null, string alphaToMask = null)
			{
				_srcBlend = srcBlend;
				_dstBlend = dstBlend;
				_customRenderQueue = customRenderQueue;
				_zWrite = zWrite;
				_alphaToMask = alphaToMask;
			}

			private struct BlendModeData
			{
				public string name;
				public string keyword;
				public BlendMode srcBlend;
				public BlendMode dstBlend;
				public RenderQueue renderQueue;
				public string renderType;

				public BlendModeData(string name, string keyword, BlendMode srcBlend, BlendMode dstBlend, RenderQueue renderQueue, string renderType)
				{
					this.name = name;
					this.keyword = keyword;
					this.srcBlend = srcBlend;
					this.dstBlend = dstBlend;
					this.renderQueue = renderQueue;
					this.renderType = renderType;
				}
			}

			private static readonly BlendModeData[] blendModes = new BlendModeData[]
			{
				new BlendModeData("Opaque", "", BlendMode.One, BlendMode.Zero, RenderQueue.Geometry, "Opaque"),
				new BlendModeData("Cutout", "_ALPHATEST_ON", BlendMode.One, BlendMode.Zero, RenderQueue.AlphaTest, "TransparentCutout"),
				new BlendModeData("Transparent", "_ALPHAPREMULTIPLY_ON", BlendMode.SrcAlpha, BlendMode.OneMinusSrcAlpha, RenderQueue.Transparent, "Transparent"),
				new BlendModeData("Fade", "_ALPHABLEND_ON", BlendMode.One, BlendMode.OneMinusSrcAlpha, RenderQueue.Transparent, "Transparent"),
				new BlendModeData("Additive", "_ALPHABLEND_ON", BlendMode.One, BlendMode.One, RenderQueue.Transparent, "Transparent")
			};

			public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
			{
				EditorGUI.BeginChangeCheck();
				int blendMode = (int)prop.floatValue;
				string[] blendModeNames = System.Array.ConvertAll(blendModes, mode => mode.name);
				blendMode = EditorGUI.Popup(position, "Blend Mode", blendMode, blendModeNames);
				if (EditorGUI.EndChangeCheck())
				{
					editor.RegisterPropertyChangeUndo("Blend Mode");
					prop.floatValue = blendMode;
					foreach (var target in prop.targets)
					{
						SetMaterialKeywords((Material)target, blendMode);
					}
				}
			}

			private void SetMaterialKeywords(Material targetMat, int blendMode)
			{
				// Disable all keywords
				foreach (var mode in blendModes)
				{
					targetMat.DisableKeyword(mode.keyword);
				}

				// Enable the selected blend mode keyword and set the blend mode properties
				var data = blendModes[blendMode];
				targetMat.EnableKeyword(data.keyword);
				targetMat.SetInt(_srcBlend, (int)data.srcBlend);
				targetMat.SetInt(_dstBlend, (int)data.dstBlend);
				targetMat.SetOverrideTag("RenderType", data.renderType);

				// Set ZWrite based on blend mode and render queue
				if (!string.IsNullOrEmpty(_zWrite))
				{
					bool zWrite = ((blendMode == 0 || blendMode == 1) || targetMat.renderQueue < 3000);
					targetMat.SetInt(_zWrite, zWrite ? 1 : 0);
				}

				// Set AlphaToMask for Cutout mode
				if (!string.IsNullOrEmpty(_alphaToMask))
				{
					// Only enable AlphaToMask if the mode is Cutout (1)
					targetMat.SetInt(_alphaToMask, blendMode == 1 ? 1 : 0);
				}

    			targetMat.renderQueue = (int)data.renderQueue;
			}
		}
    }
}
