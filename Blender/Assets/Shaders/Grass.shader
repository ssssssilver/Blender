Shader "unlit/Grass"
{
	Properties
	{
		[Header(Color)]
		[Space]
		_TopCol("topColor",Color) = (1,1,1,1)
		_BottomCol("bottomColor",Color) = (1,1,1,1)
		_TranslucentGain("表面颜色权重", Range(0,1)) = 0.5

		[Header(Density)]
		[Space]
		_TessellationUniform("基础密度", Range(0, 6)) = 1
		_TextureStrength("纹理强度",Range(0,6)) = 1
		_DensityTexture("密度纹理(A)",2D) = "black"{}

		[Header(Shape)]
		[Space]
		[Toggle(_USE_GRASS_TEXTURE)]_UseTexture("使用纹理形状",Float) = 0
		[NoScaleOffset]_GrassTexture("草叶形状(A)",2D) = "white"{}
		_BladeWidthBase("基础宽度",Float) = 0.5
		_BladeWidthRandom("宽度扰乱",Float) = 0.5
		_BladeHeightBase("基础高度",Float) = 0.5
		_BladeHeightRandom("高度扰乱",Float) = 0.5

		[Header(Wind)]
		[Space]
		_WindMap("风向贴图",2D) = "white"{}
		_WindSpeed("风速(XY)",Vector) = (0.05,0.05,0,0)
		_WindStrength("风力",Float) = 1

		[Header(Bend)]
		[Space]
		_BendStrength("bend Strength",Range(0,1)) = 0.4
		_BladeForward("Blade Forward Amount", Float) = 0.38
		_BladeCurve("Blade Curvature Amount", Range(1, 4)) = 2
		[Header(Move)]
		[Space]
		_MoveOffsetX("MoveOffsetX",range(-10,10))=0
		_MoveOffsetY("MoveOffsetY",range(-10,10)) =0
		_PushRadius("PushRadius",range(0,2))=0.1
	}

		CGINCLUDE
#include "UnityCG.cginc"
#include "AutoLight.cginc"
#include "Lighting.cginc"
#include "Assets/Shaders/GrassTessellationWithTexture.cginc"

#pragma shader_feature _USE_GRASS_TEXTURE

			float rand(float3 co)
		{
			return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
		}

		float3x3 AngleAxis3x3(float angle, float3 axis)
		{
			float c, s;
			sincos(angle, s, c);

			float t = 1 - c;
			float x = axis.x;
			float y = axis.y;
			float z = axis.z;

			return float3x3(
				t * x * x + c, t * x * y - s * z, t * x * z + s * y,
				t * x * y + s * z, t * y * y + c, t * y * z - s * x,
				t * x * z - s * y, t * y * z + s * x, t * z * z + c
				);
		}

		struct gOut {
			float4 pos:SV_POSITION;

			float2 uv:TEXCOORD0;
#if UNITY_PASS_FORWARDBASE	
			float3 normal : NORMAL;
			unityShadowCoord4 _ShadowCoord : TEXCOORD1;
#endif
		};

		gOut vertexOutput(float3 pos, float2 uv, float3 normal) {
			gOut o;
			o.pos = UnityObjectToClipPos(pos);


			o.uv = uv;
#if UNITY_PASS_FORWARDBASE	
			o._ShadowCoord = ComputeScreenPos(o.pos);
			o.normal = UnityObjectToWorldNormal(normal);
#endif

#if UNITY_PASS_SHADOWCASTER
			o.pos = UnityApplyLinearShadowBias(o.pos);
#endif

			return o;
		}

		gOut GenerateGrassPoint(float3 pos, float width, float forward, float height, float2 uv, float3x3 transform) {
			//width height构成平面，forward构成3维的弯曲
			float3 tangentPoint = float3(width, forward, height);

			float3 tangentNormal = normalize(float3(0, -1, forward));
			float3 localNormal = mul(transform, tangentNormal);

			return vertexOutput(pos + mul(transform, tangentPoint), uv, localNormal);
		}

		float _BendStrength;
		float _BladeWidthBase, _BladeWidthRandom, _BladeHeightBase, _BladeHeightRandom;
		sampler2D _WindMap;
		float4 _WindMap_ST;
		float2 _WindSpeed;
		float _WindStrength;
		float _BladeForward, _BladeCurve;
		float _MoveOffsetX;
		float _MoveOffsetY;
		float _PushRadius;

#ifdef _USE_GRASS_TEXTURE
		sampler2D _GrassTexture;
#endif

#define BLADE_SEGMENTS 3
#ifdef _USE_GRASS_TEXTURE
		[maxvertexcount(BLADE_SEGMENTS * 2 + 2)]
#else
		[maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
#endif
		void geo(point vOut i[1], inout TriangleStream<gOut> stream) {
			//float3 playerPos = float3(_MoveOffsetX,0, _MoveOffsetY);
			//float dis = distance(playerPos, i[0].pos);
			//float pushDown = saturate((1 - dis + _PushRadius) * i[0].texcoord.y);
			//float3 direction = normalize(i[0].pos - playerPos.xyz);
			//direction.y *= 0.5;

			float3 pos = i[0].pos;
			float3 vNormal = i[0].normal;
			float4 vTangent = i[0].tangent;
			float3 vBinormal = cross(vNormal, vTangent.xyz)*vTangent.w;
			//风向选择矩阵
			float2 windUV = pos.xz*_WindMap_ST.xy + _WindMap_ST.zw + _WindSpeed * _Time.y;

			float2 windSample = (tex2Dlod(_WindMap, float4(windUV, 0, 0)).xy * 2 - 1)*_WindStrength;
			float3 windAxis = normalize(float3(windSample.x, windSample.y, 0));
			float3x3 WindRoationMatrix = AngleAxis3x3(windSample.y*UNITY_PI, windAxis);

			//随机面向矩阵
			float3x3 RandomFaceMatrix = AngleAxis3x3(rand(pos)*UNITY_TWO_PI, float3(0, 0, 1));
			//随机弯曲矩阵
			float3x3 RandomBendMatrix = AngleAxis3x3(rand(pos.xzz)*UNITY_PI*0.5*_BendStrength, float3(-1, 0, 0));
			//切线空间转对象空间矩阵
			float3x3 tangentToObject = float3x3(
				vTangent.x, vBinormal.x, vNormal.x,
				vTangent.y, vBinormal.y, vNormal.y,
				vTangent.z, vBinormal.z, vNormal.z
				);
			float3x3 transformMatrix = mul(mul(mul(tangentToObject, WindRoationMatrix), RandomFaceMatrix), RandomBendMatrix);
			float3x3 transformBottomMatrix = mul(tangentToObject, RandomFaceMatrix);//底部两点应当基于xz平面

			float height = rand(pos.xxz)*_BladeHeightRandom + _BladeHeightBase;
			float width = rand(pos.xyy)*_BladeWidthRandom + _BladeWidthBase;
			float forward = rand(pos.zxy)*_BladeForward;
			for (int i = 0; i < BLADE_SEGMENTS; i++) {
				float3x3 transform = i == 0 ? transformBottomMatrix : transformMatrix;
				float t = i / (float)BLADE_SEGMENTS;//越往上，t值越大 0->1
				float segmentHeight = height * t;
				float segmentforward = pow(t, _BladeCurve)*forward;

#ifdef _USE_GRASS_TEXTURE
				float segmentWidth = width;
#else
				float segmentWidth = width * (1.0 - t);
#endif

				stream.Append(GenerateGrassPoint(pos, segmentWidth, segmentforward, segmentHeight, float2(0, t), transform));
				stream.Append(GenerateGrassPoint(pos, -segmentWidth, segmentforward, segmentHeight, float2(1, t), transform));
			}

#ifdef _USE_GRASS_TEXTURE
			stream.Append(GenerateGrassPoint(pos, width, forward, height, float2(0, 1), transformMatrix));
			stream.Append(GenerateGrassPoint(pos, -width, forward, height, float2(1, 1), transformMatrix));
#else
			stream.Append(GenerateGrassPoint(pos, 0, forward, height, float2(0.5, 1), transformMatrix));
#endif
		}
		ENDCG

			SubShader
		{
			Pass{
			Tags{"LightMode" = "ForwardBase"}
			Cull Off
			CGPROGRAM

			#pragma target 4.6
			#pragma multi_compile_fwdbase


			#pragma vertex vert
			#pragma hull hull
			#pragma domain domain
			#pragma geometry geo
			#pragma fragment frag
			float4 _BottomCol,_TopCol;
			float _TranslucentGain;
			float4 frag(gOut i,fixed facing : VFACE) :SV_Target{


				float3 normal = facing > 0 ? i.normal : -i.normal;
				float shadow = SHADOW_ATTENUATION(i);
				float NdotL = saturate(saturate(dot(normal, _WorldSpaceLightPos0)) + _TranslucentGain) * shadow;
				float3 ambient = ShadeSH9(float4(normal, 1));
				float4 lightIntensity = NdotL * _LightColor0 + float4(ambient, 1);

				#ifdef _USE_GRASS_TEXTURE
				float4 textureGrass = tex2D(_GrassTexture,i.uv);
				clip(textureGrass.a - 0.01);
				#endif
				float4 col = lerp(_BottomCol, _TopCol * lightIntensity, i.uv.y);
				return col;
			}


			ENDCG

			}
			Pass{
			Tags{"LightMode" = "ShadowCaster"}
			CGPROGRAM
			#pragma vertex vert
			#pragma geometry geo
			#pragma fragment frag
			#pragma hull hull
			#pragma domain domain
			#pragma target 4.6
			#pragma multi_compile_shadowcaster

			float4 frag(gOut i) : SV_Target
			{
				#ifdef _USE_GRASS_TEXTURE
				float4 textureGrass = tex2D(_GrassTexture,i.uv);
				clip(textureGrass.a - 0.01);
				#endif 
				return 0;
			}
			ENDCG
			}
		}
			FallBack "Diffuse"
}
