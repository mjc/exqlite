//! Erlang NIF entry point for exqlite.
//!
//! Exports the 27-entry nif_funcs table and the ErlNifEntry that the BEAM
//! finds via the `nif_init` symbol (equivalent to ERL_NIF_INIT in C).

const std = @import("std");
const nif = @import("nif.zig");
const sqlite3 = @import("sqlite3.zig");
const atoms = @import("atoms.zig");
const allocator = @import("allocator.zig");
const connection = @import("connection.zig");
const statement = @import("statement.zig");
const callbacks = @import("callbacks.zig");

// ─── NIF function table ──────────────────────────────────────────────────────
// Must be `var` (not `const`) because ErlNifEntry.funcs is a non-const pointer.
// Must match nif_funcs[] in the original sqlite3_nif.c exactly.
var nif_funcs = [_]nif.Func{
    nif.func("open", 2, connection.exqlite_open, .dirty_io),
    nif.func("close", 1, connection.exqlite_close, .dirty_io),
    nif.func("execute", 2, connection.exqlite_execute, .dirty_io),
    nif.func("changes", 1, connection.exqlite_changes, .dirty_io),
    nif.func("prepare", 2, statement.exqlite_prepare, .dirty_io),
    nif.func("reset", 1, statement.exqlite_reset, .dirty_cpu),
    nif.func("bind_parameter_count", 1, statement.exqlite_bind_parameter_count, .normal),
    nif.func("bind_parameter_index", 2, statement.exqlite_bind_parameter_index, .normal),
    nif.func("bind_text", 3, statement.exqlite_bind_text, .normal),
    nif.func("bind_blob", 3, statement.exqlite_bind_blob, .normal),
    nif.func("bind_integer", 3, statement.exqlite_bind_integer, .normal),
    nif.func("bind_float", 3, statement.exqlite_bind_float, .normal),
    nif.func("bind_null", 2, statement.exqlite_bind_null, .normal),
    nif.func("step", 2, statement.exqlite_step, .dirty_io),
    nif.func("multi_step", 3, statement.exqlite_multi_step, .dirty_io),
    nif.func("columns", 2, statement.exqlite_columns, .dirty_io),
    nif.func("last_insert_rowid", 1, connection.exqlite_last_insert_rowid, .dirty_io),
    nif.func("transaction_status", 1, connection.exqlite_transaction_status, .dirty_io),
    nif.func("serialize", 2, connection.exqlite_serialize, .dirty_io),
    nif.func("deserialize", 3, connection.exqlite_deserialize, .dirty_io),
    nif.func("release", 2, statement.exqlite_release, .dirty_io),
    nif.func("enable_load_extension", 2, connection.exqlite_enable_load_extension, .dirty_io),
    nif.func("set_update_hook", 2, callbacks.exqlite_set_update_hook, .dirty_io),
    nif.func("set_log_hook", 1, callbacks.exqlite_set_log_hook, .dirty_io),
    nif.func("interrupt", 1, connection.exqlite_interrupt, .dirty_io),
    nif.func("errmsg", 1, callbacks.exqlite_errmsg, .normal),
    nif.func("errstr", 1, callbacks.exqlite_errstr, .normal),
};

// ─── Lifecycle callbacks ─────────────────────────────────────────────────────

fn on_load(env: *nif.Env, priv: *?*anyopaque, info: nif.Term) callconv(nif.c_call) c_int {
    _ = priv;
    _ = info;

    if (!allocator.install()) return -1;
    atoms.init(env);

    connection.connection_type = nif.open_resource_type(
        env,
        null,
        "connection_type",
        connection.destructor,
        nif.RT_CREATE,
        null,
    ) orelse {
        allocator.restore();
        return -1;
    };

    statement.statement_type = nif.open_resource_type(
        env,
        null,
        "statement_type",
        statement.destructor,
        nif.RT_CREATE,
        null,
    ) orelse {
        allocator.restore();
        return -1;
    };

    callbacks.log_hook_mutex = nif.mutex_create("exqlite:log_hook") orelse {
        allocator.restore();
        return -1;
    };

    return 0;
}

fn on_unload(caller_env: *nif.Env, priv_data: ?*anyopaque) callconv(nif.c_call) void {
    _ = caller_env;
    _ = priv_data;
    if (callbacks.log_hook_pid) |p| {
        nif.free(p);
        callbacks.log_hook_pid = null;
    }
    if (callbacks.log_hook_mutex) |m| nif.mutex_destroy(m);
    allocator.restore();
}

fn on_upgrade(env: *nif.Env, priv_data: *?*anyopaque, old_priv_data: *?*anyopaque, load_info: nif.Term) callconv(nif.c_call) c_int {
    _ = env;
    _ = priv_data;
    _ = old_priv_data;
    _ = load_info;
    return 0;
}

// ─── ErlNifEntry ─────────────────────────────────────────────────────────────
// The BEAM looks for the exported symbol `nif_init` which returns a pointer to
// an ErlNifEntry.  This is what ERL_NIF_INIT() expands to in C.
// We use a module-level var so nif_init() can return a stable pointer.

var entry: nif.Entry = .{
    .major = 2,
    .minor = 17,
    .name = "Elixir.Exqlite.Sqlite3NIF",
    .num_of_funcs = nif_funcs.len,
    .funcs = &nif_funcs,
    .load = on_load,
    .reload = null,
    .upgrade = on_upgrade,
    .unload = on_unload,
    .vm_variant = "beam.vanilla",
    .options = 1, // ERL_NIF_DIRTY_NIF_OPTION
    .sizeof_ErlNifResourceTypeInit = @sizeOf(nif.c.ErlNifResourceTypeInit),
    .min_erts = "erts-10.0",
};

export fn nif_init() *const nif.Entry {
    return &entry;
}
