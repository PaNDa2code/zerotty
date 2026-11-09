const std = @import("std");

pub const Image2D = @SpirvType(.{ .image = .{
    .usage = .{ .sampled = f32 },
    .format = .unknown,
    .dim = .@"2d",
    .depth = .unknown,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });

pub const Sampler2D = @SpirvType(.{ .sampled_image = Image2D });

pub inline fn texelFetch(sampled_image: anytype, coord: @Vector(2, u32), lod: u32) @Vector(4, f32) {
    const SampledImage = switch (@typeInfo(@TypeOf(sampled_image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to a sampled image"),
    };

    const Image = switch (@typeInfo(SampledImage)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |image| image,
            else => @compileError("expected a sampled image type"),
        },
        else => @compileError("expected a sampled image type"),
    };

    return asm volatile (
        \\%loaded_sampled_image = OpLoad %SampledImage %sampled_image
        \\%image = OpImage %Image %loaded_sampled_image
        \\%ret = OpImageFetch %Vec4 %image %coord Lod %lod
        : [ret] "" (-> @Vector(4, f32)),
        : [SampledImage] "t" (SampledImage),
          [Image] "t" (Image),
          [Vec4] "t" (@Vector(4, f32)),
          [sampled_image] "" (sampled_image),
          [coord] "" (coord),
          [lod] "" (lod),
    );
}

/// Optimize to use GPUs BFE hardware
pub inline fn bitfieldExtractFromU32(
    value: u32,
    offset: u5,
    comptime bits: u16,
    comptime signedness: std.lang.Signedness,
) @Int(signedness, bits) {
    const offset_u32: u32 = offset;
    const bits_u32: u32 = bits;

    return switch (signedness) {
        .unsigned => @truncate(asm ("%ret = OpBitFieldUExtract %ty %value %offset %bits"
            : [ret] "" (-> u32),
            : [ty] "t" (u32),
              [value] "r" (value),
              [offset] "r" (offset_u32),
              [bits] "" (bits_u32),
        )),
        .signed => @truncate(asm ("%ret = OpBitFieldSExtract %ty %value %offset %bits"
            : [ret] "" (-> i32),
            : [ty] "t" (i32),
              [value] "r" (@as(i32, @bitCast(value))),
              [offset] "r" (offset_u32),
              [bits] "" (bits_u32),
        )),
    };
}
