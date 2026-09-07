`default_nettype none

module wb_simulator #(
    parameter MEM_FILE = "memh/instruction_memory.memh",
    parameter int DEPTH = 1024,
    parameter int LATENCY = 3
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        req,       // asserted for one cycle to start a transaction
    input  logic        we,        // 0 = read, 1 = write
    input  logic [31:0] addr,
    input  logic [31:0] wdata,

    output logic [31:0] rdata,
    output logic        busy,      // high while operation is in progress
    output logic        valid      // high for one cycle when transaction completes
);

    localparam int ADDR_INDEX_WIDTH = $clog2(DEPTH);

    (* ram_style = "block" *) logic [31:0] mem [0:DEPTH-1];

    logic [$clog2(LATENCY+1)-1:0] counter;
    logic pending;
    logic pending_we;
    logic [31:0] addr_reg;
    logic [31:0] wdata_reg;
    logic [31:0] mem_rdata;

    wire [ADDR_INDEX_WIDTH-1:0] addr_index;
    wire [ADDR_INDEX_WIDTH-1:0] addr_reg_index;

    assign addr_index     = addr[ADDR_INDEX_WIDTH+1:2];
    assign addr_reg_index = addr_reg[ADDR_INDEX_WIDTH+1:2];

    initial begin
        $readmemh(MEM_FILE, mem);
    end

    // Keep the memory port outside the asynchronously reset transaction
    // process so FPGA synthesis can infer block RAM. A read is sampled when
    // its request is accepted; the state machine exposes it only when the
    // configured transaction latency expires. Writes still occur on the
    // completion cycle, matching the original behavior.
    always_ff @(posedge clk) begin
        if (req && !busy && !we) begin
            mem_rdata <= mem[addr_index];
        end

        if (pending && counter == 0 && pending_we) begin
            mem[addr_reg_index] <= wdata_reg;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter    <= '0;
            pending    <= 1'b0;
            pending_we <= 1'b0;
            addr_reg   <= 32'b0;
            wdata_reg  <= 32'b0;
            busy       <= 1'b0;
            valid      <= 1'b0;
            rdata      <= 32'b0;
        end else begin
            valid <= 1'b0;

            if (req && !busy) begin
                pending    <= 1'b1;
                pending_we <= we;
                addr_reg   <= addr;
                wdata_reg  <= wdata;
                busy       <= 1'b1;
                counter <= ($bits(counter))'(LATENCY - 1);
            end else if (pending) begin
                if (counter == 0) begin
                    pending <= 1'b0;
                    busy    <= 1'b0;
                    valid   <= 1'b1;

                    if (!pending_we) rdata <= mem_rdata;
                end else begin
                    counter <= counter - 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
