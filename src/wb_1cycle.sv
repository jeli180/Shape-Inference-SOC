module wb_1cycle #(
    parameter MEM_FILE = "memh/mlp_weights.memh",
    parameter DEPTH = 1024
)(
    input  logic        clk,
    input  logic        rst,

    input  logic        ren,       // asserted for one cycle to start a transaction
    input  logic [31:0] addr,

    output logic [31:0] rdata
);
    // --- memory ---
    localparam int ADDR_WIDTH = $clog2(DEPTH);

    (* ram_style = "block" *) logic [31:0] mem [0:DEPTH-1];
    initial $readmemh(MEM_FILE, mem);

    logic [31:0] mem_rdata;
    logic ren_d;
    wire [ADDR_WIDTH-1:0] addr_index = addr[ADDR_WIDTH-1:0];

    // Keep the memory read itself free of reset/clear logic so synthesis can
    // implement this large, read-only table with ECP5 block RAMs.
    always_ff @(posedge clk) begin
      if (ren) mem_rdata <= mem[addr_index];
    end

    always_ff @(posedge clk or posedge rst) begin
      if (rst) ren_d <= 1'b0;
      else ren_d <= ren;
    end

    // Preserve the original interface behavior: rdata is zero after a cycle
    // without ren and otherwise contains the registered ROM value.
    assign rdata = ren_d ? mem_rdata : '0;

endmodule
