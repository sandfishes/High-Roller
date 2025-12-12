#include <metal_stdlib>
using namespace metal;

struct Camera_Data {
        float4x4 world_transform;
        float4x4 view_transform;
        float4x4 perspective_transform;
        float4x4 normal_transform;
        float3 pos;
};

vertex float4 vertex_main(
        device const packed_float3*     position        [[buffer(0)]],
        device const float4x4&          world_from_obj  [[buffer(4)]],
        device const Camera_Data&       camera_data     [[buffer(1)]],
        uint                            id              [[vertex_id]])
{
        return camera_data.perspective_transform * camera_data.view_transform * world_from_obj * float4(position[id], 1);
}


fragment float4 fragment_main(device const packed_float3& color_id [[buffer(0)]])
{
        return float4(color_id, 1);
}
