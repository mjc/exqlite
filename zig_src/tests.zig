//! Zig unit tests for exqlite NIF — pure-logic tests with no BEAM.
//! Uses stub erl_nif.h with libc malloc/free backing.

const std = @import("std");
const allocator_mod = @import("allocator.zig");
const helpers = @import("helpers.zig");
const nif = @import("nif.zig");
const sqlite3 = @import("sqlite3.zig");
const atoms_mod = @import("atoms.zig");

// ─── allocator.zig tests ───────────────────────────────────────────────────

test "mem_round_up: aligns to 8-byte boundary" {
    try std.testing.expectEqual(@as(c_int, 0), allocator_mod.exqlite_mem_round_up(0));
    try std.testing.expectEqual(@as(c_int, 8), allocator_mod.exqlite_mem_round_up(1));
    try std.testing.expectEqual(@as(c_int, 8), allocator_mod.exqlite_mem_round_up(7));
    try std.testing.expectEqual(@as(c_int, 8), allocator_mod.exqlite_mem_round_up(8));
    try std.testing.expectEqual(@as(c_int, 16), allocator_mod.exqlite_mem_round_up(9));
    try std.testing.expectEqual(@as(c_int, 16), allocator_mod.exqlite_mem_round_up(16));
    try std.testing.expectEqual(@as(c_int, 24), allocator_mod.exqlite_mem_round_up(17));
}

test "malloc: stores size in header; size() reads it back" {
    const p = allocator_mod.exqlite_malloc(42) orelse return error.AllocFailed;
    defer allocator_mod.exqlite_free(p);
    try std.testing.expectEqual(@as(c_int, 42), allocator_mod.exqlite_mem_size(p));
}

test "malloc: returns null for zero or negative bytes" {
    try std.testing.expect(allocator_mod.exqlite_malloc(0) == null);
    try std.testing.expect(allocator_mod.exqlite_malloc(-1) == null);
}

test "realloc: updates header to new size" {
    const p = allocator_mod.exqlite_malloc(10) orelse return error.AllocFailed;
    try std.testing.expectEqual(@as(c_int, 10), allocator_mod.exqlite_mem_size(p));
    const p2 = allocator_mod.exqlite_realloc(p, 20) orelse return error.ReallocFailed;
    defer allocator_mod.exqlite_free(p2);
    try std.testing.expectEqual(@as(c_int, 20), allocator_mod.exqlite_mem_size(p2));
}

test "malloc/free: written bytes survive until free" {
    const p: [*]u8 = @ptrCast(allocator_mod.exqlite_malloc(4) orelse return error.AllocFailed);
    defer allocator_mod.exqlite_free(p);
    p[0] = 0xDE;
    p[1] = 0xAD;
    p[2] = 0xBE;
    p[3] = 0xEF;
    try std.testing.expectEqual(@as(u8, 0xDE), p[0]);
    try std.testing.expectEqual(@as(u8, 0xEF), p[3]);
}

// ─── helpers.zig tests ──────────────────────────────────────────────────────

test "TermBuffer.init(0): valid empty buffer, stack path" {
    var buf = helpers.TermBuffer.init(0).?;
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 0), buf.slice().len);
    try std.testing.expect(buf.heap == null);
}

test "TermBuffer.init(64): fills full stack capacity" {
    var buf = helpers.TermBuffer.init(64).?;
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 64), buf.slice().len);
    try std.testing.expect(buf.heap == null);
}

test "TermBuffer.init(65): heap path allocated" {
    var buf = helpers.TermBuffer.init(65).?;
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 65), buf.slice().len);
    try std.testing.expect(buf.heap != null);
}

test "TermBuffer: stack writes visible via second slice() call" {
    var buf = helpers.TermBuffer.init(3).?;
    defer buf.deinit();
    const s = buf.slice();
    s[0] = 111;
    s[2] = 999;
    const s2 = buf.slice();
    try std.testing.expectEqual(@as(nif.Term, 111), s2[0]);
    try std.testing.expectEqual(@as(nif.Term, 999), s2[2]);
}

// ─── nif.zig tests ─────────────────────────────────────────────────────────

test "wrap: produces function pointer with correct signature" {
    const f: nif.NifFn = struct {
        fn call(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
            _ = env;
            _ = argv;
            return 0;
        }
    }.call;
    const fptr = nif.wrap(f);
    _ = fptr; // Function pointer created successfully
}

test "func: builds Func table entry with correct fields" {
    const f: nif.NifFn = struct {
        fn call(env: *nif.Env, argv: [*]const nif.Term) nif.Term {
            _ = env;
            _ = argv;
            return 0;
        }
    }.call;
    const entry = nif.func("my_nif", 3, f, .dirty_io);
    try std.testing.expectEqualStrings("my_nif", std.mem.span(entry.name));
    try std.testing.expectEqual(@as(c_uint, 3), entry.arity);
    try std.testing.expectEqual(@as(c_uint, nif.DIRTY_IO), entry.flags);
    _ = entry.fptr;
}

test "Sched enum: normal=0, dirty_io/dirty_cpu match BEAM constants" {
    try std.testing.expectEqual(@as(c_uint, 0), @intFromEnum(nif.Sched.normal));
    try std.testing.expectEqual(nif.DIRTY_IO, @intFromEnum(nif.Sched.dirty_io));
    try std.testing.expectEqual(nif.DIRTY_CPU, @intFromEnum(nif.Sched.dirty_cpu));
}

// ─── sqlite3.zig tests ─────────────────────────────────────────────────────

test "TRANSIENT is all-bits-set (C -1 cast to pointer)" {
    const val: usize = @intFromPtr(sqlite3.TRANSIENT);
    try std.testing.expectEqual(std.math.maxInt(usize), val);
}

test "STATIC is null" {
    try std.testing.expect(sqlite3.STATIC == null);
}

// ─── atoms.zig tests ───────────────────────────────────────────────────────

test "AtomTable field count matches documented atom count" {
    const field_count = @typeInfo(atoms_mod.AtomTable).@"struct".fields.len;
    // Update this constant when atoms are added/removed.
    try std.testing.expectEqual(@as(usize, 30), field_count);
}
