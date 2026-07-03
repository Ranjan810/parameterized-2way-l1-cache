class SequentialPrefetcher:
    def __init__(self, block_size, enable=False):
        self.block_size = block_size
        self.enable = enable

    def evaluate_access(self, cpu_addr):
        if not self.enable:
            return None
            
        offset_mask = self.block_size - 1
        block_aligned_addr = cpu_addr & ~offset_mask
        next_block_addr = block_aligned_addr + self.block_size
        
        return next_block_addr