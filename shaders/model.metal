#include <metal_stdlib>
using namespace metal;

struct v2f {
        float4 position [[position]];
        float3 frag_pos;
        half3 color;
        float4 normal;
        float2 texcoord;
};

struct Camera_Data {
        float4x4 world_transform;
        float4x4 view_transform;
        float4x4 perspective_transform;
        float4x4 normal_transform;
        float3 pos;
};

struct Render_Arguments {
        int selected;
};

struct Light_Data {
        constant packed_float3* pos;
        constant packed_float3* col;
        int n_lights;
};

struct Vertex_Transforms {
        float4x4 transform;
        float4x4 normal_transform;
};

v2f vertex vertex_main(
        device const packed_float3*     pos_data        [[buffer(0)]],
        device const packed_float2*     uv_data         [[buffer(1)]],
        device const packed_float3*     normal_data     [[buffer(2)]],
        device const int4*              bone_id         [[buffer(3)]],
        device const packed_float4*     bone_weight     [[buffer(4)]],
        device const float4x4*          bone_transforms [[buffer(5)]],
        device const Camera_Data&       camera_data     [[buffer(6)]],
        device const Vertex_Transforms& transforms      [[buffer(7)]],
        uint vertex_id                                  [[vertex_id]])
{
        v2f o;
        float4 pos = float4(pos_data[vertex_id], 1);
        float4 norm = float4(normal_data[vertex_id], 0);
        float4 total_position = float4(0, 0, 0, 0);
        float4 total_normal = float4(0, 0, 0, 0);
        int4 bone_ids = bone_id[vertex_id];
        float4 bone_weights = bone_weight[vertex_id];
        if (all(bone_ids == int4(-1))) {
                total_position = pos;
                total_normal = norm;
        } else {
                for (int i = 0; i < 4; i++) {
                        if (bone_ids[i] == -1) {
                                continue;
                        }
                        if (bone_ids[i] >= 100) {
                                break;
                        }
                        total_position += bone_transforms[bone_ids[i]] * pos * bone_weights[i];
                        // this should work since it's just a rotation translation and scale
                        total_normal += bone_transforms[bone_ids[i]] * norm * bone_weights[i];
                }
        }
        o.position = camera_data.perspective_transform * camera_data.view_transform * transforms.transform * total_position;
        o.frag_pos = (transforms.transform * total_position).xyz;
        o.normal = normalize(transforms.normal_transform * float4(total_normal.xyz, 0));
        o.color = half3(1,1,1);
        o.texcoord = float2(uv_data[vertex_id].xy);
        return o;
}

float4 fragment fragment_main(
        v2f                             in              [[stage_in]],
        texture2d<float>                tex             [[texture(0)]],
        texture2d<float>                spec_tex        [[texture(1)]],
        device const Camera_Data&       camera_data     [[buffer(0)]],
        device const Light_Data&        light_data      [[buffer(1)]],
        device const Render_Arguments&  arguments       [[buffer(8)]])
{
        constexpr sampler s(address::repeat, filter::linear);
        float3 object_color = float3(tex.sample(s, in.texcoord).rgb);
        float3 spec_color = float3(spec_tex.sample(s, in.texcoord).rgb);

        // // Ambient
        float ambient_strength = 0.2f;
        float3 total_light = ambient_strength * object_color;
        for (int i = 0; i < light_data.n_lights; i++) {
                float3 light_color = light_data.col[i];
                //total_light = light_color;
                //Light_Data light = Light_Data{{0, 10, 0}, {1, 1, 1}};
                float3 light_dir = normalize(light_data.pos[i] - in.frag_pos);
                float3 camera_dir = normalize(camera_data.pos - in.frag_pos);

                // // Diffuse
                float diff = max(dot(normalize(in.normal.xyz), light_dir), 0.0);
                float3 diffuse = diff * light_color * object_color.xyz;

                // // specular
                float3 half_vec = normalize(camera_dir + light_dir);
                float spec_strength = 1.5h;
                float shininess = 32.0h;
                float spec = max(dot(in.normal.xyz, half_vec), 0.0);
                spec = pow(spec, shininess);
                float3 specular = spec_strength * spec * light_color * spec_color;
                total_light = total_light + diffuse + specular;
        }
        if (arguments.selected > 0) {
                total_light = total_light + float3(-0.3, 0.5, -0.3);
        }
        return float4(total_light, 1);
}
