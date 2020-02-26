#ifndef GRASS_TESSELLATION_TEXTURE_INCLUDE
#define GRASS_TESSELLATION_TEXTURE_INCLUDE


struct vIn {
	float4 vertex:POSITION;
	float3 normal:NORMAL;
	float4 tangent:TANGENT;
	float2 texcoord:TEXCOORD0;
};

struct vOut {
	float4 pos:SV_POSITION;
	float3 normal:NORMAL;
	float4 tangent:TANGENT;
};

struct TessellationFactors
{
	float edge[3]:SV_TessFactor;
	float inside : SV_InsideTessFactor;
};



//--------------------vertex------------------------
vIn vert(vIn v) {
	return v;
}
//---------------------hull-----------------------

float _TessellationUniform, _TextureStrength;
sampler2D _DensityTexture;
float4 _DensityTexture_ST;
TessellationFactors patchConstantFunction(InputPatch<vIn, 3>patch) {

	float2 uv = (patch[0].texcoord + patch[1].texcoord + patch[2].texcoord)*0.333;
	uv = uv*_DensityTexture_ST.xy + _DensityTexture_ST.zw;
	float addDensity = tex2Dlod(_DensityTexture, float4(uv, 0, 0)).a;
	addDensity *= _TextureStrength;

	TessellationFactors f;
	f.edge[0] = _TessellationUniform + addDensity;
	f.edge[1] = _TessellationUniform + addDensity;
	f.edge[2] = _TessellationUniform + addDensity;
	f.inside = _TessellationUniform + addDensity;
	return f;
}

[UNITY_domain("tri")]
[UNITY_outputcontrolpoints(3)]
[UNITY_outputtopology("triangle_cw")]
[UNITY_partitioning("integer")]
[UNITY_patchconstantfunc("patchConstantFunction")]
vIn hull(InputPatch<vIn, 3> patch, uint id:SV_OutputControlPointID)
{
	return patch[id];
}

//GPU进行曲面细分操作 in->out

//-----------------------domain-------------------

vOut tessVert(vIn v) {
	vOut o;
	o.pos = v.vertex;
	o.normal = v.normal;
	o.tangent = v.tangent;
	return o;
}

#define MY_DOMAIN_PROGRAM_INTERPOLATE(fieldName) v.fieldName = \
patch[0].fieldName * barycentricCoordinates.x + \
patch[1].fieldName * barycentricCoordinates.y + \
patch[2].fieldName * barycentricCoordinates.z;

[UNITY_domain("tri")]
vOut domain(TessellationFactors factors, OutputPatch<vIn, 3> patch, float3 barycentricCoordinates : SV_DomainLocation) {

	vIn v;
	MY_DOMAIN_PROGRAM_INTERPOLATE(vertex)
		MY_DOMAIN_PROGRAM_INTERPOLATE(normal)
		MY_DOMAIN_PROGRAM_INTERPOLATE(tangent)
		return tessVert(v);
}

#endif
