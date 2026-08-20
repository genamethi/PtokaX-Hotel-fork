#*******************************************************************************
#
# Makefile for PtokaX. Run ./configure first; it writes config.mk.
#
#   ./configure && make && make install
#
#   make V=1                        show full compiler command lines
#   make -j8                        parallel build
#   make DESTDIR=/tmp/stage install staged install
#
#*******************************************************************************

NOCONFIG_GOALS := clean distclean help

ifeq ($(wildcard config.mk),)
  ifeq ($(filter-out $(NOCONFIG_GOALS),$(or $(MAKECMDGOALS),all)),)
    srcdir := .
  else
    $(error No config.mk found. Run ./configure first (./configure --help for options))
  endif
else
  include config.mk
endif

#*******************************************************************************
# Quiet output
#*******************************************************************************
V ?= 0
ifeq ($(V),0)
  Q := @
  say = @printf '  %-8s %s\n' '$(1)' '$(2)'
else
  Q :=
  say =
endif

#*******************************************************************************
# Sources
#*******************************************************************************
# PtokaX-win, ExceptionHandling and UpdateCheckThread are Windows-only; the
# DB-* backends are mutually exclusive and configure selects one via DB_SRC.
CORE_EXCLUDE := \
	PtokaX-win.cpp \
	ExceptionHandling.cpp \
	UpdateCheckThread.cpp \
	DB-SQLite.cpp \
	DB-PostgreSQL.cpp \
	DB-MySQL.cpp

CORE_SRCS := $(patsubst $(srcdir)/%,%,$(wildcard $(srcdir)/core/*.cpp))

SRCS_CXX := $(filter-out $(addprefix core/,$(CORE_EXCLUDE)),$(CORE_SRCS)) $(DB_SRC)
SRCS_C   :=

ifneq ($(TINYXML_DIR),)
SRCS_CXX += $(addprefix $(TINYXML_DIR)/,\
              tinystr.cpp tinyxml.cpp tinyxmlerror.cpp tinyxmlparser.cpp)
endif

ifneq ($(SKEIN_DIR),)
SRCS_C += $(addprefix $(SKEIN_DIR)/,skein.c skein_block.c)
endif

BUILDDIR := build
OBJS := $(addprefix $(BUILDDIR)/,$(SRCS_CXX:.cpp=.o) $(SRCS_C:.c=.o))
DEPS := $(OBJS:.o=.d)

TARGET := PtokaX

#*******************************************************************************
# Flags
#*******************************************************************************
DEPFLAGS := -MMD -MP

INCFLAGS := -I$(srcdir)/core \
            $(if $(SKEIN_DIR),-I$(srcdir)/$(SKEIN_DIR)) \
            $(if $(TINYXML_DIR),-I$(srcdir)/$(TINYXML_DIR))

ALL_CPPFLAGS := $(INCFLAGS) $(TINYXML_DEFINES) $(FEATURE_DEFINES) \
                $(ICONV_DEFINES) \
                $(LUA_CFLAGS) $(ZLIB_CFLAGS) $(DB_CFLAGS) \
                $(CONF_CPPFLAGS) $(CPPFLAGS)

ALL_CXXFLAGS := $(CONF_OPTFLAGS) $(CONF_WARNFLAGS) $(PTHREAD_CFLAGS) \
                $(CONF_CXXFLAGS) $(CXXFLAGS)

ALL_CFLAGS   := $(CONF_OPTFLAGS) $(CONF_WARNFLAGS) $(PTHREAD_CFLAGS) \
                $(CONF_CFLAGS) $(CFLAGS)

ALL_LDFLAGS  := $(CONF_LDFLAGS) $(LDFLAGS)

ALL_LIBS     := $(LUA_LIBS) $(ZLIB_LIBS) $(DB_LIBS) $(TINYXML_LIBS) \
                $(ICONV_LIBS) $(DL_LIBS) $(SOCKET_LIBS) $(PTHREAD_LIBS) -lm \
                $(CONF_LIBS) $(LIBS)

#*******************************************************************************
# Build
#*******************************************************************************
.PHONY: all
all: $(TARGET)

$(TARGET): $(OBJS)
	$(call say,LINK,$@)
	$(Q)$(CXX) $(ALL_LDFLAGS) $(OBJS) -o $@ $(ALL_LIBS)

$(BUILDDIR)/%.o: $(srcdir)/%.cpp
	@mkdir -p $(@D)
	$(call say,CXX,$*.cpp)
	$(Q)$(CXX) $(ALL_CPPFLAGS) $(ALL_CXXFLAGS) $(DEPFLAGS) -c $< -o $@

$(BUILDDIR)/%.o: $(srcdir)/%.c
	@mkdir -p $(@D)
	$(call say,CC,$*.c)
	$(Q)$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS) $(DEPFLAGS) -c $< -o $@

-include $(DEPS)

$(OBJS): config.mk

config.mk: $(srcdir)/configure
	@echo "  config.mk is older than configure; re-running configure"
	$(Q)eval "$(srcdir)/configure $(CONFIGURE_ARGS)"

#*******************************************************************************
# Install
#*******************************************************************************
# PtokaX resolves language/, cfg/, scripts/ and texts/ relative to its runtime
# config directory (-c), so there is no system data directory to install.
.PHONY: install
install: $(TARGET)
	$(INSTALL) -d $(DESTDIR)$(bindir)
	$(INSTALL) -m 755 $(TARGET) $(DESTDIR)$(bindir)/$(TARGET)
	@echo ""
	@echo "  $(TARGET) installed to $(DESTDIR)$(bindir)/$(TARGET)"
	@echo "  See compile.txt for seeding a config directory."
	@echo ""

.PHONY: uninstall
uninstall:
	rm -f $(DESTDIR)$(bindir)/$(TARGET)

#*******************************************************************************
# Housekeeping
#*******************************************************************************
# -v returns inside the argv loop before any path resolution or mkdir, so this
# creates no files and opens no sockets.
.PHONY: check
check: $(TARGET)
	$(Q)./$(TARGET) -v

.PHONY: clean
clean:
	rm -rf $(BUILDDIR) $(TARGET)

.PHONY: distclean
distclean: clean
	rm -f config.mk config.log $(GENERATED_MAKEFILE)

.PHONY: config
config:
	$(Q)eval "$(srcdir)/configure $(CONFIGURE_ARGS)"

.PHONY: help
help:
	@echo "PtokaX $(PACKAGE_VERSION) -- make targets"
	@echo ""
	@echo "  all        build $(TARGET) (default)"
	@echo "  install    install to \$$(DESTDIR)\$$(bindir)"
	@echo "  uninstall  remove the installed binary"
	@echo "  check      smoke test the built binary"
	@echo "  clean      remove build output"
	@echo "  distclean  also remove config.mk and config.log"
	@echo "  config     re-run ./configure with the options it was last given"
	@echo ""
	@echo "  make V=1   show full compiler command lines"
	@echo ""
ifeq ($(wildcard config.mk),)
	@echo "Not configured yet -- run ./configure (--help for options)."
	@echo ""
else
	@echo "Current configuration (from config.mk):"
	@echo "  prefix     $(prefix)"
	@echo "  bindir     $(DESTDIR)$(bindir)"
	@echo "  compiler   $(CXX)"
	@echo "  Lua        $(LUA_VERSION)"
	@echo "  database   $(DB_BACKEND)"
	@echo "  tinyxml    $(if $(TINYXML_DIR),bundled,system)"
	@echo "  Skein      $(if $(SKEIN_DIR),yes,no)"
	@echo ""
endif
