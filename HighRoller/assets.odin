package HighRoller

import "core:encoding/json"
import "core:os/os2"
import "core:fmt"
import "core:math"
import "core:strings"
import ai "../include/assimp"
import glm "core:math/linalg/glsl"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "core:math/rand"
import "core:mem"
//TODO bone_name might not be allocating correctly. Will need to check on this

// a pointer to the render context is passed so we can add textures to the global register
load_model :: proc(path: string, rc: ^Render_Context
) -> ^Model
{
        c_path := strings.clone_to_cstring(path)
        defer delete(c_path)
        scene: ^ai.Scene = ai.ImportFile(c_path, {.Triangulate})
        if scene == nil || scene.mFlags == {.INCOMPLETE} || scene.mRootNode == nil {
                fmt.println(ai.GetErrorString())
                return nil
        }
        last_slash_idx := strings.last_index(path, "/")
        directory := string(path[:last_slash_idx])
        model := new(Model)
        model.meshes = make([dynamic]Mesh)
        model.directory = directory
        model.transform_buffer = rc.device->newBuffer(size_of(Vertex_Transforms), {.StorageModeManaged})
        model.transform_buffer->didModifyRange(NS.Range_Make(0, size_of(Vertex_Transforms)))
        process_ai_node(model, scene.mRootNode, scene, directory, rc)
        return model
}



load_mesh :: proc(path: string, rc:^Render_Context, idx: u32
) -> (Mesh, bool)
{
                c_path := strings.clone_to_cstring(path)
        defer delete(c_path)
        scene: ^ai.Scene = ai.ImportFile(c_path, {.Triangulate})
        if scene == nil || scene.mFlags == {.INCOMPLETE} || scene.mRootNode == nil {
                fmt.println(ai.GetErrorString())
                return Mesh{}, false
        }
        last_slash_idx := strings.last_index(path, "/")
        directory := string(path[:last_slash_idx])
        if idx > scene.mNumMeshes {
                return Mesh{}, false
        }
        ai_mesh := scene.mMeshes[idx]
        mesh := Mesh{}
        mesh.vertices = make(#soa[dynamic]Mesh_Vertex)
        for i in 0..<ai_mesh.mNumVertices {
                vertex: Mesh_Vertex
                vertex.pos = ai_mesh.mVertices[i]
                vertex.norm = ai_mesh.mNormals[i]
                if ai_mesh.mTextureCoords[0] != nil {
                        vertex.uv = ai_mesh.mTextureCoords[0][i].xy
                }
                append_soa(&mesh.vertices, vertex)
        }   
        for i in 0..<ai_mesh.mNumFaces {
                face: ai.Face = ai_mesh.mFaces[i]
                for j in 0..<face.mNumIndices {
                        append(&mesh.indices, i32(face.mIndices[j]))
                }
        }     
        mesh.buffers = build_mesh_buffers(mesh.vertices, mesh.indices, rc)
        return mesh, true
}



free_model :: proc(model: Model)
{
        unimplemented("Can't free models yet")
}



// The recursive approach is not required since we don't use a hierarchy, but at some point might.
process_ai_node :: proc(model: ^Model, node: ^ai.Node, scene: ^ai.Scene, directory: string, rc: ^Render_Context)
{
        for i in 0..<node.mNumMeshes {
                mesh: ^ai.Mesh = scene.mMeshes[node.mMeshes[i]]
                append(&model.meshes, process_ai_mesh(model, mesh, scene, directory, rc))
        }
        for i in 0..<node.mNumChildren {
                process_ai_node(model, node.mChildren[i], scene, directory, rc)
        }
}



process_ai_mesh :: proc(model: ^Model, ai_mesh: ^ai.Mesh, scene: ^ai.Scene, directory: string, rc: ^Render_Context
) -> Mesh
{
        mesh := Mesh{}
        mesh.vertices = make(#soa[dynamic]Mesh_Vertex)
        for i in 0..<ai_mesh.mNumVertices {
                vertex: Mesh_Vertex
                set_default_bone_data(&vertex)
                vertex.pos = ai_mesh.mVertices[i]
                vertex.norm = ai_mesh.mNormals[i]
                if ai_mesh.mTextureCoords[0] != nil {
                        vertex.uv = ai_mesh.mTextureCoords[0][i].xy
                }
                append_soa(&mesh.vertices, vertex)
        }
        for i in 0..<ai_mesh.mNumFaces {
                face: ai.Face = ai_mesh.mFaces[i]
                for j in 0..<face.mNumIndices {
                        append(&mesh.indices, i32(face.mIndices[j]))
                }
        }
        extract_bone_weights(model, &mesh, ai_mesh, scene)
        // Use the render context to determine backend, then load appropriate texture type
        if ai_mesh.mMaterialIndex >= 0 {
                material: ^ai.Material = scene.mMaterials[ai_mesh.mMaterialIndex]
                diffuse := load_ai_material_textures(material, ai.TextureType.DIFFUSE, .DIFFUSE, directory, rc)
                defer delete(diffuse)
                for elem in diffuse {
                        append(&mesh.textures, elem)
                }
                specular := load_ai_material_textures(material, ai.TextureType.SPECULAR, .SPECULAR, directory, rc)
                defer delete(specular)
                for elem in specular {
                        append(&mesh.textures, elem)
                }
        }
        mesh.buffers = build_mesh_buffers(mesh.vertices, mesh.indices, rc)
        return mesh;
}

set_default_bone_data :: proc(vertex: ^Mesh_Vertex)
{
        for i in 0..<MAX_BONE_INFLUENCE {
                vertex.bone_ids[i] = -1
                vertex.bone_weights[i] = 0
        }
}



// Sets the bone data for a single bone into the first available slot
set_bone_data :: proc(vertices: ^#soa[dynamic]Mesh_Vertex, vertex_id: int, bone_id: i32, weight: f32) {
        for i in 0..<MAX_BONE_INFLUENCE {
                if vertices[vertex_id].bone_ids[i] < 0 { // slot hasn't been taken yet
                        vertices[vertex_id].bone_ids[i] = bone_id
                        vertices[vertex_id].bone_weights[i] = weight
                        break;
                }
        }
}



extract_bone_weights :: proc(model: ^Model, mesh: ^Mesh, ai_mesh: ^ai.Mesh, scene: ^ai.Scene) {
        total_bone_weights: int = 0
        for i in 0..<ai_mesh.mNumBones {
                bone_id: i32 = -1
                ai_string := ai_mesh.mBones[i].mName
                bone_name: string = strings.clone_from_bytes(ai_string.data[:ai_string.length])
                if bone_name in model.bone_infos {
                        bone_id = model.bone_infos[bone_name].id
                        delete(bone_name)
                } else {
                        bone_info: Bone_Info
                        bone_info.id = model.bone_counter
                        bone_info.offset = ai_matrix_translate(ai_mesh.mBones[i].mOffsetMatrix)
                        model.bone_infos[bone_name] = bone_info
                        bone_id = model.bone_counter
                        model.bone_counter += 1
                }
                assert(bone_id != -1)
                weights := ai_mesh.mBones[i].mWeights
                num_weights := ai_mesh.mBones[i].mNumWeights
                for j in 0..<num_weights {
                        total_bone_weights += 1
                        vertex_id := int(weights[j].mVertexId)
                        weight := weights[j].mWeight
                        assert(vertex_id < len(mesh.vertices))
                        set_bone_data(&mesh.vertices, vertex_id, bone_id, weight)
                }
        }

}



ai_matrix_translate :: proc {
        ai_matrix_translate_4x4,
}



ai_matrix_translate_4x4 :: proc(ai_mat: ai.Matrix4x4
) -> matrix[4,4]f32
{
        // todo simd?
        return ai.GetMatrix(ai_mat)

}



ai_quaternion_translate :: proc(ai_quat: ai.Quaternion) -> quaternion128 {
        return quaternion(real = ai_quat.x,
                        imag = ai_quat.y,
                        jmag = ai_quat.z,
                        kmag = ai_quat.w)
}


ai_load_bone :: proc(name: string, id: i32, channel: ^ai.NodeAnim
) -> ^Bone
{
        bone := new(Bone)
        bone.name = name

        bone.key_pos = make([]Key_Position, channel.mNumPositionKeys)
        for i in 0..<channel.mNumPositionKeys {
                ai_pos := channel.mPositionKeys[i]
                bone.key_pos[i].value = ai_pos.mValue
                bone.key_pos[i].time = ai_pos.mTime
        }

        bone.key_rot = make([]Key_Rotation, channel.mNumRotationKeys)
        for i in 0..<channel.mNumRotationKeys {
                ai_rot := channel.mRotationKeys[i]
                bone.key_rot[i].value = ai_quaternion_translate(ai_rot.mValue)
                bone.key_rot[i].time = ai_rot.mTime
        }

        bone.key_scale = make([]Key_Scale, channel.mNumScalingKeys)
        for i in 0..<channel.mNumScalingKeys {
                ai_scale := channel.mScalingKeys[i]
                bone.key_scale[i].value = ai_scale.mValue
                bone.key_scale[i].time = ai_scale.mTime
        }

        return bone
}



bone_update :: proc(bone: ^Bone, time: f64)
{
        translation := bone_interpolate_position(bone, time)
        rotation := bone_interpolate_rotation(bone, time)
        scale := bone_interpolate_scale(bone, time)
        bone.local_transform = translation * rotation * scale
}



bone_get_position_index :: proc(bone: ^Bone, time: f64
) -> int {
        for i in 0..<len(bone.key_pos)-1 {
                if time < bone.key_pos[i+1].time {
                        return i
                }
        }
        return -1
}



bone_get_rotation_index :: proc(bone: ^Bone, time: f64
) -> int {
        for i in 0..<len(bone.key_rot)-1 {
                if time < bone.key_rot[i+1].time {
                        return i
                }
        }
        return -1
}



bone_get_scale_index :: proc(bone: ^Bone, time: f64
) -> int
{
        for i in 0..<len(bone.key_scale)-1 {
                if time < bone.key_scale[i+1].time {
                        return i
                }
        }
        return -1
}



bone_interpolate_position :: proc(bone: ^Bone, time: f64
) -> matrix[4,4]f32
{
        if len(bone.key_pos) == 1 {
                return glm.mat4Translate(bone.key_pos[0].value)
        }
        p0_idx := bone_get_position_index(bone, time)
        p1_idx := p0_idx + 1
        //lerp_factor := f32(glm.lerp(bone.key_pos[p0_idx].time, bone.key_pos[p1_idx].time, time))
        lerp_factor := f32((time - bone.key_pos[p0_idx].time) /
                    (bone.key_pos[p1_idx].time - bone.key_pos[p0_idx].time))
        final_pos := glm.lerp(bone.key_pos[p0_idx].value, bone.key_pos[p1_idx].value, [3]f32{lerp_factor, lerp_factor, lerp_factor})
        return glm.mat4Translate(final_pos)
}



bone_interpolate_rotation :: proc(bone: ^Bone, time: f64
) -> matrix[4,4]f32
{
        if len(bone.key_rot) == 1 {
                rotation := glm.normalize(bone.key_rot[0].value)
                return glm.mat4FromQuat(rotation)
        }
        p0_idx := bone_get_rotation_index(bone, time)
        // failsafe for invalid times
        p1_idx := p0_idx + 1
        //slerp_factor := f32(glm.lerp(bone.key_pos[p0_idx].time, bone.key_pos[p1_idx].time, time))
        slerp_factor := f32((time - bone.key_rot[p0_idx].time) /
                    (bone.key_rot[p1_idx].time - bone.key_rot[p0_idx].time))
        quat := glm.slerp(bone.key_rot[p0_idx].value, bone.key_rot[p1_idx].value, slerp_factor)
        final_quat := glm.normalize(quat)
        return glm.mat4FromQuat(final_quat)
}



bone_interpolate_scale :: proc(bone: ^Bone, time: f64
) -> matrix[4,4]f32
{
        if len(bone.key_scale) == 1 {
                return glm.mat4Scale(bone.key_scale[0].value)
        }
        p0_idx := bone_get_scale_index(bone, time)
        p1_idx := p0_idx + 1
        lerp_factor := f32((time - bone.key_scale[p0_idx].time) /
                    (bone.key_scale[p1_idx].time - bone.key_scale[p0_idx].time))
        final_scale := glm.lerp(bone.key_scale[p0_idx].value, bone.key_scale[p1_idx].value, [3]f32{lerp_factor, lerp_factor, lerp_factor})
        return glm.mat4Scale(final_scale)
}



load_animation :: proc(path: string, model: ^Model
) -> []Animation
{
        c_path := strings.clone_to_cstring(path)
        defer delete(c_path)
        scene := ai.ImportFile(c_path, {.Triangulate})
        animations := make([]Animation, scene.mNumAnimations)
        for i in 0..<scene.mNumAnimations {
                ai_animation := scene.mAnimations[i]
                animations[i].duration = ai_animation.mDuration
                animations[i].tick_rate = ai_animation.mTicksPerSecond
                animations[i].root_node = animation_read_heirarchy_data(scene.mRootNode)
                animations[i].bones = make([dynamic]^Bone)
                animation_fetch_missing_bones(&animations[i], ai_animation, model)
        }
        return animations
}



// Apparently this proc is needed for cases where the animation file has bones that the FBX file doesn't
animation_fetch_missing_bones :: proc(animation: ^Animation, ai_animation: ^ai.Animation, model: ^Model)
{
        for i in 0..<ai_animation.mNumChannels {
                channel := ai_animation.mChannels[i]
                bone_name := strings.clone_from_bytes(channel.mNodeName.data[:channel.mNodeName.length])
                if bone_name not_in model.bone_infos {
                        model.bone_infos[bone_name] = Bone_Info{id=model.bone_counter}
                        model.bone_counter += 1
                }
                append(&animation.bones, ai_load_bone(bone_name, model.bone_infos[bone_name].id, channel))
        }
        animation.bone_infos = model.bone_infos
}



animation_read_heirarchy_data :: proc(src: ^ai.Node
) -> ^AI_Node_Data
{
        dest := new(AI_Node_Data)
        dest.name = strings.clone(string(src.mName.data[:src.mName.length]))
        dest.transformation = ai_matrix_translate(src.mTransformation)
        dest.child_count= int(src.mNumChildren)
        dest.children = make([]^AI_Node_Data, src.mNumChildren)
        for i in 0..<src.mNumChildren {
                dest.children[i] = animation_read_heirarchy_data(src.mChildren[i])
        }
        return dest
}



animation_find_bone :: proc(animation: ^Animation, name: string
) -> ^Bone
{
        for bone in animation.bones {
                if bone.name == name {
                        return bone
                }
        }
        return nil
}



create_animator :: proc(animation: ^Animation
) -> ^Animator
{
        animator := new(Animator)
        animator.time = 0.0
        animator.current_animation = animation
        MAX_BONES :: 100
        animator.bone_matrices = make([]matrix[4,4]f32, MAX_BONES)
        animator.blend_matrices = make([]matrix[4,4]f32, MAX_BONES)
        for i in 0..<MAX_BONES {
                animator.bone_matrices[i] = 1
        }
        return animator
}



update_animation :: proc(animator: ^Animator, dt: f64)
{
        animator.dt = dt
        if animator.current_animation != nil {
                animator.time += dt * animator.current_animation.tick_rate
                animator.time = math.mod_f64(animator.time, animator.current_animation.duration)
                calculate_bone_transform(animator, animator.current_animation.root_node, 1)
        }
        if animator.blending {
                if animator.time < animator.blend_duration {
                        frac := f32(animator.time / animator.blend_duration)
                        for i in 0..<len(animator.bone_matrices) {
                                animator.bone_matrices[i] = frac * animator.bone_matrices[i] + (1.0-frac) * animator.blend_matrices[i]
                        }
                } else {
                        animator.blending = false
                }
        }
}



play_animation :: proc(animator: ^Animator, animation: ^Animation) {
        animator.current_animation = animation
        animator.time = 0
}



calculate_bone_transform :: proc(animator: ^Animator, node: ^AI_Node_Data, parent_transform: matrix[4,4]f32) {
        bone: ^Bone = animation_find_bone(animator.current_animation, node.name)
        if bone != nil {
                bone_update(bone, animator.time)
                node.transformation = bone.local_transform
        }
        global_transform := parent_transform * node.transformation
        bone_infos := animator.current_animation.bone_infos
        if node.name in bone_infos {
                idx := bone_infos[node.name].id
                offset := bone_infos[node.name].offset
                animator.bone_matrices[idx] = global_transform * offset
        }

        // recurse down the heirarchy
        for child in node.children {
                calculate_bone_transform(animator, child, global_transform)
        }
}



switch_animation :: proc(animator: ^Animator, animation: ^Animation) {
        if animator.current_animation == animation {
                return
        }
        animator.current_animation = animation
        animator.blending = true
        animator.time = 0
        animator.blend_duration = 2
        // Switch the beld and bone matrices to interpolate between
        hold := animator.blend_matrices
        animator.blend_matrices = animator.bone_matrices
        animator.bone_matrices = hold
}



load_ai_material_textures :: proc(material: ^ai.Material, type: ai.TextureType, type_enum: Texture_Type, directory: string, rc: ^Render_Context
) -> [dynamic]^Texture
{
        textures := make([dynamic]^Texture)
        for i in 0..<ai.GetMaterialTextureCount(material^, type) {
                path: ai.String
                ai.GetMaterialTexture(material, type, i, &path, nil, nil, nil, nil, nil)
                location := strings.concatenate({directory, "/", string(path.data[:path.length])})
                if location in rc.textures {
                        texture := rc.textures[location]
                        append(&textures, texture)
                        defer delete(location)
                } else {
                       texture := new(Texture)
                       texture.value = load_texture(rc.device, location)
                       texture.type = type_enum
                       append(&textures, texture)
                       rc.textures[location] = texture
                }
        }
        return textures
}



load_plane :: proc(textures: []^Texture, pos: [3]f32, rot: quaternion128, scale: f32, rc: ^Render_Context, double_sided := true
) -> Object
{
        plane := Object{}
        plane.mesh.vertices = make(#soa[dynamic]Mesh_Vertex)
        append_soa(&plane.mesh.vertices,
        Mesh_Vertex{
                pos = {-1, 0, -1}, // top left
                norm = {0, 1, 0},
                uv = {0, 0}
        },Mesh_Vertex{
                pos = {1, 0, -1}, // top right
                norm = {0, 1, 0},
                uv = {1, 0}
        },Mesh_Vertex{
                pos = {-1, 0, 1}, // bottom left
                norm = {0, 1, 0},
                uv = {0, 1}
        },Mesh_Vertex{
                pos = {1, 0, 1}, //bottom right
                norm = {0, 1, 0},
                uv = {1, 1}

        },Mesh_Vertex{
                pos = {-1, 0, -1}, // top left
                norm = {0, -1, 0},
                uv = {0, 0}
        },Mesh_Vertex{
                pos = {1, 0, -1}, // top right
                norm = {0, -1, 0},
                uv = {1, 0}
        },Mesh_Vertex{
                pos = {-1, 0, 1}, // bottom left
                norm = {0, -1, 0},
                uv = {0, 1}
        },Mesh_Vertex{
                pos = {1, 0, 1}, //bottom right
                norm = {0, -1, 0},
                uv = {1, 1}
        })
        plane.mesh.indices = make([dynamic]i32)
        append(&plane.mesh.indices, 0, 2, 1, 3, 1, 2, 6, 5, 7, 5, 6, 4)
        plane.mesh.textures = make([dynamic]^Texture)
        for texture in textures {
                append(&plane.mesh.textures, texture)
        }
        plane.pos = pos
        plane.rot = rot
        plane.scale = scale
        plane.transform = glm.mat4Translate(pos) * glm.mat4FromQuat(rot) * glm.mat4Scale(scale)
        plane.mesh.buffers = build_mesh_buffers(plane.mesh.vertices, plane.mesh.indices, rc)
        plane.color_id = Color_ID{u8(rand.int_max(255)), u8(rand.int_max(255)), u8(rand.int_max(255))}
        plane.type = .Mesh
        return plane
}


free_object :: proc(object: ^Object, allo := context.allocator)
{
        free(object.collider, allo)
        delete(object.mesh.indices) // No allocator passed since the array contains it's own reference. Good to know.
        delete(object.mesh.textures) // The textures are owned by the render context, so don't need to free individually
        delete(object.mesh.vertices)
        free(object.mesh.buffers, allo)
        free(object, allo)
}
