//! Allows Vulkan to use Zig's memory management via adapter style callbacks.
//! Provides a `VkAllocationCallbacks` using Zig's `Allocator`.

// TODO: store allocation data without extra map
const Record = struct {
    size: usize,
    alignment: std.mem.Alignment,
};
const RecordMap = std.AutoHashMapUnmanaged(usize, Record);

const VkAllocatorAdapter = @This();

allocator: Allocator,
record_map: RecordMap = .empty,

pub fn create(allocator: Allocator) VkAllocatorAdapter {
    return .{
        .allocator = allocator,
    };
}

pub fn destroy(self: *VkAllocatorAdapter) void {
    // var iter = self.record_map.iterator();
    // while (iter.next()) |entry| {
    //     const ptr: [*]u8 = @ptrFromInt(entry.key_ptr.*);
    //     const block = ptr[0..entry.value_ptr.size];
    //     self.allocator.vtable.free(
    //         self.allocator.ptr,
    //         block,
    //         entry.value_ptr.alignment,
    //         @returnAddress(),
    //     );
    // }
    self.record_map.deinit(self.allocator);
}

pub fn vkAllocatorCallbacks(self: *VkAllocatorAdapter) vk.AllocationCallbacks {
    return .{
        .p_user_data = self,
        .pfn_allocation = VkAllocatorAdapter.vkAlloc,
        .pfn_reallocation = VkAllocatorAdapter.vkRealloc,
        .pfn_free = VkAllocatorAdapter.vkFree,
    };
}

fn allocAndRecord(
    allocator: Allocator,
    record_map: *RecordMap,
    size: usize,
    alignment: std.mem.Alignment,
) ?[*]u8 {
    const buf = allocator.vtable.alloc(allocator.ptr, size, alignment, @returnAddress()) orelse return null;
    record_map.put(
        allocator,
        @intFromPtr(buf),
        .{ .size = size, .alignment = alignment },
    ) catch {
        allocator.vtable.free(allocator.ptr, buf[0..size], alignment, @returnAddress());
        return null;
    };
    return buf;
}

fn freeRecored(
    allocator: Allocator,
    record_map: *RecordMap,
    ptr: *anyopaque,
) void {
    const record_entry = record_map.fetchRemove(@intFromPtr(ptr)) orelse return;
    const block = @as([*]u8, @ptrCast(ptr))[0..record_entry.value.size];
    allocator.vtable.free(allocator.ptr, block, record_entry.value.alignment, @returnAddress());
}

fn vkAlloc(
    p_user_data: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: vk.SystemAllocationScope,
) callconv(.c) ?*anyopaque {
    _ = allocation_scope;
    if (p_user_data == null or size == 0)
        return null;

    const vk_allocator: *VkAllocatorAdapter = @alignCast(@ptrCast(p_user_data.?));

    const alignment_enum = std.mem.Alignment.fromByteUnits(alignment);

    return VkAllocatorAdapter.allocAndRecord(vk_allocator.allocator, &vk_allocator.record_map, size, alignment_enum);
}

fn vkFree(
    p_user_data: ?*anyopaque,
    memory: ?*anyopaque,
) callconv(.c) void {
    if (p_user_data == null or memory == null)
        return;

    const vk_allocator: *VkAllocatorAdapter = @alignCast(@ptrCast(p_user_data));
    VkAllocatorAdapter.freeRecored(vk_allocator.allocator, &vk_allocator.record_map, memory.?);
}

fn vkRealloc(
    p_user_data: ?*anyopaque,
    p_original: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: vk.SystemAllocationScope,
) callconv(.c) ?*anyopaque {
    _ = allocation_scope;
    if (p_user_data == null or p_original == null or size == 0)
        return null;

    const vk_allocator: *VkAllocatorAdapter = @alignCast(@ptrCast(p_user_data));
    const allocator = vk_allocator.allocator;

    const old_record_ptr = vk_allocator.record_map.getPtr(@intFromPtr(p_original.?)) orelse return null;
    const new_alignment = std.mem.Alignment.fromByteUnits(alignment);
    const old_block = @as([*]u8, @ptrCast(p_original.?))[0..old_record_ptr.size];

    var new: ?[*]u8 = null;

    if (allocator.vtable.resize(
        allocator.ptr,
        old_block,
        new_alignment,
        size,
        @returnAddress(),
    )) {
        new = old_block.ptr;
        old_record_ptr.size = size;
        old_record_ptr.alignment = new_alignment;
    }

    if (new == null) {
        new = VkAllocatorAdapter.allocAndRecord(allocator, &vk_allocator.record_map, size, new_alignment);

        const bytes_to_copy = @min(size, old_block.len);
        @memcpy(new.?[0..bytes_to_copy], old_block[0..bytes_to_copy]);

        VkAllocatorAdapter.freeRecored(allocator, &vk_allocator.record_map, p_original.?);
    }

    return new;
}

const std = @import("std");
const vk = @import("vulkan");
const Allocator = std.mem.Allocator;

test {
    var vk_allocator = VkAllocatorAdapter.create(std.testing.allocator);
    defer vk_allocator.destroy();

    const callbacks = vk_allocator.vkAllocatorCallbacks();

    var size: usize = 0;
    var rand = std.Random.DefaultPrng.init(std.testing.random_seed);

    var ptrs: [1000]?*anyopaque = undefined;
    for (0..ptrs.len) |i| {
        size = rand.random().uintAtMost(usize, 1024 * 1024);
        ptrs[i] = callbacks.pfn_allocation.?(callbacks.p_user_data, size, 8, .command);
    }
    for (ptrs) |ptr| {
        callbacks.pfn_free.?(callbacks.p_user_data, ptr);
    }
}
