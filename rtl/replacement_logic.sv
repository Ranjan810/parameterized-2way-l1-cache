`timescale 1ns / 1ps
import cache_pkg::*;

module replacement_logic #(
    parameter int SETS = 128
)(
    input  logic                             clk,
    input  logic                             rst_n,
    input  replace_policy_t                  policy,
    input  logic [$clog2(SETS)-1:0]          set_idx,
    
    input  logic                             update_lru,
    input  logic                             accessed_way,
    
    input  logic                             update_fifo,
    output logic                             evict_way
);

    // LRU and FIFO pointers for each set
    logic [SETS-1:0] lru_array;
    logic [SETS-1:0] fifo_array;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lru_array  <= '0;
            fifo_array <= '0;
        end else begin
            // LRU updates on both hits and misses (points to least recently used)
            if (update_lru) begin
                lru_array[set_idx] <= ~accessed_way; 
            end
            
            // FIFO updates ONLY on allocations (points to oldest allocated)
            if (update_fifo) begin
                fifo_array[set_idx] <= ~fifo_array[set_idx];
            end
        end
    end

    // Dynamic policy selection
    assign evict_way = (policy == REPLACE_FIFO) ? fifo_array[set_idx] : lru_array[set_idx];

endmodule
