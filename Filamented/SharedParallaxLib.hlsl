#ifndef SERVICE_PARALLAX_INCLUDED
#define SERVICE_PARALLAX_INCLUDED

// Please define a PerPixelHeightDisplacementParam parameter
// and ComputePerPixelHeightDisplacement function to sample the heightmap.

float2 ParallaxRaymarching(float2 viewDir, PerPixelHeightDisplacementParam ppdParam,
    float strength, out float outHeight)
{
    const float raymarch_steps = 10;

    float2 uvOffset = 0;
    const float stepSize = 1.0 / raymarch_steps;
    float2 uvDelta = viewDir * (stepSize * strength);

    float stepHeight = 1;
    float surfaceHeight = ComputePerPixelHeightDisplacement(0, 0, ppdParam);

    float2 prevUVOffset = uvOffset;
    float prevStepHeight = stepHeight;
    float prevSurfaceHeight = surfaceHeight;

    for (int i = 1; i < raymarch_steps && stepHeight > surfaceHeight; i++)
    {
        prevUVOffset = uvOffset;
        prevStepHeight = stepHeight;
        prevSurfaceHeight = surfaceHeight;

        uvOffset -= uvDelta;
        stepHeight -= stepSize;
        surfaceHeight = ComputePerPixelHeightDisplacement(uvOffset, 0, ppdParam);
    }

    float prevDifference = prevStepHeight - prevSurfaceHeight;
    float difference = surfaceHeight - stepHeight;
    float t = prevDifference / (prevDifference + difference);
    uvOffset = prevUVOffset -uvDelta * t;

    outHeight = surfaceHeight;
    return uvOffset;
}

float2 ParallaxRaymarchingDynamic(float3 viewDir, PerPixelHeightDisplacementParam ppdParam,
    float strength, float lod)
{
    const float minLayers = 8.0;
    const float maxLayers = 48.0;
    // lod should be dot(normalWS, viewDirWS)
    float numLayers = lerp(maxLayers, minLayers, clamp(lod, 0, 1));

    if (viewDir.z < 0.001) return 0;

    float heightScale = _Parallax; // 0.05
    float layerDepth = 1.0 / numLayers;
    float currLayerDepth = 0.0;
    float2 deltaUV = viewDir.xy * heightScale / (viewDir.z * numLayers);
    float2 uvOffset = 0;
    float height = 1.0 - ComputePerPixelHeightDisplacement(0, 0, ppdParam);

    for (int i = 0; i < numLayers; i++) {
        currLayerDepth += layerDepth;
        uvOffset -= deltaUV;
        height = 1.0 - ComputePerPixelHeightDisplacement(uvOffset, 0, ppdParam);
        if (height < currLayerDepth) {
            break;
        }
    }
    float2 prevOffset = uvOffset + deltaUV;
    float nextDepth = height - currLayerDepth;
    float prevDepth = 1.0 - ComputePerPixelHeightDisplacement(prevOffset, 0, ppdParam) -
            currLayerDepth + layerDepth;
    float2 parallaxUVs = lerp(uvOffset, prevOffset, nextDepth / (nextDepth - prevDepth));
    return parallaxUVs;
}


float2 ParallaxRaymarchingDynamicOffset(float3 viewDir, PerPixelHeightDisplacementParam ppdParam,
    float strength, float lod)
{
    const float minLayers = 8.0;
    const float maxLayers = 48.0;
    float numLayers = lerp(maxLayers, minLayers, clamp(lod, 0, 1));

    if (viewDir.z < 0.001) return 0;

    float heightScale = _Parallax;
    float refPlane = 0.5;

    float layerDepth = 1.0 / numLayers;
    float currLayerDepth = 0.0;

    float2 totalDelta = viewDir.xy * heightScale / viewDir.z;
    float2 deltaUV = totalDelta / numLayers;

    // Shift the starting UVs forward so that the ray starts above the surface
    float2 uvOffset = totalDelta * refPlane;

    float height = 1.0 - ComputePerPixelHeightDisplacement(uvOffset, 0, ppdParam);

    for (int i = 0; i < numLayers; i++) {
        if (height < currLayerDepth) break;

        currLayerDepth += layerDepth;
        uvOffset -= deltaUV;
        height = 1.0 - ComputePerPixelHeightDisplacement(uvOffset, 0, ppdParam);
    }

    float2 prevOffset = uvOffset + deltaUV;
    float nextDepth = height - currLayerDepth;
    float prevDepth = (1.0 - ComputePerPixelHeightDisplacement(prevOffset, 0, ppdParam)) -
                      (currLayerDepth - layerDepth);

    float weight = nextDepth / (nextDepth - prevDepth);
    float2 parallaxUVs = lerp(uvOffset, prevOffset, weight);

    return parallaxUVs;
}

float GetParallaxSelfShadow(float3 lightDir, float2 uv, PerPixelHeightDisplacementParam ppdParam, float noise)
{
    // lightDir.z is the cosine of the angle between the light and the tangent surface.
    // If it's 0, we are at the horizon.
    if (lightDir.z <= 0.0) return 0.0;

    const int numSamples = 8;

    float initialHeight = ComputePerPixelHeightDisplacement(0, 0, ppdParam);

    // Scale the penumbra by the surface depth.
    float shadowHardness = 1.0 / (_Parallax * 2.0);

    float heightToTravel = 1.0 - initialHeight;
    float2 uvStep = (lightDir.xy * _Parallax) / (lightDir.z * numSamples);
    float stepHeight = heightToTravel / numSamples;

    float2 currentOffset = uvStep * noise;
    float currentRayHeight = initialHeight + (stepHeight * noise);

    float shadowFactor = 1.0;

    [unroll(numSamples)]
    for(int i = 0; i < numSamples; i++)
    {
        float mipLOD = (float(i) / float(numSamples)) * 7.0;
        float sampledHeight = ComputePerPixelHeightDisplacement(currentOffset, mipLOD, ppdParam);

        if (sampledHeight > currentRayHeight)
        {
            float distanceAlongRay = (float)i / (float)numSamples;
            float penetration = (sampledHeight - currentRayHeight) * (1.0 - distanceAlongRay);

            shadowFactor = min(shadowFactor, saturate(1.0 - penetration * shadowHardness * 8.0));
        }

        if (shadowFactor <= 0.0) break;

        currentOffset += uvStep;
        currentRayHeight += stepHeight;
    }

    return shadowFactor;
}

#endif // SERVICE_PARALLAX_INCLUDED
