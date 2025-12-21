const Interface = @This();

pub const VTable = struct {};

ptr: *anyopaque,
vtable: VTable,
