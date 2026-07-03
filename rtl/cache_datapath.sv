`timescale 1ns / 1ps
import cache_pkg::*;

module cache_datapath #(
    parameter int BLOCK_SIZE = 16,
    parameter int SETS = 128,
    parameter int ADDR_WIDTH = 32,
    parameter int OFFSET_WIDTH = $clog2(BLOCK_SIZE),
    parameter int INDEX_WIDTH = $clog2(SETS),
    parameter int TAG_WIDTH = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH
)(
    input  logic                             clk,
    input  logic                             rst_n,
    
    input  logic [INDEX_WIDTH-1:0]           index,
    
    input  logic                             we_way0,
    input  logic                             set_dirty_way0,
    input  logic                             clear_dirty_way0,
    
    input  logic                             we_way1,
    input  logic                             set_dirty_way1,
    input  logic                             clear_dirty_way1,
    
    input  logic [TAG_WIDTH-1:0]             tag_in,
    input  logic [(BLOCK_SIZE*8)-1:0]        data_in,
    
    output logic                             valid_way0,
    output logic                             dirty_way0,
    output logic [TAG_WIDTH-1:0]             tag_way0,
    output logic [(BLOCK_SIZE*8)-1:0]        data_way0,
    
    output logic                             valid_way1,
    output logic                             dirty_way1,
    output logic [TAG_WIDTH-1:0]             tag_way1,
    output logic [(BLOCK_SIZE*8)-1:0]        data_way1
);

    logic                             v_array_way0    [SETS-1:0];
    logic                             d_array_way0    [SETS-1:0];
    logic [TAG_WIDTH-1:0]             tag_array_way0  [SETS-1:0];
    logic [(BLOCK_SIZE*8)-1:0]        data_array_way0 [SETS-1:0];

    logic                             v_array_way1    [SETS-1:0];
    logic                             d_array_way1    [SETS-1:0];
    logic [TAG_WIDTH-1:0]             tag_array_way1  [SETS-1:0];
    logic [(BLOCK_SIZE*8)-1:0]        data_array_way1 [SETS-1:0];

    assign valid_way0 = v_array_way0[index];
    assign dirty_way0 = d_array_way0[index];
    assign tag_way0   = tag_array_way0[index];
    assign data_way0  = data_array_way0[index];

    assign valid_way1 = v_array_way1[index];
    assign dirty_way1 = d_array_way1[index];
    assign tag_way1   = tag_array_way1[index];
    assign data_way1  = data_array_way1[index];

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < SETS; i = i + 1) begin
                v_array_way0[i]    <= 1'b0;
                d_array_way0[i]    <= 1'b0;
                tag_array_way0[i]  <= '0;
                data_array_way0[i] <= '0;
                
                v_array_way1[i]    <= 1'b0;
                d_array_way1[i]    <= 1'b0;
                tag_array_way1[i]  <= '0;
                data_array_way1[i] <= '0;
            end
        end else begin
            if (we_way0) begin
                v_array_way0[index]    <= 1'b1;
                tag_array_way0[index]  <= tag_in;
                data_array_way0[index] <= data_in;
            end
            if (set_dirty_way0)   d_array_way0[index] <= 1'b1;
            if (clear_dirty_way0) d_array_way0[index] <= 1'b0;

            if (we_way1) begin
                v_array_way1[index]    <= 1'b1;
                tag_array_way1[index]  <= tag_in;
                data_array_way1[index] <= data_in;
            end
            if (set_dirty_way1)   d_array_way1[index] <= 1'b1;
            if (clear_dirty_way1) d_array_way1[index] <= 1'b0;
        end
    end

endmodule
