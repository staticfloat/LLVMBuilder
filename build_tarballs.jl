using BinaryBuilder

# Collection of sources required to build LLVM
llvm_ver = "6.0.0"
sources = [
    "http://releases.llvm.org/$(llvm_ver)/llvm-$(llvm_ver).src.tar.xz" =>
    "1ff53c915b4e761ef400b803f07261ade637b0c269d99569f18040f3dcee4408",
    "http://releases.llvm.org/$(llvm_ver)/cfe-$(llvm_ver).src.tar.xz" =>
    "e07d6dd8d9ef196cfc8e8bb131cbd6a2ed0b1caf1715f9d05b0f0eeaddb6df32",
    "http://releases.llvm.org/$(llvm_ver)/compiler-rt-$(llvm_ver).src.tar.xz" =>
    "d0cc1342cf57e9a8d52f5498da47a3b28d24ac0d39cbc92308781b3ee0cea79a",
    #"http://releases.llvm.org/$(llvm_ver)/lldb-$(llvm_ver).src.tar.xz" =>
    #"46f54c1d7adcd047d87c0179f7b6fa751614f339f4f87e60abceaa45f414d454",
    "http://releases.llvm.org/$(llvm_ver)/libcxx-$(llvm_ver).src.tar.xz" =>
    "70931a87bde9d358af6cb7869e7535ec6b015f7e6df64def6d2ecdd954040dd9",
    "http://releases.llvm.org/$(llvm_ver)/libcxxabi-$(llvm_ver).src.tar.xz" =>
    "91c6d9c5426306ce28d0627d6a4448e7d164d6a3f64b01cb1d196003b16d641b",
    "http://releases.llvm.org/$(llvm_ver)/polly-$(llvm_ver).src.tar.xz" =>
    "47e493a799dca35bc68ca2ceaeed27c5ca09b12241f87f7220b5f5882194f59c",
    "http://releases.llvm.org/$(llvm_ver)/libunwind-$(llvm_ver).src.tar.xz" =>
    "256c4ed971191bde42208386c8d39e5143fa4afd098e03bd2c140c878c63f1d6",

    # Include our LLVM patches
    "patches",
]

# Since we kind of do this LLVM setup twice, this is the shared setup start:
script_setup = raw"""
# We want to exit the program if errors occur.
set -o errexit

cd $WORKSPACE/srcdir/

# First, move our other projects into llvm/projects
for f in *.src; do
    # Don't symlink llvm itself into llvm/projects...
    if [[ ${f} == llvm-*.src ]]; then
        continue
    fi

    # clang lives in tools/clang and not projects/cfe
    if [[ ${f} == cfe-*.src ]]; then
        mv $(pwd)/${f} $(echo llvm-*.src)/tools/clang
    elif [[ ${f} == polly-*.src ]]; then
        mv $(pwd)/${f} $(echo llvm-*.src)/tools/polly
    else
        mv $(pwd)/${f} $(echo llvm-*.src)/projects/${f%-*}
    fi
done

# Next, boogie on down to llvm town
cd llvm-*.src

# Update config.guess/config.sub stuff
update_configure_scripts

# Apply all our patches
for f in $WORKSPACE/srcdir/llvm_patches/*.patch; do
    patch -p1 < ${f}
done
"""

# The very first thing we need to do is to build llvm-tblgen for x86_64-linux-gnu
# This is because LLVM's cross-compile setup is kind of borked, so we just
# build the tools natively ourselves, directly.  :/
script = script_setup * raw"""
# Build llvm-tblgen, clang-tblgen, and llvm-config
mkdir build && cd build
CMAKE_FLAGS="-DLLVM_TARGETS_TO_BUILD:STRING=host"
CMAKE_FLAGS="${CMAKE_FLAGS} -DCMAKE_CXX_FLAGS=-std=c++0x"
cmake .. ${CMAKE_FLAGS}
make -j${nproc} llvm-tblgen clang-tblgen llvm-config

# Copy the tblgens and llvm-config into our destination `bin` folder:
mkdir -p $prefix/bin
mv bin/llvm-tblgen $prefix/bin/
mv bin/clang-tblgen $prefix/bin/
mv bin/llvm-config $prefix/bin/
"""

# We'll do this build for x86_64-linux-gnu only, as that's the arch we're building on
platforms = [
    Linux(:x86_64),
]

# We only care about llvm-tblgen and clang-tblgen
products(prefix) = [
    ExecutableProduct(prefix, "llvm-tblgen", :llvm_tblgen)
    ExecutableProduct(prefix, "clang-tblgen", :clang_tblgen)
    ExecutableProduct(prefix, "llvm-config", :llvm_config)
]

# Dependencies that must be installed before this package can be built
dependencies = [
]

llvm_ARGS = filter(s->startswith(s, "--llvm"), ARGS)
filter!(s->!startswith(s, "--llvm"), ARGS)

# Build the tarball, overriding ARGS so that the user doesn't shoot themselves in the foot,
# but only do this if we don't already have a Tblgen tarball available:
tblgen_tarball = joinpath("products", "tblgen.x86_64-linux-gnu.tar.gz")
if !isfile(tblgen_tarball)
    tblgen_ARGS = ["x86_64-linux-gnu"]
    if "--verbose" in ARGS
        push!(tblgen_ARGS, "--verbose")
    end
    product_hashes = build_tarballs(tblgen_ARGS, "tblgen", sources, script, platforms, products, dependencies)

    # Extract path information to the built tblgen tarball and its hash
    tblgen_tarball, tblgen_hash = product_hashes["x86_64-linux-gnu"]
    tblgen_tarball = joinpath("products", tblgen_tarball)
else
    info("Using pre-built tblgen tarball at $(tblgen_tarball)")
    using SHA: sha256
    tblgen_hash = open(tblgen_tarball) do f
        bytes2hex(sha256(f))
    end
end

# Take that tarball, feed it into our next build as another "source".
push!(sources, tblgen_tarball => tblgen_hash)

# Next, we will Bash recipe for building across all platforms
script = script_setup * raw"""
# This value is really useful later
LLVM_DIR=$(pwd)

# Let's do the actual build within the `build` subdirectory
mkdir build && cd build

# Accumulate these flags outside CMAKE_FLAGS,
# they will be added at the end.
CMAKE_CPP_FLAGS=""
CMAKE_CXX_FLAGS=""
CMAKE_C_FLAGS=""

# Start the cmake flags off with building for both our host arch, NVidia and AMD
CMAKE_FLAGS="-DLLVM_TARGETS_TO_BUILD:STRING=\"host\;NVPTX\;AMDGPU\""

# Also target Wasm because Javascript is the Platform Of The Future (TM)
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD:STRING=\"WebAssembly\""

if [[ "${RELDBG}" == "1" ]]; then
    CMAKE_FLAGS="${CMAKE_FLAGS} -DCMAKE_BUILD_TYPE=RelWithDebInfo"
    CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_ENABLE_ASSERTIONS:BOOL=ON"
else
    CMAKE_FLAGS="${CMAKE_FLAGS} -DCMAKE_BUILD_TYPE=Release"
fi

# We want a build with no bindings
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_BINDINGS_LIST=\"\" "

# Turn off ZLIB and XML2
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_ENABLE_ZLIB=OFF"
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_ENABLE_LIBXML2=OFF"

# Disable useless things like docs, terminfo, etc....
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_INCLUDE_DOCS=Off"
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_ENABLE_TERMINFO=Off"
CMAKE_FLAGS="${CMAKE_FLAGS} -DHAVE_HISTEDIT_H=Off"
CMAKE_FLAGS="${CMAKE_FLAGS} -DHAVE_LIBEDIT=Off"

# We want a shared library
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_BUILD_LLVM_DYLIB:BOOL=ON"
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_LINK_LLVM_DYLIB:BOOL=ON"

# Install things into $prefix, and make sure it knows we're cross-compiling
CMAKE_FLAGS="${CMAKE_FLAGS} -DCMAKE_INSTALL_PREFIX=${prefix}"
CMAKE_FLAGS="${CMAKE_FLAGS} -DCMAKE_CROSSCOMPILING=True"

# Julia expects the produced LLVM tools to be installed into tools and not bin
# We can't simply move bin to tools since on MingW64 it will also contain the shlib.
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_TOOLS_INSTALL_DIR=${prefix}/tools"

# Tell LLVM where our pre-built tblgen tools are
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_TABLEGEN=${WORKSPACE}/srcdir/bin/llvm-tblgen"
CMAKE_FLAGS="${CMAKE_FLAGS} -DCLANG_TABLEGEN=${WORKSPACE}/srcdir/bin/clang-tblgen"
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_CONFIG_PATH=${WORKSPACE}/srcdir/bin/llvm-config"

# Explicitly use our cmake toolchain file
CMAKE_FLAGS="${CMAKE_FLAGS} -DCMAKE_TOOLCHAIN_FILE=/opt/${target}/${target}.toolchain"

# Manually set the host triplet, as otherwise on some platforms it tries to guess using
# `ld -v`, which is hilariously wrong.
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_HOST_TRIPLE=${target}"

# For now we focus on building llvm, clang, polly, and compiler-rt.
# We would like to build libc++, libc++abi and libunwind eventually
# but we currently don't due to issues on ppc and windows with
# libc++ and the LLVM libunwind conflicts with the one Julia is using.
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_TOOL_LIBUNWIND_BUILD=OFF"
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_TOOL_LIBCXX_BUILD=OFF"
CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_TOOL_LIBCXXABI_BUILD=OFF"

if [[ "${target}" == *apple* ]]; then
    # On OSX, we need to override LLVM's looking around for our SDK
    CMAKE_FLAGS="${CMAKE_FLAGS} -DDARWIN_macosx_CACHED_SYSROOT:STRING=/opt/${target}/MacOSX10.10.sdk"

    # LLVM actually won't build against 10.8, so we bump ourselves up slightly to 10.9
    export MACOSX_DEPLOYMENT_TARGET=10.9
    export LDFLAGS=-mmacosx-version-min=10.9
fi

if [[ "${target}" == *apple* ]] || [[ "${target}" == *freebsd* ]]; then
    # On clang-based platforms we need to override the check for ffs because it doesn't work with `clang`.
    export ac_cv_have_decl___builtin_ffs=yes
fi

if [[ "${target}" == *mingw* ]]; then
    CMAKE_CPP_FLAGS="${CMAKE_CPP_FLAGS} -remap -D__USING_SJLJ_EXCEPTIONS__ -D__CRT__NO_INLINE"
    # Windows is case-insensitive and some dependencies take full advantage of that
    echo "BaseTsd.h basetsd.h" >> /opt/${target}/${target}/include/header.gcc

    # We don't Polly on windows
    CMAKE_FLAGS="${CMAKE_FLAGS} -DLLVM_POLLY_BUILD=OFF"
fi

# Build!
cmake .. ${CMAKE_FLAGS} -DCMAKE_C_FLAGS="${CMAKE_CPP_FLAGS} ${CMAKE_C_FLAGS}" -DCMAKE_CXX_FLAGS="${CMAKE_CPP_FLAGS} ${CMAKE_CXX_FLAGS}"
cmake -LA || true
make -j${nproc} VERBOSE=1

# Test
if [[ "${CHECK}" == "1" ]]; then
make check -j${nproc}
fi

# Install!
make install -j${nproc} VERBOSE=1

# move clang products out of $prefix/bin to $prefix/tools
mv ${prefix}/bin/clang* ${prefix}/tools/
mv ${prefix}/bin/scan-* ${prefix}/tools/
mv ${prefix}/bin/c-index* ${prefix}/tools/
mv ${prefix}/bin/git-clang* ${prefix}/tools/

# Live is harsh on Windows and dynamic libraries are
# expected to live alongside the binaries. So we have
# to copy the *.dll from bin/ to tools/ as well...
if [[ "${target}" == *mingw* ]]; then
    cp ${prefix}/bin/*.dll ${prefix}/tools/
fi
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
    BinaryProvider.Linux(:i686, :glibc),
    BinaryProvider.Linux(:x86_64, :glibc),
    BinaryProvider.Linux(:aarch64, :glibc),
    BinaryProvider.Linux(:armv7l, :glibc),
    BinaryProvider.Linux(:powerpc64le, :glibc),
    BinaryProvider.MacOS(),
    BinaryProvider.Windows(:i686),
    BinaryProvider.Windows(:x86_64)
]

# The products that we will ensure are always built
products(prefix) = [
    # libraries
    LibraryProduct(prefix, "libLLVM",  :libLLVM)
    LibraryProduct(prefix, "libLTO",   :libLTO)
    LibraryProduct(prefix, "libclang", :libclang)
    # tools
    ExecutableProduct(prefix, "llvm-config", :llvm_config)
]

# Dependencies that must be installed before this package can be built
dependencies = [
]

# Build the tarballs, and possibly a `build.jl` as well.
config = ""
name = "LLVM"
if !("--llvm-release" in llvm_ARGS)
    config *= "RELDBG=1\n"
    name *= ".dbg"
elseif !("--llvm-reldbg" in llvm_ARGS)
    config *= "RELDBG=0\n"
else
    error("Both --llvm-reldbg, and --llvm-release passed. Choose only one.")
end

if "--llvm-check" in llvm_ARGS
   config *= "CHECK=1\n"
else
   config *= "CHECK=0\n"
end

build_tarballs(ARGS, name, sources, config * script, platforms, products, dependencies)

if !("--llvm-keep-tblgen" in llvm_ARGS)
    # Remove tblgen tarball as it's no longer useful, and we don't want to upload them.
    rm(tblgen_tarball; force=true)
end
