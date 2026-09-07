module mshr (
  input logic clk, rst,

  input logic [31:0] addr_evict, addr_load, evict_data,
  input logic [4:0] regD_in,
  input logic load_valid, evict_valid, load_way_in,

  output logic [31:0] addr1, addr2, addr3, addr4,
  output logic [31:0] addr_out, data_out,
  output logic [4:0] regD_out,
  output logic load_way_out, done_pulse,
  output logic full
);

  localparam int NUM_REG = 4;
  localparam int ENTRY_WIDTH = 72;
  localparam int VALID_BIT = 71;
  localparam int LW_BIT = 70;
  localparam int WAY_BIT = 69;
  localparam int REGD_MSB = 68;
  localparam int REGD_LSB = 64;
  localparam int ADDR_MSB = 63;
  localparam int ADDR_LSB = 32;

  localparam logic [31:0] INVALID_ADDR = 32'hDEAD_BEEF;
  localparam logic [ENTRY_WIDTH-1:0] EMPTY_ENTRY = {
    1'b0, 1'b0, 1'b0, 5'b0, INVALID_ADDR, 32'b0
  };

  typedef enum logic [1:0] {IDLE, REQ, WAIT} wb_state;
  wb_state state, next_state;

  // Four physical slots form a circular FIFO. Each entry is
  // {valid, load, way, destination register, address, store data}.
  logic [ENTRY_WIDTH-1:0] entry [0:NUM_REG-1];
  logic [ENTRY_WIDTH-1:0] load_entry, evict_entry;
  logic [1:0] head, tail, next_head, next_tail;
  logic [2:0] count, next_count;

  // Up to one completion and two appends can touch the slots in one cycle.
  // Later append assignments intentionally override a clear when a full FIFO
  // pops and reuses that same physical slot.
  logic [NUM_REG-1:0] slot_we;
  logic [ENTRY_WIDTH-1:0] slot_wdata [0:NUM_REG-1];
  logic pop;
  logic [1:0] enqueue_count;
  logic [2:0] available;
  logic [ENTRY_WIDTH-1:0] enqueue_first;

  logic [1:0] head1, head2, head3, tail1;

  logic [31:0] rdata;
  logic valid_wb;
  logic req;

  logic [31:0] next_addr_out, next_data_out;
  logic [4:0] next_regD_out;
  logic next_load_way_out, next_done_pulse;

  assign load_entry = {1'b1, 1'b1, load_way_in, regD_in, addr_load, 32'b0};
  assign evict_entry = {1'b1, 1'b0, 1'b0, 5'b0, addr_evict, evict_data};

  assign head1 = head + 2'd1;
  assign head2 = head + 2'd2;
  assign head3 = head + 2'd3;
  assign tail1 = tail + 2'd1;

  // Preserve the old logical queue order on the hazard outputs even though
  // entries no longer move between physical slots.
  assign addr1 = entry[head][ADDR_MSB:ADDR_LSB];
  assign addr2 = entry[head1][ADDR_MSB:ADDR_LSB];
  assign addr3 = entry[head2][ADDR_MSB:ADDR_LSB];
  assign addr4 = entry[head3][ADDR_MSB:ADDR_LSB];

  // The cache reserves the fourth slot for a possible load-plus-eviction pair.
  assign full = count >= 3'd3;
  assign req = state == REQ;

  always_comb begin
    pop = state == WAIT && valid_wb;
    available = 3'd4 - count + (pop ? 3'd1 : 3'd0);
    enqueue_count = 2'd0;
    enqueue_first = evict_entry;

    // Loads retain priority over evictions when only one slot is available.
    if (load_valid && available != 0) begin
      enqueue_first = load_entry;
      enqueue_count = 2'd1;
      if (evict_valid && available >= 3'd2) enqueue_count = 2'd2;
    end else if (evict_valid && available != 0) begin
      enqueue_count = 2'd1;
    end

    next_head = head + (pop ? 2'd1 : 2'd0);
    next_tail = tail + enqueue_count;
    next_count = count - (pop ? 3'd1 : 3'd0) + {1'b0, enqueue_count};

    slot_we = '0;
    for (int i = 0; i < NUM_REG; i++) slot_wdata[i] = EMPTY_ENTRY;

    if (pop) begin
      case (head)
        2'd0: begin slot_we[0] = 1'b1; slot_wdata[0] = EMPTY_ENTRY; end
        2'd1: begin slot_we[1] = 1'b1; slot_wdata[1] = EMPTY_ENTRY; end
        2'd2: begin slot_we[2] = 1'b1; slot_wdata[2] = EMPTY_ENTRY; end
        2'd3: begin slot_we[3] = 1'b1; slot_wdata[3] = EMPTY_ENTRY; end
      endcase
    end

    if (enqueue_count != 0) begin
      case (tail)
        2'd0: begin slot_we[0] = 1'b1; slot_wdata[0] = enqueue_first; end
        2'd1: begin slot_we[1] = 1'b1; slot_wdata[1] = enqueue_first; end
        2'd2: begin slot_we[2] = 1'b1; slot_wdata[2] = enqueue_first; end
        2'd3: begin slot_we[3] = 1'b1; slot_wdata[3] = enqueue_first; end
      endcase
    end

    if (enqueue_count == 2) begin
      case (tail1)
        2'd0: begin slot_we[0] = 1'b1; slot_wdata[0] = evict_entry; end
        2'd1: begin slot_we[1] = 1'b1; slot_wdata[1] = evict_entry; end
        2'd2: begin slot_we[2] = 1'b1; slot_wdata[2] = evict_entry; end
        2'd3: begin slot_we[3] = 1'b1; slot_wdata[3] = evict_entry; end
      endcase
    end
  end

  always_comb begin
    next_state = state;
    next_addr_out = INVALID_ADDR;
    next_data_out = '0;
    next_regD_out = '0;
    next_load_way_out = 1'b0;
    next_done_pulse = 1'b0;

    case (state)
      IDLE: begin
        if (load_valid || evict_valid) next_state = REQ;
      end

      REQ: begin
        next_state = WAIT;
      end

      WAIT: begin
        if (valid_wb) begin
          if (entry[head][LW_BIT]) begin
            next_addr_out = entry[head][ADDR_MSB:ADDR_LSB];
            next_data_out = rdata;
            next_regD_out = entry[head][REGD_MSB:REGD_LSB];
            next_load_way_out = entry[head][WAY_BIT];
            next_done_pulse = 1'b1;
          end

          if (count == 3'd1 && !load_valid && !evict_valid)
            next_state = IDLE;
          else
            next_state = REQ;
        end
      end

      default:;
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
      head <= '0;
      tail <= '0;
      count <= '0;
      addr_out <= INVALID_ADDR;
      data_out <= '0;
      regD_out <= '0;
      load_way_out <= 1'b0;
      done_pulse <= 1'b0;
      for (int i = 0; i < NUM_REG; i++) entry[i] <= EMPTY_ENTRY;
    end else begin
      state <= next_state;
      head <= next_head;
      tail <= next_tail;
      count <= next_count;
      addr_out <= next_addr_out;
      data_out <= next_data_out;
      regD_out <= next_regD_out;
      load_way_out <= next_load_way_out;
      done_pulse <= next_done_pulse;
      for (int i = 0; i < NUM_REG; i++) begin
        if (slot_we[i]) entry[i] <= slot_wdata[i];
      end
    end
  end

  wb_simulator #(
    .MEM_FILE("data.memh"),
    .DEPTH(2048),
    .LATENCY(3)
  ) dcache_wb (
    .clk(clk),
    .rst_n(~rst),
    .req(req),
    .we(!entry[head][LW_BIT]),
    .addr(entry[head][ADDR_MSB:ADDR_LSB]),
    .wdata(entry[head][31:0]),
    .rdata(rdata),
    .busy(),
    .valid(valid_wb)
  );

endmodule
