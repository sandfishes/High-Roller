package HighRoller

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "vendor:glfw"
import glm "core:math/linalg/glsl"

draw_box_DEBUG :: proc(camera: Camera, rc: ^Render_Context, pos: [3]f32, col: [3]f32, ambient: f32, width: f32, shadow_map: ^MTL.Texture, light_view: matrix[4,4]f32)
{
        // Set up camera buffer
        camera_buffer := rc.device->newBuffer(size_of(Camera), {.StorageModeManaged})
	defer camera_buffer->release()
        camera_data := camera_buffer->contentsAsType(Camera)
        camera_data.world_transform = camera.world_transform
        camera_data.view_transform = camera.view_transform
        camera_data.perspective_transform = camera.perspective_transform
        camera_data.normal_transform = camera.normal_transform
        camera_data.pos = camera.pos
        camera_buffer->didModifyRange(NS.Range_Make(0, size_of(Camera)))

        Vertex_Data :: struct {
                pos: [3]f32,
                norm: [3]f32,
        }
        s := width
	positions := []Vertex_Data{
		// Positions      Normals
		{{-s, -s, +s}, {0,  0,  1}},
		{{+s, -s, +s}, {0,  0,  1}},
		{{+s, +s, +s}, {0,  0,  1}},
		{{-s, +s, +s}, {0,  0,  1}},
		{{+s, -s, +s}, {1,  0,  0}},
		{{+s, -s, -s}, {1,  0,  0}},
		{{+s, +s, -s}, {1,  0,  0}},
		{{+s, +s, +s}, {1,  0,  0}},
		{{+s, -s, -s}, {0,  0, -1}},
		{{-s, -s, -s}, {0,  0, -1}},
		{{-s, +s, -s}, {0,  0, -1}},
		{{+s, +s, -s}, {0,  0, -1}},

		{{-s, -s, -s}, {-1, 0,  0}},
		{{-s, -s, +s}, {-1, 0,  0}},
		{{-s, +s, +s}, {-1, 0,  0}},
		{{-s, +s, -s}, {-1, 0,  0}},

		{{-s, +s, +s}, {0,  1,  0}},
		{{+s, +s, +s}, {0,  1,  0}},
		{{+s, +s, -s}, {0,  1,  0}},
		{{-s, +s, -s}, {0,  1,  0}},

		{{-s, -s, -s}, {0, -1,  0}},
		{{+s, -s, -s}, {0, -1,  0}},
		{{+s, -s, +s}, {0, -1,  0}},
		{{-s, -s, +s}, {0, -1,  0}},
	}
	indices := []u32{
		 0,  1,  2,  2,  3,  0, // front
		 4,  5,  6,  6,  7,  4, // right
		 8,  9, 10, 10, 11,  8, // back
		12, 13, 14, 14, 15, 12, // left
		16, 17, 18, 18, 19, 16, // top
		20, 21, 22, 22, 23, 20, // bottom
	}

	vertex_buffer := rc.device->newBufferWithSlice(positions[:], {.StorageModeManaged})
        vertex_buffer->didModifyRange(NS.Range_Make(0, vertex_buffer->length()))
        defer vertex_buffer->release()
	index_buffer := rc.device->newBufferWithSlice(indices[:],   {.StorageModeManaged})
        index_buffer->didModifyRange(NS.Range_Make(0, index_buffer->length()))
        defer index_buffer->release()
        translate := glm.mat4Translate(pos);
        Arg_Buffer :: struct {
                transform: matrix[4,4]f32,
                light_view: matrix[4,4]f32,
                color: [3]f32,
                ambient: f32,
        }
        arg_buffer := rc.device->newBuffer(size_of(Arg_Buffer), {.StorageModeManaged})
	defer arg_buffer->release()
        arg_data := arg_buffer->contentsAsType(Arg_Buffer)
        arg_data.transform = translate
        arg_data.light_view = light_view
        arg_data.color = col
        arg_data.ambient = ambient
        arg_buffer->didModifyRange(NS.Range_Make(0, size_of(Arg_Buffer)))

        rc.draw_stage.encoder->setVertexBuffer(buffer=vertex_buffer, offset=0, index=0)
        rc.draw_stage.encoder->setVertexBuffer(buffer=arg_buffer, offset=0, index=1)
        rc.draw_stage.encoder->setVertexBuffer(buffer=camera_buffer, offset=0, index=2)
        rc.draw_stage.encoder->setFragmentBuffer(buffer=camera_buffer, offset=0, index=0)
        rc.draw_stage.encoder->setFragmentBuffer(buffer=arg_buffer, offset=0, index=1)
        rc.draw_stage.encoder->setFragmentBuffer(buffer=camera_buffer, offset=0, index=2)
        rc.draw_stage.encoder->setFragmentTexture(shadow_map, 0)
        rc.draw_stage.encoder->drawIndexedPrimitives(.Triangle, index_buffer->length()/4, .UInt32, index_buffer, 0)
}
