// Minimal stub of erl_nif.h for standalone Zig unit tests.
// Uses static inline implementations backed by libc malloc/free.
// No BEAM symbols are required; tests run without Erlang installation.

#ifndef __ERL_NIF_STUB_H
#define __ERL_NIF_STUB_H

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>

// ─── Basic types ──────────────────────────────────────────────────────────

// ERL_NIF_TERM: in Zig this becomes nif.Term = usize
typedef uintptr_t ERL_NIF_TERM;
typedef int ErlNifSInt64;

// ErlNifBinary: layout must match what nif.Binary expects
typedef struct {
    size_t size;
    unsigned char *data;
} ErlNifBinary;

// ErlNifPid: sized generously (oversized to be safe across OTP versions)
typedef struct {
    unsigned char pid_data[32];
} ErlNifPid;

// ErlNifMutex: opaque single-field struct
typedef struct {
    void *data;
} ErlNifMutex;

// ErlNifResourceType: opaque single-field struct
typedef struct {
    void *data;
} ErlNifResourceType;

// ErlNifResourceTypeInit: opaque single-field struct
typedef struct {
    void *data;
} ErlNifResourceTypeInit;

// ErlNifEnv: opaque single-field struct
typedef struct {
    void *data;
} ErlNifEnv;

// Function pointer type used by sqlite3_set_destructor
typedef void (*sqlite3_destructor_type)(void*);

// ─── Constants ─────────────────────────────────────────────────────────────

#define ERL_NIF_RT_CREATE    1
#define ERL_NIF_RT_TAKEOVER  2

#define ERL_NIF_DIRTY_JOB_IO_BOUND   2
#define ERL_NIF_DIRTY_JOB_CPU_BOUND  4

// Resource flags
typedef unsigned int ErlNifResourceFlags;

// ─── Stub implementations: libc malloc/free backed ────────────────────────

static inline void *enif_alloc(size_t size) {
    return malloc(size);
}

static inline void enif_free(void *ptr) {
    free(ptr);
}

static inline void *enif_realloc(void *ptr, size_t size) {
    return realloc(ptr, size);
}

// Mutex stubs (non-thread-safe no-ops for tests)
static inline ErlNifMutex *enif_mutex_create(const char *name) {
    (void)name;
    ErlNifMutex *m = (ErlNifMutex *)malloc(sizeof(ErlNifMutex));
    if (m) m->data = NULL;
    return m;
}

static inline void enif_mutex_destroy(ErlNifMutex *mutex) {
    free(mutex);
}

static inline void enif_mutex_lock(ErlNifMutex *mutex) {
    (void)mutex;
    // no-op
}

static inline void enif_mutex_unlock(ErlNifMutex *mutex) {
    (void)mutex;
    // no-op
}

// Resource stubs: return NULL (tests won't use resources)
static inline ErlNifResourceType *enif_open_resource_type(
    ErlNifEnv *env,
    const char *module_name,
    const char *name,
    void (*destructor)(ErlNifEnv*, void *),
    ErlNifResourceFlags flags,
    ErlNifResourceFlags *tried
) {
    (void)env; (void)module_name; (void)name; (void)destructor; (void)flags; (void)tried;
    return NULL;
}

static inline void *enif_alloc_resource(ErlNifResourceType *type, size_t size) {
    (void)type;
    return malloc(size);
}

static inline void enif_release_resource(void *obj) {
    (void)obj;
    // no-op
}

static inline void enif_keep_resource(void *obj) {
    (void)obj;
    // no-op
}

// Binary stubs
static inline int enif_alloc_binary(size_t size, ErlNifBinary *bin) {
    if (!bin) return 0;
    bin->data = (unsigned char *)malloc(size);
    if (!bin->data && size > 0) return 0;
    bin->size = size;
    return 1;
}

static inline int enif_inspect_iolist_as_binary(ErlNifEnv *env, ERL_NIF_TERM term, ErlNifBinary *bin) {
    (void)env; (void)term; (void)bin;
    return 0;  // stub: unsupported in tests
}

static inline int enif_inspect_binary(ErlNifEnv *env, ERL_NIF_TERM term, ErlNifBinary *bin) {
    (void)env; (void)term; (void)bin;
    return 0;  // stub: unsupported in tests
}

static inline void enif_release_binary(ErlNifBinary *bin) {
    free(bin->data);
    bin->data = NULL;
    bin->size = 0;
}

// Term construction stubs (return 0; tests won't use these)
static inline ERL_NIF_TERM enif_make_atom(ErlNifEnv *env, const char *name) {
    (void)env; (void)name;
    return 0;
}

static inline ERL_NIF_TERM enif_make_int(ErlNifEnv *env, int i) {
    (void)env; (void)i;
    return 0;
}

static inline ERL_NIF_TERM enif_make_int64(ErlNifEnv *env, ErlNifSInt64 i) {
    (void)env; (void)i;
    return 0;
}

static inline ERL_NIF_TERM enif_make_double(ErlNifEnv *env, double d) {
    (void)env; (void)d;
    return 0;
}

static inline ERL_NIF_TERM enif_make_binary(ErlNifEnv *env, ErlNifBinary *bin) {
    (void)env; (void)bin;
    return 0;
}

static inline ERL_NIF_TERM enif_make_tuple2(ErlNifEnv *env, ERL_NIF_TERM a1, ERL_NIF_TERM a2) {
    (void)env; (void)a1; (void)a2;
    return 0;
}

static inline ERL_NIF_TERM enif_make_tuple3(ErlNifEnv *env, ERL_NIF_TERM a1, ERL_NIF_TERM a2, ERL_NIF_TERM a3) {
    (void)env; (void)a1; (void)a2; (void)a3;
    return 0;
}

static inline ERL_NIF_TERM enif_make_tuple4(ErlNifEnv *env, ERL_NIF_TERM a1, ERL_NIF_TERM a2, ERL_NIF_TERM a3, ERL_NIF_TERM a4) {
    (void)env; (void)a1; (void)a2; (void)a3; (void)a4;
    return 0;
}

static inline ERL_NIF_TERM enif_make_list_from_array(ErlNifEnv *env, const ERL_NIF_TERM *arr, unsigned int cnt) {
    (void)env; (void)arr; (void)cnt;
    return 0;
}

static inline ERL_NIF_TERM enif_make_list2(ErlNifEnv *env, ERL_NIF_TERM a1, ERL_NIF_TERM a2) {
    (void)env; (void)a1; (void)a2;
    return 0;
}

static inline ERL_NIF_TERM enif_make_list_cell(ErlNifEnv *env, ERL_NIF_TERM head, ERL_NIF_TERM tail) {
    (void)env; (void)head; (void)tail;
    return 0;
}

static inline ERL_NIF_TERM enif_make_badarg(ErlNifEnv *env) {
    (void)env;
    return 0;
}

static inline ERL_NIF_TERM enif_raise_exception(ErlNifEnv *env, ERL_NIF_TERM reason) {
    (void)env; (void)reason;
    return 0;
}

static inline ERL_NIF_TERM enif_make_resource(ErlNifEnv *env, void *obj) {
    (void)env; (void)obj;
    return 0;
}

static inline ERL_NIF_TERM enif_make_copy(ErlNifEnv *dst, ERL_NIF_TERM term) {
    (void)dst; (void)term;
    return 0;
}

// Getters: return 0 (unsupported in stub)
static inline int enif_get_resource(ErlNifEnv *env, ERL_NIF_TERM term, ErlNifResourceType *type, void **obj) {
    (void)env; (void)term; (void)type; (void)obj;
    return 0;
}

static inline int enif_get_int(ErlNifEnv *env, ERL_NIF_TERM term, int *value) {
    (void)env; (void)term; (void)value;
    return 0;
}

static inline int enif_get_uint(ErlNifEnv *env, ERL_NIF_TERM term, unsigned int *value) {
    (void)env; (void)term; (void)value;
    return 0;
}

static inline int enif_get_int64(ErlNifEnv *env, ERL_NIF_TERM term, ErlNifSInt64 *value) {
    (void)env; (void)term; (void)value;
    return 0;
}

static inline int enif_get_double(ErlNifEnv *env, ERL_NIF_TERM term, double *value) {
    (void)env; (void)term; (void)value;
    return 0;
}

static inline int enif_get_local_pid(ErlNifEnv *env, ERL_NIF_TERM term, ErlNifPid *pid) {
    (void)env; (void)term; (void)pid;
    return 0;
}

// Env allocation stubs
static inline ErlNifEnv *enif_alloc_env(void) {
    return (ErlNifEnv *)malloc(sizeof(ErlNifEnv));
}

static inline void enif_free_env(ErlNifEnv *env) {
    free(env);
}

static inline int enif_send(ErlNifEnv *from_env, const ErlNifPid *to_pid,
                             ErlNifEnv *msg_env, ERL_NIF_TERM msg) {
    (void)from_env; (void)to_pid; (void)msg_env; (void)msg;
    return 0;
}

#endif  // __ERL_NIF_STUB_H
