`timescale 1ns / 1ps
import cache_pkg::*;

module cache_controller #(
    parameter int BLOCK_SIZE = 16,
    parameter int SETS = 128,
    parameter int ADDR_WIDTH = 32,
    parameter int OFFSET_WIDTH = $clog2(BLOCK_SIZE),
    parameter int INDEX_WIDTH = $clog2(SETS),
    parameter int TAG_WIDTH = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH
)(
    input  logic                             clk,
    input  logic                             rst_n,
    
    input  replace_policy_t                  policy,
    input  logic                             enable_prefetch,
    
    input  logic                             cpu_req,
    input  logic                             cpu_rw,
    input  logic [ADDR_WIDTH-1:0]            cpu_addr,
    input  logic [(BLOCK_SIZE*8)-1:0]        cpu_wdata,
    output logic [(BLOCK_SIZE*8)-1:0]        cpu_rdata,
    output logic                             cpu_ready,
    output logic                             access_hit, 
    
    output logic                             mem_req,
    output logic                             mem_rw,
    output logic [ADDR_WIDTH-1:0]            mem_addr,
    output logic [(BLOCK_SIZE*8)-1:0]        mem_wdata,
    input  logic [(BLOCK_SIZE*8)-1:0]        mem_rdata,
    input  logic                             mem_ready
);

    localparam int TAG_MSB = ADDR_WIDTH - 1;
    localparam int TAG_LSB = ADDR_WIDTH - TAG_WIDTH;
    localparam int IDX_MSB = TAG_LSB - 1;
    localparam int IDX_LSB = OFFSET_WIDTH;

    // --------------------------------------------------------
    // Registered Signals (Input Buffers & FSM State)
    // --------------------------------------------------------
    logic                      req_valid_reg;
    logic [ADDR_WIDTH-1:0]     req_addr_reg;
    logic                      req_rw_reg;
    logic [(BLOCK_SIZE*8)-1:0] req_wdata_reg;
    logic [TAG_WIDTH-1:0]      req_tag_reg;
    logic [INDEX_WIDTH-1:0]    req_idx_reg;
    
    logic                      demand_target_way_reg;
    logic                      pref_target_way_reg;
    
    logic [ADDR_WIDTH-1:0]     pref_addr_reg; 
    logic                      is_miss_reg; 

    assign access_hit = cpu_ready & ~is_miss_reg;

    cache_state_t state, next_state;

    // --------------------------------------------------------
    // Datapath Multiplexing
    // --------------------------------------------------------
    logic is_pref_state;
    // UPDATED: Include the new prefetch write-back state
    assign is_pref_state = (state == STATE_PREF_COMPARE)    || 
                           (state == STATE_PREF_WRITE_BACK) ||
                           (state == STATE_PREF_ALLOCATE)   || 
                           (state == STATE_PREF_FILL);

    logic [INDEX_WIDTH-1:0] dp_index_in;
    logic [TAG_WIDTH-1:0]   dp_tag_in;
    logic [(BLOCK_SIZE*8)-1:0] dp_data_in;
    
    assign dp_index_in = is_pref_state ? pref_addr_reg[IDX_MSB : IDX_LSB] : req_idx_reg;
    assign dp_tag_in   = is_pref_state ? pref_addr_reg[TAG_MSB : TAG_LSB] : req_tag_reg;

    logic we_way0, set_dirty_way0, clear_dirty_way0;
    logic we_way1, set_dirty_way1, clear_dirty_way1;
    logic valid_way0, dirty_way0;
    logic valid_way1, dirty_way1;
    logic [TAG_WIDTH-1:0] tag_way0, tag_way1;
    logic [(BLOCK_SIZE*8)-1:0] data_way0, data_way1;

    logic hit_way0, hit_way1, cache_hit;
    assign hit_way0 = valid_way0 && (tag_way0 == dp_tag_in);
    assign hit_way1 = valid_way1 && (tag_way1 == dp_tag_in);
    assign cache_hit = hit_way0 || hit_way1;

    logic evict_way; 
    logic update_lru, update_fifo;
    logic repl_accessed_way;
    
    assign repl_accessed_way = (state == STATE_ALLOCATE)      ? demand_target_way_reg : 
                               (state == STATE_PREF_ALLOCATE) ? pref_target_way_reg   : hit_way1;

    // --------------------------------------------------------
    // Sub-Modules
    // --------------------------------------------------------
    cache_datapath #(.BLOCK_SIZE(BLOCK_SIZE), .SETS(SETS), .ADDR_WIDTH(ADDR_WIDTH)) i_datapath (
        .clk(clk), .rst_n(rst_n), .index(dp_index_in),
        .we_way0(we_way0), .set_dirty_way0(set_dirty_way0), .clear_dirty_way0(clear_dirty_way0),
        .we_way1(we_way1), .set_dirty_way1(set_dirty_way1), .clear_dirty_way1(clear_dirty_way1),
        .tag_in(dp_tag_in), .data_in(dp_data_in),
        .valid_way0(valid_way0), .dirty_way0(dirty_way0), .tag_way0(tag_way0), .data_way0(data_way0),
        .valid_way1(valid_way1), .dirty_way1(dirty_way1), .tag_way1(tag_way1), .data_way1(data_way1)
    );

    replacement_logic #(.SETS(SETS)) i_repl_logic (
        .clk(clk), .rst_n(rst_n), .policy(policy), .set_idx(dp_index_in),
        .update_lru(update_lru), .accessed_way(repl_accessed_way),
        .update_fifo(update_fifo), .evict_way(evict_way)
    );

    logic prefetch_req_valid;
    logic [ADDR_WIDTH-1:0] prefetch_req_addr;
    logic prefetch_ack;
    logic trigger_prefetch;
    
    assign trigger_prefetch = (state == STATE_COMPARE && req_valid_reg && cache_hit);

    prefetcher #(.ADDR_WIDTH(ADDR_WIDTH), .BLOCK_SIZE(BLOCK_SIZE)) i_prefetch (
        .clk(clk), .rst_n(rst_n), .enable_prefetch(enable_prefetch),
        .cpu_req_valid(trigger_prefetch), 
        .cpu_req_addr(req_addr_reg),
        .prefetch_ack(prefetch_ack),
        .prefetch_req_valid(prefetch_req_valid), 
        .prefetch_req_addr(prefetch_req_addr)
    );

    // --------------------------------------------------------
    // Sequential State & Request Latching
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            req_valid_reg <= 1'b0;
            req_addr_reg  <= '0;
            req_rw_reg    <= 1'b0;
            req_wdata_reg <= '0;
            req_tag_reg   <= '0;
            req_idx_reg   <= '0;
            demand_target_way_reg <= 1'b0;
            pref_target_way_reg   <= 1'b0;
            pref_addr_reg <= '0;
            is_miss_reg   <= 1'b0;
        end else begin
            state <= next_state;
            
            if (cpu_req) begin
                req_valid_reg <= 1'b1;
                req_addr_reg  <= cpu_addr;
                req_rw_reg    <= cpu_rw;
                req_wdata_reg <= cpu_wdata;
                req_tag_reg   <= cpu_addr[TAG_MSB : TAG_LSB];
                req_idx_reg   <= cpu_addr[IDX_MSB : IDX_LSB];
                is_miss_reg   <= 1'b0; 
            end else if (state == STATE_COMPARE && cache_hit) begin
                req_valid_reg <= 1'b0; 
            end
            
            if (state == STATE_COMPARE && req_valid_reg && !cache_hit) begin
                is_miss_reg <= 1'b1;
                if (!valid_way0)      demand_target_way_reg <= 1'b0;
                else if (!valid_way1) demand_target_way_reg <= 1'b1;
                else                  demand_target_way_reg <= evict_way;
            end
            
            if (state == STATE_PREF_COMPARE && !cache_hit) begin
                if (!valid_way0)      pref_target_way_reg <= 1'b0;
                else if (!valid_way1) pref_target_way_reg <= 1'b1;
                else                  pref_target_way_reg <= evict_way;
            end
            
            if (state == STATE_IDLE && !(cpu_req || req_valid_reg) && prefetch_req_valid && enable_prefetch) begin
                pref_addr_reg <= prefetch_req_addr;
            end
        end
    end

    // --------------------------------------------------------
    // Combinational FSM Logic
    // --------------------------------------------------------
    always_comb begin
        next_state = state;
        cpu_ready = 1'b0;
        cpu_rdata = '0;
        
        mem_req = 1'b0;
        mem_rw = 1'b0;
        mem_addr = '0;
        mem_wdata = '0;
        
        we_way0 = 1'b0; set_dirty_way0 = 1'b0; clear_dirty_way0 = 1'b0;
        we_way1 = 1'b0; set_dirty_way1 = 1'b0; clear_dirty_way1 = 1'b0;
        
        dp_data_in = req_wdata_reg;
        
        update_lru = 1'b0;
        update_fifo = 1'b0;
        prefetch_ack = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (cpu_req || req_valid_reg) begin
                    next_state = STATE_COMPARE;
                end 
                else if (prefetch_req_valid && enable_prefetch) begin
                    prefetch_ack = 1'b1;
                    next_state = STATE_PREF_COMPARE;
                end
            end

            STATE_COMPARE: begin
                if (cache_hit) begin
                    cpu_ready = 1'b1;
                    update_lru = 1'b1;
                    
                    if (req_rw_reg == 1'b0) begin 
                        cpu_rdata = hit_way0 ? data_way0 : data_way1;
                    end else begin                
                        if (hit_way0) begin
                            we_way0 = 1'b1;
                            set_dirty_way0 = 1'b1;
                        end else begin
                            we_way1 = 1'b1;
                            set_dirty_way1 = 1'b1;
                        end
                    end
                    next_state = STATE_IDLE;
                end else begin
                    next_state = STATE_EVICT;
                end
            end

            STATE_EVICT: begin
                if ((demand_target_way_reg ? valid_way1 : valid_way0) && 
                    (demand_target_way_reg ? dirty_way1 : dirty_way0)) begin
                    next_state = STATE_WRITE_BACK;
                end else begin
                    next_state = STATE_ALLOCATE;
                end
            end

            STATE_WRITE_BACK: begin
                mem_req = !mem_ready; 
                mem_rw = 1'b1; 
                mem_addr = demand_target_way_reg ? {tag_way1, req_idx_reg, {OFFSET_WIDTH{1'b0}}} 
                                                 : {tag_way0, req_idx_reg, {OFFSET_WIDTH{1'b0}}};
                mem_wdata = demand_target_way_reg ? data_way1 : data_way0;
                
                if (mem_ready) begin
                    if (demand_target_way_reg == 1'b0) clear_dirty_way0 = 1'b1;
                    else                               clear_dirty_way1 = 1'b1;
                    next_state = STATE_ALLOCATE;
                end
            end

            STATE_ALLOCATE: begin
                mem_req = !mem_ready; 
                mem_rw = 1'b0; 
                mem_addr = {req_tag_reg, req_idx_reg, {OFFSET_WIDTH{1'b0}}};
                
                if (mem_ready) begin
                    dp_data_in = mem_rdata;
                    update_fifo = 1'b1; 
                    update_lru = 1'b1; 
                    
                    if (demand_target_way_reg == 1'b0) begin
                        we_way0 = 1'b1;
                        clear_dirty_way0 = 1'b1;
                    end else begin
                        we_way1 = 1'b1;
                        clear_dirty_way1 = 1'b1;
                    end
                    next_state = STATE_FILL;
                end
            end
            
            STATE_FILL: next_state = STATE_COMPARE;

            STATE_PREF_COMPARE: begin
                if (cache_hit) begin
                    next_state = STATE_IDLE;
                end else begin
                    // AGGRESSIVE POLICY: Write back dirty lines instead of aborting
                    if ((evict_way ? valid_way1 : valid_way0) && 
                        (evict_way ? dirty_way1 : dirty_way0)) begin
                        next_state = STATE_PREF_WRITE_BACK; 
                    end else begin
                        next_state = STATE_PREF_ALLOCATE;
                    end
                end
            end

            STATE_PREF_WRITE_BACK: begin
                mem_req = !mem_ready; 
                mem_rw  = 1'b1; 
                // Construct memory address using pref_addr_reg index instead of demand index
                mem_addr = pref_target_way_reg ? {tag_way1, pref_addr_reg[IDX_MSB : IDX_LSB], {OFFSET_WIDTH{1'b0}}} 
                                               : {tag_way0, pref_addr_reg[IDX_MSB : IDX_LSB], {OFFSET_WIDTH{1'b0}}};
                mem_wdata = pref_target_way_reg ? data_way1 : data_way0;
                
                if (mem_ready) begin
                    if (pref_target_way_reg == 1'b0) clear_dirty_way0 = 1'b1;
                    else                             clear_dirty_way1 = 1'b1;
                    next_state = STATE_PREF_ALLOCATE;
                end
            end

            STATE_PREF_ALLOCATE: begin
                mem_req = !mem_ready; 
                mem_rw = 1'b0; 
                mem_addr = pref_addr_reg;
                
                if (mem_ready) begin
                    dp_data_in = mem_rdata;
                    update_fifo = 1'b1; 
                    update_lru = 1'b1; 
                    
                    if (pref_target_way_reg == 1'b0) begin
                        we_way0 = 1'b1;
                        clear_dirty_way0 = 1'b1;
                    end else begin
                        we_way1 = 1'b1;
                        clear_dirty_way1 = 1'b1;
                    end
                    next_state = STATE_PREF_FILL;
                end
            end

            STATE_PREF_FILL: next_state = STATE_IDLE;

            default: next_state = STATE_IDLE;
        endcase
    end

    // --------------------------------------------------------
    // SURGICAL DEBUG PROBES
    // --------------------------------------------------------
    cache_state_t prev_state;
    
    //always_ff @(posedge clk) begin
        //if (rst_n) begin
           // prev_state <= state;
            //if (state != prev_state && 
               //(state == STATE_PREF_WRITE_BACK || state == STATE_WRITE_BACK)) begin
              //  $display("[%0t] STATE %0d -> %0d | Issuing Writeback", $time, prev_state, state);
           // end
       // end
    //end

endmodule