//! Custom SQLite memory allocator that routes through enif_alloc/enif_free/enif_realloc.
//! Stores the requested size in a size_t header before each allocation so that
//! xSize() can return it without an extra bookkeeping structure.

const nif = @import("nif.zig");
const sqlite3 = @import("sqlite3.zig");

// Saved default allocator, restored in on_unload.
var default_alloc_methods: sqlite3.MemMethods = .{
    .xMalloc = null,
    .xFree = null,
    .xRealloc = null,
    .xSize = null,
    .xRoundup = null,
    .xInit = null,
    .xShutdown = null,
    .pAppData = null,
};

pub fn exqlite_malloc(bytes: c_int) callconv(nif.c_call) ?*anyopaque {
    if (bytes <= 0) return null;
    const total: usize = @intCast(bytes);
    const p: ?[*]usize = @ptrCast(@alignCast(nif.alloc(total + @sizeOf(usize))));
    if (p) |ptr| {
        ptr[0] = total;
        return @ptrCast(ptr + 1);
    }
    return null;
}

pub fn exqlite_free(prior: ?*anyopaque) callconv(nif.c_call) void {
    if (prior == null) return;
    const p: [*]usize = @ptrCast(@alignCast(prior));
    nif.free(@ptrCast(p - 1));
}

pub fn exqlite_realloc(prior: ?*anyopaque, bytes: c_int) callconv(nif.c_call) ?*anyopaque {
    if (prior == null or bytes <= 0) return null;
    const total: usize = @intCast(bytes);
    const p: [*]usize = @ptrCast(@alignCast(prior));
    const base: ?[*]usize = @ptrCast(@alignCast(nif.realloc(@ptrCast(p - 1), total + @sizeOf(usize))));
    if (base) |ptr| {
        ptr[0] = total;
        return @ptrCast(ptr + 1);
    }
    return null;
}

pub fn exqlite_mem_size(prior: ?*anyopaque) callconv(nif.c_call) c_int {
    if (prior == null) return 0;
    const p: [*]usize = @ptrCast(@alignCast(prior));
    return @intCast((p - 1)[0]);
}

pub fn exqlite_mem_round_up(bytes: c_int) callconv(nif.c_call) c_int {
    return (bytes + 7) & ~@as(c_int, 7);
}

fn exqlite_mem_init(ptr: ?*anyopaque) callconv(nif.c_call) c_int {
    _ = ptr;
    return sqlite3.OK;
}

fn exqlite_mem_shutdown(ptr: ?*anyopaque) callconv(nif.c_call) void {
    _ = ptr;
}

const methods: sqlite3.MemMethods = .{
    .xMalloc = exqlite_malloc,
    .xFree = exqlite_free,
    .xRealloc = exqlite_realloc,
    .xSize = exqlite_mem_size,
    .xRoundup = exqlite_mem_round_up,
    .xInit = exqlite_mem_init,
    .xShutdown = exqlite_mem_shutdown,
    .pAppData = null,
};

pub fn install() bool {
    if (sqlite3.c.sqlite3_config(sqlite3.CONFIG_GETMALLOC, &default_alloc_methods) != sqlite3.OK) return false;
    if (sqlite3.c.sqlite3_config(sqlite3.CONFIG_MALLOC, &methods) != sqlite3.OK) return false;
    return true;
}

pub fn restore() void {
    _ = sqlite3.c.sqlite3_config(sqlite3.CONFIG_MALLOC, &default_alloc_methods);
}
