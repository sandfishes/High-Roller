#include <metal_stdlib>
using namespace metal;

struct Transform_Data {
        float4x4 proj_from_world;
        float4x4 world_from_obj;
};

vertex float4 vertex_main(
        device const packed_float3*     position        [[buffer(0)]],
        device const int4*              bone_id         [[buffer(1)]],
        device const packed_float4*     bone_weight     [[buffer(2)]],
        device const float4x4*          bone_transforms [[buffer(3)]],
        device const float4x4&          world_from_obj  [[buffer(4)]],
        device const float4x4&          proj_from_world [[buffer(5)]],
        uint                            id              [[vertex_id]])
{
        float4 pos = float4(position[id], 1);
        float4 total_position = float4(0, 0, 0, 0);
        int4 bone_ids = bone_id[id];
        float4 bone_weights = bone_weight[id];
        if (all(bone_ids == int4(-1))) {
                total_position = pos;
        } else {
                for (int i = 0; i < 4; i++) {
                        if (bone_ids[i] == -1) {
                                continue;
                        }
                        if (bone_ids[i] >= 100) {
                                break;
                        }
                        total_position += bone_transforms[bone_ids[i]] * pos * bone_weights[i];
                }
        }
        return proj_from_world * world_from_obj * total_position;
}

fragment void fragment_main() {}
