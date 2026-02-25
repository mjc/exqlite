const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Path to ERTS include directory.  Prefer -Derts-include=<path>, fall back
    // to the ERTS_INCLUDE_DIR environment variable set by the Nix shell / Makefile.
    const erts_include = b.option(
        []const u8,
        "erts-include",
        "Path to ERTS include directory (contains erl_nif.h)",
    ) orelse (std.process.getEnvVarOwned(b.allocator, "ERTS_INCLUDE_DIR") catch "");

    // Use system SQLite instead of the bundled amalgamation.
    const use_system_sqlite = b.option(
        bool,
        "use-system-sqlite",
        "Link against system libsqlite3 instead of the bundled amalgamation",
    ) orelse ((std.process.getEnvVarOwned(b.allocator, "EXQLITE_USE_SYSTEM") catch null) != null);

    // Build a static archive (.a) instead of a shared library.
    const build_static = b.option(
        bool,
        "static",
        "Build a static archive (.a) instead of a shared library",
    ) orelse false;

    // SQLite compile-time feature flags (mirrors the Makefile).
    const sqlite_flags = &[_][]const u8{
        "-DSQLITE_THREADSAFE=1",
        "-DSQLITE_USE_URI=1",
        "-DSQLITE_LIKE_DOESNT_MATCH_BLOBS=1",
        "-DSQLITE_DQS=0",
        "-DHAVE_USLEEP=1",
        "-DALLOW_COVERING_INDEX_SCAN=1",
        "-DENABLE_FTS3_PARENTHESIS=1",
        "-DENABLE_LOAD_EXTENSION=1",
        "-DENABLE_SOUNDEX=1",
        "-DENABLE_STAT4=1",
        "-DENABLE_UPDATE_DELETE_LIMIT=1",
        "-DSQLITE_ENABLE_FTS3=1",
        "-DSQLITE_ENABLE_FTS4=1",
        "-DSQLITE_ENABLE_FTS5=1",
        "-DSQLITE_ENABLE_GEOPOLY=1",
        "-DSQLITE_ENABLE_MATH_FUNCTIONS=1",
        "-DSQLITE_ENABLE_RBU=1",
        "-DSQLITE_ENABLE_RTREE=1",
        "-DSQLITE_OMIT_DEPRECATED=1",
        "-DSQLITE_ENABLE_DBSTAT_VTAB=1",
        "-DNDEBUG=1",
    };

    // ── Root module ────────────────────────────────────────────────────────────
    // In Zig 0.15 the module is the primary unit: includes, C sources, and
    // library linkage are all attached to the module, not the Compile step.
    const root_module = b.createModule(.{
        .root_source_file = b.path("zig_src/sqlite3_nif.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // ERTS headers (erl_nif.h).
    if (erts_include.len > 0) {
        root_module.addIncludePath(.{ .cwd_relative = erts_include });
    }

    // SQLite headers.
    root_module.addIncludePath(b.path("c_src"));

    // SQLite amalgamation or system library.
    if (!use_system_sqlite) {
        root_module.addCSourceFile(.{
            .file = b.path("c_src/sqlite3.c"),
            .flags = sqlite_flags,
        });
    } else {
        root_module.linkSystemLibrary("sqlite3", .{});
    }

    // ── Library ────────────────────────────────────────────────────────────────
    const lib = b.addLibrary(.{
        .name = "sqlite3_nif",
        .root_module = root_module,
        .linkage = if (build_static) .static else .dynamic,
    });

    // macOS: NIFs must use -undefined dynamic_lookup so BEAM symbols resolve
    // at load time rather than link time.
    const resolved_target = target.result;
    if (resolved_target.os.tag == .macos) {
        lib.linker_allow_shlib_undefined = true;
    }

    // ── Install ────────────────────────────────────────────────────────────────
    // The BEAM expects `priv/sqlite3_nif.so` (no `lib` prefix, always `.so`
    // even on macOS; `.dll` on Windows).  Zig's default would produce
    // `lib/libsqlite3_nif.so`, so we use addInstallFileWithDir with an explicit
    // destination name and install directly into the --prefix directory.
    const lib_ext = if (resolved_target.os.tag == .windows) ".dll" else ".so";
    const lib_filename = std.mem.concat(b.allocator, u8, &.{ "sqlite3_nif", lib_ext }) catch @panic("OOM");

    const install_step = b.addInstallFileWithDir(
        lib.getEmittedBin(),
        .prefix, // goes to the directory passed via --prefix
        lib_filename,
    );
    b.getInstallStep().dependOn(&install_step.step);

    // ── Test step ──────────────────────────────────────────────────────────────
    // Runs pure-logic Zig unit tests without the BEAM. Uses a stub erl_nif.h so
    // no Erlang installation is needed.
    const test_module = b.createModule(.{
        .root_source_file = b.path("zig_src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Stub erl_nif.h must come before any real ERTS path.
    test_module.addIncludePath(b.path("zig_src/test_stubs"));
    test_module.addIncludePath(b.path("c_src")); // sqlite3.h
    test_module.addCSourceFile(.{
        .file = b.path("c_src/sqlite3.c"),
        .flags = sqlite_flags,
    });
    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run Zig unit tests (no BEAM required)");
    test_step.dependOn(&run_unit_tests.step);
}
