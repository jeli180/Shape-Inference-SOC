module temp_controller (
  input logic clk, rst,

  // fpga interface
  input logic [6:0] btn_edge,
  output logic [6:0] led,

  // dpu interface
  input logic ack,
  input logic [31:0] read_data,

  output logic req, load,
  output logic [31:0] addr, write_data
);

  typedef enum logic [2:0] {
    IDLE,
    START_DPU,
    WAIT_START_ACK,
    POLL_STATUS,
    WAIT_STATUS_ACK,
    DONE,
    ERROR
  } state_t;

  state_t state, next_state;
  logic readback_passed, next_readback_passed;
  logic [1:0] debug_phase, next_debug_phase;
  logic [1:0] test_mode, next_test_mode;

  always_comb begin
    req = 1'b0;
    load = 1'b0;
    addr = 32'b0;
    write_data = 32'b0;
    led = 7'b0;
    next_state = state;
    next_readback_passed = readback_passed;
    next_debug_phase = debug_phase;
    next_test_mode = test_mode;

    // LED0 confirms that the RA8875 configuration registers read back correctly.
    led[0] = readback_passed;

    case (state)
      IDLE: begin
        if (btn_edge[1]) begin
          next_test_mode = 2'd0;
          next_state = START_DPU;
        end else if (btn_edge[2]) begin
          next_test_mode = 2'd1;
          next_state = START_DPU;
        end else if (btn_edge[3]) begin
          next_test_mode = 2'd2;
          next_state = START_DPU;
        end else if (btn_edge[4]) begin
          next_test_mode = 2'd3;
          next_state = START_DPU;
        end
      end

      START_DPU: begin
        req = 1'b1;
        addr = 32'd4;
        write_data = {30'b0, test_mode};
        next_state = WAIT_START_ACK;
      end

      WAIT_START_ACK: begin
        if (ack) begin
          next_state = POLL_STATUS;
        end
      end

      POLL_STATUS: begin
        req = 1'b1;
        load = 1'b1;
        addr = 32'd8;
        next_state = WAIT_STATUS_ACK;
      end

      WAIT_STATUS_ACK: begin
        if (ack) begin
          next_readback_passed = read_data[2];
          if (read_data[1]) begin
            next_state = ERROR;
          end else if (read_data[0]) begin
            next_state = DONE;
          end else begin
            next_state = POLL_STATUS;
          end
        end
      end

      DONE: begin
        led[1] = 1'b1;
      end

      ERROR: begin
        // LED[1:0] identifies which returned DDRAM nibble is on LED[5:2].
        led[1:0] = debug_phase;
        req = 1'b1;
        load = 1'b1;
        addr = 32'd8;
        if (ack) begin
          next_readback_passed = read_data[2];
          next_debug_phase = read_data[3:2];
        end
      end

      default:;
    endcase
  end

  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      state <= IDLE;
      readback_passed <= 1'b0;
      debug_phase <= '0;
      test_mode <= '0;
    end else begin
      state <= next_state;
      readback_passed <= next_readback_passed;
      debug_phase <= next_debug_phase;
      test_mode <= next_test_mode;
    end
  end

endmodule
