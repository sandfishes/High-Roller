#include <metal_stdlib>
using namespace metal;

struct v2f {
        float4 position [[position]];
        float3 frag_pos;
        half3 color;
        float4 normal;
        float2 texcoord;
        float ambient;
};

struct Camera_Data {
        float4x4 world_transform;
        float4x4 view_transform;
        float4x4 perspective_transform;
        float4x4 normal_transform;
        float3 pos;
};

struct Vertex_Data {
        packed_float3 position;
        packed_float3 normal;
};

struct Render_Arguments {
        int selected;
};

struct Vertex_Transforms {
        float4x4 transform;
        float4x4 normal_transform;
};

struct Light_Data {
        constant packed_float3* pos;
        constant packed_float3* col;
        int n_lights;
};

v2f vertex vertex_main(
        device const packed_float3*     pos_data        [[buffer(0)]],
        device const packed_float2*     uv_data         [[buffer(1)]],
        device const packed_float3*     normal_data     [[buffer(2)]],
        device const Camera_Data&       camera_data     [[buffer(6)]],
        device const Vertex_Transforms& world_from_obj  [[buffer(7)]],
        uint vertex_id                                  [[vertex_id]])
{
        v2f o;
        o.position = camera_data.perspective_transform * camera_data.view_transform * world_from_obj.transform * float4(pos_data[vertex_id], 1);
        o.frag_pos = (world_from_obj.transform * float4(pos_data[vertex_id], 1)).xyz;
        o.normal = normalize(world_from_obj.normal_transform * float4(normal_data[vertex_id].xyz, 0));
        o.color = half3(1,1,1);
        o.texcoord = float2(uv_data[vertex_id].xy);
        return o;
}



float4 fragment fragment_main(
        v2f                             in              [[stage_in]],
        texture2d<float>                tex             [[texture(0)]],
        texture2d<float>                spec_tex        [[texture(1)]],
        texture2d<float>                shadow          [[texture(2)]],
        device const float4x4&          shadow_map      [[buffer(3)]],
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
        // TODO have multiple lights each with their own shadow map. (lights are expensive as shit apparently)
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
        float4 light_space_pos = shadow_map * float4(in.frag_pos, 1);
        light_space_pos.xyz /= light_space_pos.w;
        float2 light_space_coord = light_space_pos.xy * 0.5 + 0.5;
        light_space_coord.y = 1.0 - light_space_coord.y;
        light_space_coord = saturate(light_space_coord);
        float light_depth = shadow.sample(s, light_space_coord).x;
        float visibility = 1.0;
        if (light_space_pos.z > light_depth) {
                visibility = 0.5;
        }
        if (arguments.selected > 0) {
                total_light = total_light + float3(-0.3, 0.5, -0.3);
        }
        return float4(total_light*visibility, 1);
}
