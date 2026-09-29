/* XMRig
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

// Checks rx/oag against the mainnet test vectors in Orange's docs/STRATUM.md §6,
// using XMRig's own Job, Algorithm, RxAlgo and RandomX code.
//
// Build with -DWITH_OAG_TESTS=ON, then run ./xmrig-oag-test (exit code 0 = all passed).


#include <cinttypes>
#include <cstdio>
#include <cstring>
#include <string>


#include "backend/cpu/Cpu.h"
#include "base/crypto/Algorithm.h"
#include "base/net/stratum/Job.h"
#include "base/tools/Cvt.h"
#include "crypto/common/VirtualMemory.h"
#include "crypto/randomx/aes_hash.hpp"
#include "crypto/randomx/randomx.h"
#include "crypto/rx/RxAlgo.h"
#include "crypto/rx/RxCache.h"
#include "crypto/rx/RxDataset.h"
#include "crypto/rx/RxVm.h"
#include "net/JobResult.h"


using namespace xmrig;


namespace {


int failures = 0;
int checks   = 0;


#define CHECK(cond) do { ++checks; if (!(cond)) { ++failures; printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)


struct Vector
{
    uint64_t height;
    const char *blob;
    const char *seed;
    const char *powHash;
    const char *target;
    uint64_t target64;
    uint64_t difficulty;
    uint32_t nonce;         // the 4 bytes at byte 92, read little-endian
    const char *nonceHex;   // the same 4 bytes as submitted
};


// docs/STRATUM.md §6
const Vector kVectors[] = {
    {
        1,
        "000000007511b77a9fb2aac8d7ba4655ed372c6fc3fbf800e1872a5c907bb64a775f0c40"
        "1c52530a718baff7d389da1afff96a5af3e89529ef2bb3180bf63ad4bbc2c9ad"
        "2fc8ab6a00000000e80300000000000001000000000000004100000000000000",
        "7511b77a9fb2aac8d7ba4655ed372c6fc3fbf800e1872a5c907bb64a775f0c40",
        "002d5ca362a5364c6a63fc3e87a85401468846f084f44b0f680acb73559d3da3",
        "efa7c64b37894100",
        0x004189374bc6a7efULL,
        1000,
        0x00000041,
        "41000000"
    },
    {
        16965,
        "00000000dd5580b564b8e2eb22f8d597b1bf062b6fd3930837461c1bb882bd423cd6642a"
        "bbae524eacd6500682f58c38c653bd5526a52622927fd722bb80d25e9e42f743"
        "56aabb6a00000000e4cf0f00000000004542000000000000bc060000000000c0",
        "7ddfebd83d6ac2a58c4987d9034d22228e17aae5f65ef5746708b97a16a8cfdb",
        "00000ce135fb6f2acaa1bf01fe142afae302e35a0e93787bd56ff9507fb1bd07",
        "1e5260ae30100000",
        0x00001030ae60521eULL,
        1036260,
        0x000006bc,
        "bc060000"
    }
};


void testAlgorithm()
{
    printf("algorithm\n");

    const Algorithm algo("rx/oag");
    CHECK(algo == Algorithm::RX_OAG);
    CHECK(algo.isValid());
    CHECK(strcmp(algo.name(), "rx/oag") == 0);
    CHECK(Algorithm("randomx/oag") == Algorithm::RX_OAG);
    CHECK(Algorithm(static_cast<uint32_t>(0x7215126f)) == Algorithm::RX_OAG);
    CHECK(algo.family() == Algorithm::RANDOM_X);
    CHECK(algo.l3() == 2 * 1024 * 1024);
    CHECK(algo.l2() == 256 * 1024);

    bool listed = false;
    for (const auto &a : Algorithm::all()) {
        listed |= a == Algorithm::RX_OAG;
    }
    CHECK(listed);

    // RandomX configuration: Monero v1 (rx/0), not v2.
    CHECK(RxAlgo::base(Algorithm::RX_OAG) == &RandomX_MoneroConfig);
    CHECK(RxAlgo::base(Algorithm::RX_OAG) != &RandomX_MoneroConfigV2);

    RxAlgo::apply(Algorithm::RX_OAG);
    CHECK(RandomX_CurrentConfig.Tweak_V2_COMMITMENT == 0);
    CHECK(RandomX_CurrentConfig.Tweak_V2_CFROUND == 0);
    CHECK(RandomX_CurrentConfig.Tweak_V2_AES == 0);
    CHECK(RandomX_CurrentConfig.Tweak_V2_PREFETCH == 0);
    CHECK(RandomX_CurrentConfig.ProgramCount == RandomX_MoneroConfig.ProgramCount);
    CHECK(RandomX_CurrentConfig.ProgramIterations == RandomX_MoneroConfig.ProgramIterations);
    CHECK(RandomX_CurrentConfig.ProgramSize == RandomX_MoneroConfig.ProgramSize);
    CHECK(strcmp(RandomX_CurrentConfig.ArgonSalt, RandomX_MoneroConfig.ArgonSalt) == 0);

    // Existing algorithms are unchanged.
    CHECK(RxAlgo::base(Algorithm::RX_0) == &RandomX_MoneroConfig);
    CHECK(RxAlgo::base(Algorithm::RX_V2) == &RandomX_MoneroConfigV2);
    CHECK(Job(false, Algorithm::RX_0, "t").nonceOffset() == 39);
    CHECK(Job(false, Algorithm::RX_V2, "t").nonceOffset() == 39);
    CHECK(Job(false, Algorithm::RX_YADA, "t").nonceOffset() == 147);
}


void testShareCheck()
{
    printf("share check (first 8 bytes, big-endian, <= target)\n");

    uint8_t hash[32] = {};
    const uint64_t target = 0x004189374bc6a7efULL;

    auto put = [&hash](uint64_t head) {
        for (size_t i = 0; i < 8; ++i) {
            hash[i] = static_cast<uint8_t>(head >> (56 - 8 * i));
        }
    };

    put(target);
    CHECK(Job::oagHashValue(hash) == target);
    CHECK(Job::oagHashValue(hash) <= target);     // equal is a hit

    put(target + 1);
    CHECK(!(Job::oagHashValue(hash) <= target));

    put(target - 1);
    CHECK(Job::oagHashValue(hash) <= target);

    // Only the first 8 bytes count; the tail is ignored.
    put(target);
    memset(hash + 8, 0xff, 24);
    CHECK(Job::oagHashValue(hash) <= target);
}


void testVector(const Vector &v, randomx_vm *vm)
{
    printf("block %" PRIu64 "\n", v.height);

    // The node sends the header with bytes 92..95 set to zero.
    std::string nodeBlob = v.blob;
    nodeBlob.replace(92 * 2, 8, "00000000");

    Job job(false, Algorithm::RX_OAG, "t");
    CHECK(job.setBlob(nodeBlob.c_str()));
    CHECK(job.size() == 100);
    CHECK(job.nonceOffset() == 92);
    CHECK(!job.isNicehash());
    CHECK(job.setSeedHash(v.seed));

    CHECK(job.setTarget(v.target));
    CHECK(job.target() == v.target64);
    CHECK(job.diff() == Job::toDiff(v.target64));
    printf("  target %s -> 0x%016" PRIx64 " (diff %" PRIu64 ")\n", v.target, job.target(), job.diff());

    const auto node96 = Cvt::fromHex(nodeBlob.c_str() + 96 * 2, 8);

    // Write the nonce the way the CPU worker does: 4 bytes, little-endian, at nonceOffset().
    const uint32_t nonce = v.nonce;
    memcpy(job.blob() + job.nonceOffset(), &nonce, sizeof(nonce));

    const auto expectedBlob = Cvt::fromHex(v.blob, strlen(v.blob));
    CHECK(expectedBlob.size() == job.size());
    CHECK(memcmp(job.blob(), expectedBlob.data(), job.size()) == 0);
    CHECK(memcmp(job.blob() + 96, node96.data(), 4) == 0);     // the node's half of the nonce is untouched
    CHECK(Cvt::toHex(job.blob() + job.nonceOffset(), 4) == v.nonceHex);

    alignas(64) uint8_t hash[RANDOMX_HASH_SIZE] = {};
    randomx_calculate_hash(vm, job.blob(), job.size(), hash);

    const auto hex = Cvt::toHex(hash, sizeof(hash));
    printf("  pow_hash %s\n", hex.data());
    CHECK(hex == v.powHash);

    const uint64_t head = Job::oagHashValue(hash);
    printf("  0x%016" PRIx64 " <= 0x%016" PRIx64 " : %s\n", head, job.target(), head <= job.target() ? "hit" : "miss");
    CHECK(head <= job.target());

    const uint64_t tail = *reinterpret_cast<const uint64_t *>(hash + 24);
    printf("  (stock rx/0 check would read 0x%016" PRIx64 " < target : %s)\n", tail, tail < job.target() ? "hit" : "miss");

    const JobResult result(job, nonce, hash);
    CHECK(result.actualDiff() == Job::toDiff(head));
    CHECK(result.actualDiff() >= v.difficulty);
}


} // namespace


int main()
{
    setvbuf(stdout, nullptr, _IONBF, 0);

    VirtualMemory::init(0, 0);
    RxAlgo::apply(Algorithm::RX_OAG);

    testAlgorithm();
    testShareCheck();

    const bool softAes = !Cpu::info()->hasAES();
    if (softAes) {
        SelectSoftAESImpl(1);
    }

    for (const auto &v : kVectors) {
        RxAlgo::apply(Algorithm::RX_OAG);

        // Light mode: the dataset only wraps the cache, and owns it.
        auto cache = new RxCache(false, 0);
        CHECK(cache->get() != nullptr);
        CHECK(cache->init(Cvt::fromHex(v.seed, strlen(v.seed))));

        RxDataset dataset(cache);
        VirtualMemory scratchpad(Algorithm(Algorithm::RX_OAG).l3(), false, false, false, 0);

        randomx_vm *vm = RxVm::create(&dataset, scratchpad.scratchpad(), softAes, Assembly::AUTO, 0);
        CHECK(vm != nullptr);
        if (vm) {
            testVector(v, vm);
            RxVm::destroy(vm);
        }
    }

    printf("%d checks, %d failed\n", checks, failures);

    return failures == 0 ? 0 : 1;
}
