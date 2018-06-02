# vim:noet

release:
	julia build_tarballs.jl --llvm-release

reldbg:
	julia build_tarballs.jl --llvm-reldbg

check:
	julia build_tarballs.jl --llvm-check --verbose

both:
	julia build_tarballs.jl --llvm-reldbg
	julia build_tarballs.jl --llvm-release

buildjl:
	julia build_tarballs.jl --llvm-release --only-buildjl

clean:
	rm -rf build
	rm -rf products
