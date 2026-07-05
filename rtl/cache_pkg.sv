`timescale 1ns / 1ps

package cache_pkg;

    typedef enum logic {
        REPLACE_LRU  = 1'b0,
        REPLACE_FIFO = 1'b1
    } replace_policy_t;

    typedef enum logic [3:0] {
        STATE_IDLE            = 4'd0,
        STATE_COMPARE         = 4'd1,
        STATE_EVICT           = 4'd2,
        STATE_WRITE_BACK      = 4'd3,
        STATE_ALLOCATE        = 4'd4,
        STATE_FILL            = 4'd5,
        STATE_PREF_COMPARE    = 4'd6,
        STATE_PREF_WRITE_BACK = 4'd7,
        STATE_PREF_ALLOCATE   = 4'd8,
        STATE_PREF_FILL       = 4'd9,
        STATE_PREF_EVICT      = 4'd10
    } cache_state_t;

endpackage
