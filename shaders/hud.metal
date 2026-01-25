#include <metal_stdlib>
using namespace metal;

struct v2f {
        float4 position [[position]];
        float4 color; 
};

v2f vertex vertex_main(
        device const packed_float3*     pos_data        [[buffer(0)]],
        uint vertex_id                                  [[vertex_id]])
{
        v2f o;
        o.position = float4(pos_data[vertex_id], 1);
        o.color = float4(1, 1, 1, 1);
        return o;
}

float4 fragment fragment_main(v2f in [[stage_in]])
{
    return float4(1, 1, 1, 1);
}
