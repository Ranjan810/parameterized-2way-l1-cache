class ReplacementPolicy:
    def __init__(self, sets, ways=2):
        self.sets = sets
        self.ways = ways

    def get_victim(self, set_idx):
        raise NotImplementedError

    def update_on_hit(self, set_idx, accessed_way):
        pass

    def update_on_miss(self, set_idx, allocated_way):
        pass

class LRUPolicy(ReplacementPolicy):
    def __init__(self, sets, ways=2):
        super().__init__(sets, ways)
        self.lru_state = [0] * sets

    def get_victim(self, set_idx):
        return self.lru_state[set_idx]

    def update_on_hit(self, set_idx, accessed_way):
        self.lru_state[set_idx] = 1 - accessed_way

    def update_on_miss(self, set_idx, allocated_way):
        self.lru_state[set_idx] = 1 - allocated_way

class FIFOPolicy(ReplacementPolicy):
    def __init__(self, sets, ways=2):
        super().__init__(sets, ways)
        self.fifo_ptr = [0] * sets

    def get_victim(self, set_idx):
        return self.fifo_ptr[set_idx]

    def update_on_miss(self, set_idx, allocated_way):
        self.fifo_ptr[set_idx] = 1 - self.fifo_ptr[set_idx]