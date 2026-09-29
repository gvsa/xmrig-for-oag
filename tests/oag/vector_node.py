#!/usr/bin/env python3
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# End-to-end check of rx/oag with a real xmrig binary.
#
# Serves the two mainnet blocks of Orange's docs/STRATUM.md §6 as stratum
# jobs (with bytes 92..95 zeroed, as the node sends them) and expects xmrig
# to find and submit exactly the recorded nonce and pow_hash for each.
# With one thread xmrig walks the nonces from 0, so the first hit it finds
# is the one the chain recorded.
#
#   python3 tests/oag/vector_node.py build/xmrig [extra xmrig args...]
#
# Exit code 0 means both blocks were found by xmrig and matched the spec.

import json
import socket
import subprocess
import sys
import threading
import time

VECTORS = [
    {
        "height": 1,
        "blob": "000000007511b77a9fb2aac8d7ba4655ed372c6fc3fbf800e1872a5c907bb64a775f0c40"
                "1c52530a718baff7d389da1afff96a5af3e89529ef2bb3180bf63ad4bbc2c9ad"
                "2fc8ab6a00000000e80300000000000001000000000000004100000000000000",
        "seed_hash": "7511b77a9fb2aac8d7ba4655ed372c6fc3fbf800e1872a5c907bb64a775f0c40",
        "pow_hash": "002d5ca362a5364c6a63fc3e87a85401468846f084f44b0f680acb73559d3da3",
        "target": "efa7c64b37894100",
        "nonce": "41000000",
    },
    {
        "height": 16965,
        "blob": "00000000dd5580b564b8e2eb22f8d597b1bf062b6fd3930837461c1bb882bd423cd6642a"
                "bbae524eacd6500682f58c38c653bd5526a52622927fd722bb80d25e9e42f743"
                "56aabb6a00000000e4cf0f00000000004542000000000000bc060000000000c0",
        "seed_hash": "7ddfebd83d6ac2a58c4987d9034d22228e17aae5f65ef5746708b97a16a8cfdb",
        "pow_hash": "00000ce135fb6f2acaa1bf01fe142afae302e35a0e93787bd56ff9507fb1bd07",
        "target": "1e5260ae30100000",
        "nonce": "bc060000",
    },
]

NONCE_OFFSET = 92
TIMEOUT = 600


def job(index):
    v = VECTORS[index]
    blob = v["blob"][: NONCE_OFFSET * 2] + "00000000" + v["blob"][(NONCE_OFFSET + 4) * 2 :]
    return {
        "job_id": format(index + 1, "x"),
        "blob": blob,
        "target": v["target"],
        "algo": "rx/oag",
        "height": v["height"],
        "seed_hash": v["seed_hash"],
    }


def serve(listener, state):
    conn, _ = listener.accept()
    reader = conn.makefile("r")

    def send(obj):
        conn.sendall((json.dumps(obj) + "\n").encode())

    current = 0
    for line in reader:
        msg = json.loads(line)
        method = msg.get("method")
        params = msg.get("params", {})
        reply = {"id": msg.get("id"), "jsonrpc": "2.0", "error": None}

        if method == "login":
            algos = params.get("algo", [])
            print(f"[node] login agent={params.get('agent')!r} algo={algos}", flush=True)
            if "rx/oag" not in algos:
                reply["error"] = {"code": -1, "message": "this node hands out rx/oag jobs only"}
                reply["result"] = None
                send(reply)
                state["errors"].append("login did not offer rx/oag")
                break
            reply["result"] = {"id": "00000001", "job": job(0), "extensions": ["algo", "keepalive"], "status": "OK"}
            send(reply)

        elif method == "submit":
            v = VECTORS[current]
            got = (params.get("job_id"), params.get("nonce"), params.get("result"))
            want = (format(current + 1, "x"), v["nonce"], v["pow_hash"])
            print(f"[node] submit job_id={got[0]} nonce={got[1]} result={got[2]}", flush=True)
            if got != want:
                state["errors"].append(f"block {v['height']}: got {got}, want {want}")
                reply["error"] = {"code": -1, "message": "the result does not match the spec vector"}
                reply["result"] = None
                send(reply)
                break

            print(f"[node] block {v['height']}: nonce and pow_hash match docs/STRATUM.md", flush=True)
            state["matched"].append(v["height"])
            reply["result"] = {"status": "OK"}
            send(reply)

            current += 1
            if current == len(VECTORS):
                break
            send({"jsonrpc": "2.0", "method": "job", "params": job(current)})

        elif method == "keepalived":
            reply["result"] = {"status": "KEEPALIVED"}
            send(reply)

        else:
            reply["error"] = {"code": -1, "message": f"unknown method {method}"}
            reply["result"] = None
            send(reply)

    state["done"].set()
    conn.close()


def main():
    if len(sys.argv) < 2:
        print("usage: vector_node.py path/to/xmrig [extra xmrig args...]")
        return 2

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    port = listener.getsockname()[1]

    state = {"matched": [], "errors": [], "done": threading.Event()}
    threading.Thread(target=serve, args=(listener, state), daemon=True).start()

    cmd = [sys.argv[1], "-o", f"127.0.0.1:{port}", "-u", "x", "-a", "rx/oag", "-t", "1",
           "--no-color", "--donate-level", "1"] + sys.argv[2:]
    print("[node] running:", " ".join(cmd), flush=True)
    start = time.time()
    miner = subprocess.Popen(cmd)
    try:
        state["done"].wait(TIMEOUT)
    finally:
        miner.terminate()
        try:
            miner.wait(10)
        except subprocess.TimeoutExpired:
            miner.kill()

    ok = not state["errors"] and len(state["matched"]) == len(VECTORS)
    print(f"[node] {'PASS' if ok else 'FAIL'} in {time.time() - start:.0f} s: matched blocks {state['matched']}", flush=True)
    for e in state["errors"]:
        print("[node] error:", e, flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
