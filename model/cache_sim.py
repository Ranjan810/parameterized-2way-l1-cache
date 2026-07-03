import math
import argparse
import os
from replacement import LRUPolicy, FIFOPolicy
from prefetch_sim import SequentialPrefetcher

class CacheLine:
    def __init__(self):
        self.valid = False
        self.dirty = False
        self.tag = None

class CacheController:
    def __init__(self, sets=128, block_size=16, policy_name="LRU", enable_prefetch=False):
        self.sets = sets
        self.block_size = block_size
        self.offset_bits = int(math.log2(block_size))
        self.index_bits = int(math.log2(sets))
        
        self.cache = [[CacheLine(), CacheLine()] for _ in range(sets)]
        
        if policy_name == "FIFO":
            self.repl_logic = FIFOPolicy(sets)
        else:
            self.repl_logic = LRUPolicy(sets)
            
        self.prefetcher = SequentialPrefetcher(block_size, enable=enable_prefetch)
        
        self.hits = 0
        self.misses = 0
        self.write_backs = 0
        self.memory_reads = 0
        self.memory_writes = 0
        self.prefetches_issued = 0
        
    def _parse_address(self, addr):
        offset = addr & ((1 << self.offset_bits) - 1)
        index = (addr >> self.offset_bits) & ((1 << self.index_bits) - 1)
        tag = addr >> (self.offset_bits + self.index_bits)
        return tag, index
        
    def access(self, is_write, addr, is_prefetch=False):
        tag, index = self._parse_address(addr)
        target_set = self.cache[index]
        
        hit = False
        hit_way = -1
        
        for way in range(2):
            if target_set[way].valid and target_set[way].tag == tag:
                hit = True
                hit_way = way
                break
                
        if hit:
            if not is_prefetch:
                self.hits += 1
                if is_write:
                    target_set[hit_way].dirty = True
                self.repl_logic.update_on_hit(index, hit_way)
        else:
            if not is_prefetch:
                self.misses += 1
                
            self.memory_reads += 1 
            
            # Prioritize invalid ways before asking the replacement logic
            if not target_set[0].valid:
                evict_way = 0
            elif not target_set[1].valid:
                evict_way = 1
            else:
                evict_way = self.repl_logic.get_victim(index)
                
            if target_set[evict_way].valid and target_set[evict_way].dirty:
                self.write_backs += 1
                self.memory_writes += 1
                
            target_set[evict_way].valid = True
            target_set[evict_way].tag = tag
            target_set[evict_way].dirty = is_write and not is_prefetch 
            
            self.repl_logic.update_on_miss(index, evict_way)

        if not is_prefetch:
            prefetch_addr = self.prefetcher.evaluate_access(addr)
            if prefetch_addr is not None:
                self.prefetches_issued += 1
                self.access(is_write=False, addr=prefetch_addr, is_prefetch=True)

    def print_stats(self, trace_name):
        total_accesses = self.hits + self.misses
        
        if total_accesses > 0:
            hit_rate = (self.hits / total_accesses) * 100
            miss_rate = self.misses / total_accesses
            # Architectural AMAT calculation matching the RTL assumptions
            hit_time = 2.0
            miss_penalty = 5.0
            amat = hit_time + (miss_rate * miss_penalty)
        else:
            hit_rate = 0
            miss_rate = 0
            amat = 0
            
        print(f"--- Results for {trace_name} ---")
        print(f"Policy          : {type(self.repl_logic).__name__}")
        print(f"Prefetcher      : {'ON' if self.prefetcher.enable else 'OFF'}")
        print(f"Total Accesses  : {total_accesses}")
        print(f"Hits            : {self.hits}")
        print(f"Misses          : {self.misses}")
        print(f"Hit Rate        : {hit_rate:.2f}%")
        print("-" * 40)
        print(f"Write-Backs     : {self.write_backs}")
        print(f"Memory Reads    : {self.memory_reads}")
        print(f"Memory Writes   : {self.memory_writes}")
        if self.prefetcher.enable:
            print(f"Prefetches      : {self.prefetches_issued}")
        print("-" * 40)
        print(f"AMAT (Cycles)   : {amat:.2f}")
        print("=" * 40)

def run_simulation(trace_file, policy, enable_prefetch):
    cache = CacheController(policy_name=policy, enable_prefetch=enable_prefetch)
    
    if not os.path.exists(trace_file):
        print(f"Error: Trace file {trace_file} not found.")
        return
        
    with open(trace_file, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                is_write = int(parts[0]) == 1
                addr = int(parts[1], 16)
                cache.access(is_write, addr)
                
    cache.print_stats(os.path.basename(trace_file))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Modular Cache Golden Model Simulation")
    parser.add_argument("--trace", required=True)
    parser.add_argument("--policy", choices=["LRU", "FIFO"], default="LRU")
    parser.add_argument("--prefetch", action="store_true")
    
    args = parser.parse_args()
    run_simulation(args.trace, args.policy, args.prefetch)