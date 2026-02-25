//! Erlang NIF bindings via @cImport, plus hand-written Func/Entry structs
//! (we define those manually to get exact Zig types for the function-pointer fields,
//! avoiding the @cImport pointer-type translation issues).

const std = @import("std");

pub const c = @cImport({
    @cInclude("erl_nif.h");
});

/// The C calling convention for the current platform.
/// In Zig 0.15, CallingConvention became a tagged union; `.C` was removed.
/// Use `callconv(nif.c_call)` everywhere instead of `callconv(c_call)`.
pub const c_call = std.builtin.CallingConvention.c;

// ─── Basic type aliases ────────────────────────────────────────────────────────
pub const Env = c.ErlNifEnv;
pub const Term = c.ERL_NIF_TERM;
pub const Binary = c.ErlNifBinary;
pub const Pid = c.ErlNifPid;
pub const Mutex = c.ErlNifMutex;
pub const ResourceType = c.ErlNifResourceType;

// ─── Dirty scheduler flags ────────────────────────────────────────────────────
pub const DIRTY_IO: c_uint = c.ERL_NIF_DIRTY_JOB_IO_BOUND;
pub const DIRTY_CPU: c_uint = c.ERL_NIF_DIRTY_JOB_CPU_BOUND;

// ─── Resource type flags ──────────────────────────────────────────────────────
pub const RT_CREATE = c.ERL_NIF_RT_CREATE;
pub const RT_TAKEOVER = c.ERL_NIF_RT_TAKEOVER;

// ─── Hand-written ErlNifFunc ──────────────────────────────────────────────────
// We define this manually so that our NIF function signatures (with [*]const Term)
// match the fptr type without any @ptrCast gymnastics.
// Layout must match ErlNifFunc in erl_nif.h on all platforms; we use extern struct
// so Zig applies C padding rules automatically.
pub const Func = extern struct {
    name: [*c]const u8,
    arity: c_uint,
    fptr: ?FptrType,
    flags: c_uint,

    /// The C-ABI function pointer type the BEAM expects in ErlNifFunc.
    pub const FptrType = *const fn (*Env, c_int, [*]const Term) callconv(c_call) Term;
};

/// Type of a simplified Zig NIF function: no argc, no callconv annotation.
pub const NifFn = *const fn (*Env, [*]const Term) Term;

/// Wrap a simplified Zig NIF function into the C-ABI signature the BEAM expects.
/// The returned function is monomorphized at comptime for each distinct `f`.
pub fn wrap(comptime f: NifFn) Func.FptrType {
    return struct {
        fn call(env: *Env, _: c_int, argv: [*]const Term) callconv(c_call) Term {
            return f(env, argv);
        }
    }.call;
}

/// Scheduler hint for a NIF function.
pub const Sched = enum(c_uint) {
    normal = 0,
    dirty_io = DIRTY_IO,
    dirty_cpu = DIRTY_CPU,
};

/// Build a Func table entry, wrapping the simplified NIF function signature.
pub fn func(
    comptime name: [*:0]const u8,
    comptime arity: c_uint,
    comptime f: NifFn,
    comptime sched: Sched,
) Func {
    return .{
        .name = name,
        .arity = arity,
        .fptr = wrap(f),
        .flags = @intFromEnum(sched),
    };
}

/// Get a typed resource pointer from an Erlang term.
pub fn getResource(comptime T: type, env: *Env, term: Term, rt: *ResourceType) ?*T {
    var ptr: ?*anyopaque = null;
    if (!get_resource(env, term, rt, &ptr)) return null;
    return @ptrCast(@alignCast(ptr));
}

/// Allocate a resource and return a typed pointer, or null on failure.
pub fn allocResource(comptime T: type, rt: *ResourceType) ?*T {
    const raw = alloc_resource(rt, @sizeOf(T)) orelse return null;
    return @ptrCast(@alignCast(raw));
}

// ─── Hand-written ErlNifEntry ─────────────────────────────────────────────────
// All fields from erl_nif.h (OTP 20+). The sizeof_ErlNifResourceTypeInit field
// was introduced in OTP 20 to handle ABI-compatible evolution of that struct.
pub const Entry = extern struct {
    major: c_int,
    minor: c_int,
    name: [*c]const u8,
    num_of_funcs: c_uint,
    funcs: [*c]Func,
    load: ?*const fn (*Env, *?*anyopaque, Term) callconv(c_call) c_int,
    reload: ?*const fn (*Env, *?*anyopaque, Term) callconv(c_call) c_int,
    upgrade: ?*const fn (*Env, *?*anyopaque, *?*anyopaque, Term) callconv(c_call) c_int,
    unload: ?*const fn (*Env, ?*anyopaque) callconv(c_call) void,
    vm_variant: [*c]const u8,
    options: c_uint,
    sizeof_ErlNifResourceTypeInit: usize,
    min_erts: [*c]const u8,
};

// ─── Thin wrappers returning optionals ────────────────────────────────────────

pub fn get_resource(env: *Env, term: Term, rt: *ResourceType, out: *?*anyopaque) bool {
    return c.enif_get_resource(env, term, rt, out) != 0;
}

pub fn get_int(env: *Env, term: Term) ?c_int {
    var v: c_int = 0;
    return if (c.enif_get_int(env, term, &v) != 0) v else null;
}

pub fn get_uint(env: *Env, term: Term) ?c_uint {
    var v: c_uint = 0;
    return if (c.enif_get_uint(env, term, &v) != 0) v else null;
}

pub fn get_int64(env: *Env, term: Term) ?i64 {
    var v: c.ErlNifSInt64 = 0;
    return if (c.enif_get_int64(env, term, &v) != 0) @intCast(v) else null;
}

pub fn get_double(env: *Env, term: Term) ?f64 {
    var v: f64 = 0;
    return if (c.enif_get_double(env, term, &v) != 0) v else null;
}

pub fn get_local_pid(env: *Env, term: Term) ?Pid {
    var pid: Pid = undefined;
    return if (c.enif_get_local_pid(env, term, &pid) != 0) pid else null;
}

pub fn get_local_pid_into(env: *Env, term: Term, out: *Pid) bool {
    return c.enif_get_local_pid(env, term, out) != 0;
}

pub fn inspect_iolist_as_binary(env: *Env, term: Term) ?Binary {
    var bin: Binary = undefined;
    return if (c.enif_inspect_iolist_as_binary(env, term, &bin) != 0) bin else null;
}

pub fn inspect_binary(env: *Env, term: Term) ?Binary {
    var bin: Binary = undefined;
    return if (c.enif_inspect_binary(env, term, &bin) != 0) bin else null;
}

pub fn alloc_binary(size: usize) ?Binary {
    var bin: Binary = undefined;
    return if (c.enif_alloc_binary(size, &bin) != 0) bin else null;
}

pub fn mutex_create(name: [*:0]const u8) ?*Mutex {
    return c.enif_mutex_create(@constCast(name));
}

pub fn mutex_lock(mutex: *Mutex) void {
    c.enif_mutex_lock(mutex);
}

pub fn mutex_unlock(mutex: *Mutex) void {
    c.enif_mutex_unlock(mutex);
}

pub fn mutex_destroy(mutex: *Mutex) void {
    c.enif_mutex_destroy(mutex);
}

pub fn open_resource_type(
    env: *Env,
    module_str: ?[*:0]const u8,
    name_str: [*:0]const u8,
    destructor: ?*const fn (?*Env, ?*anyopaque) callconv(c_call) void,
    flags: c.ErlNifResourceFlags,
    tried: ?*c.ErlNifResourceFlags,
) ?*ResourceType {
    return c.enif_open_resource_type(env, module_str, name_str, destructor, flags, tried);
}

pub fn alloc_resource(rt: *ResourceType, size: usize) ?*anyopaque {
    return c.enif_alloc_resource(rt, size);
}

pub fn release_resource(obj: *anyopaque) void {
    c.enif_release_resource(obj);
}

pub fn keep_resource(obj: *anyopaque) void {
    c.enif_keep_resource(obj);
}

pub fn make_resource(env: *Env, obj: *anyopaque) Term {
    return c.enif_make_resource(env, obj);
}

pub fn make_atom(env: *Env, name: [*:0]const u8) Term {
    return c.enif_make_atom(env, name);
}

pub fn make_int(env: *Env, v: c_int) Term {
    return c.enif_make_int(env, v);
}

pub fn make_int64(env: *Env, v: i64) Term {
    return c.enif_make_int64(env, v);
}

pub fn make_double(env: *Env, v: f64) Term {
    return c.enif_make_double(env, v);
}

pub fn make_binary(env: *Env, bin: *Binary) Term {
    return c.enif_make_binary(env, bin);
}

pub fn release_binary(bin: *Binary) void {
    c.enif_release_binary(bin);
}

pub fn make_tuple2(env: *Env, a1: Term, a2: Term) Term {
    return c.enif_make_tuple2(env, a1, a2);
}

pub fn make_tuple3(env: *Env, a1: Term, a2: Term, a3: Term) Term {
    return c.enif_make_tuple3(env, a1, a2, a3);
}

pub fn make_tuple4(env: *Env, a1: Term, a2: Term, a3: Term, a4: Term) Term {
    return c.enif_make_tuple4(env, a1, a2, a3, a4);
}

pub fn make_list(env: *Env, cnt: c_uint, arr: [*]const Term) Term {
    return c.enif_make_list_from_array(env, arr, cnt);
}

pub fn make_list_cell(env: *Env, head: Term, tail: Term) Term {
    return c.enif_make_list_cell(env, head, tail);
}

pub fn make_empty_list(env: *Env) Term {
    return c.enif_make_list_from_array(env, null, 0);
}

pub fn make_badarg(env: *Env) Term {
    return c.enif_make_badarg(env);
}

pub fn raise_exception(env: *Env, reason: Term) Term {
    return c.enif_raise_exception(env, reason);
}

pub fn alloc(size: usize) ?*anyopaque {
    return c.enif_alloc(size);
}

pub fn free(ptr: ?*anyopaque) void {
    c.enif_free(ptr);
}

pub fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    return c.enif_realloc(ptr, size);
}

pub fn alloc_env() ?*Env {
    return c.enif_alloc_env();
}

pub fn free_env(env: *Env) void {
    c.enif_free_env(env);
}

pub fn send(from_env: ?*Env, to_pid: *Pid, msg_env: *Env, msg: Term) bool {
    return c.enif_send(from_env, to_pid, msg_env, msg) != 0;
}

pub fn make_copy(dst_env: *Env, term: Term) Term {
    return c.enif_make_copy(dst_env, term);
}
