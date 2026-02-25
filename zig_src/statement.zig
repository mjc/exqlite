//! Statement resource: prepare/step/bind_*/release/columns/multi_step/errmsg.

const std = @import("std");
const nif = @import("nif.zig");
const sqlite3 = @import("sqlite3.zig");
const atoms = @import("atoms.zig");
const helpers = @import("helpers.zig");
const connection = @import("connection.zig");

/// The NIF resource type handle, set during on_load.
pub var statement_type: ?*nif.ResourceType = null;

pub const Statement = extern struct {
    conn: ?*connection.Connection,
    statement: ?*sqlite3.Stmt,

    pub fn acquireLock(self: *Statement) void {
        self.conn.?.acquireLock();
    }

    pub fn releaseLock(self: *Statement) void {
        self.conn.?.releaseLock();
    }
};

/// Called by the BEAM GC when a statement resource is collected.
pub fn destructor(env: ?*nif.Env, arg: ?*anyopaque) callconv(nif.c_call) void {
    _ = env;
    const stmt: *Statement = @ptrCast(@alignCast(arg orelse return));
    {
        stmt.acquireLock();
        defer stmt.releaseLock();
        if (stmt.statement) |s| {
            _ = sqlite3.c.sqlite3_finalize(s);
            stmt.statement = null;
        }
    }
    // release_resource must be called after releasing the lock (conn owns the mutex).
    if (stmt.conn) |c| {
        nif.release_resource(c);
        stmt.conn = null;
    }
}

/// Get a *Statement from an Erlang term.
pub fn get(env: *nif.Env, term: nif.Term) ?*Statement {
    return nif.getResource(Statement, env, term, statement_type.?);
}

// ─── NIF functions ─────────────────────────────────────────────────────────

pub fn exqlite_prepare(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = connection.get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    const sql_bin = helpers.iolist_to_nul_binary(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.sql_not_iolist);

    const stmt_res = nif.allocResource(Statement, statement_type.?) orelse
        return helpers.make_error_tuple(env, atoms.a.out_of_memory);
    stmt_res.statement = null;
    nif.keep_resource(conn);
    stmt_res.conn = conn;

    conn.acquireLock();
    defer conn.releaseLock();

    if (conn.db == null) {
        nif.release_resource(stmt_res);
        return helpers.make_error_tuple(env, atoms.a.connection_closed);
    }

    var raw_stmt: ?*sqlite3.Stmt = null;
    const rc = sqlite3.c.sqlite3_prepare_v3(
        conn.db,
        @ptrCast(sql_bin.data),
        @intCast(sql_bin.size),
        0,
        &raw_stmt,
        null,
    );

    if (rc != sqlite3.OK) {
        const err = helpers.make_sqlite3_error_tuple(env, rc, conn.db);
        nif.release_resource(stmt_res);
        return err;
    }

    stmt_res.statement = raw_stmt;
    const result = nif.make_resource(env, stmt_res);
    nif.release_resource(stmt_res);
    return helpers.make_ok_tuple(env, result);
}

pub fn exqlite_step(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = connection.get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    const stmt_res = get(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    conn.acquireLock();
    defer conn.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const rc = sqlite3.c.sqlite3_step(stmt_res.statement);
    return switch (rc) {
        sqlite3.ROW => nif.make_tuple2(env, atoms.a.row, helpers.make_row(env, stmt_res.statement.?)),
        sqlite3.BUSY => blk: {
            _ = sqlite3.c.sqlite3_reset(stmt_res.statement);
            break :blk atoms.a.busy;
        },
        sqlite3.DONE => blk: {
            _ = sqlite3.c.sqlite3_reset(stmt_res.statement);
            break :blk atoms.a.done;
        },
        else => blk: {
            _ = sqlite3.c.sqlite3_reset(stmt_res.statement);
            break :blk helpers.make_sqlite3_error_tuple(env, rc, conn.db);
        },
    };
}

pub fn exqlite_multi_step(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = connection.get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    const stmt_res = get(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const chunk_size = nif.get_int(env, argv[2]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_chunk_size);

    if (chunk_size < 1)
        return helpers.make_error_tuple(env, atoms.a.invalid_chunk_size);

    conn.acquireLock();
    defer conn.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    // Rows are prepended; the Elixir side reverses the list after receiving it.
    var rows = nif.make_empty_list(env);
    var i: c_int = 0;
    while (i < chunk_size) : (i += 1) {
        const rc = sqlite3.c.sqlite3_step(stmt_res.statement);
        switch (rc) {
            sqlite3.BUSY => {
                _ = sqlite3.c.sqlite3_reset(stmt_res.statement);
                return atoms.a.busy;
            },
            sqlite3.DONE => {
                _ = sqlite3.c.sqlite3_reset(stmt_res.statement);
                return nif.make_tuple2(env, atoms.a.done, rows);
            },
            sqlite3.ROW => {
                const row_term = helpers.make_row(env, stmt_res.statement.?);
                rows = nif.make_list_cell(env, row_term, rows);
            },
            else => {
                _ = sqlite3.c.sqlite3_reset(stmt_res.statement);
                return helpers.make_sqlite3_error_tuple(env, rc, conn.db);
            },
        }
    }

    return nif.make_tuple2(env, atoms.a.rows, rows);
}

pub fn exqlite_reset(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const stmt_res = get(env, argv[0]) orelse
        return helpers.raise_badarg(env, argv[0]);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    _ = sqlite3.c.sqlite3_reset(stmt_res.statement);
    return atoms.a.ok;
}

pub fn exqlite_columns(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const conn = connection.get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);
    // Validates argv[0] is a live connection resource; actual operations use stmt_res.
    _ = conn;

    const stmt_res = get(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const size = sqlite3.c.sqlite3_column_count(stmt_res.statement);
    if (size == 0)
        return helpers.make_ok_tuple(env, nif.make_empty_list(env));
    if (size < 0)
        return helpers.make_error_tuple(env, atoms.a.invalid_column_count);

    const n: usize = @intCast(size);
    var buf = helpers.TermBuffer.init(n) orelse
        return helpers.make_error_tuple(env, atoms.a.out_of_memory);
    defer buf.deinit();
    const columns = buf.slice();

    for (0..n) |i| {
        const name = sqlite3.c.sqlite3_column_name(stmt_res.statement, @intCast(i));
        // sqlite3_column_name returns NULL only on OOM
        if (name == null)
            return helpers.make_error_tuple(env, atoms.a.out_of_memory);
        columns[i] = helpers.make_binary_from_c_str(env, name);
    }

    return helpers.make_ok_tuple(env, nif.make_list(env, @intCast(n), columns.ptr));
}

pub fn exqlite_release(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    _ = connection.get(env, argv[0]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_connection);

    const stmt_res = get(env, argv[1]) orelse
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement) |s| {
        _ = sqlite3.c.sqlite3_finalize(s);
        stmt_res.statement = null;
    }
    return atoms.a.ok;
}

pub fn exqlite_bind_parameter_count(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const stmt_res = get(env, argv[0]) orelse
        return helpers.raise_badarg(env, argv[0]);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const count = sqlite3.c.sqlite3_bind_parameter_count(stmt_res.statement);
    return nif.make_int(env, count);
}

pub fn exqlite_bind_parameter_index(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const stmt_res = get(env, argv[0]) orelse
        return helpers.raise_badarg(env, argv[0]);

    const name_bin = helpers.iolist_to_nul_binary(env, argv[1]) orelse
        return helpers.raise_badarg(env, argv[1]);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const idx = sqlite3.c.sqlite3_bind_parameter_index(
        stmt_res.statement,
        @ptrCast(name_bin.data),
    );
    return nif.make_int(env, idx);
}

pub fn exqlite_bind_text(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const stmt_res = get(env, argv[0]) orelse
        return helpers.raise_badarg(env, argv[0]);

    const idx = nif.get_uint(env, argv[1]) orelse
        return helpers.raise_badarg(env, argv[1]);

    const text = nif.inspect_binary(env, argv[2]) orelse
        return helpers.raise_badarg(env, argv[2]);

    if (text.size > std.math.maxInt(c_int)) return nif.make_badarg(env);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const rc = sqlite3.c.sqlite3_bind_text(
        stmt_res.statement,
        @intCast(idx),
        @ptrCast(text.data),
        @intCast(text.size),
        sqlite3.TRANSIENT,
    );
    return nif.make_int(env, rc);
}

pub fn exqlite_bind_blob(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const stmt_res = get(env, argv[0]) orelse
        return helpers.raise_badarg(env, argv[0]);

    const idx = nif.get_uint(env, argv[1]) orelse
        return helpers.raise_badarg(env, argv[1]);

    const blob = nif.inspect_binary(env, argv[2]) orelse
        return helpers.raise_badarg(env, argv[2]);

    if (blob.size > std.math.maxInt(c_int)) return nif.make_badarg(env);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const rc = sqlite3.c.sqlite3_bind_blob(
        stmt_res.statement,
        @intCast(idx),
        @ptrCast(blob.data),
        @intCast(blob.size),
        sqlite3.TRANSIENT,
    );
    return nif.make_int(env, rc);
}

pub fn exqlite_bind_integer(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const stmt_res = get(env, argv[0]) orelse
        return helpers.raise_badarg(env, argv[0]);

    const idx = nif.get_uint(env, argv[1]) orelse
        return helpers.raise_badarg(env, argv[1]);

    const val = nif.get_int64(env, argv[2]) orelse
        return helpers.raise_badarg(env, argv[2]);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const rc = sqlite3.c.sqlite3_bind_int64(stmt_res.statement, @intCast(idx), val);
    return nif.make_int(env, rc);
}

pub fn exqlite_bind_float(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const stmt_res = get(env, argv[0]) orelse
        return helpers.raise_badarg(env, argv[0]);

    const idx = nif.get_uint(env, argv[1]) orelse
        return helpers.raise_badarg(env, argv[1]);

    const val = nif.get_double(env, argv[2]) orelse
        return helpers.raise_badarg(env, argv[2]);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const rc = sqlite3.c.sqlite3_bind_double(stmt_res.statement, @intCast(idx), val);
    return nif.make_int(env, rc);
}

pub fn exqlite_bind_null(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
    const stmt_res = get(env, argv[0]) orelse
        return helpers.raise_badarg(env, argv[0]);

    const idx = nif.get_uint(env, argv[1]) orelse
        return helpers.raise_badarg(env, argv[1]);

    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null)
        return helpers.make_error_tuple(env, atoms.a.invalid_statement);

    const rc = sqlite3.c.sqlite3_bind_null(stmt_res.statement, @intCast(idx));
    return nif.make_int(env, rc);
}

pub fn exqlite_errmsg_stmt(env: *nif.Env, stmt_res: *Statement) nif.Term {
    stmt_res.acquireLock();
    defer stmt_res.releaseLock();

    if (stmt_res.statement == null) return atoms.a.nil;

    const db = sqlite3.c.sqlite3_db_handle(stmt_res.statement);
    return helpers.make_binary_from_c_str(env, sqlite3.c.sqlite3_errmsg(db));
}
