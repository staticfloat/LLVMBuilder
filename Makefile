# vim:noet

release:
	julia build_tarballs.jl --llvm-release --verbose-audit

debug:
	julia build_tarballs.jl --llvm-debug --verbose-audit

buildjl:
	julia build_tarballs.jl --llvm-release --only-buildjl

clean:
	rm -rf build
	rm -rf products
