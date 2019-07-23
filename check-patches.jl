##
# Check that patches between BinaryBuilder and Julia are consistent.
# julia check_patches.jl .../path/to/julia/patchdir
##

@assert length(ARGS) == 1

DIR = joinpath(@__DIR__, "patches", "llvm_patches")
patches = readdir(DIR)

files = Dict(map(x -> x => joinpath(DIR, x), patches))
orig_files = Dict(map(x -> x => joinpath(ARGS[1], x[6:end]), patches))

for patch in patches
    orig = orig_files[patch]
    file = files[patch]

    if !isfile(orig)
        warn("$patch is not present in $(ARGS[1])")
        continue
    end
    try
        run(`diff $orig $file`)
    catch
        @warn("$patch differs")
    end
end

patches = map(p->string(p[6:end]), patches)

for patch in readdir(ARGS[1])
    if startswith(patch, "llvm") && !(patch in patches)
        warn("$patch not present for LLVMBuilder")
    end
end
