# XMRig for Orange (OAG)

XMRig 6.26.0 に、Orange (OAG) を掘るためのアルゴリズム **`rx/oag`** を足したものです。
素の XMRig では OAG は掘れません (ブロックヘッダの形が Monero と違うため)。

- OAG: https://github.com/manh923/Orange
- 採掘器との取り決め: https://github.com/manh923/Orange/blob/main/docs/STRATUM.md
- このフォークのソース: https://github.com/manh923/xmrig-for-oag (GPL-3.0)

## 使い方

OAG のノードを `--stratum` 付きで動かし、そこにつなぎます。

```sh
# ノード (本番。同じ機械で掘るなら既定のままでよい)
oag-node run --network mainnet --stratum

# 採掘器
xmrig -o 127.0.0.1:1919 -u <自分の OAG アドレス> -a rx/oag
```

| ネットワーク | ポート |
| --- | --- |
| mainnet | 1919 |
| testnet | 11919 |
| regtest | 21919 |

- `-a rx/oag` を必ず付けてください。無いとノードに断られます。
- 機械ごとに名前を付けるなら `-u <アドレス>.<名前>` か `--rig-id <名前>`。
- ノードに `--pool` を足すとプールとして動きます。採掘器の側は何も変わりません。

## 素の rx/0 との違い

| 項目 | rx/0 | rx/oag |
| --- | --- | --- |
| RandomX の設定 | Monero v1 | 同じ (v2 ではない) |
| ハッシュする範囲 | blob 全体 | 同じ (100 バイト) |
| ナンスの位置 | 39 バイト目 | **92 バイト目** (4 バイト LE) |
| 当たりの判定 | 末尾 8 バイト LE `<` target | **先頭 8 バイト BE `<=` target** |

## 注意

- **CPU 専用です。** OpenCL / CUDA は `rx/oag` を引き受けません。配布しているバイナリは GPU 抜きで作っています。
- **寄付 (donate) は XMRig の既定のまま 1% です。** 約 100 分に 1 分、XMRig の作者のプールにつなぎ、作者のために Monero を掘ります。その間は OAG を掘りません。`--donate-level` で 1 より下にはできません。
- testnet は高さ 91 までは難易度が 10 のまま動きません。そこに速い採掘器をつなぐと、当たりが多すぎてノードの確認が追いつかず、提出が溢れます。まず `oag-node run --mine` などで高さ 91 を越えさせてからつないでください。

## 作り方

### Linux

```sh
sudo apt install git build-essential cmake libuv1-dev libssl-dev libhwloc-dev
git clone https://github.com/manh923/xmrig-for-oag
cd xmrig-for-oag && mkdir build && cd build
cmake .. -DWITH_OPENCL=OFF -DWITH_CUDA=OFF
make -j$(nproc)
```

配布物と同じ完全静的なバイナリ (musl) は、docker があれば次で作れます。

```sh
docker run --rm -v "$PWD":/src -w /src alpine:3.21 sh scripts/oag/build-linux-static.sh <版> <x64|arm64>
```

### Windows

MSYS2 の MINGW64 の端末で、XMRig の依存ライブラリ集 (xmrig-deps) を使います。

```sh
pacman -S git mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
git clone --depth 1 --branch v5.0 https://github.com/xmrig/xmrig-deps.git ../xmrig-deps
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DXMRIG_DEPS="$(cygpath -m "$PWD/../xmrig-deps/gcc/x64")" -DWITH_OPENCL=OFF -DWITH_CUDA=OFF
cmake --build build
```

## 試験

`-DWITH_OAG_TESTS=ON` を付けて作ると、次の 2 つで確かめられます。

```sh
./build/xmrig-oag-test                          # STRATUM.md §6 の検算用の値 (ブロック 1 と 16965)
python3 tests/oag/vector_node.py build/xmrig    # 同じ 2 ブロックを仕事として配り、xmrig が正しいナンスを出すか
```
