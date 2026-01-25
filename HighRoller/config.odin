package HighRoller

DISABLE_DOCKING :: #config(DISABLE_DOCKING, false)

default_shader_options :: Shader_Options{
        pixel_format =                          .RGBA8Unorm,
        blending_enabled =                      true,
        rgb_blend_operation =                   .Add,
        alpha_blend_operation =                 .Add,
        source_rgb_blend_operation =            .SourceAlpha,
        source_alpha_blend_operation =          .SourceAlpha,
        destination_rgb_blend_operation =       .OneMinusSourceAlpha,
        destination_alpha_blend_operation =     .OneMinusSourceAlpha,
        depth_attachment_pixel_format =         .Depth16Unorm,
}

shadow_shader_options :: Shader_Options{
        pixel_format =                  .Invalid,
        blending_enabled =              false,
        depth_attachment_pixel_format = .Depth32Float
}

default_render_pass_options :: Render_Pass_Options{
        color_attachment_load_action =          .Clear,
        color_attachment_store_action =         .Store,
        depth_attachment_clear_depth =          1.0,
        depth_attachment_load_action =          .Clear,
        depth_attachment_store_action =         .Store,
        depth_descriptor_write_enabled =        true,
        depth_descriptor_compare_function =     .Less,
        cull_mode =                             .Back,
        front_facing_winding =                  .CounterClockwise,
        with_color_attachment =                 true,

}

shadow_render_pass_options :: Render_Pass_Options{
        depth_attachment_clear_depth =          1.0,
        depth_attachment_load_action =          .Clear,
        depth_attachment_store_action =         .Store,
        depth_descriptor_write_enabled =        true,
        depth_descriptor_compare_function =     .Less,
        cull_mode =                             .Front,
        front_facing_winding =                  .CounterClockwise,
        with_color_attachment =                 false,
        depth_bias =                            4.0,
        slope_scaled_depth_bias =               1.1,
        depth_bias_clamp =                      0
}


CUBE_VERTICES :: [?][3]f32 {
		// Positions
		{-1.0, -1.0, +1.0},
		{+1.0, -1.0, +1.0},
		{+1.0, +1.0, +1.0},
		{-1.0, +1.0, +1.0},

		{+1.0, -1.0, +1.0},
		{+1.0, -1.0, -1.0},
		{+1.0, +1.0, -1.0},
		{+1.0, +1.0, +1.0},

		{+1.0, -1.0, -1.0},
		{-1.0, -1.0, -1.0},
		{-1.0, +1.0, -1.0},
		{+1.0, +1.0, -1.0},

		{-1.0, -1.0, -1.0},
		{-1.0, -1.0, +1.0},
		{-1.0, +1.0, +1.0},
		{-1.0, +1.0, -1.0},

		{-1.0, +1.0, +1.0},
	        {+1.0, +1.0, +1.0},
		{+1.0, +1.0, -1.0},
		{-1.0, +1.0, -1.0},

		{-1.0, -1.0, -1.0},
		{+1.0, -1.0, -1.0},
		{+1.0, -1.0, +1.0},
		{-1.0, -1.0, +1.0},
}

CROSSHAIR_VERTICES :: [?][3]f32 {
        {-1.0, -1.0, 0.0},
	{+1.0, -1.0, 0.0},
        {+1.0, +1.0, 0.0},
        {-1.0, +1.0, 0.0},
}

CROSSHAIR_INDICES :: [?]i32 {
        2, 0, 1, 2, 3, 0
}