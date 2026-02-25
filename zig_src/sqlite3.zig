//! Thin Zig wrapper around sqlite3.h via @cImport.

const std = @import("std");

pub const c = @cImport({
    @cInclude("sqlite3.h");
});

// Type aliases
pub const Database = c.sqlite3;
pub const Stmt = c.sqlite3_stmt;
pub const MemMethods = c.sqlite3_mem_methods;

// Result codes
pub const OK = c.SQLITE_OK;
pub const ROW = c.SQLITE_ROW;
pub const DONE = c.SQLITE_DONE;
pub const BUSY = c.SQLITE_BUSY;
pub const MISUSE = c.SQLITE_MISUSE;
pub const ERROR = c.SQLITE_ERROR;

// Column types
pub const INTEGER = c.SQLITE_INTEGER;
pub const FLOAT = c.SQLITE_FLOAT;
pub const TEXT = c.SQLITE_TEXT;
pub const BLOB = c.SQLITE_BLOB;
pub const NULL = c.SQLITE_NULL;

// sqlite3_update_hook operation codes
pub const INSERT = c.SQLITE_INSERT;
pub const DELETE = c.SQLITE_DELETE;
pub const UPDATE = c.SQLITE_UPDATE;

// Memory passing semantics.
// SQLITE_TRANSIENT = ((sqlite3_destructor_type)(-1)) — a C macro involving a
// function-pointer cast that @cImport cannot translate.  Define manually: -1
// as usize == all bits set, which is the sentinel value sqlite3 checks for.
pub const TRANSIENT: c.sqlite3_destructor_type = @ptrFromInt(std.math.maxInt(usize));
pub const STATIC: c.sqlite3_destructor_type = null;

// Deserialize flags
pub const DESERIALIZE_FREEONCLOSE = c.SQLITE_DESERIALIZE_FREEONCLOSE;
pub const DESERIALIZE_RESIZEABLE = c.SQLITE_DESERIALIZE_RESIZEABLE;

// Config options
pub const CONFIG_GETMALLOC = c.SQLITE_CONFIG_GETMALLOC;
pub const CONFIG_MALLOC = c.SQLITE_CONFIG_MALLOC;
pub const CONFIG_LOG = c.SQLITE_CONFIG_LOG;
