const std = @import("std");
const vk = @import("vulkan");

pub const MAX_SET_COUNT = 100;
pub const MAX_SPIRV_IDS = 4096;

const SPIRV_MAGIC = 0x07230203;

pub const SpirvParseResult = struct {
    set_count: u32,
    sets: [MAX_SET_COUNT]DescriptorSetLayoutCreation,
};

pub const DescriptorSetLayoutCreation = struct {
    pub const Binding = struct {
        binding: u32,
        count: u32,
        type: vk.DescriptorType,
    };

    set_index: u32,
    binding_count: u32,
    bindings: [32]Binding,
};

const SpirvOpcode = enum(u16) {
    type_int = 21,
    type_image = 25,
    type_sampler = 26,
    type_sampled_image = 27,
    type_array = 28,
    type_runtime_array = 29,
    type_struct = 30,
    type_pointer = 32,
    constant = 43,
    variable = 59,
    decorate = 71,
    _,
};

const SpirvDecoration = enum(u32) {
    block = 2,
    buffer_block = 3,
    binding = 33,
    descriptor_set = 34,
    _,
};

const SpirvStorageClass = enum(u32) {
    uniform_constant = 0,
    uniform = 2,
    storage_buffer = 12,
    _,
};

const SpirvInstruction = packed struct(u32) {
    opcode: SpirvOpcode,
    word_count: u16,

    pub fn fromInt(int: u32) SpirvInstruction {
        return @bitCast(int);
    }
};

const IdState = struct {
    opcode: SpirvOpcode = undefined,
    type_id: u32 = 0,
    length_id: u32 = 0,
    constant_value: u32 = 0,
    set: ?u32 = null,
    binding: ?u32 = null,
    is_block: bool = false,
    is_buffer_block: bool = false,
    dim: u32 = 0,
    sampled: u32 = 0,
};

const ShaderType = enum(c_int) {
    vertex = 0,
    fragment = 1,
    compute = 2,
    geometry = 3,
    tess_control = 4,
    tess_evaluation = 5,
    infer_from_source = 6,
    default_vertex = 7,
    default_fragment = 8,
    default_compute = 9,
    default_geometry = 10,
    default_tess_control = 11,
    default_tess_evaluation = 12,
};

pub fn parseSpirv(shader_bytes: []const u8) !SpirvParseResult {
    if (shader_bytes.len % 4 != 0) {
        return error.InvalidSpirv;
    }

    const shader_words = std.mem.bytesAsSlice(u32, shader_bytes);

    if (shader_words.len < 5 or shader_words[0] != SPIRV_MAGIC) {
        return error.InvalidSpirv;
    }

    const id_bound = shader_words[3];

    if (id_bound > MAX_SPIRV_IDS) {
        return error.SpirvIdLimitExceeded;
    }

    var ids_buffer: [MAX_SPIRV_IDS]IdState = undefined;
    const ids = ids_buffer[0..id_bound];
    @memset(ids, .{});

    var parse_result = SpirvParseResult{
        .set_count = 0,
        .sets = undefined,
    };

    var i: usize = 5;

    if (@inComptime())
        @setEvalBranchQuota(shader_words.len);

    while (i < shader_words.len) {
        const instruction = SpirvInstruction.fromInt(shader_words[i]);
        if (instruction.word_count == 0) return error.InvalidSpirv;

        const operands = shader_words[i + 1 .. i + instruction.word_count];

        switch (instruction.opcode) {
            .decorate => {
                const target_id = operands[0];
                const decoration: SpirvDecoration = @enumFromInt(operands[1]);

                switch (decoration) {
                    .descriptor_set => ids[target_id].set = operands[2],
                    .binding => ids[target_id].binding = operands[2],
                    .block => ids[target_id].is_block = true,
                    .buffer_block => ids[target_id].is_buffer_block = true,
                    _ => {},
                }
            },
            .constant => {
                const result_id = operands[1];
                ids[result_id].opcode = .constant;
                ids[result_id].constant_value = operands[2];
            },
            .type_array => {
                const result_id = operands[0];
                ids[result_id].opcode = .type_array;
                ids[result_id].type_id = operands[1];
                ids[result_id].length_id = operands[2];
            },
            .type_runtime_array => {
                const result_id = operands[0];
                ids[result_id].opcode = .type_runtime_array;
                ids[result_id].type_id = operands[1];
            },

            .type_image => {
                const result_id = operands[0];
                ids[result_id].opcode = .type_image;
                ids[result_id].dim = operands[2];
                if (operands.len >= 7) {
                    ids[result_id].sampled = operands[6];
                }
            },
            .type_sampled_image => {
                const result_id = operands[0];
                ids[result_id].opcode = .type_sampled_image;
                ids[result_id].type_id = operands[1];
            },

            .type_struct, .type_sampler => {
                const result_id = operands[0];
                ids[result_id].opcode = instruction.opcode;
            },

            .type_pointer => {
                const result_id = operands[0];
                ids[result_id].opcode = .type_pointer;
                ids[result_id].type_id = operands[2];
            },

            .variable => {
                const result_type_id = operands[0];
                const result_id = operands[1];
                const storage_class: SpirvStorageClass = @enumFromInt(operands[2]);

                if (ids[result_id].set) |set_index| {
                    if (ids[result_id].binding) |binding| {
                        var desc_type: vk.DescriptorType = .uniform_buffer;
                        var count: u32 = 1;

                        const ptr_state = ids[result_type_id];
                        if (ptr_state.opcode == .type_pointer) {
                            var base_state = ids[ptr_state.type_id];

                            // Unwrap arrays
                            if (base_state.opcode == .type_array) {
                                count = ids[base_state.length_id].constant_value;
                                base_state = ids[base_state.type_id];
                            } else if (base_state.opcode == .type_runtime_array) {
                                count = 0; // Bindless arrays detected!
                                base_state = ids[base_state.type_id];
                            }

                            // Determine Vulkan Descriptor Type
                            switch (storage_class) {
                                .uniform => {
                                    // Vulkan 1.0 quirk: SSBOs and UBOs are both "uniform" storage class.
                                    // Differentiate them using the struct's decoration.
                                    if (base_state.is_buffer_block) {
                                        desc_type = .storage_buffer;
                                    } else {
                                        desc_type = .uniform_buffer;
                                    }
                                },
                                .storage_buffer => desc_type = .storage_buffer, // Vulkan 1.1+ behavior
                                .uniform_constant => {
                                    switch (base_state.opcode) {
                                        .type_sampled_image => desc_type = .combined_image_sampler,
                                        .type_image => desc_type = .storage_image,
                                        .type_sampler => desc_type = .sampler,
                                        else => {},
                                    }
                                },
                                else => {},
                            }
                        }

                        // --- Group bindings into the correct Set ---
                        var target_set_idx: ?usize = null;

                        for (0..parse_result.set_count) |s| {
                            if (parse_result.sets[s].set_index == set_index) {
                                target_set_idx = s;
                                break;
                            }
                        }

                        if (target_set_idx == null) {
                            if (parse_result.set_count >= parse_result.sets.len) {
                                return error.TooManyDescriptorSets;
                            }
                            target_set_idx = parse_result.set_count;
                            parse_result.sets[target_set_idx.?] = .{
                                .set_index = set_index,
                                .binding_count = 0,
                                .bindings = undefined,
                            };
                            parse_result.set_count += 1;
                        }

                        var set_ref = &parse_result.sets[target_set_idx.?];
                        if (set_ref.binding_count >= set_ref.bindings.len) {
                            return error.TooManyBindingsInSet;
                        }

                        set_ref.bindings[set_ref.binding_count] = .{
                            .binding = binding,
                            .count = count,
                            .type = desc_type,
                        };
                        set_ref.binding_count += 1;
                    }
                }
            },
            .type_int, _ => {},
        }

        i += instruction.word_count;
    }

    return parse_result;
}

test "SPIR-V Parser" {
    const spv_bytes align(4) = @import("assets").shaders.text_frag;

    const spv_slice: []align(4) const u8 = @alignCast(spv_bytes[0..]);

    var parse_result = try parseSpirv(spv_slice);

    std.sort.heap(DescriptorSetLayoutCreation, parse_result.sets[0..parse_result.set_count], {}, struct {
        fn lessThan(_: void, a: DescriptorSetLayoutCreation, b: DescriptorSetLayoutCreation) bool {
            return a.set_index < b.set_index;
        }
    }.lessThan);

    // const expected_sets = [_]DescriptorSetLayoutCreation{
    //     .{
    //         .set_index = 0,
    //         .binding_count = 255,
    //         .bindings = [1]DescriptorSetLayoutCreation.Binding{
    //             .{ .binding = 0, .count = 1, .type = .sampled_image },
    //         } ** 32,
    //     },
    // };
    //
    // try std.testing.expectEqualSlices(
    //     DescriptorSetLayoutCreation,
    //     parse_result.sets[0..parse_result.set_count],
    //     expected_sets[0..],
    // );
}
