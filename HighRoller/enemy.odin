package HighRoller

import "core:math/rand"
import glm "core:math/linalg/glsl"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"

create_enemy:: proc(
	model_path: string,
	animation_path: string,
        pos: [3]f32,
	rc: ^Render_Context,
) ->  ^Enemy
{
	model := load_model(model_path, rc)
	anims := load_animation(animation_path, model)
	animator := create_animator(&anims[0])
	enemy := new(Enemy)
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



update_enemy :: proc(enemy: ^Enemy, scene: ^Scene, dt: f64, rc: ^Render_Context)
{
        SPEED :: 2
        FRICTION :: 2
        enemy.velocity = player_drag_velocity(enemy.velocity, FRICTION)
        dt := min(dt, 0.01667) // limit physics so that step size can't be greater than 0.01667
        animation_state := Player_State.STANDING // TODO figure out why this is failing
        direction := glm.normalize(scene.player.pos - enemy.pos)
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

