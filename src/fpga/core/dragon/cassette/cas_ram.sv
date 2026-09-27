//
// Simple dual-port RAM buffer for a loaded .cas file: one write port (fed
// by core_top.v's second data_loader instance) and one read port (fed by
// cas_player.sv). Single clock domain (clk_dragon) - the data_loader's
// write side and cas_player's read side both already run on it, so no
// cross-domain synchronization is needed here.
//
// Registered address, output updated the cycle after the address changes
// - matches the same read-latency convention as the real dpram/
// dpram_1r1w BRAM wrappers elsewhere in this design (confirmed by reading
// their own generic maps: address_reg=>"CLOCK1", outdata_reg=>
// "UNREGISTERED"), which is what cas_player.sv's ST_FETCH state expects.
//
`default_nettype none

module cas_ram #(
    parameter ADDR_WIDTH = 16
) (
    input  wire                   clk,

    input  wire                   wr_en,
    input  wire [ADDR_WIDTH-1:0]  wr_addr,
    input  wire [7:0]             wr_data,

    input  wire [ADDR_WIDTH-1:0]  rd_addr,
    output reg  [7:0]             rd_data
);

    reg [7:0] mem [0:(1<<ADDR_WIDTH)-1];

    always @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        rd_data <= mem[rd_addr];
    end

endmodule
