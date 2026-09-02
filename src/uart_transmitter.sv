module uart_transmitter #(
    parameter int CLK_HZ = 25_000_000,
    parameter int BAUD = 115_200
) (
    input logic clk, rst,

    input logic [7:0] data,
    input logic valid,

    output logic busy,

    output logic uart_tx
);

    localparam int CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam int BAUD_CNT_W = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);
    localparam logic [BAUD_CNT_W-1:0] FULL_BIT_TICK = CLKS_PER_BIT - 1;

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;

    state_t state;

    logic [BAUD_CNT_W-1:0] baud_cnt;
    logic [2:0] bit_idx;
    logic [7:0] shift_data;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            state <= IDLE;
            baud_cnt <= '0;
            bit_idx <= '0;
            shift_data <= '0;
            busy <= 1'b0;
            uart_tx <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    baud_cnt <= '0;
                    bit_idx <= '0;
                    busy <= 1'b0;
                    uart_tx <= 1'b1;

                    if (valid) begin
                        shift_data <= data;
                        busy <= 1'b1;
                        uart_tx <= 1'b0;
                        state <= START;
                    end
                end

                START: begin
                    busy <= 1'b1;
                    uart_tx <= 1'b0;

                    if (baud_cnt == FULL_BIT_TICK) begin
                        baud_cnt <= '0;
                        uart_tx <= shift_data[0];
                        state <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                DATA: begin
                    busy <= 1'b1;
                    uart_tx <= shift_data[bit_idx];

                    if (baud_cnt == FULL_BIT_TICK) begin
                        baud_cnt <= '0;

                        if (bit_idx == 3'd7) begin
                            uart_tx <= 1'b1;
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                            uart_tx <= shift_data[bit_idx + 1'b1];
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STOP: begin
                    uart_tx <= 1'b1;

                    if (baud_cnt == FULL_BIT_TICK) begin
                        baud_cnt <= '0;
                        bit_idx <= '0;
                        busy <= 1'b0;
                        state <= IDLE;
                    end else begin
                        busy <= 1'b1;
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                    baud_cnt <= '0;
                    bit_idx <= '0;
                    shift_data <= '0;
                    busy <= 1'b0;
                    uart_tx <= 1'b1;
                end
            endcase
        end
    end

endmodule
