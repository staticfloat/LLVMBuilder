# vim:noet

release:
	julia build_tarballs.jl

asserts:
	julia build_tarballs.jl --llvm-asserts

quick:
	julia build_tarballs.jl --llvm-asserts i686-w64-mingw32 x86_64-w64-mingw32 x86_64-apple-darwin14

check:
	julia build_tarballs.jl --llvm-check --verbose

both:
	julia build_tarballs.jl --llvm-asserts
	julia build_tarballs.jl

buildjl:
	julia build_tarballs.jl --only-buildjl

clean:
	rm -rf build
	rm -rf products
