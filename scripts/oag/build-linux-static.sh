#!/bin/sh -e
#
# Builds a fully static (musl) xmrig with rx/oag, runs the rx/oag tests and packs it.
# Run it inside Alpine from the top of the source tree:
#
#   docker run --rm -v "$PWD":/src -w /src alpine:3.21 sh scripts/oag/build-linux-static.sh <version> <x64|arm64>
#
# The archive is written to dist/xmrig-oag-<version>-linux-static-<arch>.tar.gz

VERSION="$1"
ARCH="$2"

if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
    echo "usage: $0 <version> <x64|arm64>"
    exit 2
fi

apk add --no-cache git make cmake gcc g++ libstdc++ linux-headers automake autoconf libtool wget perl python3 tar

(cd scripts && ./build_deps.sh)

cmake -S . -B build-static -DCMAKE_BUILD_TYPE=Release -DXMRIG_DEPS=scripts/deps -DBUILD_STATIC=ON \
    -DWITH_OPENCL=OFF -DWITH_CUDA=OFF -DWITH_OAG_TESTS=ON
cmake --build build-static -j"$(nproc)"

./build-static/xmrig-oag-test
python3 tests/oag/vector_node.py build-static/xmrig

NAME="xmrig-oag-${VERSION}-linux-static-${ARCH}"
rm -rf "dist/${NAME}"
mkdir -p "dist/${NAME}"
cp build-static/xmrig LICENSE doc/OAG.md "dist/${NAME}/"
strip "dist/${NAME}/xmrig"
tar -C dist -czf "dist/${NAME}.tar.gz" "${NAME}"
rm -rf "dist/${NAME}"

./build-static/xmrig --version
ls -l "dist/${NAME}.tar.gz"
