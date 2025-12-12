#include <metal_stdlib>
using namespace metal;

vertex float4 vertex_main(
        device const packed_float3*     position        [[buffer(0)]],
        device const float4x4&          world_from_obj  [[buffer(4)]],
        device const float4x4&          proj_from_world [[buffer(5)]],
        uint                            id              [[vertex_id]])
{
        return proj_from_world * world_from_obj * float4(position[id], 1);
}


fragment void fragment_main() {}
