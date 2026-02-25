//! SQLite update_hook and log_hook callbacks, plus the NIF functions that register them.

const std = @import("std");
const nif = @import("nif.zig");
const sqlite3 = @import("sqlite3.zig");
const atoms = @import("atoms.zig");
const helpers = @import("helpers.zig");
const connection = @import("connection.zig");
const statement = @import("statement.zig");

/// Heap-allocated PID for the log hook recipient (NULL when not set).
pub var log_hook_pid: ?*nif.Pid = null;
pub var log_hook_mutex: ?*nif.Mutex = null;

// ─── Callbacks called from SQLite C code ─────────────────────────────────────

pub fn update_callback(
    arg: ?*anyopaque,
    sqlite_operation_type: c_int,
    sqlite_database: ?[*:0]const u8,
    sqlite_table: ?[*:0]const u8,
    sqlite_rowid: sqlite3.c.sqlite3_int64,
) callconv(nif.c_call) void {
    const conn: *connection.Connection = @ptrCast(@alignCast(arg orelse return));

    const change_type: nif.Term = switch (sqlite_operation_type) {
        sqlite3.INSERT => atoms.a.insert,
        sqlite3.DELETE => atoms.a.delete,
        sqlite3.UPDATE => atoms.a.update,
        else => return,
    };

    const msg_env = nif.alloc_env() orelse return;
    defer nif.free_env(msg_env);

    const db_str = sqlite_database orelse return;
    const tbl_str = sqlite_table orelse return;
    const db_len = std.mem.len(db_str);
    const tbl_len = std.mem.len(tbl_str);

    const database = helpers.make_binary_from_slice(msg_env, db_str[0..db_len]);
    const table = helpers.make_binary_from_slice(msg_env, tbl_str[0..tbl_len]);
    const rowid = nif.make_int64(msg_env, sqlite_rowid);
    const msg = nif.make_tuple4(msg_env, change_type, database, table, rowid);

    if (!nif.send(null, &conn.update_hook_pid, msg_env, msg)) {
        // Recipient is gone -- unregister the hook so we stop being called.
        _ = sqlite3.c.sqlite3_update_hook(conn.db, null, null);
    }
}

pub fn log_callback(arg: ?*anyopaque, iErrCode: c_int, zMsg: ?[*:0]const u8) callconv(nif.c_call) void {
    _ = arg;

    // Copy PID under mutex to avoid TOCTOU race with exqlite_set_log_hook.
    nif.mutex_lock(log_hook_mutex.?);
    const maybe_pid = log_hook_pid;
    nif.mutex_unlock(log_hook_mutex.?);

    const pid_ptr = maybe_pid orelse return;
    var pid_copy = pid_ptr.*;

    const msg_env = nif.alloc_env() orelse return;
    defer nif.free_env(msg_env);

    const msg_str = zMsg orelse return;
    const msg_len = std.mem.len(msg_str);
    const error_binary = helpers.make_binary_from_slice(msg_env, msg_str[0..msg_len]);
    const msg = nif.make_tuple3(msg_env, atoms.a.log, nif.make_int(msg_env, iErrCode), error_binary);

    if (!nif.send(null, &pid_copy, msg_env, msg)) {
        nif.mutex_lock(log_hook_mutex.?);
        if (log_hook_pid) |p| {
            _ = sqlite3.c.sqlite3_config(sqlite3.CONFIG_LOG, @as(?*anyopaque, null), @as(?*anyopaque, null));
            nif.free(p);
            log_hook_pid = null;
        }
        nif.mutex_unlock(log_hook_mutex.?);
    }
}

// ─── NIF functions ───────────────────────────────────────────────────────────

pub fn exqlite_set_update_hook(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = connection.get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    const pid = nif.get_local_pid(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_pid);

    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null)
        return helpers.make_error_tuple(env, atoms.a.connection_closed);

    conn.update_hook_pid = pid;
    _ = sqlite3.c.sqlite3_update_hook(conn.db, update_callback, conn);
    return atoms.a.ok;
}

pub fn exqlite_set_log_hook(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const pid_raw: ?*nif.Pid = @ptrCast(@alignCast(nif.alloc(@sizeOf(nif.Pid))));
    const pid = pid_raw orelse return helpers.make_error_tuple(env, atoms.a.out_of_memory);

    if (!nif.get_local_pid_into(env, argv[0], pid)) {
        nif.free(pid);
        return helpers.make_error_tuple(env, atoms.a.invalid_pid);
    }

    nif.mutex_lock(log_hook_mutex.?);
    defer nif.mutex_unlock(log_hook_mutex.?);

    if (log_hook_pid) |old| nif.free(old);
    log_hook_pid = pid;
    _ = sqlite3.c.sqlite3_config(sqlite3.CONFIG_LOG, log_callback, @as(?*anyopaque, null));

    return atoms.a.ok;
}

// ─── errmsg / errstr (shared, normal scheduler) ──────────────────────────────

pub fn exqlite_errmsg(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    // Try connection resource first, then statement resource.
    if (connection.get(env, argv[0])) |conn| {
        return connection.exqlite_errmsg_conn(env, conn);
    }

    if (statement.get(env, argv[0])) |stmt_res| {
        return statement.exqlite_errmsg_stmt(env, stmt_res);
    }

    return helpers.raise_badarg(env, argv[0]);
}

pub fn exqlite_errstr(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const rc = nif.get_int(env, argv[0]) orelse
        return helpers.raise_badarg(env, argv[0]);

    return helpers.make_binary_from_c_str(env, sqlite3.c.sqlite3_errstr(rc));
}
