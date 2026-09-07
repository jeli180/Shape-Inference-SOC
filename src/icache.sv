module icache (
  input logic [31:0] addr,
  input logic send_pulse, clk, rst,
  output logic [31:0] inst,
  output logic ack
);

  //state machine for rewriting cache from new origin
  typedef enum {
    START_WRITE, 
    WAIT_BUSY,
    REWRITE,    
    IDLE_WRITE
  } write_state;

  //state machine for miss fetching with wishbone
  typedef enum {
    START_WB,
    POLL,
    IDLE_WB
  } wb_state;

  //state machine for hit
  typedef enum {
    REC,
    SEND
  } hit_state;

  write_state next_write, write;
  wb_state next_wb, wb;
  hit_state next_hit, hit;

  //internal signals
  logic [58:0] data [0:15]; //{valid, 26b tag, 32b inst}
  logic [58:0] next_data [0:15];
  logic [25:0] next_origin, origin; //origin of current cache instructions

  //wishbone signals for miss fetch
  logic req_solo, valid_solo; 
  logic [31:0] rdata_solo, next_addr_solo, addr_solo;

  //wishbone signals for cache rewrite
  logic req, valid_0, valid_1, valid_2, valid_3, busy_0, busy_1, busy_2, busy_3;
  logic [31:0] addr_0, addr_1, addr_2, addr_3;
  logic [31:0] rdata_0, rdata_1, rdata_2, rdata_3;

  //other signals
  logic [1:0] ct, next_ct; //4 wb, ct tracks 4 cycles of transactions to fill 16 instructions
  logic [3:0] idx, next_idx, reg_idx;
  logic [25:0] tag;
  logic ack_hit, ack_miss; //acks for when instruction is ready after hit and miss


  assign idx = addr [5:2];
  assign tag = addr [31:6];
  assign ack = ack_hit | ack_miss;

  always_comb begin
    //miss fetch signals
    ack_miss = 1'b0;
    next_wb = wb;
    req_solo = 1'b0;
    next_idx = idx;
    next_addr_solo = addr;

    //start signals
    ack_hit = 1'b0;
    next_origin = origin;
    inst = '0;
    
    //cache rewrite signals
    req = 1'b0;
    next_ct = ct;
    next_write = write;
    addr_0 = '0;
    addr_1 = '0;
    addr_2 = '0;
    addr_3 = '0;
    for (int i = 0; i < 16; i++) begin
      next_data[i] = data[i];
    end

    next_hit = hit;

    //wb statemachine (for misses)
    case (wb)
      START_WB: begin
        req_solo = 1'b1;
        next_wb = POLL;
      end
      POLL: begin
        if (valid_solo) begin
          next_wb = IDLE_WB;
          inst = rdata_solo;
          ack_miss = 1'b1;
        end
      end
      default:;
    endcase

    //cache rewrite statemachine
    case (write)
      START_WRITE: begin
        if (busy_0 || busy_1 || busy_2 || busy_3) begin //cache rewrite in the middle of another rewrite
          next_ct = 2'b00;
          next_write = WAIT_BUSY;
        end else begin
          req = 1'b1;
          addr_0 = {origin, ct, 4'b0000};
          addr_1 = {origin, ct, 4'b0100};
          addr_2 = {origin, ct, 4'b1000};
          addr_3 = {origin, ct, 4'b1100};
          next_write = REWRITE;
        end
      end 
      WAIT_BUSY: if (valid_0 && valid_1 && valid_2 && valid_3) next_write = START_WRITE;
      REWRITE: begin
        if (valid_0 && valid_1 && valid_2 && valid_3) begin
          next_data[{ct, 2'b00}] = {1'b1, origin, rdata_0};
          next_data[{ct, 2'b01}] = {1'b1, origin, rdata_1};
          next_data[{ct, 2'b10}] = {1'b1, origin, rdata_2};
          next_data[{ct, 2'b11}] = {1'b1, origin, rdata_3};
          if (ct == 2'b11) begin //
            next_write = IDLE_WRITE;
            next_ct = '0;
          end else begin
            next_write = START_WRITE;
            next_ct = ct + 2'b01;
          end
        end
      end
      IDLE_WRITE: next_ct = 2'b00;
      default:;
    endcase

    //hit statemachine gets prio for resetting ct
    case (hit)
      REC: begin
        if (send_pulse) begin
          if (data[idx][58] && tag == data[idx][57:32] && origin == tag) begin //hit
            next_hit = SEND;
          end else begin //miss
            next_wb = START_WB;
            if (origin != tag || write == IDLE_WRITE) begin //if cache is not currently being rewritten in the correct frame, start rewriting
              next_write = START_WRITE; //this needs to be a complete restart, complete restart 
              next_origin = tag;
              next_ct = 2'b0;
            end
          end
        end
      end
      SEND: begin //need registered
        next_hit = REC;
        inst = data[reg_idx][31:0];
        ack_hit = 1'b1;
      end
      default:;
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      origin <= '0;
      write <= IDLE_WRITE;
      wb <= IDLE_WB;
      hit <= REC;
      ct <= '0;
      addr_solo <= '0;
      reg_idx <= 4'b0;
      for (int i = 0; i < 16; i++) begin
        data[i] <= '0;
      end
    end else begin
      reg_idx <= next_idx;
      hit <= next_hit;
      origin <= next_origin;
      write <= next_write;
      wb <= next_wb;
      ct <= next_ct;
      addr_solo <= next_addr_solo;
      for (int i = 0; i < 16; i++) begin
        data[i] <= next_data[i];
      end
    end
  end

  //solo inst to get miss instr
  wb_simulator #(
    .MEM_FILE("memh/instruction_memory.memh"),
    .DEPTH(2048),
    .LATENCY(3)
  ) wb_solo_inst (
    .clk(clk),
    .rst_n(~rst),
    .req(req_solo),
    .we(1'b0),
    .addr(addr_solo),
    .wdata(32'd0),
    .rdata(rdata_solo),
    .busy(),
    .valid(valid_solo)
  );

  //cache rewrite wb
  wb_simulator #(
    .MEM_FILE("memh/instruction_memory.memh"),
    .DEPTH(2048),
    .LATENCY(3)
  ) wb0 (
    .clk(clk),
    .rst_n(~rst),
    .req(req),
    .we(1'b0),
    .addr(addr_0),
    .wdata(32'd0),
    .rdata(rdata_0),
    .busy(busy_0),
    .valid(valid_0)
    );

  wb_simulator #(
    .MEM_FILE("memh/instruction_memory.memh"),
    .DEPTH(2048),
    .LATENCY(3)
  ) wb1 (
    .clk(clk),
    .rst_n(~rst),
    .req(req),
    .we(1'b0),
    .addr(addr_1),
    .wdata(32'd0),
    .rdata(rdata_1),
    .busy(busy_1),
    .valid(valid_1)
  );

  wb_simulator #(
    .MEM_FILE("memh/instruction_memory.memh"),
    .DEPTH(2048),
    .LATENCY(3)
  ) wb2 (
    .clk(clk),
    .rst_n(~rst),
    .req(req),
    .we(1'b0),
    .addr(addr_2),
    .wdata(32'd0),
    .rdata(rdata_2),
    .busy(busy_2),
    .valid(valid_2)
  );

  wb_simulator #(
    .MEM_FILE("memh/instruction_memory.memh"),
    .DEPTH(2048),
    .LATENCY(3)
  ) wb3 (
    .clk(clk),
    .rst_n(~rst),
    .req(req),
    .we(1'b0),
    .addr(addr_3),
    .wdata(32'd0),
    .rdata(rdata_3),
    .busy(busy_3),
    .valid(valid_3)
  );

endmodule
