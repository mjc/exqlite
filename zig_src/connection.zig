//! Connection resource: open/close/execute/interrupt/errmsg/etc.

const std = @import("std");
const nif = @import("nif.zig");
const sqlite3 = @import("sqlite3.zig");
const atoms = @import("atoms.zig");
const helpers = @import("helpers.zig");

/// The NIF resource type handle, set during on_load.
pub var connection_type: ?*nif.ResourceType = null;

/// Extern struct so its layout is C-compatible (enif_alloc_resource gives us raw bytes).
pub const Connection = extern struct {
    db: ?*sqlite3.Database,
    mutex: ?*nif.Mutex,
    interrupt_mutex: ?*nif.Mutex,
    update_hook_pid: nif.Pid,

    pub fn acquireLock(self: *Connection) void {
        nif.mutex_lock(self.mutex.?);
    }

    pub fn releaseLock(self: *Connection) void {
        nif.mutex_unlock(self.mutex.?);
    }
};

/// Called by the BEAM GC when a connection resource is collected.
pub fn destructor(env: ?*nif.Env, arg: ?*anyopaque) callconv(nif.c_call) void {
    _ = env;
    const conn: *Connection = @ptrCast(@alignCast(arg orelse return));
    if (conn.db) |db| {
        _ = sqlite3.c.sqlite3_close_v2(db);
        conn.db = null;
    }
    if (conn.mutex) |m| {
        nif.mutex_destroy(m);
        conn.mutex = null;
    }
    if (conn.interrupt_mutex) |m| {
        nif.mutex_destroy(m);
        conn.interrupt_mutex = null;
    }
}

/// Get a *Connection from an Erlang term, or return null.
pub fn get(env: *nif.Env, term: nif.Term) ?*Connection {
    return nif.getResource(Connection, env, term, connection_type.?);
}

// ─── NIF functions ─────────────────────────────────────────────────────────

pub fn exqlite_open(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    // argv[0] = filename (iolist), argv[1] = flags (integer)
    const filename_bin = helpers.iolist_to_nul_binary(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_filename);

    const flags = nif.get_int(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_flags);

    var db: ?*sqlite3.Database = null;
    const rc = sqlite3.c.sqlite3_open_v2(
        @ptrCast(filename_bin.data),
        &db,
        flags,
        null,
    );
    if (rc != sqlite3.OK) {
        if (db) |d| _ = sqlite3.c.sqlite3_close_v2(d);
        return helpers.make_error_tuple(env, atoms.a.database_open_failed);
    }

    const mutex = nif.mutex_create("exqlite:connection") orelse {
        _ = sqlite3.c.sqlite3_close_v2(db);
        return helpers.make_error_tuple(env, atoms.a.failed_to_create_mutex);
    };

    _ = sqlite3.c.sqlite3_busy_timeout(db, 2000);

    const conn = nif.allocResource(Connection, connection_type.?) orelse {
        _ = sqlite3.c.sqlite3_close_v2(db);
        nif.mutex_destroy(mutex);
        return helpers.make_error_tuple(env, atoms.a.out_of_memory);
    };
    // Initialize ALL fields before anything that can trigger the destructor.
    conn.db = db;
    conn.mutex = mutex;
    conn.interrupt_mutex = null;
    conn.update_hook_pid = std.mem.zeroes(nif.Pid);
    conn.interrupt_mutex = nif.mutex_create("exqlite:interrupt") orelse {
        // destructor will close db and destroy mutex via release_resource
        nif.release_resource(conn);
        return helpers.make_error_tuple(env, atoms.a.failed_to_create_mutex);
    };

    const result = nif.make_resource(env, conn);
    nif.release_resource(conn);
    return helpers.make_ok_tuple(env, result);
}

pub fn exqlite_close(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    conn.acquireLock();

    if (conn.db == null) {
        conn.releaseLock();
        return atoms.a.ok;
    }

    const autocommit = sqlite3.c.sqlite3_get_autocommit(conn.db);
    if (autocommit == 0) {
        const rc = sqlite3.c.sqlite3_exec(conn.db, "ROLLBACK;", null, null, null);
        if (rc != sqlite3.OK) {
            const err = helpers.make_sqlite3_error_tuple(env, rc, conn.db);
            conn.releaseLock();
            return err;
        }
    }

    nif.mutex_lock(conn.interrupt_mutex.?);
    const rc = sqlite3.c.sqlite3_close_v2(conn.db);
    if (rc != sqlite3.OK) {
        nif.mutex_unlock(conn.interrupt_mutex.?);
        const err = helpers.make_sqlite3_error_tuple(env, rc, conn.db);
        conn.releaseLock();
        return err;
    }
    conn.db = null;
    nif.mutex_unlock(conn.interrupt_mutex.?);

    conn.releaseLock();
    return atoms.a.ok;
}

pub fn exqlite_execute(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    const sql_bin = helpers.iolist_to_nul_binary(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.sql_not_iolist);

    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null)
        return helpers.make_error_tuple(env, atoms.a.connection_closed);

    const rc = sqlite3.c.sqlite3_exec(conn.db, @ptrCast(sql_bin.data), null, null, null);
    if (rc != sqlite3.OK)
        return helpers.make_sqlite3_error_tuple(env, rc, conn.db);

    return atoms.a.ok;
}

pub fn exqlite_changes(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null)
        return helpers.make_error_tuple(env, atoms.a.connection_closed);

    const changes = sqlite3.c.sqlite3_changes(conn.db);
    return helpers.make_ok_tuple(env, nif.make_int(env, changes));
}

pub fn exqlite_last_insert_rowid(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null)
        return helpers.make_error_tuple(env, atoms.a.connection_closed);

    const rowid = sqlite3.c.sqlite3_last_insert_rowid(conn.db);
    return helpers.make_ok_tuple(env, nif.make_int64(env, rowid));
}

pub fn exqlite_transaction_status(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null)
        return helpers.make_ok_tuple(env, atoms.a.@"error");

    const autocommit = sqlite3.c.sqlite3_get_autocommit(conn.db);
    return helpers.make_ok_tuple(env, if (autocommit == 0) atoms.a.transaction else atoms.a.idle);
}

pub fn exqlite_serialize(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    const db_name_bin = helpers.iolist_to_nul_binary(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.database_name_not_iolist);

    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null)
        return helpers.make_error_tuple(env, atoms.a.connection_closed);

    var buffer_size: sqlite3.c.sqlite3_int64 = 0;
    const buffer = sqlite3.c.sqlite3_serialize(
        conn.db,
        @ptrCast(db_name_bin.data),
        &buffer_size,
        0,
    );
    if (buffer == null)
        return helpers.make_error_tuple(env, atoms.a.serialization_failed);
    defer sqlite3.c.sqlite3_free(buffer);

    const bytes: []const u8 = @as([*]const u8, @ptrCast(buffer))[0..@intCast(buffer_size)];
    return helpers.make_ok_tuple(env, helpers.make_binary_from_slice(env, bytes));
}

pub fn exqlite_deserialize(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    const db_name_bin = helpers.iolist_to_nul_binary(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.database_name_not_iolist);

    const serialized = nif.inspect_binary(env, argv[2]) orelse
        return nif.make_badarg(env);

    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null)
        return helpers.make_error_tuple(env, atoms.a.connection_closed);

    const size: i64 = @intCast(serialized.size);
    const buf_raw = sqlite3.c.sqlite3_malloc64(@intCast(serialized.size)) orelse
        return helpers.make_error_tuple(env, atoms.a.deserialization_failed);
    const buf: [*]u8 = @ptrCast(buf_raw);

    @memcpy(buf[0..serialized.size], serialized.data[0..serialized.size]);

    const flags = sqlite3.DESERIALIZE_FREEONCLOSE | sqlite3.DESERIALIZE_RESIZEABLE;
    const rc = sqlite3.c.sqlite3_deserialize(
        conn.db,
        @ptrCast(db_name_bin.data),
        buf,
        size,
        size,
        @intCast(flags),
    );
    if (rc != sqlite3.OK) {
        // SQLite has already freed buf via FREEONCLOSE on failure path — do NOT double-free.
        return helpers.make_sqlite3_error_tuple(env, rc, conn.db);
    }

    return atoms.a.ok;
}

pub fn exqlite_enable_load_extension(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    const enable_val = nif.get_int(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_enable_load_extension_value);

    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null)
        return helpers.make_error_tuple(env, atoms.a.connection_closed);

    const rc = sqlite3.c.sqlite3_enable_load_extension(conn.db, enable_val);
    if (rc != sqlite3.OK)
        return helpers.make_sqlite3_error_tuple(env, rc, conn.db);

    return atoms.a.ok;
}

pub fn exqlite_interrupt(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    // Do NOT acquire conn.mutex here -- a running query holds it for its
    // entire duration, so acquiring it would block until the query finishes,
    // defeating the purpose.  interrupt_mutex is a dedicated lock shared only
    // with close(), ensuring we never call sqlite3_interrupt on a NULL db.
    nif.mutex_lock(conn.interrupt_mutex.?);
    if (conn.db) |db| sqlite3.c.sqlite3_interrupt(db);
    nif.mutex_unlock(conn.interrupt_mutex.?);

    return atoms.a.ok;
}

pub fn exqlite_errmsg_conn(env: *nif.Env, conn: *Connection) nif.Term {
    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null)
        return helpers.make_error_tuple(env, atoms.a.connection_closed);

    return helpers.make_binary_from_c_str(env, sqlite3.c.sqlite3_errmsg(conn.db));
}
