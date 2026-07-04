`timescale 1ns / 1ps
import cache_pkg::*;

module prefetcher #(
    parameter int ADDR_WIDTH = 32,
    parameter int BLOCK_SIZE = 16,
    parameter int OFFSET_WIDTH = $clog2(BLOCK_SIZE)
)(
    input  logic                      clk,
    input  logic                      rst_n,
    
    input  logic                      enable_prefetch,
    
    input  logic                      cpu_req_valid,
    input  logic [ADDR_WIDTH-1:0]     cpu_req_addr,
    
    input  logic                      prefetch_ack,
    output logic                      prefetch_req_valid,
    output logic [ADDR_WIDTH-1:0]     prefetch_req_addr
);

    logic [ADDR_WIDTH-1:0] block_aligned_addr;
    logic [ADDR_WIDTH-1:0] next_block_addr;

    assign block_aligned_addr = {cpu_req_addr[ADDR_WIDTH-1:OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};
    assign next_block_addr = block_aligned_addr + BLOCK_SIZE;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prefetch_req_valid <= 1'b0;
            prefetch_req_addr  <= '0;
        end else begin
            if (enable_prefetch && cpu_req_valid) begin
                prefetch_req_valid <= 1'b1;
                prefetch_req_addr  <= next_block_addr;
            end else if (prefetch_ack) begin
                prefetch_req_valid <= 1'b0; 
            end
        end
    end

endmodule