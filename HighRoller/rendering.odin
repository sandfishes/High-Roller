package HighRoller

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "vendor:glfw"
import os "core:os/os2"
import "core:strings"
import "core:fmt"
import "core:image/png"
import "core:image/jpeg"
import glm "core:math/linalg/glsl"


init_render_context :: proc(width, height: i32, label: string
) -> ^Render_Context
{
	rc := new(Render_Context)
        rc.width = width
        rc.height = height

	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw_window := glfw.CreateWindow(width, height, "High Roller", nil, nil)
	native_window := glfw.GetCocoaWindow(glfw_window)

	title := NS.String_initWithOdinString(NS.String_alloc(), label)
	defer title->release()
	device := MTL.CreateSystemDefaultDevice()
	swapchain := CA.MetalLayer_layer()
	CA.MetalLayer_setDevice(swapchain, device)
	CA.MetalLayer_setPixelFormat(swapchain, .RGBA8Unorm)
	CA.MetalLayer_setFramebufferOnly(swapchain, true)
	CA.MetalLayer_setFrame(swapchain, NS.Window_frame(native_window))

	content_view := NS.Window_contentView(native_window)
	NS.View_setLayer(content_view, swapchain)

	command_queue := MTL.Device_newCommandQueue(device)
	depth_desc := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
		pixelFormat = .Depth16Unorm,
		width = NS.UInteger(width),
		height = NS.UInteger(height),
		mipmapped = false,
	)
	defer depth_desc->release()
	depth_desc->setUsage({.RenderTarget})
	depth_desc->setStorageMode(.Private)
	rc.depth_texture = device->newTextureWithDescriptor(depth_desc)
	rc.device = device
	rc.native_window = native_window
	rc.glfw_window = glfw_window
	rc.swapchain = swapchain
	rc.command_queue = command_queue
	rc.textures = make(map[string]^Texture)
	rc.shaders = make(map[string]Shader)
	return rc
}



build_shader :: proc(device: ^MTL.Device, path: string, options: Shader_Options = default_shader_options,
) -> Shader
{
        library: ^MTL.Library
        rps: ^MTL.RenderPipelineState
        shader_src, os_err := os.read_entire_file_from_path(path, context.allocator)
        if os_err != nil {
                fmt.eprintln("Failed to load shader source file.")
                os.exit(FILE_LOADING_ERROR)
        }
        defer delete(shader_src)
        shader_src_ns := NS.String.alloc()->initWithOdinString(string(shader_src))
        defer shader_src_ns->release()
        ns_err: ^NS.Error
        library, ns_err = device->newLibraryWithSource(shader_src_ns, nil)
        if ns_err != nil {
                fmt.println(NS.Error_localizedFailureReason(ns_err))
        }

        vertex_function := library->newFunctionWithName(NS.AT("vertex_main"))
        fragment_function := library->newFunctionWithName(NS.AT("fragment_main"))
        defer vertex_function->release()
        defer fragment_function->release()

        desc := MTL.RenderPipelineDescriptor.alloc()->init()
        MTL.RenderPipelineDescriptor_setShaderValidation(desc, MTL.ShaderValidation.Enabled)
        defer desc->release()
        desc->setVertexFunction(vertex_function)
        desc->setFragmentFunction(fragment_function)
        object_0 := desc->colorAttachments()->object(0)
        object_0->setPixelFormat(options.pixel_format)
        object_0->setBlendingEnabled(options.blending_enabled)
        object_0->setRgbBlendOperation(options.rgb_blend_operation)
        object_0->setAlphaBlendOperation(options.alpha_blend_operation)
        object_0->setSourceRGBBlendFactor(options.source_rgb_blend_operation)
        object_0->setSourceAlphaBlendFactor(options.source_alpha_blend_operation)
        object_0->setDestinationRGBBlendFactor(options.destination_rgb_blend_operation)
        object_0->setDestinationAlphaBlendFactor(options.destination_alpha_blend_operation)
        desc->setDepthAttachmentPixelFormat(options.depth_attachment_pixel_format)
        rps, ns_err = device->newRenderPipelineStateWithDescriptor(desc)
        if ns_err != nil {
                fmt.println(NS.Error_localizedFailureReason(ns_err))
        }
        return Shader{rps, library}
}



render_mesh :: proc(
        camera_buffer, light_buffer: ^MTL.Buffer,
        mesh: Mesh,
        render_encoder: ^MTL.RenderCommandEncoder,
        bone_buffer: ^MTL.Buffer = nil)
{
        buf := mesh.buffers
        // TODO arg encoder
        render_encoder->setVertexBuffer(buffer=buf.pos, offset=0, index=0)
        render_encoder->setVertexBuffer(buffer=buf.uv, offset=0, index=1)
        render_encoder->setVertexBuffer(buffer=buf.norm, offset=0, index=2)
        render_encoder->setVertexBuffer(buffer=buf.bone_ids, offset=0, index=3)
        render_encoder->setVertexBuffer(buffer=buf.bone_weights, offset=0, index=4)
        if bone_buffer != nil {
                render_encoder->setVertexBuffer(buffer=bone_buffer, offset=0, index=5)
        }
        render_encoder->setVertexBuffer(buffer=camera_buffer, offset=0, index=6)
        render_encoder->setFragmentBuffer(buffer=camera_buffer, offset=0, index=0)
        render_encoder->setFragmentBuffer(buffer=light_buffer, offset=0, index=1)
        for texture in mesh.textures {
                if texture.type == .DIFFUSE {
                        render_encoder->setFragmentTexture(texture.value, 0)
                }
                if texture.type == .SPECULAR {
                        render_encoder->setFragmentTexture(texture.value, 1)
                }
        }
        render_encoder->drawIndexedPrimitives(.Triangle, buf.index->length() / 4, .UInt32, buf.index, 0)
}



build_mesh_buffers :: proc(
        vertices: #soa[dynamic]Mesh_Vertex,
        indices: [dynamic]i32,
        rc: ^Render_Context
) -> ^Mesh_Buffers
{
        device := rc.device
        buffers := new(Mesh_Buffers)
        pos, norm, uv, bone_ids, bone_weights := soa_unzip(vertices[:])
        buffers.pos = device->newBufferWithSlice(pos, {.StorageModeManaged})
        buffers.pos->didModifyRange(NS.Range_Make(0, buffers.pos->length()))
        buffers.uv = device->newBufferWithSlice(uv, {.StorageModeManaged})
        buffers.uv->didModifyRange(NS.Range_Make(0, buffers.uv->length()))
        buffers.norm = device->newBufferWithSlice(norm, {.StorageModeManaged})
        buffers.norm->didModifyRange(NS.Range_Make(0, buffers.norm->length()))
        buffers.bone_ids = device->newBufferWithSlice(bone_ids[:], {.StorageModeManaged})
        buffers.bone_ids->didModifyRange(NS.Range_Make(0, buffers.bone_ids->length()))
        buffers.bone_weights = device->newBufferWithSlice(bone_weights[:], {.StorageModeManaged})
        buffers.bone_weights->didModifyRange(NS.Range_Make(0, buffers.bone_weights->length()))
        buffers.index = device->newBufferWithSlice(indices[:], {.StorageModeManaged})
        buffers.index->didModifyRange(NS.Range_Make(0, buffers.index->length()))
        return buffers
}



load_texture :: proc(device: ^MTL.Device, path: string
) -> ^MTL.Texture
{
        desc := MTL.TextureDescriptor.alloc()->init()
        defer desc->release()
        file_type := path[strings.last_index(path,"."):]
        image: ^png.Image
        err: png.Error
        switch file_type {
                case ".png": {
                        image, err = png.load_from_file(path, options = {.alpha_add_if_missing})
                        desc->setPixelFormat(.RGBA8Unorm)
                }
                case ".jpeg", ".jpg": {
                        image, err = jpeg.load_from_file(path, options = {.alpha_add_if_missing})
                        desc->setPixelFormat(.RG8Unorm_sRGB)
                }
                }
        defer png.destroy(image)
        if err != nil {
                fmt.eprintln("Failed to load texture file.", err)
                return nil
        }
        desc->setWidth(NS.UInteger(image.width))
        desc->setHeight(NS.UInteger(image.height))
        desc->setStorageMode(.Managed)
        desc->setUsage({.ShaderRead})
        texture := device->newTextureWithDescriptor(desc)
        texture->replaceRegion(MTL.Region{{0, 0, 0}, {NS.Integer(image.width), NS.Integer(image.height), 1}}, 0, raw_data(image.pixels.buf), NS.UInteger(image.width*image.channels))
        return texture
}



render_model :: proc(
        camera_buffer, light_buffer: ^MTL.Buffer,
        model: ^Model,
        rc: ^Render_Context)
{
        rc.draw_stage.encoder->setVertexBuffer(buffer=model.transform_buffer, offset=0, index=7)
        for &mesh in model.meshes {
                render_mesh(camera_buffer, light_buffer, mesh, rc.draw_stage.encoder, model.bone_buffer)
        }
}



build_bone_buffer :: proc(device: ^MTL.Device, transforms: []matrix[4,4]f32
) -> ^MTL.Buffer
{
        buffer := device->newBufferWithSlice(transforms[:], {.StorageModeManaged})
        buffer->didModifyRange(NS.Range_Make(0, buffer->length()))
        return buffer
}



clear_mesh_buffers :: proc(buffers: Mesh_Buffers) {
        buffers.pos->release()
        buffers.norm->release()
        buffers.uv->release()
        buffers.bone_ids->release()
        buffers.bone_weights->release()
}



begin_render_pass :: proc(
        rc: ^Render_Context,
        depth_texture: ^MTL.Texture = nil,
        color_texture: ^MTL.Texture = nil,
        options: Render_Pass_Options = default_render_pass_options)
{
        rc.draw_stage.pass = MTL.RenderPassDescriptor.renderPassDescriptor();
        rc.draw_stage.drawable = CA.MetalLayer_nextDrawable(rc.swapchain)
        rc.draw_stage.command_buffer = MTL.CommandQueue_commandBuffer(rc.command_queue)
        if options.with_color_attachment {
                color_attachment := rc.draw_stage.pass->colorAttachments()->object(0)
                color_attachment->setClearColor(MTL.ClearColor{0.5, 0.5, 0.7, 1.0})
                color_attachment->setLoadAction(options.color_attachment_load_action)
                color_attachment->setStoreAction(options.color_attachment_store_action)
                if color_texture != nil {
                        color_attachment->setTexture(color_texture)
                } else {
                        color_attachment->setTexture(rc.draw_stage.drawable->texture())
                }
        }
        
        depth_attachment := rc.draw_stage.pass->depthAttachment()
        depth_attachment->setTexture(depth_texture != nil ? depth_texture : rc.depth_texture)
        depth_attachment->setClearDepth(options.depth_attachment_clear_depth)
        depth_attachment->setLoadAction(options.depth_attachment_load_action)
        depth_attachment->setStoreAction(options.depth_attachment_store_action)
}



end_render_pass :: proc(rc: ^Render_Context, present: bool = true)
{
        if present {
                rc.draw_stage.command_buffer->presentDrawable(rc.draw_stage.drawable)
        }
        MTL.CommandBuffer_commit(rc.draw_stage.command_buffer)
}



init_shadow_map :: proc(
        rc: ^Render_Context,
        light_pos: [3]f32,
        light_type: Light_Type = .DIRECTIONAL,
) -> (Shadow_Map)
{
        look_at := glm.mat4LookAt(light_pos, {0,0,0}, {0,1,0})
        proj_from_world: matrix[4, 4]f32
        switch light_type {
        case .DIRECTIONAL: {
                proj_from_world = glm.mat4Ortho3d(-50,50,-50,50,-1000,1000) * look_at
        }
        case .POINT: {
                proj_from_world = glm.mat4Perspective(glm.radians_f32(90), 1.3, 0.03, 2000) * look_at
        }
        }

        transform_buffer := rc.device->newBuffer(size_of(matrix[4,4]f32), {.StorageModeManaged})
        transform_data := transform_buffer->contentsAsType(matrix[4,4]f32)
        transform_data^ = proj_from_world
        transform_buffer->didModifyRange(NS.Range_Make(0, size_of(matrix[4,4]f32)))
        tex_desc := MTL.TextureDescriptor_alloc()
        defer tex_desc->release()
        tex_desc->init()
        tex_desc->setPixelFormat(.Depth32Float)
        tex_desc->setUsage({.ShaderRead, .RenderTarget})
        tex_desc->setWidth(2048)
        tex_desc->setHeight(2048)
        // Private since we don't read or write to it on the cpu
        tex_desc->setStorageMode(.Private)
        shadow_texture := rc.device->newTextureWithDescriptor(tex_desc)
        return Shadow_Map{texture=shadow_texture, transform = transform_buffer}
}



write_model_to_shadow_map :: proc(
        model: ^Model,
        rc: ^Render_Context,
        model_transform: ^MTL.Buffer,
        shadow_map: Shadow_Map)
{
        
        rc.draw_stage.encoder->setVertexBuffer(buffer=shadow_map.transform, offset=0, index=5)
        rc.draw_stage.encoder->setVertexBuffer(buffer=model_transform, offset=0, index=4)
        rc.draw_stage.encoder->setVertexBuffer(buffer=model.bone_buffer, offset=0, index=3)
        for mesh in model.meshes {
                rc.draw_stage.encoder->setVertexBuffer(buffer=mesh.buffers.pos, offset=0, index=0)
                rc.draw_stage.encoder->setVertexBuffer(buffer=mesh.buffers.bone_ids, offset=0, index=1)
                rc.draw_stage.encoder->setVertexBuffer(buffer=mesh.buffers.bone_weights, offset=0, index=2)
                rc.draw_stage.encoder->drawIndexedPrimitives(.Triangle, mesh.buffers.index->length()/4, .UInt32, mesh.buffers.index, 0)
        }
}



write_object_to_shadow_map :: proc(
        object: Object,
        rc: ^Render_Context,
        shadow_map: Shadow_Map,
)
{
        // TODO don't recompute the transform buffer
        transform_buffer := rc.device->newBuffer(size_of(matrix[4,4]f32), {.StorageModeManaged})
        transform_data := transform_buffer->contentsAsType(matrix[4,4]f32)
        transform_data^ = object.transform
        transform_buffer->didModifyRange(NS.Range_Make(0, size_of(matrix[4,4]f32)))

        rc.draw_stage.encoder->setVertexBuffer(buffer=shadow_map.transform, offset=0, index=3)
        rc.draw_stage.encoder->setVertexBuffer(buffer=object.mesh.buffers.pos, offset=0, index=0)
        rc.draw_stage.encoder->setVertexBuffer(buffer=transform_buffer, offset=0, index=4)
        rc.draw_stage.encoder->setVertexBuffer(buffer=shadow_map.transform, offset=0, index=5)
        rc.draw_stage.encoder->drawIndexedPrimitives(.Triangle, object.mesh.buffers.index->length()/4, .UInt32, object.mesh.buffers.index, 0)
        

}

write_model_to_color_id :: proc(model: ^Model, model_transform: ^MTL.Buffer, camera_buffer: ^MTL.Buffer, rc: ^Render_Context)
{
        rc.draw_stage.encoder->setVertexBuffer(buffer=camera_buffer, offset=0, index=5)
        rc.draw_stage.encoder->setVertexBuffer(buffer=model_transform, offset=0, index=4)
        rc.draw_stage.encoder->setVertexBuffer(buffer=model.bone_buffer, offset=0, index=3)

        color_buffer := rc.device->newBuffer(size_of([3]f32), {.StorageModeManaged})
        color_data := color_buffer->contentsAsType([3]f32)
        color_data^ = [3]f32{f32(model.color_id.x)/255, f32(model.color_id.y)/255, f32(model.color_id.z)/255}
        color_buffer->didModifyRange(NS.Range_Make(0, size_of([3]f32)))
        defer color_buffer->release()

        rc.draw_stage.encoder->setFragmentBuffer(buffer=color_buffer, offset=0, index=0)
        for mesh in model.meshes {
                rc.draw_stage.encoder->setVertexBuffer(buffer=mesh.buffers.pos, offset=0, index=0)
                rc.draw_stage.encoder->setVertexBuffer(buffer=mesh.buffers.bone_ids, offset=0, index=1)
                rc.draw_stage.encoder->setVertexBuffer(buffer=mesh.buffers.bone_weights, offset=0, index=2)
                rc.draw_stage.encoder->drawIndexedPrimitives(.Triangle, mesh.buffers.index->length()/4, .UInt32, mesh.buffers.index, 0)
        }
}

write_object_to_color_id :: proc(object: Object, camera_buffer: ^MTL.Buffer, rc: ^Render_Context)
{
        transform_buffer := rc.device->newBuffer(size_of(matrix[4,4]f32), {.StorageModeManaged})
        transform_data := transform_buffer->contentsAsType(matrix[4,4]f32)
        transform_data^ = object.transform
        transform_buffer->didModifyRange(NS.Range_Make(0, size_of(matrix[4,4]f32)))
        defer transform_buffer->release()

        color_buffer := rc.device->newBuffer(size_of([3]f32), {.StorageModeManaged})
        color_data := color_buffer->contentsAsType([3]f32)
        color_data^ = [3]f32{f32(object.color_id.x)/255, f32(object.color_id.y)/255, f32(object.color_id.z)/255}
        color_buffer->didModifyRange(NS.Range_Make(0, size_of([3]f32)))
        defer color_buffer->release()

        rc.draw_stage.encoder->setFragmentBuffer(buffer=color_buffer, offset=0, index=0)
        rc.draw_stage.encoder->setVertexBuffer(buffer=camera_buffer, offset=0, index=1)
        rc.draw_stage.encoder->setVertexBuffer(buffer=object.mesh.buffers.pos, offset=0, index=0)
        rc.draw_stage.encoder->setVertexBuffer(buffer=transform_buffer, offset=0, index=4)
        rc.draw_stage.encoder->drawIndexedPrimitives(.Triangle, object.mesh.buffers.index->length()/4, .UInt32, object.mesh.buffers.index, 0)
}

build_light_buffers :: proc(lights: #soa[]Light, rc: ^Render_Context
) -> ^MTL.Buffer
{
        pos_buffer: ^MTL.Buffer
        col_buffer: ^MTL.Buffer
        if (len(lights) == 0) {
                pos_buffer = rc.device->newBufferWithLength(1, {.StorageModeManaged})
                col_buffer = rc.device->newBufferWithLength(1, {.StorageModeManaged})
        } else {
                pos, col, _ := soa_unzip(lights[:])
                pos_buffer = rc.device->newBufferWithSlice(pos, {.StorageModeManaged})
                col_buffer = rc.device->newBufferWithSlice(col, {.StorageModeManaged})
        }
        Light_Buffer :: struct #align(16) {
                // u64 to hold GPU addresses
                pos: u64,
                col: u64,
                n_lights: i32,
        }
        light_arg_buffer := rc.device->newBufferWithLength(size_of(Light_Buffer), {.StorageModeManaged})
        arg_buffer := light_arg_buffer->contentsAsType(Light_Buffer)
        arg_buffer.pos = pos_buffer->gpuAddress()
        arg_buffer.col = col_buffer->gpuAddress()
        arg_buffer.n_lights = i32(len(lights))
        light_arg_buffer->didModifyRange(NS.Range_Make(0, size_of(Light_Buffer)))
        return light_arg_buffer
}



new_encoder :: proc(rc: ^Render_Context, options: Render_Pass_Options)
{
        depth_desc := MTL.DepthStencilDescriptor.alloc()->init()
        defer depth_desc->release()
	depth_desc->setDepthCompareFunction(options.depth_descriptor_compare_function)
	depth_desc->setDepthWriteEnabled(options.depth_descriptor_write_enabled)
	depth_stencil_state := MTL.Device_newDepthStencilState(rc.device, depth_desc)

        rc.draw_stage.encoder = rc.draw_stage.command_buffer->renderCommandEncoderWithDescriptor(rc.draw_stage.pass)
        rc.draw_stage.encoder->setDepthStencilState(depth_stencil_state)
        rc.draw_stage.encoder->setCullMode(options.cull_mode)
        rc.draw_stage.encoder->setFrontFacingWinding(options.front_facing_winding)
        if options.depth_bias > 0 {
                rc.draw_stage.encoder->setDepthBias(options.depth_bias, options.slope_scaled_depth_bias, options.depth_bias_clamp) 
        }
}



clear_shadow_map :: proc(rc: ^Render_Context) 
{       
        rc.shadow_map.texture->release()
        tex_desc := MTL.TextureDescriptor_alloc()
        defer tex_desc->release()
        tex_desc->init()
        tex_desc->setPixelFormat(.Depth32Float)
        tex_desc->setWidth(10)
        tex_desc->setHeight(10)
        // Private since we don't read or write to it on the cpu
        tex_desc->setStorageMode(.Private)
        rc.shadow_map.texture = rc.device->newTextureWithDescriptor(tex_desc)
}