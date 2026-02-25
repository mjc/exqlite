#
# Makefile for building the NIF
#
# Makefile targets:
#
# all    build and install the NIF
# clean  clean build products and intermediates
#
# Variables to override:
#
# MIX_APP_PATH  path to the build directory
#
# CC            The C compiler (used only with EXQLITE_USE_C_NIF=1)
# CROSSCOMPILE  crosscompiler prefix, if any
# CFLAGS        compiler flags for compiling all C files
# LDFLAGS       linker flags for linking all binaries
# ERL_CFLAGS    additional compiler flags for files using Erlang header files
# ERL_EI_INCLUDE_DIR  include path to header files (Possibly required for crosscompile)
#

PREFIX = $(MIX_APP_PATH)/priv
BUILD  = $(MIX_APP_PATH)/obj
LIB_NAME = $(PREFIX)/sqlite3_nif.so
ARCHIVE_NAME = $(PREFIX)/sqlite3_nif.a

KERNEL_NAME := $(shell uname -s)

# ####################
# ZIG BUILD (default)
# ####################

# Use C NIF rollback if explicitly requested
ifeq ($(EXQLITE_USE_C_NIF),)

ZIG ?= zig
ZIG_OPTS = --prefix "$(PREFIX)"

ifneq ($(ERTS_INCLUDE_DIR),)
	ZIG_OPTS += -Derts-include="$(ERTS_INCLUDE_DIR)"
endif

ifneq ($(EXQLITE_USE_SYSTEM),)
	ZIG_OPTS += -Duse-system-sqlite=true
endif

ifneq ($(DEBUG),)
	ZIG_OPTS += -Doptimize=Debug
else
	ZIG_OPTS += -Doptimize=ReleaseFast
endif

ifneq ($(STATIC_ERLANG_NIF),)
	ZIG_OPTS += -Dstatic=true
endif

ifneq ($(CC_PRECOMPILER_CURRENT_TARGET),)
	ZIG_OPTS += -Dtarget=$(CC_PRECOMPILER_CURRENT_TARGET)
endif

ifeq ($(STATIC_ERLANG_NIF),)
all: $(PREFIX)
	$(ZIG) build $(ZIG_OPTS)
else
all: $(PREFIX)
	$(ZIG) build $(ZIG_OPTS)
endif

clean:
	$(RM) $(LIB_NAME) $(ARCHIVE_NAME)
	$(RM) -r zig-out zig-cache .zig-cache

else

# ####################
# C BUILD (rollback via EXQLITE_USE_C_NIF=1)
# ####################

SRC = c_src/sqlite3_nif.c

CFLAGS = -I"$(ERTS_INCLUDE_DIR)"

ifeq ($(EXQLITE_USE_SYSTEM),)
	SRC += c_src/sqlite3.c
	CFLAGS += -Ic_src
else
	ifneq ($(EXQLITE_SYSTEM_LDFLAGS),)
		LDFLAGS += $(EXQLITE_SYSTEM_LDFLAGS)
	else
		LDFLAGS += -lsqlite3
	endif
endif

ifneq ($(DEBUG),)
	CFLAGS += -g
else
	CFLAGS += -DNDEBUG=1 -O2
endif

OBJ = $(SRC:c_src/%.c=$(BUILD)/%.o)

ifneq ($(CROSSCOMPILE),)
	ifeq ($(CROSSCOMPILE), Android)
		CFLAGS:=$(filter-out -O2,$(CFLAGS))
		CFLAGS += -fPIC -Os -z global
		LDFLAGS += -fPIC -shared -lm
	else ifeq ($(findstring linux,$(CROSSCOMPILE)),linux)
		CFLAGS:=$(filter-out -O2,$(CFLAGS))
		CFLAGS += -fPIC -Os -fvisibility=hidden
		LDFLAGS += -fPIC -shared
	else
		CFLAGS += -fPIC -fvisibility=hidden
		LDFLAGS += -fPIC -shared
	endif
else
	ifeq ($(KERNEL_NAME), Linux)
		CFLAGS += -fPIC -fvisibility=hidden
		LDFLAGS += -fPIC -shared
	endif
	ifeq ($(KERNEL_NAME), Darwin)
		CFLAGS += -fPIC
		LDFLAGS += -dynamiclib -undefined dynamic_lookup
	endif
	ifeq (MINGW, $(findstring MINGW,$(KERNEL_NAME)))
		CFLAGS += -fPIC
		LDFLAGS += -fPIC -shared
		LIB_NAME = $(PREFIX)/sqlite3_nif.dll
	endif
	ifeq ($(KERNEL_NAME), $(filter $(KERNEL_NAME),OpenBSD FreeBSD NetBSD SunOS))
		CFLAGS += -fPIC
		LDFLAGS += -fPIC -shared
	endif
endif

# ########################
# COMPILE TIME DEFINITIONS
# ########################

CFLAGS += -DSQLITE_THREADSAFE=1
CFLAGS += -DSQLITE_USE_URI=1
CFLAGS += -DSQLITE_LIKE_DOESNT_MATCH_BLOBS=1
CFLAGS += -DSQLITE_DQS=0
CFLAGS += -DHAVE_USLEEP=1
CFLAGS += -DALLOW_COVERING_INDEX_SCAN=1
CFLAGS += -DENABLE_FTS3_PARENTHESIS=1
CFLAGS += -DENABLE_LOAD_EXTENSION=1
CFLAGS += -DENABLE_SOUNDEX=1
CFLAGS += -DENABLE_STAT4=1
CFLAGS += -DENABLE_UPDATE_DELETE_LIMIT=1
CFLAGS += -DSQLITE_ENABLE_FTS3=1
CFLAGS += -DSQLITE_ENABLE_FTS4=1
CFLAGS += -DSQLITE_ENABLE_FTS5=1
CFLAGS += -DSQLITE_ENABLE_GEOPOLY=1
CFLAGS += -DSQLITE_ENABLE_MATH_FUNCTIONS=1
CFLAGS += -DSQLITE_ENABLE_RBU=1
CFLAGS += -DSQLITE_ENABLE_RTREE=1
CFLAGS += -DSQLITE_OMIT_DEPRECATED=1
CFLAGS += -DSQLITE_ENABLE_DBSTAT_VTAB=1

ifneq ($(EXQLITE_SYSTEM_CFLAGS),)
	CFLAGS += $(EXQLITE_SYSTEM_CFLAGS)
endif

ifeq ($(CC_PRECOMPILER_CURRENT_TARGET),armv7l-linux-gnueabihf)
	ERL_CFLAGS ?= -I"$(PRECOMPILE_ERL_EI_INCLUDE_DIR)"
else
	ERL_CFLAGS ?= -I"$(ERL_EI_INCLUDE_DIR)"
endif

ifneq ($(STATIC_ERLANG_NIF),)
	CFLAGS += -DSTATIC_ERLANG_NIF=1
endif

ifeq ($(STATIC_ERLANG_NIF),)
all: $(PREFIX) $(BUILD) $(LIB_NAME)
else
all: $(PREFIX) $(BUILD) $(ARCHIVE_NAME)
endif

$(BUILD)/%.o: c_src/%.c
	@echo " CC $(notdir $@)"
	$(CC) -c $(ERL_CFLAGS) $(CFLAGS) -o $@ $<

$(LIB_NAME): $(OBJ)
	@echo " LD $(notdir $@)"
	$(CC) -o $@ $^ $(LDFLAGS)

$(ARCHIVE_NAME): $(OBJ)
	@echo " AR $(notdir $@)"
	$(AR) -rv $@ $^

clean:
	$(RM) $(LIB_NAME) $(ARCHIVE_NAME) $(OBJ)

endif

$(PREFIX) $(BUILD):
	mkdir -p $@

.PHONY: all clean test

test:
	@echo " ZIG test"
	zig test zig_src/tests.zig -I zig_src/test_stubs -I c_src -lc c_src/sqlite3.c

# Don't echo commands unless the caller exports "V=1"
${V}.SILENT:
