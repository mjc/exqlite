//! Term construction utilities shared across connection.zig, statement.zig, callbacks.zig.

const std = @import("std");
const nif = @import("nif.zig");
const sqlite3 = @import("sqlite3.zig");
const atoms = @import("atoms.zig");

pub fn make_ok_tuple(env: *nif.Env, value: nif.Term) nif.Term {
    return nif.make_tuple2(env, atoms.a.ok, value);
}

pub fn make_error_tuple(env: *nif.Env, reason: nif.Term) nif.Term {
    return nif.make_tuple2(env, atoms.a.@"error", reason);
}

/// Copy `bytes` into a new Erlang binary term. Returns `out_of_memory` atom on failure.
/// Note: do NOT call enif_release_binary after enif_make_binary (OTP docs).
pub fn make_binary_from_slice(env: *nif.Env, bytes: []const u8) nif.Term {
    var bin = nif.alloc_binary(bytes.len) orelse return atoms.a.out_of_memory;
    @memcpy(bin.data[0..bytes.len], bytes);
    return nif.make_binary(env, &bin);
}

/// Convert a C string (from @cImport) to an Erlang binary term.
/// Returns the `nil` atom if `c_str` is null.
pub fn make_binary_from_c_str(env: *nif.Env, c_str: [*c]const u8) nif.Term {
    if (c_str == null) return atoms.a.nil;
    const ptr: [*:0]const u8 = @ptrCast(c_str);
    return make_binary_from_slice(env, ptr[0..std.mem.len(ptr)]);
}

/// Build `{:error, "<errmsg>"}` from a SQLite result code + db handle.
pub fn make_sqlite3_error_tuple(env: *nif.Env, rc: c_int, db: ?*sqlite3.Database) nif.Term {
    const msg: [*:0]const u8 = blk: {
        if (rc == sqlite3.MISUSE) break :blk "Sqlite3 was invoked incorrectly.";
        if (db) |d| {
            const m = sqlite3.c.sqlite3_errmsg(d);
            if (m != null) break :blk @as([*:0]const u8, @ptrCast(m));
        }
        break :blk "No error message available.";
    };
    const len = std.mem.len(msg);
    return make_error_tuple(env, make_binary_from_slice(env, msg[0..len]));
}

pub fn raise_badarg(env: *nif.Env, term: nif.Term) nif.Term {
    const reason = nif.make_tuple2(env, atoms.a.badarg, term);
    return nif.raise_exception(env, reason);
}

/// Build an iolist term that has a NUL byte appended, then inspect as binary.
/// Returns the resulting binary (with NUL at the end) so callers can cast .data to [*:0]u8.
pub fn iolist_to_nul_binary(env: *nif.Env, term: nif.Term) ?nif.Binary {
    const eos = nif.make_int(env, 0);
    const list = nif.c.enif_make_list2(env, term, eos);
    return nif.inspect_iolist_as_binary(env, list);
}

/// Stack-or-heap Term buffer. Uses a 64-element stack array for small counts,
/// falls back to enif_alloc for larger ones.
pub const TermBuffer = struct {
    stack: [64]nif.Term = undefined,
    heap: ?[*]nif.Term = null,
    len: usize,

    pub fn init(count: usize) ?TermBuffer {
        var buf = TermBuffer{ .len = count };
        if (count > 64) {
            const raw = nif.alloc(count * @sizeOf(nif.Term)) orelse return null;
            buf.heap = @ptrCast(@alignCast(raw));
        }
        return buf;
    }

    pub fn deinit(self: *TermBuffer) void {
        if (self.heap) |h| nif.free(@ptrCast(h));
    }

    pub fn slice(self: *TermBuffer) []nif.Term {
        if (self.heap) |h| return h[0..self.len];
        return self.stack[0..self.len];
    }
};

/// Build an Erlang binary from a nullable column data pointer and byte count.
fn make_column_binary(env: *nif.Env, ptr: ?*const anyopaque, sz: c_int) nif.Term {
    if (ptr == null or sz <= 0) return make_binary_from_slice(env, &.{});
    const bytes: []const u8 = @as([*]const u8, @ptrCast(ptr))[0..@intCast(sz)];
    return make_binary_from_slice(env, bytes);
}

/// Build a single cell (column value) from a sqlite3 statement.
pub fn make_cell(env: *nif.Env, stmt: *sqlite3.Stmt, i: c_int) nif.Term {
    return switch (sqlite3.c.sqlite3_column_type(stmt, i)) {
        sqlite3.INTEGER => nif.make_int64(env, sqlite3.c.sqlite3_column_int64(stmt, i)),
        sqlite3.FLOAT => nif.make_double(env, sqlite3.c.sqlite3_column_double(stmt, i)),
        sqlite3.NULL => atoms.a.nil,
        sqlite3.BLOB => make_column_binary(env, sqlite3.c.sqlite3_column_blob(stmt, i), sqlite3.c.sqlite3_column_bytes(stmt, i)),
        sqlite3.TEXT => make_column_binary(env, @ptrCast(sqlite3.c.sqlite3_column_text(stmt, i)), sqlite3.c.sqlite3_column_bytes(stmt, i)),
        else => atoms.a.nil,
    };
}

/// Build an Erlang list from one row of sqlite3 results.
pub fn make_row(env: *nif.Env, stmt: *sqlite3.Stmt) nif.Term {
    const count: usize = @intCast(sqlite3.c.sqlite3_column_count(stmt));
    var buf = TermBuffer.init(count) orelse
        return make_error_tuple(env, atoms.a.out_of_memory);
    defer buf.deinit();
    const columns = buf.slice();

    for (0..count) |i| {
        columns[i] = make_cell(env, stmt, @intCast(i));
    }

    return nif.make_list(env, @intCast(count), columns.ptr);
}
