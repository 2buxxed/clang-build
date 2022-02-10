#!/usr/bin/env bash

set -eo pipefail

# Build LLVM
echo "* Building LLVM..."
./build-llvm.py \
	--clang-vendor "Lunatic" \
	--defines "LLVM_PARALLEL_COMPILE_JOBS=$(nproc) LLVM_PARALLEL_LINK_JOBS=$(nproc) CMAKE_C_FLAGS=-O3 CMAKE_CXX_FLAGS=-O3" \
	--projects "clang;lld;polly" \
	--targets "ARM;AArch64;X86" \
	--lto full \
	--shallow-clone \
	--incremental \
	--install-stage1-only \
	--build-type "Release" 2>&1

# Verify clang get built
[ ! -f install/bin/clang-1* ] && {
	echo "* LLVM Building Failed"
	exit 1
}

# Build binutils
echo "* Building binutils..."
./build-binutils.py --targets arm aarch64 x86_64

# Remove unused products
echo "* Removing unused products..."
rm -fr install/include
rm -f install/lib/*.a install/lib/*.la

# Strip remaining products
echo "* Stripping remaining products..."
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
	strip ${f: : -1}
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
echo "* Setting library load paths for portability..."
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
	# Remove last character from file output (':')
	bin="${bin: : -1}"

	echo "$bin"
	patchelf --set-rpath '$ORIGIN/../lib' "$bin"
done

# Set Commit Author
git config --global user,name "${GIT_USERNAME}"
git config --global user.email "${GIT_MAIL}"
git config --global http.postBuffer 15728640

# Setup Release Repository
git clone git://${GIT_REPO_URL}.git product -b main
rm -rf product/*
mv install/* product/

# Create Commit
cd product/
git add -a
git commit -m "clang: $(date) Build"

# Push built product
push_prod() {
    git push git://${GIT_USERNAME}:${GIT_PASS}@${GIT_REPO_URL}.git -f
}

push_prod