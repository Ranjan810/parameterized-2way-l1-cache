// tb_cache_top.sv
`timescale 1ns / 1ps
import cache_pkg::*;

module tb_cache_top;

    logic clk;
    logic rst_n;
    replace_policy_t policy;
    logic            enable_prefetch;
    
    logic            cpu_req;
    logic            cpu_rw;
    logic [31:0]     cpu_addr;
    logic [127:0]    cpu_wdata;
    logic [127:0]    cpu_rdata;
    logic            cpu_ready;
    logic            access_hit; 
    
    logic            mem_req;
    logic            mem_rw;
    logic [31:0]     mem_addr;
    logic [127:0]    mem_wdata;
    logic [127:0]    mem_rdata;
    logic            mem_ready;

    int cache_hits;
    int cache_misses;
    int memory_reads;
    int memory_writes;
    int dirty_evictions;
    int total_cycles;
    int total_accesses;

    logic [127:0] main_memory [0:8191]; 
    
    typedef enum logic {MEM_IDLE, MEM_BUSY} mem_state_t;
    mem_state_t mem_state;
    int mem_latency_ctr;
    
    cache_controller #(
        .BLOCK_SIZE(16),
        .SETS(128),
        .ADDR_WIDTH(32)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .policy(policy),
        .enable_prefetch(enable_prefetch),
        .cpu_req(cpu_req),
        .cpu_rw(cpu_rw),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .access_hit(access_hit), 
        .mem_req(mem_req),
        .mem_rw(mem_rw),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_cycles <= 0;
        end else begin
            total_cycles++;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_state <= MEM_IDLE;
            mem_ready <= 1'b0;
            mem_latency_ctr <= 0;
            memory_reads <= 0;
            memory_writes <= 0;
            dirty_evictions <= 0;
        end else begin
            case (mem_state)
                MEM_IDLE: begin
                    mem_ready <= 1'b0;
                   if (mem_req) begin
                       // $display("[%0t] MEMORY ACCEPT rw=%0b addr=%h", $time, mem_rw, mem_addr);
                        mem_state <= MEM_BUSY;
                        mem_latency_ctr <= 3; 
                        
                        if (mem_rw) memory_writes++;
                        else        memory_reads++;
                    end
                end
                MEM_BUSY: begin
                    if (mem_latency_ctr > 0) begin
                        mem_latency_ctr <= mem_latency_ctr - 1;
                    end else begin
                        mem_ready <= 1'b1;
                        if (mem_rw) begin
                            main_memory[mem_addr[16:4]] <= mem_wdata;
                            dirty_evictions++;
                        end else begin
                            mem_rdata <= main_memory[mem_addr[16:4]];
                        end
                        mem_state <= MEM_IDLE;
                    end
                end
            endcase
        end
    end

    initial begin
        int fd;
        string trace_file;
        string trc_rw; 
        logic [31:0] trc_addr;
        int scan_result;
        
        cache_hits = 0;
        cache_misses = 0;
        total_accesses = 0;
        
        trace_file = "thrashing.trc";
        policy = REPLACE_LRU;
        enable_prefetch = 1'b0; 
        
        if ($value$plusargs("TRACE=%s", trace_file)) begin
            $display("Using trace file: %s", trace_file);
        end
        if ($test$plusargs("FIFO")) begin
            policy = REPLACE_FIFO;
            $display("Configuration: FIFO Replacement");
        end else begin
            $display("Configuration: LRU Replacement");
        end
        if ($test$plusargs("PREFETCH")) begin
            enable_prefetch = 1'b1;
            $display("Configuration: Prefetcher ON");
        end else begin
            $display("Configuration: Prefetcher OFF");
        end

        rst_n = 0;
        cpu_req = 0;
        cpu_rw = 0;
        cpu_addr = 0;
        cpu_wdata = 0;
        
        #20 rst_n = 1; 
        
        fd = $fopen(trace_file, "r");
        if (fd == 0) begin
            $display("Error: Could not open %s", trace_file);
            $finish;
        end

        while (!$feof(fd)) begin
            scan_result = $fscanf(fd, "%s %h\n", trc_rw, trc_addr); 
            if (scan_result == 2) begin
                @(posedge clk);
                cpu_req   <= 1'b1;
                cpu_rw    <= (trc_rw == "W" || trc_rw == "1") ? 1'b1 : 1'b0;
                cpu_addr  <= trc_addr;
                cpu_wdata <= {4{trc_addr}}; 
                
                @(posedge clk);
                cpu_req   <= 1'b0;
                
                wait (cpu_ready == 1'b1);
                
                if (access_hit) begin
                    cache_hits++;
                end else begin
                    cache_misses++;
                end
                total_accesses++;
                @(posedge clk);
            end
        end
        
        $fclose(fd);
        #100;
        
        $display("=========================================");
        $display("       ARCHITECTURAL SIMULATION          ");
        $display("=========================================");
        $display("Trace             : %s", trace_file);
        $display("Total Accesses    : %11d", total_accesses);
        $display("Cache Hits        : %11d", cache_hits);
        $display("Cache Misses      : %11d", cache_misses);
        $display("Hit Rate          : %6.2f %%", (real'(cache_hits) / total_accesses) * 100.0);
        $display("-----------------------------------------");
        $display("Dirty Evictions   : %11d", dirty_evictions);
        $display("Memory Reads      : %11d", memory_reads);
        $display("Memory Writes     : %11d", memory_writes);
        $display("Total Mem Traffic : %11d blocks", memory_reads + memory_writes);
        $display("-----------------------------------------");
        $display("Total Cycles      : %11d", total_cycles);
        
        if (total_accesses > 0) begin
            real amat;
            amat = 2.0 + ((real'(cache_misses) / real'(total_accesses)) * 5.0);
            $display("AMAT (Cycles)     : %6.2f", amat);
        end
        $display("=========================================");
        
        $finish;
    end
endmodule