module ingress_buffer #(parameter int IB_DEPTH = 31) (
    input logic clk, rst,

    //tower interface
    input logic pop, pop4,
    output logic [7:0] rx_data,
    output logic [31:0] rx4_data,
    output logic [2:0] rx4_valid,

    input logic uart_rx
);

    logic [IB_DEPTH - 1:0][7:0] ib, next_ib;

    logic [$clog2(IB_DEPTH + 1) - 1:0] wr_ptr, next_wr_ptr; //if empty, should be 0

    //uart reciever interface
    logic [7:0] data;
    logic valid;

    uart_reciever rx0 (
        .clk(clk),
        .rst(rst),
        .data(data),
        .valid(valid),
        .uart_rx(uart_rx)
    );

    assign rx_data = ib[0];
    assign rx4_data = {ib[3], ib[2], ib[1], ib[0]};
    assign rx4_valid = wr_ptr > 3 ? 3'd4 : wr_ptr[2:0];

    always_comb begin
        for (int i = 0; i < IB_DEPTH; i++) next_ib[i] = ib[i];
        next_wr_ptr = wr_ptr;

        if (valid && pop) begin
            for (int i = 0; i < IB_DEPTH - 1; i++) next_ib[i] = ib[i + 1];
            next_ib[wr_ptr - 1] = data;
        end else if (valid && pop4) begin
            for (int i = 0; i < IB_DEPTH - 4; i++) next_ib[i] = ib[i + 4];
            next_ib[wr_ptr - 4] = data;
            next_wr_ptr = wr_ptr - 3;
        end else if (valid) begin 
            next_ib[wr_ptr] = data;
            next_wr_ptr = wr_ptr + 1;
        end else if (pop) begin
            for (int i = 0; i < IB_DEPTH - 1; i++) next_ib[i] = ib[i + 1];
            next_wr_ptr = wr_ptr - 1;
        end else if (pop4) begin
            for (int i = 0; i < IB_DEPTH - 4; i++) next_ib[i] = ib[i + 4];
            next_wr_ptr = wr_ptr - 4;
        end
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            for (int i = 0; i < IB_DEPTH; i++) ib[i] <= '0;
            wr_ptr <= '0;
        end else begin
            for (int i = 0; i < IB_DEPTH; i++) ib[i] <= next_ib[i];
            wr_ptr <= next_wr_ptr;
        end
    end

endmodule
