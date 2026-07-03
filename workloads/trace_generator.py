import random
import os

NUM_ACCESSES = 5000
ADDR_MAX = 0x000FFFFF
BLOCK_SIZE = 16
TRACE_DIR = "workloads/traces"

def ensure_dir():
    if not os.path.exists(TRACE_DIR):
        os.makedirs(TRACE_DIR)

def generate_sequential(filename, num_accesses):
    with open(filename, 'w') as f:
        addr = 0x1000
        for _ in range(num_accesses):
            f.write(f"0 {addr:08X}\n") 
            addr += 4 

def generate_random(filename, num_accesses):
    with open(filename, 'w') as f:
        for _ in range(num_accesses):
            rw = random.choice([0, 1]) 
            addr = random.randint(0, ADDR_MAX) & ~0x3
            f.write(f"{rw} {addr:08X}\n")

def generate_stride(filename, num_accesses, stride=256):
    with open(filename, 'w') as f:
        addr = 0x2000
        for _ in range(num_accesses):
            rw = random.choice([0, 0, 0, 1])
            f.write(f"{rw} {addr:08X}\n")
            addr = (addr + stride) & ADDR_MAX

def generate_thrashing(filename, num_accesses):
    with open(filename, 'w') as f:
        base_addrs = [0x1000, 0x2000, 0x3000, 0x4000, 0x5000]
        for _ in range(num_accesses):
            rw = random.choice([0, 1]) 
            addr = random.choice(base_addrs) + (random.randint(0, 3) * 4)
            f.write(f"{rw} {addr:08X}\n")

if __name__ == "__main__":
    ensure_dir()
    generate_sequential(f"{TRACE_DIR}/sequential.trc", NUM_ACCESSES)
    generate_random(f"{TRACE_DIR}/random.trc", NUM_ACCESSES)
    generate_stride(f"{TRACE_DIR}/stride.trc", NUM_ACCESSES)
    generate_thrashing(f"{TRACE_DIR}/thrashing.trc", NUM_ACCESSES)