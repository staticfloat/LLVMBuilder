# vim:noet

release:
	julia build_tarballs.jl --llvm-release

debug:
	julia build_tarballs.jl --llvm-debug

check:
	julia build_tarballs.jl --llvm-debug --llvm-check --verbose

both:
	julia build_tarballs.jl --llvm-debug
	julia build_tarballs.jl --llvm-release

buildjl:
	julia build_tarballs.jl --llvm-release --only-buildjl

clean:
	rm -rf build
	rm -rf products
