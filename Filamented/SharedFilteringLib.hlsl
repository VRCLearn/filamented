#ifndef SERVICE_FILTERING_INCLUDED
#define SERVICE_FILTERING_INCLUDED

half4 cubic(half v)
{
    half4 n = half4(1.0, 2.0, 3.0, 4.0) - v;
    half4 s = n * n * n;
    half x = s.x;
    half y = s.y - 4.0 * s.x;
    half z = s.z - 4.0 * s.y + 6.0 * s.x;
    half w = 6.0 - x - y - z;
    return half4(x, y, z, w);
}


// Unity's SampleTexture2DBicubic doesn't exist in 2018, which is our target here.
// So this is a similar function with tweaks to have similar semantics.

half4 SampleTexture2DBicubicFilter(TEXTURE2D_PARAM(tex, smp), float2 coord, float4 texSize)
{
    coord = coord * texSize.xy - 0.5;
    half fx = frac(coord.x);
    half fy = frac(coord.y);
    coord.x -= fx;
    coord.y -= fy;

    half4 xcubic = cubic(fx);
    half4 ycubic = cubic(fy);

    float4 c = float4(coord.x - 0.5, coord.x + 1.5, coord.y - 0.5, coord.y + 1.5);
    float4 s = float4(xcubic.x + xcubic.y, xcubic.z + xcubic.w, ycubic.x + ycubic.y, ycubic.z + ycubic.w);
    float4 offset = c + float4(xcubic.y, xcubic.w, ycubic.y, ycubic.w) / s;

    half4 sample0 = SAMPLE_TEXTURE2D(tex, smp, half2(offset.x, offset.z) * texSize.zw);
    half4 sample1 = SAMPLE_TEXTURE2D(tex, smp, half2(offset.y, offset.z) * texSize.zw);
    half4 sample2 = SAMPLE_TEXTURE2D(tex, smp, half2(offset.x, offset.w) * texSize.zw);
    half4 sample3 = SAMPLE_TEXTURE2D(tex, smp, half2(offset.y, offset.w) * texSize.zw);

    half sx = s.x / (s.x + s.y);
    half sy = s.z / (s.z + s.w);

    return lerp(
        lerp(sample3, sample2, sx),
        lerp(sample1, sample0, sx), sy);
}

#endif // SERVICE_FILTERING_INCLUDED
