# Define a set of targets for generating a fake JLL package.  This "fake JLL package" will
# load libraries off of the global library search path; it won't use artifacts.
# It also has (extremely limited) support for executable products; it just assumes they
# are inside `libexec`.
#
# Parameters to this macro::
#   $1 = jll_name (e.g. OpenBLAS_jll)
#   $2 = list of library names in "varname1=filename1 varname2=filename2 ..." format.
#        Example: "libopenblas=libopenblas64_ liblapack=libopenblas64_"
#   $3 = list of executable names in "varname1=fileaname1 varname2=filename2 ..."
#        Example: "clang=clang-6$(EXE)"
#   $4 = jll_uuid (e.g. "f1936524-4db9-4c7a-6f3e-6fc869057263")
#   $5 = JLL dependencies in "name1=UUID1 name2=UUID2:..." format.
#        Example: "OpenBLAS_JLL=f1936524-4db9-4c7a-6f3e-6fc869057263".

define jll-generate
# Target name is lowercased prefix, e.g. "MbedTLS_jll" -> "mbedtls"
$(1)_TARGET_NAME := $(firstword $(subst _, ,$(call lowercase,$(1))))
# We are going to generate this directly into the target directory
$(1)_SRC_DIR := $(build_datarootdir)/julia/stdlib/$(VERSDIR)/$(1)

$$($(1)_SRC_DIR):
	@mkdir -p "$$@"

# Generate boilerplate `dlopen()` pasta
$$($(1)_SRC_DIR)/src/$(1).jl: | $$($(1)_SRC_DIR)
	@mkdir -p "$$(dir $$@)"
	@echo "module $(strip $(1))" > "$$@"
	@echo "using Base.Libc.Libdl" >> "$$@"
	@echo "const PATH_list = String[]; const LIBPATH_list = String[]" >> "$$@"
	@# Generate `using $dep` for each dependency
	@for deppair in $(5); do \
		name=$$$$(echo $$$${deppair} | cut -d'=' -f1); \
		echo "Base.@include_stdlib_jll(\"$$$${name}\")" >> "$$@"; \
		echo "using .$$$${name}" >> "$$@"; \
	done

	@# Generate placeholder global variables for all libraries we're going to export
	@for libpair in $(2); do \
		varname=$$$$(echo $$$${libpair} | cut -d'=' -f1); \
		fname=$$$$(echo $$$${libpair} | cut -d'=' -f2); \
		echo "export $$$${varname}" >> "$$@"; \
		echo "const $$$${varname} = $$$${fname}" >> "$$@"; \
		echo "$$$${varname}_handle = C_NULL" >> "$$@"; \
		echo "$$$${varname}_path = \"\"" >> "$$@"; \
		echo >> "$$@"; \
	done

	@# Generate functions for all the executables we're going to export
	@for exepair in $(3); do \
		varname=$$$$(echo $$$${exepair} | cut -d'=' -f1); \
		fname=$$$$(echo $$$${exepair} | cut -d'=' -f2); \
		echo "export $$$${varname}" >> "$$@"; \
		echo "function $$$${varname}(f::Function; adjust_PATH::Bool = true, adjust_LIBPATH::Bool = true)" >> "$$@"; \
		echo "    f(joinpath(Sys.BINDIR, Base.LIBEXECDIR, $$$${fname}))" >> "$$@"; \
		echo "end" >> "$$@"; \
		echo >> "$$@"; \
	done

	@# Generate an `__init__()` that just blithely calls `dlopen(SONAME)` for each library.
	@# This only works if the library is locatable on the current RPATH of the executable,
	@# and all dependencies are as well or have already been dlopen'ed, which, if we're
	@# generating a fake JLL, we know to be true.
	@echo "function __init__()" >> "$$@"
	@for libpair in $(2); do \
		varname=$$$$(echo $$$${libpair} | cut -d'=' -f1); \
		echo "    global $$$${varname}_handle, $$$${varname}_path" >> "$$@"; \
		echo "    $$$${varname}_handle = dlopen($$$${varname})" >> "$$@"; \
		echo "    $$$${varname}_path = abspath(dlpath($$$${varname}))" >> "$$@"; \
	done
	@echo "end # function __init__()" >> "$$@"
	@echo "end # module $(1)" >> "$$@"

# Generate an appropriate Project.toml
$$($(1)_SRC_DIR)/Project.toml: | $$($(1)_SRC_DIR)
	@echo "name = \"$(strip $(1))\"" > "$$@"
	@echo "uuid = \"$(strip $(4))\"" >> "$$@"
	@echo "version = \"$(shell cat $(JULIAHOME)/VERSION | cut -d. -f1-3)\"" >> "$$@"
	
	@echo "[deps]" >> "$$@"
	@echo "Libdl = \"8f399da3-3557-5675-b5ff-fb832c97cbdb\"" >> "$$@"
	@# Generate dependency mappings for all deps
	@for deppair in $(5); do \
		name=$$$$(echo $$$${deppair} | cut -d'=' -f1); \
		uuid=$$$$(echo $$$${deppair} | cut -d'=' -f2); \
		echo "$$$${name} = \"$$$${uuid}\"" >> "$$@"; \
	done

$$($(1)_SRC_DIR)/README.md: | $$($(1)_SRC_DIR)
	@echo "This is an autogenerated package." > "$$@"
 
UNINSTALL_$(1) := delete-uninstaller $$($(1)_SRC_DIR)
$(build_prefix)/manifest/$(1): $$($(1)_SRC_DIR)/src/$(1).jl $$($(1)_SRC_DIR)/Project.toml $$($(1)_SRC_DIR)/README.md | $(build_prefix)/manifest
	@echo '$$(UNINSTALL_$(1))' > "$$@"

get-$(1):
configure-$(1):
install-$(1): $(build_prefix)/manifest/$(1)
clean-$(1):
	rm -rf $(build_datarootdir)/julia/stdlib/$(VERSDIR)/$(1)
	rm -f $(build_prefix)/manifest/$(1)
distclean-$(1): clean-$(1)

# Generate helpful MBEDTLS_LIBDIR/MBEDTLS_INCDIR variable to point to julia's libdir/include dir
$$(call uppercase,$$($(1)_TARGET_NAME))_LIBDIR := $(build_libdir)
$$(call uppercase,$$($(1)_TARGET_NAME))_INCDIR := $(build_includedir)

# Make install-mbedtls rely on install-MbedTLS_jll
install-$$($(1)_TARGET_NAME): install-$(1)
endef