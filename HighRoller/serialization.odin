package HighRoller

import "core:encoding/json"
import "core:fmt"
import "core:bytes"
import "core:strconv"
import "core:strings"
import hm "handle_map"
serialize_scene :: proc(scene:  ^Scene
) -> json.Object
{
        cam_obj := serialize_camera(scene.camera^)
        player := serialize_player(hm.get(scene.entities, scene.player))
        return cam_obj
}

serialize_player :: proc(player: Entity
) -> json.Object
{
        out := make(json.Object)
        return out
}

serialize_camera :: proc(camera: Camera
) -> json.Object
{
        out := make(json.Object)
        out["world_transform"] = serialize_matrix(camera.world_transform)
        out["view_transform"] = serialize_matrix(camera.view_transform)
        out["perspective_transform"] = serialize_matrix(camera.perspective_transform)
        out["normal_transform"] = serialize_matrix(camera.normal_transform)
        out["pos"] = serialize_3f32(camera.pos)
        out["front"] = serialize_3f32(camera.front)
        out["right"] = serialize_3f32(camera.right)
        out["up"] = serialize_3f32(camera.up)
        out["yaw"] = serialize_f32(camera.yaw)
        out["pitch"] = serialize_f32(camera.yaw)
        out["free"] = camera.free ? 1 : 0
        return out
}

serialize_matrix :: proc {
        serialize_matrix_4x4_f32,
}

serialize_f32 :: proc(val: f32
) -> string 
{
        bldr := strings.Builder{}
        strings.write_f32(&bldr, val, 'f', true)
        return strings.to_string(bldr)
}

serialize_3f32 :: proc(vec: [3]f32
) -> json.Array
{
        vals := make(json.Array)
        append(&vals, serialize_f32(vec.x))
        append(&vals, serialize_f32(vec.y))
        append(&vals, serialize_f32(vec.z))
        return vals

}

serialize_matrix_4x4_f32 :: proc(mat: matrix[4, 4]f32
) -> json.Array
{
        vals := make(json.Array)
        for i in 0..<4 {
                for j in 0..<4 {
                        buf: [8]u8
                        append(&vals, serialize_f32(mat[i][j]))
                }
        }
        return vals
} 