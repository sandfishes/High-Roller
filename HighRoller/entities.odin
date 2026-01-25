package HighRoller

import "core:math/rand"
import glm "core:math/linalg/glsl"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import hm "handle_map"

GRAVITY :: [3]f32{0, -15, 0}
JUMP_VELOCITY :: [3]f32{0, 10, 0}
SPEED :: 8
FRICTION :: 8

create_enemy:: proc(
	model_path: string,
	animation_path: string,
        pos: [3]f32,
	rc: ^Render_Context,
) ->  Entity
{
	model := load_model(model_path, rc)
	anims := load_animation(animation_path, model)
	animator := create_animator(&anims[0])
	enemy := Entity{}
        enemy.type = .Enemy
        enemy.model = model
        enemy.animator = animator
        enemy.animations = anims
        enemy.transform  = 1
	enemy.pos = pos
	enemy.scale = 0.01
	enemy.speed = 10
	enemy.rot = 1
        enemy.model.color_id = Color_ID{u8(rand.int_max(255)), u8(rand.int_max(255)), u8(rand.int_max(255))}
        
        mesh, ok := load_mesh("../resources/meshes/icosphere.obj", rc, 0)
        if !ok {
                return enemy
        }
        rc.textures["debug_red"] = new(Texture)
        rc.textures["debug_red"].value = load_texture(rc.device, "../resources/textures/DEBUG/debug_red.png")
        rc.textures["debug_red"].type = .DIFFUSE
        mesh.textures = make([dynamic]^Texture)
        append(&mesh.textures, rc.textures["debug_red"])
        enemy.collider = Sphere_Collider{1, mesh}
	return enemy
}

update_enemy :: proc(enemy: ^Entity, scene: ^Scene, dt: f64, rc: ^Render_Context) {
        SPEED :: 2
        FRICTION :: 2
        player := hm.get_pointer(&scene.entities, scene.player)
        enemy.velocity = player_drag_velocity(enemy.velocity, FRICTION)
        dt := min(dt, 0.01667) // limit physics so that step size can't be greater than 0.01667
        animation_state := Player_State.STANDING // TODO figure out why this is failing
        direction := glm.normalize(player.pos - enemy.pos)
        enemy.rot = glm.quatFromMat4(glm.mat4LookAt({0,0,0}, {direction.x, 0, -direction.z}, {0, 1, 0}))
        enemy.velocity += direction * SPEED
        if enemy.on_ground {
                animation_state = .WALKING        
        }
        if enemy.state != animation_state {
                enemy.state = animation_state
                switch_animation(enemy.animator, &enemy.animations[animation_state])
        }
        enemy.transform =
		glm.mat4Translate(enemy.pos) *
		glm.mat4Scale({enemy.scale, enemy.scale, enemy.scale}) *
		glm.mat4FromQuat(enemy.rot)
	update_animation(enemy.animator, dt)
        transform_data := enemy.model.transform_buffer->contentsAsType(Vertex_Transforms)
        transform_data.transform = enemy.transform
        transform_data.normal_transform = glm.transpose(glm.inverse_matrix4x4(enemy.transform))
        enemy.model.transform_buffer->didModifyRange(NS.Range_Make(0, size_of(Vertex_Transforms)))        
        if enemy.model.bone_buffer != nil {
                enemy.model.bone_buffer->release()
        }
        enemy.velocity += GRAVITY * f32(dt)
        enemy.pos += enemy.velocity * f32(dt)
        enemy.model.bone_buffer = build_bone_buffer(rc.device, enemy.animator.bone_matrices)
}



///////////////////////////////////////////////////
/////////////////// PLAYER ////////////////////////
///////////////////////////////////////////////////
create_player :: proc(
	model_path: string,
	animation_path: string,
	rc: ^Render_Context,
) -> Entity 
{
	model := load_model(model_path, rc)
	anims := load_animation(animation_path, model)
	animator := create_animator(&anims[0])
	player := Entity {
		model      = model,
		animator   = animator,
		animations = anims,
		transform  = 1,
                type       = .Player
	}
	player.pos = {0, 1, 0}
	player.scale = 0.01
	player.speed = 10
	player.rot = 1
        player.model.color_id = Color_ID{u8(rand.int_max(255)), u8(rand.int_max(255)), u8(rand.int_max(255))}
        
        mesh, ok := load_mesh("../resources/meshes/icosphere.obj", rc, 0)
        if !ok {
                return player
        }
        rc.textures["debug_red"] = new(Texture)
        rc.textures["debug_red"].value = load_texture(rc.device, "../resources/textures/DEBUG/debug_red.png")
        rc.textures["debug_red"].type = .DIFFUSE
        mesh.textures = make([dynamic]^Texture)
        append(&mesh.textures, rc.textures["debug_red"])
        player.collider = Sphere_Collider{1, mesh}
	return player
}



update_player :: proc(player: ^Entity, camera: ^Camera, key_state: ^Key_State, dt: f64, rc: ^Render_Context, edit: bool)
{
        dt := min(dt, 0.01667) // limit physics so that step size can't be greater than 0.01667
        animation_state := Player_State.STANDING
        player.velocity = player_drag_velocity(player.velocity, FRICTION)
        if !edit {
                direction: [3]f32
                if key_state.a {
                        direction -= camera.right
                }
                if key_state.d {
                        direction += camera.right
                }
                if key_state.w {
                        direction += camera.front
                }
                if key_state.s {
                        direction -= camera.front
                }
                direction.y = 0
                direction = glm.normalize(direction)
                // Still need so we render shadows correctly
                if glm.dot(direction, direction) > 0 {
                        look_direction := camera.front
                        look_direction.y = 0
                        look_direction.z = -look_direction.z
                        player.rot = glm.quatFromMat4(glm.mat4LookAt({0, 0, 0}, look_direction, {0, 1, 0}))
                        player.velocity += direction * SPEED
                        if player.on_ground {
                                animation_state = .WALKING        
                        }
                } else {
                        animation_state = .STANDING
                }
                
                if key_state.space && player.on_ground {
                        player.on_ground = false
                        player.velocity.y = JUMP_VELOCITY.y
                        animation_state = .STANDING // TODO add falling state
                }
        }
	

        if player.state != animation_state {
                player.state = animation_state
                switch_animation(player.animator, &player.animations[animation_state])
        }

	player.transform =
		glm.mat4Translate(player.pos) *
		glm.mat4Scale({player.scale, player.scale, player.scale}) *
		glm.mat4FromQuat(player.rot)
	update_animation(player.animator, dt)
	// Update model transform up front
        transform_data := player.model.transform_buffer->contentsAsType(Vertex_Transforms)
        transform_data.transform = player.transform
        transform_data.normal_transform = glm.transpose(glm.inverse_matrix4x4(player.transform))
        player.model.transform_buffer->didModifyRange(NS.Range_Make(0, size_of(Vertex_Transforms)))
        if player.model.bone_buffer != nil {
                player.model.bone_buffer->release()
        }
        player.velocity += GRAVITY * f32(dt)
        player.pos += player.velocity * f32(dt)
        player.model.bone_buffer = build_bone_buffer(rc.device, player.animator.bone_matrices)
}



player_drag_velocity :: proc(velocity: [3]f32, friction: f32
) -> [3]f32  
{
        new_velocity: [3]f32
        if velocity.x < 0 {
                new_velocity.x = min(velocity.x+friction, 0)
        } else {
                new_velocity.x = max(velocity.x-friction, 0)
        }
        if velocity.z < 0 {
                new_velocity.z = min(velocity.z+friction, 0)
        } else {
                new_velocity.z = max(velocity.z-friction, 0)
        }
        new_velocity.y = velocity.y
        return new_velocity
}



////////////// OBJECTS ////////////////
///////////////////////////////////////

load_plane :: proc(textures: []^Texture, pos: [3]f32, rot: quaternion128, scale: f32, rc: ^Render_Context, double_sided := true
) -> Entity
{
        plane := Entity{}
        plane.type = .Object
        plane.model = new(Model)
        plane.model.meshes = make([dynamic]Mesh)
        mesh := Mesh{}
        mesh.vertices = make(#soa[dynamic]Mesh_Vertex)
        append_soa(&mesh.vertices,
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
        mesh.indices = make([dynamic]i32)
        append(&mesh.indices, 0, 2, 1, 3, 1, 2, 6, 5, 7, 5, 6, 4)
        mesh.textures = make([dynamic]^Texture)
        for texture in textures {
                append(&mesh.textures, texture)
        }
        mesh.buffers = build_mesh_buffers(mesh.vertices, mesh.indices, rc)
        append(&plane.model.meshes, mesh)
        plane.pos = pos
        plane.rot = rot
        plane.scale = scale
        plane.transform = glm.mat4Translate(pos) * glm.mat4FromQuat(rot) * glm.mat4Scale(scale)

        transforms := rc.device->newBuffer(size_of(Vertex_Transforms), {.StorageModeManaged})
        transform_data := transforms->contentsAsType(Vertex_Transforms)
        transform_data.transform = plane.transform
        transform_data.normal_transform = glm.transpose(glm.inverse_matrix4x4(plane.transform))
        plane.model.transform_buffer = transforms 
        
        plane.model.color_id = Color_ID{u8(rand.int_max(255)), u8(rand.int_max(255)), u8(rand.int_max(255))}
        plane.type = .Object
        return plane
}

entity_delete :: proc(entity: ^Entity, allo := context.allocator)
{
        for animation in entity.animations {
                delete(animation.bone_infos)
                delete(animation.bones)
        }
        free(entity.animator.current_animation, allo)
        entity.model.bone_buffer->release()
        entity.model.transform_buffer->release()
        for &mesh in &entity.model.meshes {
                delete_mesh(&mesh)
        }
}

delete_mesh :: proc(mesh: ^Mesh)
{
        // TODO: Do I need to free the pointers too?
        mesh.buffers.bone_ids->release()
        mesh.buffers.bone_weights->release()
        mesh.buffers.index->release()
        mesh.buffers.norm->release()
        mesh.buffers.pos->release()
        mesh.buffers.uv->release()
        delete(mesh.indices)
        for texture in mesh.textures {
                texture.value->release()
        }
        delete(mesh.textures)
        delete(mesh.vertices)
}