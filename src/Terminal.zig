const Terminal = @This();

pty: Pty,
shell: ChildProcess, 
scroll_buffer: Scrollback,

const Pty = @import("pty").Pty;
const ChildProcess = @import("ChildProcess");
const Scrollback = @import("Scrollback.zig");
