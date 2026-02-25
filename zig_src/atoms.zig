//! Cached Erlang atoms. Call init(env) once in on_load.
//! Access atoms via `atoms.a.foo` (e.g. `atoms.a.ok`, `atoms.a.@"error"`).

const nif = @import("nif.zig");

pub const AtomTable = struct {
    ok: nif.Term = undefined,
    @"error": nif.Term = undefined,
    badarg: nif.Term = undefined,
    nil: nif.Term = undefined,
    out_of_memory: nif.Term = undefined,
    done: nif.Term = undefined,
    row: nif.Term = undefined,
    rows: nif.Term = undefined,
    invalid_filename: nif.Term = undefined,
    invalid_flags: nif.Term = undefined,
    database_open_failed: nif.Term = undefined,
    failed_to_create_mutex: nif.Term = undefined,
    invalid_connection: nif.Term = undefined,
    sql_not_iolist: nif.Term = undefined,
    connection_closed: nif.Term = undefined,
    invalid_statement: nif.Term = undefined,
    invalid_chunk_size: nif.Term = undefined,
    busy: nif.Term = undefined,
    invalid_column_count: nif.Term = undefined,
    transaction: nif.Term = undefined,
    idle: nif.Term = undefined,
    database_name_not_iolist: nif.Term = undefined,
    serialization_failed: nif.Term = undefined,
    deserialization_failed: nif.Term = undefined,
    invalid_enable_load_extension_value: nif.Term = undefined,
    insert: nif.Term = undefined,
    delete: nif.Term = undefined,
    update: nif.Term = undefined,
    invalid_pid: nif.Term = undefined,
    log: nif.Term = undefined,
};

pub var a: AtomTable = .{};

pub fn init(env: *nif.Env) void {
    inline for (@typeInfo(AtomTable).@"struct".fields) |field| {
        @field(a, field.name) = nif.make_atom(env, field.name);
    }
}
