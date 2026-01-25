package HighRoller

import "base:sanitizer"
import "vendor:directx/d3d12"
import "vendor:glfw"
import glm "core:math/linalg/glsl"
import "base:runtime"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "core:fmt"
foreign import "objc_runtime"
import im "../include/imgui"
import "../include/imgui/imgui_impl_metal"
import "../include/imgui/imgui_impl_glfw"
import "core:strings"
import os "core:os/os2"
import "core:math"
import "core:math/rand"
import "core:slice"
import hm "handle_map"

WIDTH :f32: 800.0
HEIGHT :f32: 600.0
CAMERA_NEAR :f32: 0.03
FOV :f32: 90
UP :: [3]f32{0, 1, 0}

// MAIN GAME LOOP //////////////////////////////////////
run_game :: proc() {
	rc := init_render_context(800, 600, "High Roller")
        // TODO setup gui function
	io := init_gui(rc)
        gui := GUI{}
        gui.texture_files = make([dynamic]cstring)
        dirs, _ := os.read_all_directory_by_path("../resources/textures/DEBUG", runtime.default_allocator())
        for dir in dirs {
                files, err := os.read_directory_by_path(dir.fullpath, 0, runtime.default_allocator())
                if err == nil {
                        for file in files {
                                append(&gui.texture_files, strings.clone_to_cstring(file.fullpath))
                        }
                }
        }
        gui.selected_texture = gui.texture_files[0]
	defer im.DestroyContext()

	load_shaders(rc)
	camera := init_camera(f32(rc.width), f32(rc.height))
	scene := init_scene(&camera, rc)
	key_state := init_key_state(rc, scene)
        key_state.can_select = true

	t: f64 = 0
	for !glfw.WindowShouldClose(rc.glfw_window) {
		t2 := glfw.GetTime()
		dt := t2 - t
		t = t2
		// fmt.println(dt)
		glfw.PollEvents()

		auto_pool := NS.AutoreleasePool_alloc()->init()
		update_scene(scene, key_state, dt, rc)
	        pre_process(scene, rc)

		begin_render_pass(rc)
		render_scene(scene, rc, options = default_render_pass_options)
		//update_gui(rc, io, scene, &gui)
		end_render_pass(rc, true)

		post_process(scene, rc)
		auto_pool->release()
	}
}
///////////////////////////////////////////////////////

init_camera :: proc(width, height: f32
) -> Camera
{
	camera := Camera{}
	camera.pos = {-15, 5, 1}
	camera.view_transform = glm.mat4LookAt(camera.pos, {0,0,0}, {0,1,0})
        camera.perspective_transform = glm.mat4Perspective(glm.radians_f32(90), width/height, CAMERA_NEAR, 2000)
	return camera
}



init_key_state :: proc(rc: ^Render_Context, scene: ^Scene
) -> ^Key_State
{
	key_state := new(Key_State)
        user_pointer := new(User_Pointer)
        user_pointer.key_state = key_state
        user_pointer.rc = rc
        user_pointer.scene = scene
        glfw.SetWindowUserPointer(rc.glfw_window, rawptr(user_pointer))
        glfw.SetKeyCallback(rc.glfw_window, key_callback)
        glfw.SetCursorPosCallback(rc.glfw_window, cursor_pos_callback)
        glfw.SetMouseButtonCallback(rc.glfw_window, mouse_button_callback)
        glfw.SetWindowSizeCallback(rc.glfw_window, window_size_callback)
	return key_state
}



init_scene :: proc(camera: ^Camera, rc: ^Render_Context
) -> ^Scene
{
        scene := new(Scene)
        scene.lights = make(#soa[dynamic]Light, 1)
        scene.enemies = make([dynamic]hm.Handle)
        scene.objects = make([dynamic]hm.Handle)
        scene.color_id_map = make(map[Color_ID]hm.Handle)
        hm.init_handle_map(&scene.entities)
        scene.entities.delete_func = entity_delete
	player := create_player("../resources/models/voxel/Voxel character.fbx", "../resources/models/voxel/Voxel character.fbx", rc)
        handle := hm.add(&scene.entities, player)
        scene.color_id_map[player.model.color_id] = handle
        scene.player = handle
        scene.camera = camera

	enemy := create_enemy("../resources/models/voxel/Voxel character.fbx", "../resources/models/voxel/Voxel character.fbx", {15, 1, 0}, rc)
        handle = hm.add(&scene.entities, enemy)
        append(&scene.enemies, handle)
        scene.color_id_map[enemy.model.color_id] = handle

        // create the ground
        rc.textures["ground_d"] = new(Texture)
        rc.textures["ground_d"].value = load_texture(rc.device, "../resources/textures/DEBUG/Purple/texture_02.png")
        rc.textures["ground_d"].type = .DIFFUSE
        ground_textures: [1]^Texture = {rc.textures["ground_d"]}
        plane := load_plane(ground_textures[:], {0,-1,0}, 0, 10, rc)
        plane.collider = Plane_Collider{x=10, z=10, normal=[3]f32{0, 1, 0}, binormal = [3]f32{1, 0, 0}}
        handle = hm.add(&scene.entities, plane)
        append(&scene.objects, handle)
        scene.color_id_map[plane.model.color_id] = handle

        scene_clear_lights(scene, rc)
        vert := CUBE_VERTICES
        scene_add_light(scene, Light{
                pos={0.1, 70, -0.1},
                col={1, 1, 1},
                vertices=vert[:]
        }, rc)
        // This needs to be done every time a light is added.
        scene.light_buffer = build_light_buffers(scene.lights[:], rc)

        desc := MTL.TextureDescriptor.alloc()->init()
        // Make this match the dimensions of the screen. Can lower resolution but must have same aspect ratio
	tex_desc := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
		pixelFormat = .RGBA8Unorm,
		width = NS.UInteger(rc.width),
		height = NS.UInteger(rc.height),
		mipmapped = false,
	)
	defer tex_desc->release()
	tex_desc->setUsage({.RenderTarget})
	tex_desc->setStorageMode(.Managed)
        scene.color_id_texture = rc.device->newTextureWithDescriptor(tex_desc)

        scene.hud = HUD{crosshair_scale = 0.01}
        return scene
}



load_shaders :: proc(rc: ^Render_Context)
{
        rc.shaders[MESH_SHADER] = build_shader(rc.device, "../shaders/mesh.metal")
        rc.shaders[MESH_SHADOW_SHADER] = build_shader(rc.device, "../shaders/mesh_shadow.metal", shadow_shader_options)
        rc.shaders[MESH_COLOR_ID_SHADER] = build_shader(rc.device, "../shaders/mesh_color_id.metal")

        rc.shaders[MODEL_SHADER] = build_shader(rc.device, "../shaders/model.metal")
        rc.shaders[MODEL_SHADOW_SHADER] = build_shader(rc.device, "../shaders/model_shadow.metal", shadow_shader_options)
        rc.shaders[MODEL_COLOR_ID_SHADER] = build_shader(rc.device, "../shaders/model_color_id.metal")

        // rc.shaders[HUD_SHADER] = build_shader(rc.device, "../shaders/hud.metal")
        rc.shaders[HUD_SHADER] = build_shader(rc.device, "../shaders/hud.metal")
}



update_gui :: proc(rc: ^Render_Context, io: ^im.IO, scene: ^Scene, gui: ^GUI)
{
        begin_gui_draw(rc)
        //im.ShowDemoWindow()
	if im.Begin("Editor") {
	        if im.Button("Add Light") {
                        vert := CUBE_VERTICES
                        scene_add_light(scene, Light{pos={-1, 20, 1},
                                col={1, 1, 1},
                                vertices=vert[:]}, rc)
		}
                if im.Button("Remove Light") {
                        scene_clear_lights(scene, rc)
                }
                if im.Button("Add Plane") {
                        scene_add_plane(scene, rc, "DEBUG/Orange/texture_02.png")
                }
                selected := hm.get_pointer(&scene.entities, scene.selected)
                #partial switch selected.type {
                case .Collider: 
                {
                        if im.Button("Make Visible Object") {
                                selected.type = .Object
                        }
                }
                case .Object: 
                {
                        if im.Button("Make Collider Only") {
                                selected.type = .Collider
                        }
                }
                }

                if im.BeginCombo("Texture", gui.selected_texture) {
                        for texture in gui.texture_files {
                                is_selected := gui.selected_texture == texture
                                if im.Selectable(texture, is_selected) {
                                        gui.selected_texture = texture
                                        scene_update_texture(scene, texture, rc)
                                }
                        }
                        im.EndCombo()
                }

                im.Text("Object rotation")
                if im.SliderAngle("roll", &gui.roll) {
                        scene_update_rotation(scene, gui)
                }
                if im.SliderAngle("pitch", &gui.pitch) {
                        scene_update_rotation(scene, gui)
                }
                if im.SliderAngle("yaw", &gui.yaw){
                        scene_update_rotation(scene, gui)
                }
	}
        end_gui_draw(rc)
}

update_scene :: proc(scene: ^Scene, key_state: ^Key_State, dt: f64, rc: ^Render_Context)
{
        if !scene.edit {
                player := hm.get_pointer(&scene.entities, scene.player)
                update_player(player, scene.camera, key_state, dt, rc, scene.edit)
                for enemy_handle, idx in scene.enemies {
                        enemy := hm.get_pointer(&scene.entities, enemy_handle)
                        if enemy.handle.idx != 0 {
                                update_enemy(enemy, scene, dt, rc)
                        } else {
                                remove_range(&scene.enemies, idx, idx+1)
                        }
                }
                // Handle firing shots
                if key_state.left_mouse_down {
                        handle := find_object_under_crosshair(scene, rc)
                        if handle.idx != 0 {
                                entity := hm.get(scene.entities, handle)
                                if entity.type == .Enemy {
                                        hm.delete(&scene.entities, handle)
                                        entity.handle.idx = 0 // inactive handle == dead
                                        // Deallocate the entity
                                }
                        }
                }
        }
        scene_read_input(scene, key_state, dt)
        scene_check_collisions(scene, dt)
        if !scene.edit {
                glfw.SetInputMode(rc.glfw_window, glfw.CURSOR, glfw.CURSOR_DISABLED)
        } else {
                glfw.SetInputMode(rc.glfw_window, glfw.CURSOR, glfw.CURSOR_NORMAL)

        }
        update_camera(scene, key_state, dt)
}

scene_check_collisions :: proc(scene: ^Scene, dt: f64)
{
        // For now just check collisions with the player
        // TODO multi thread with a mutex on the player position
        // TODO is it worth storing player and enemy handles separately?
        // TODO allocate player + enemy entities next to eachother for cache efficiency 
        for &entity in hm.active_slice(&scene.entities) {
                if entity.handle.idx == 0 {continue}
                #partial switch entity.type {
                case .Enemy, .Player: {
                        new_pos, on_ground, should_update := check_sphere_collisions(entity.pos, entity.collider.(Sphere_Collider), scene, dt)
                        if should_update {
                                entity.pos = new_pos
                        }
                        if on_ground {
                                entity.velocity.y = 0
                                entity.on_ground = true
                        }
                }
                }
        }
}

check_sphere_collisions :: proc(pos: [3]f32, sphere_coll: Sphere_Collider, scene: ^Scene, dt: f64,
) -> ([3]f32, bool, bool) 
{
        collider_pos := pos + {0, sphere_coll.radius, 0}
        should_update: bool
        on_ground: bool
        pos := pos

        // TODO add object storage
        for handle in scene.objects {
                entity := hm.get(scene.entities, handle)
                if entity.handle.idx == 0 || entity.type != .Object {continue}
                if entity.collider != nil {
                        switch collider in entity.collider {
                        case Box_Collider: {}
                        case Capsule_Collider: {}
                        case Sphere_Collider: {}
                        case Plane_Collider: {
                                vector := collider_pos - entity.pos
                                // Transform into an orthonormal basis
                                n := (glm.mat4FromQuat(entity.rot) * [4]f32{collider.normal.x, collider.normal.y, collider.normal.z, 0}).xyz
                                b := (glm.mat4FromQuat(entity.rot) * [4]f32{collider.binormal.x, collider.binormal.y, collider.binormal.z, 0}).xyz
                                t := glm.cross(n, b)
                                ortho_transform := glm.transpose(matrix[3,3]f32{
                                        b.x, n.x, t.x,
                                        b.y, n.y, t.y,
                                        b.z, n.z, t.z,
                                })
                                coll_plane := ortho_transform * vector // convert player position into plane coordinates
                                closest_z := clamp(coll_plane.z, -collider.z, collider.z)
                                closest_x := clamp(coll_plane.x, -collider.x, collider.x)
                                closest := [3]f32{closest_x, 0, closest_z} // closest point on plane in plane coordinates in plane coordinates
                                dist := glm.distance(closest, coll_plane)
                                if dist < sphere_coll.radius {
                                        // Translate from plane coordinates back to world coordinates and then repulse
                                        to_move := glm.transpose(ortho_transform) * glm.normalize(coll_plane-closest) * (sphere_coll.radius-dist)
                                        pos += to_move
                                        if abs(glm.dot(n, UP)) > 0.7 && glm.dot(to_move, UP) > 0{
                                               on_ground = true 
                                        }
                                        should_update = true
                                }
                        }
                        }
                }
        }
        return pos, on_ground, should_update
}

update_camera :: proc(scene: ^Scene, key_state: ^Key_State, dt: f64)
{
        MOUSE_SENSITIVITY :: 0.1
        // TODO optimise
        if !scene.camera.free || (key_state.right_mouse_down && scene.camera.free) {
                scene.camera.yaw += key_state.x_offset * MOUSE_SENSITIVITY
                scene.camera.pitch -= key_state.y_offset * MOUSE_SENSITIVITY
                key_state.x_offset = 0
                key_state.y_offset = 0
                scene.camera.pitch = clamp(scene.camera.pitch, -89.9, 89.9)
                scene.camera.front = glm.normalize([3]f32{
                        math.cos(math.to_radians(scene.camera.yaw)) * math.cos(math.to_radians(scene.camera.pitch)),
                        math.sin(math.to_radians(scene.camera.pitch)),
                        math.sin(math.to_radians(scene.camera.yaw)) * math.cos(math.to_radians(scene.camera.pitch))
                })
                scene.camera.right = glm.normalize(glm.cross(scene.camera.front, UP))
                scene.camera.up = glm.normalize(glm.cross(scene.camera.right, scene.camera.front))
        } 
        if scene.camera.free {
                CAMERA_SPEED :: 10
                if key_state.d {
                        scene.camera.pos = scene.camera.pos + scene.camera.right * CAMERA_SPEED * f32(dt)
                }
                if key_state.a {
                        scene.camera.pos = scene.camera.pos - scene.camera.right * CAMERA_SPEED * f32(dt)
                }
                if key_state.w {
                        scene.camera.pos = scene.camera.pos + scene.camera.front * CAMERA_SPEED * f32(dt)
                }
                if key_state.s {
                        scene.camera.pos = scene.camera.pos - scene.camera.front * CAMERA_SPEED * f32(dt)
                }
        } else {
                // TODO should just store as a pointer?
                player := hm.get(scene.entities, scene.player)
                scene.camera.pos = player.pos + {0, 2, 0}
        }
        scene.camera.view_transform = glm.mat4LookAt(scene.camera.pos, scene.camera.pos + scene.camera.front, UP)
}



pre_process :: proc(scene: ^Scene, rc: ^Render_Context)
{
        // Generate shadow map
        begin_render_pass(rc, depth_texture = rc.shadow_map.texture, options = shadow_render_pass_options)
        new_encoder(rc, shadow_render_pass_options)
        set_render_pipeline_state(MODEL_SHADOW_SHADER, rc)
        player := hm.get(scene.entities, scene.player)
        write_model_to_shadow_map(player.model, rc, player.model.transform_buffer, rc.shadow_map)
        for handle in scene.enemies {
                enemy := hm.get(scene.entities, handle)
                if enemy.handle.idx != 0 {
                        write_model_to_shadow_map(enemy.model, rc, enemy.model.transform_buffer, rc.shadow_map)
                }
        }
        set_render_pipeline_state(MESH_SHADOW_SHADER, rc)
        for handle in scene.objects { 
                object := hm.get(scene.entities, handle)
                write_model_to_shadow_map(object.model, rc, object.model.transform_buffer, rc.shadow_map)
        }
        rc.draw_stage.encoder->endEncoding()
        end_render_pass(rc, present=false)
        
        // I don't know why this needs it's own auto-release pool. But it does...
        auto_pool := NS.AutoreleasePool_alloc()->init()
        /// Generate colour id texture
        camera_buffer := rc.device->newBuffer(size_of(Camera), {.StorageModeManaged})
	defer camera_buffer->release()
        camera_data := camera_buffer->contentsAsType(Camera)
        camera_data.view_transform = scene.camera.view_transform
        camera_data.perspective_transform = scene.camera.perspective_transform
        camera_data.pos = scene.camera.pos

        begin_render_pass(rc, nil, color_texture = scene.color_id_texture, options = default_render_pass_options)
        new_encoder(rc, default_render_pass_options)
        set_render_pipeline_state(MODEL_COLOR_ID_SHADER, rc)
        write_model_to_color_id(player.model, player.model.transform_buffer, camera_buffer, rc)
        for enemy_handle in scene.enemies {
                enemy := hm.get(scene.entities, enemy_handle)
                if enemy.state != nil {
                        write_model_to_color_id(enemy.model, enemy.model.transform_buffer, camera_buffer, rc)
                }
        }
        set_render_pipeline_state(MESH_COLOR_ID_SHADER, rc)
        for handle in scene.objects {
                object := hm.get(scene.entities, handle)
                if object.type != .Collider || scene.edit {
                        write_model_to_color_id(object.model, object.model.transform_buffer, camera_buffer, rc)
                }
        }
        rc.draw_stage.encoder->endEncoding()
        end_render_pass(rc, present=false)
        auto_pool->release()
}



render_scene :: proc(scene: ^Scene, rc: ^Render_Context, options: Render_Pass_Options)
{
        new_encoder(rc, default_render_pass_options)
        //Build the camera buffer
        camera_buffer := rc.device->newBuffer(size_of(Camera), {.StorageModeManaged})
	defer camera_buffer->release()
        camera_data := camera_buffer->contentsAsType(Camera)
        camera_data.view_transform = scene.camera.view_transform
        camera_data.perspective_transform = scene.camera.perspective_transform
        camera_data.pos = scene.camera.pos

        // Render Player
        set_render_pipeline_state(MODEL_SHADER, rc)

	rc.draw_stage.encoder->setVertexBuffer(buffer=camera_buffer, offset=0, index=6)
	rc.draw_stage.encoder->setFragmentBuffer(buffer=camera_buffer, offset=0, index=0)
	rc.draw_stage.encoder->setFragmentBuffer(buffer=scene.light_buffer, offset=0, index=1)

        if scene.edit {
                player := hm.get(scene.entities, scene.player)
                // Is the player selected?
                options_buffer := rc.device->newBufferWithLength(size_of(Render_Arguments), {.StorageModeManaged})
                defer options_buffer->release()
                options := options_buffer->contentsAsType(Render_Arguments)
                options.selected = scene.selected == player.handle ? 1 : 0
                options_buffer->didModifyRange(NS.Range_Make(0, size_of(Render_Arguments)))
                rc.draw_stage.encoder->setFragmentBuffer(buffer=options_buffer, offset=0, index=8)
                render_model(camera_buffer, scene.light_buffer, player.model, rc)
        }

        for enemy_handle in scene.enemies {
                enemy := hm.get(scene.entities, enemy_handle)
                if enemy.handle.idx == 0 {
                        continue
                }
                // Create render options buffer
                options_buffer := rc.device->newBufferWithLength(size_of(Render_Arguments), {.StorageModeManaged})
                defer options_buffer->release()
                options := options_buffer->contentsAsType(Render_Arguments)
                options.selected = scene.selected == enemy.handle ? 1 : 0
                options_buffer->didModifyRange(NS.Range_Make(0, size_of(Render_Arguments)))
                rc.draw_stage.encoder->setFragmentBuffer(buffer=options_buffer, offset=0, index=8)
                render_model(camera_buffer, scene.light_buffer, enemy.model, rc)
        }

        set_render_pipeline_state(MESH_SHADER, rc)
        // Set up the shadow map
        rc.draw_stage.encoder->setFragmentTexture(rc.shadow_map.texture, 2)
        rc.draw_stage.encoder->setFragmentBuffer(buffer=rc.shadow_map.transform, offset=0, index=3)
        for handle in scene.objects {
                object := hm.get(scene.entities, handle)
                if object.handle.idx == 0 || (object.type == .Collider && !scene.edit) {
                        continue
                }
                options_buffer := rc.device->newBufferWithLength(size_of(Render_Arguments), {.StorageModeManaged})
                defer options_buffer->release()
                options := options_buffer->contentsAsType(Render_Arguments)
                options.selected = scene.selected == handle && scene.edit ? 1 : 0
                options_buffer->didModifyRange(NS.Range_Make(0, size_of(Render_Arguments)))
                rc.draw_stage.encoder->setFragmentBuffer(buffer=options_buffer, offset=0, index=8)

                render_model(camera_buffer, scene.light_buffer, object.model, rc)
        }
        if scene.edit {
                player := hm.get(scene.entities, scene.player)
                mesh := player.collider.(Sphere_Collider).mesh
                rc.draw_stage.encoder->setFragmentTexture(mesh.textures[0].value, 0)
                translation := glm.mat4Translate(player.pos + {0, 1, 0}) * glm.mat4Scale(player.collider.(Sphere_Collider).radius)
                transforms := rc.device->newBuffer(size_of(Vertex_Transforms), {.StorageModeManaged})
                defer transforms->release()
                transform_data := transforms->contentsAsType(Vertex_Transforms)
                transform_data.transform = translation
                transform_data.normal_transform = glm.transpose(glm.inverse_matrix4x4(translation))
                rc.draw_stage.encoder->setVertexBuffer(buffer=transforms, offset=0, index=7)
                render_mesh(camera_buffer, scene.light_buffer, mesh, rc.draw_stage.encoder)
        } 
        set_render_pipeline_state(HUD_SHADER, rc)
        render_hud(scene.hud, rc)
        
        rc.draw_stage.encoder->endEncoding()
        
}



post_process :: proc(scene: ^Scene, rc: ^Render_Context)
{
        
}



scene_add_light :: proc(scene: ^Scene, light: Light, rc: ^Render_Context)
{
        append(&scene.lights, light)
        scene.light_buffer->release()
        scene.light_buffer = build_light_buffers(scene.lights[:], rc)
        if len(scene.lights) == 1 {
                if (rc.shadow_map.texture != nil) {
                        rc.shadow_map.texture->release()
                }
                rc.shadow_map = init_shadow_map(rc, scene.lights[0].pos)
        }
}



scene_clear_lights :: proc(scene: ^Scene, rc: ^Render_Context)
{
        clear(&scene.lights)
        scene.light_buffer->release()
        scene.light_buffer = build_light_buffers(scene.lights[:], rc)
        clear_shadow_map(rc)
}


scene_add_plane :: proc(scene: ^Scene, rc: ^Render_Context, texture: string)
{
        // TODO loading and storing of both diffuse and specular textures
        if !(texture in rc.textures) {
                texture_path := strings.concatenate({"../resources/textures/", texture})
                defer delete(texture_path)
                rc.textures[texture] = new(Texture)
                rc.textures[texture].value = load_texture(rc.device, texture_path)
                rc.textures[texture].type = .DIFFUSE
        }

        plane_textures: [1]^Texture = {rc.textures[texture]}
        rotation: quaternion128 = quaternion(real=0, imag=0, kmag=1, jmag=0)
        plane := load_plane(plane_textures[:], {0,0,0}, rotation, 10, rc)
        plane.collider = Plane_Collider{x=10, z=10, normal=[3]f32{0, 1, 0}, binormal = [3]f32{1, 0, 0}}
        handle := hm.add(&scene.entities, plane)
        scene.color_id_map[plane.model.color_id] = handle
        scene.selected = handle
}



scene_read_input :: proc(scene: ^Scene, key_state: ^Key_State, dt: f64)
{
        if key_state.escape && key_state.shift {
                os.exit(1)
        } else if key_state.escape {
                key_state.escape = false
                scene.camera.free = !scene.camera.free
                scene.edit = !scene.edit
        }
        if !scene.edit {
                return 
        }
        direction: [3]f32
        selected := hm.get_pointer(&scene.entities, scene.selected)
        if selected.handle.idx != 0 {
                if key_state.left_mouse_down && key_state.mouse_moved {
                        dist := glm.distance(selected.pos, scene.camera.pos)
                        screen_width := 2*CAMERA_NEAR * math.tan(math.to_radians(FOV)/2) // The world space screen width
                        true_x_offset := key_state.x_offset * screen_width / WIDTH // world space x_offset
                        x_move := dist * true_x_offset / CAMERA_NEAR
                        true_y_offset := key_state.y_offset * screen_width / WIDTH // use same scaling as width
                        y_move := dist * true_y_offset / CAMERA_NEAR
                        direction = -scene.camera.up * y_move + scene.camera.right * x_move
                }
                if (glm.dot(direction, direction) > 0) {
                        pos := selected.pos + direction
                        rot := selected.rot
                        scale := selected.scale
                        selected.pos = pos
                        selected.transform = glm.mat4Translate(pos) * glm.mat4FromQuat(rot) * glm.mat4Scale(scale)
                        transform_data := selected.model.transform_buffer->contentsAsType(Vertex_Transforms)
                        transform_data.transform = selected.transform
                        transform_data.normal_transform = glm.transpose(glm.inverse_matrix4x4(selected.transform))
                        selected.model.transform_buffer->didModifyRange(NS.Range_Make(0, size_of(Vertex_Transforms)))
                }
        }
        if key_state.left_mouse_down && key_state.can_select {
                scene.selected = find_object_under_mouse(scene, key_state)
                key_state.can_select = false
        }
        key_state.mouse_moved = false
}

find_object_under_mouse :: proc(scene: ^Scene, key_state: ^Key_State
) -> hm.Handle
{
        color_bytes: [3]byte = {} // 3 f32 values should be 12 bytes
        region_origin := MTL.Origin{NS.Integer(key_state.mouse_pos.x), NS.Integer(key_state.mouse_pos.y), 0}
        //region_origin := MTL.Origin{0, 0, 0}
        region_size := MTL.Size{1,1,1}
        region := MTL.Region{region_origin, region_size}
        scene.color_id_texture->getBytes(rawptr(&color_bytes), scene.color_id_texture->width()*4, region, 0)
        
        // find the color value at that position in the texture
        // Match ColorID to an object via the map (this may or may not work)
        color := slice.reinterpret([]u8, color_bytes[:])
        color_id := Color_ID{color[0], color[1], color[2]}
        if color_id in scene.color_id_map {
                return scene.color_id_map[color_id]
        }
        return hm.Handle{}
}

find_object_under_crosshair:: proc(scene: ^Scene, rc: ^Render_Context
) -> hm.Handle 
{
        color_bytes: [3]byte = {} // 3 f32 values should be 12 bytes
        region_origin := MTL.Origin{NS.Integer(rc.width / 2), NS.Integer(rc.height / 2), 0}
        //region_origin := MTL.Origin{0, 0, 0}
        region_size := MTL.Size{1,1,1}
        region := MTL.Region{region_origin, region_size}
        scene.color_id_texture->getBytes(rawptr(&color_bytes), scene.color_id_texture->width()*4, region, 0)
        
        // find the color value at that position in the texture
        // Match ColorID to an object via the map (this may or may not work)
        color := slice.reinterpret([]u8, color_bytes[:])
        color_id := Color_ID{color[0], color[1], color[2]}
        if color_id in scene.color_id_map {
                return scene.color_id_map[color_id]
        }
        return hm.Handle{} 
}


scene_update_transform :: proc(scene: ^Scene)
{
        selected := hm.get_pointer(&scene.entities, scene.selected)
        if selected.handle.idx != 0 {
                selected.transform =
                        glm.mat4Translate(selected.pos) *
                        glm.mat4FromQuat(selected.rot) *
                        glm.mat4Scale(selected.scale)
        }
}



scene_update_rotation :: proc(scene: ^Scene, gui: ^GUI)
{
        thing := hm.get_pointer(&scene.entities, scene.selected)
        if thing.handle.idx == 0 {
                return
        }
        thing.rot =     
                glm.quatAxisAngle({0, 0, 1}, gui.roll) *
                glm.quatAxisAngle({0, 1, 0}, gui.pitch) *
                glm.quatAxisAngle({1, 0, 0}, gui.yaw)
        thing.transform =
                glm.mat4Translate(thing.pos) *
                glm.mat4FromQuat(thing.rot) *
                glm.mat4Scale(thing.scale)
}



// TODO error handling
scene_update_texture :: proc(scene: ^Scene, texture_path: cstring, rc: ^Render_Context)
{
        thing := hm.get_pointer(&scene.entities, scene.selected)
        #partial switch thing.type {
        case .Object: {
                if string(texture_path) in rc.textures {
                        for &mesh in &thing.model.meshes {
                                clear(&mesh.textures)
                                append(&mesh.textures, rc.textures[string(texture_path)])
                        }
                } else {
                        for &mesh in &thing.model.meshes {
                                texture := new(Texture)
                                texture.value = load_texture(rc.device, string(texture_path))
                                texture .type = .DIFFUSE
                                rc.textures[string(texture_path)] = texture
                                append(&mesh.textures, texture)
                        }
                }
        }
        }
}
