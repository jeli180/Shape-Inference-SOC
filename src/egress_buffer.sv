module egress_buffer (
    input logic clk, rst,

    //tower
    input logic [7:0] tx_data, tx_data2,
    input logic tx_valid, tx_valid2,

    output logic uart_tx
);

    localparam int EB_DEPTH = 4;

    logic [EB_DEPTH - 1:0][7:0] eb, next_eb;
    logic [$clog2(EB_DEPTH + 1) - 1:0] wr_ptr, next_wr_ptr; //0 means eb empty

    //transmitter interface
    logic busy, valid;
    logic [7:0] data;

    uart_transmitter tx0(
        .clk(clk),
        .rst(rst),
        .data(data),
        .valid(valid),
        .busy(busy),
        .uart_tx(uart_tx)
    );

    always_comb begin
        for (int i = 0; i < EB_DEPTH; i++) next_eb[i] = eb[i];
        next_wr_ptr = wr_ptr;
        data = '0;
        valid = 1'b0;

        if (busy && tx_valid) begin
            next_eb[wr_ptr] = tx_data;
            next_wr_ptr = wr_ptr + 1;
        end else if (busy && tx_valid2) begin
            next_eb[wr_ptr] = tx_data;
            next_eb[wr_ptr + 1] = tx_data2;
            next_wr_ptr = wr_ptr + 2;
        end else if (!busy) begin
            if (tx_valid && |wr_ptr) begin
                valid = 1'b1;
                data = eb[0];

                for (int i = 0; i < EB_DEPTH - 1; i++) next_eb[i] = eb[i + 1];
                next_eb[wr_ptr - 1] = tx_data;
            end else if (tx_valid2 && |wr_ptr) begin
                valid = 1'b1;
                data = eb[0];

                for (int i = 0; i < EB_DEPTH - 1; i++) next_eb[i] = eb[i + 1];
                next_eb[wr_ptr - 1] = tx_data;
                next_eb[wr_ptr] = tx_data2;
                next_wr_ptr = wr_ptr + 1;
            end else if (tx_valid) begin
                valid = 1'b1;
                data = tx_data;
            end else if (tx_valid2) begin
                valid = 1'b1;
                data = tx_data;

                next_eb[0] = tx_data2;
                next_wr_ptr = 1;
            end else if (|wr_ptr) begin
                valid = 1'b1;
                data = eb[0];

                for (int i = 0; i < EB_DEPTH - 1; i++) next_eb[i] = eb[i + 1];
                next_wr_ptr = wr_ptr - 1;
            end
        end
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            for (int i = 0; i < EB_DEPTH; i++) eb[i] <= '0;
            wr_ptr <= '0;
        end else begin
            for (int i = 0; i < EB_DEPTH; i++) eb[i] <= next_eb[i];
            wr_ptr <= next_wr_ptr;
        end
    end

endmodule
