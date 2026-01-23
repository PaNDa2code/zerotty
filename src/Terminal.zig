const Terminal = @This();

pty: Pty,
shell: ChildProcess, 
scroll_buffer: Scrollback,

const Pty = @import("pty/root.zig").Pty;
const ChildProcess = @import("ChildProcess.zig");
const Scrollback = @import("Scrollback.zig");
