package HighRoller

import glm "core:math/linalg/glsl"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "core:math/rand"
import "core:fmt"
import ai "../include/assimp"

GRAVITY :: [3]f32{0, -15, 0}
JUMP_VELOCITY :: [3]f32{0, 10, 0}
SPEED :: 8
FRICTION :: 8

update_player :: proc(player: ^Player, camera: ^Camera, key_state: ^Key_State, dt: f64, rc: ^Render_Context, edit: bool)
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

create_player :: proc(
	model_path: string,
	animation_path: string,
	rc: ^Render_Context,
) -> Player
{
	model := load_model(model_path, rc)
	anims := load_animation(animation_path, model)
	animator := create_animator(&anims[0])
	player := Player {
		model      = model,
		animator   = animator,
		animations = anims,
		transform  = 1,
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

