module uart_reciever #(
    parameter int CLK_HZ = 25_000_000,
    parameter int BAUD = 115_200
) (
    input logic clk, rst,

    output logic [7:0] data,
    output logic valid,

    input logic uart_rx
);

    localparam int CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam int HALF_BIT_CLKS = CLKS_PER_BIT / 2;
    localparam int BAUD_CNT_W = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);
    localparam logic [BAUD_CNT_W-1:0] HALF_BIT_TICK = HALF_BIT_CLKS;
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
    logic rx_meta, rx_sync;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
        end
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            state <= IDLE;
            baud_cnt <= '0;
            bit_idx <= '0;
            shift_data <= '0;
            data <= '0;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;

            case (state)
                IDLE: begin
                    baud_cnt <= '0;
                    bit_idx <= '0;

                    if (!rx_sync) begin
                        state <= START;
                    end
                end

                START: begin
                    if (baud_cnt == HALF_BIT_TICK) begin
                        baud_cnt <= '0;

                        if (!rx_sync) begin
                            state <= DATA;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_cnt == FULL_BIT_TICK) begin
                        baud_cnt <= '0;
                        shift_data[bit_idx] <= rx_sync;

                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_cnt == FULL_BIT_TICK) begin
                        baud_cnt <= '0;
                        state <= IDLE;

                        if (rx_sync) begin
                            data <= shift_data;
                            valid <= 1'b1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                    baud_cnt <= '0;
                    bit_idx <= '0;
                end
            endcase
        end
    end

endmodule
