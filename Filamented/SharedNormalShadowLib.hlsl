#ifndef SERVICE_NORMALSHADOW_INCLUDED
#define SERVICE_NORMALSHADOW_INCLUDED

// Ref: Normal Mapping Shadows by Boris Vorontsov

// Please define a NormalMapShadowsParam parameter
// and SampleNormalMap function to sample the normal map.

half NormalMapShadows (half3 lightDirTangent, NormalMapShadowsParam nmsParam, half noise,
	half heightScale, half shadowHardness)
{
	const half screenShadowSamples = 20;
	const half hardness = heightScale * shadowHardness;
	const half sampleStep = 1.0 / screenShadowSamples;

	half2 dir = lightDirTangent.xy * heightScale;

	// Redundancy can't be helped
	half3 normal = SampleNormalMap(nmsParam, 0);

	lightDirTangent = normalize(lightDirTangent);
    half tangentNdotL = saturate(dot(lightDirTangent, normal));

    half currentSample = sampleStep - sampleStep * noise;

    // Skip on backfaces
	currentSample += (tangentNdotL <= 0.0);

	/*
	From the PDF:
	Trace from hit point to light direction and compute sum of dot products
	between normal map and light direction.
	If slope is bigger than 0, pixel is shadowed. If slope is also bigger
	than previous maximal value, increase hardness of shadow.
	*/

	half result = 0;
	half slope = -tangentNdotL;
	half maxslope = 0.0;
	while (currentSample <= 1.0)
	{
		normal = SampleNormalMap(nmsParam, dir * currentSample);
		tangentNdotL = dot(lightDirTangent, normal);
		slope = slope - tangentNdotL;
		if (slope > maxslope)
		{
			result += hardness * (1.0-currentSample);
		}
		maxslope = max(maxslope, slope);
		currentSample += sampleStep;
	}

	return result * sampleStep;
}

#endif // SERVICE_NORMALSHADOW_INCLUDED
