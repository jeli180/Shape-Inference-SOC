module dcache (
  input logic clk, rst,

  //CPU
  input logic [4:0] regD_in,
  input logic [31:0] addr_in, store_data,
  input logic send_pulse, lw, //sw is low
  output logic hit_ack, miss_send, //both pulses, store dependent registers (lw reg) on miss_send
  output logic [4:0] regD_out,
  output logic [31:0] load_data,

  //Dcache hazard signals to CPU
  output logic load_done_stall, //pulse when mshr entry completes, if lw send to CPU/stall 1 cycle, miss_done not raised for SW completion
  output logic passive_stall, //raise when mshr reg file full and CPU sends another a miss or there is addr dependency against mshr entry | CPU stalls while mshr_full

  //MSHR 
  input logic [31:0] addr1, addr2, addr3, addr4, //track the 2 addr of every mshr entry
  input logic [4:0] mshr_regD_out,
  input logic [31:0] mshr_addr_out, mshr_data_out,
  input logic mshr_done_pulse, load_way_out,
  output logic [31:0] addr_evict, addr_load, evict_data,
  output logic [4:0] mshr_regD_in,
  output logic load_valid, evict_valid, load_way_in, //load is high

  //MSHR Hazard
  input logic mshr_full //all mshr outputs are sequential
);

  //mshr outputs only load data, store misses are handled before
  /*
  handle cases in order of prio:
    mshr done  
    - (sends everything to CPU) and raises load_done_stall as pulse DON'T SERVICE HITS AND MISSES AS NEXT CYCLE INSTRUCTIONS WILL BE SAME DUE TO STALL
    no mshr load done is 2nd in prio
    - check for addr dependencies against input register, raise addr_dep if yes and skip rest, else addr_dep = 0
    - if hit, process as normal
    - if miss, and mshr full, and no store miss with no mshr use, raise full_stall (full stall already being on also takes this branch, as the miss instruction is kept in place)
    - if miss and mshr NOT full, raise miss_send, send data to mshr reg same cycle

    In addition to the mshr related stuff, also handle normal Dcache behavior
  */

  /*
    new dcache to fix comb loop:
    - make all outputs to cpu registered, so 1 cycle delay 
  */

  //need to manually add/take away ack and store miss 1 cycle branches depending on num_ways val
  localparam int NUM_SETS = 64;
  localparam int NUM_WAYS = 2;
  localparam int SET_BITS = 6;
  localparam int TAG_BITS = 24;

  //64 set 2 way allocation
  // Keep each way's tag and data in one reset-free payload memory. Valid bits
  // gate every payload read, so invalid payload contents are unobservable.
  logic [TAG_BITS+31:0] payload_way0 [0:NUM_SETS-1];
  logic [TAG_BITS+31:0] payload_way1 [0:NUM_SETS-1];
  logic valid [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic dirty [0:NUM_SETS-1][0:NUM_WAYS-1];

  logic mru [0:NUM_SETS-1]; //most recently used way in a set

  // A transaction changes at most one cache entry. Explicit write enables
  // avoid building a full next-state mux for every bit in every entry.
  logic cache_payload_we, cache_valid_we, cache_dirty_we, cache_mru_we;
  logic [SET_BITS-1:0] cache_set_w;
  logic cache_way_w, cache_valid_w, cache_dirty_w, cache_mru_w;
  logic [TAG_BITS+31:0] cache_payload_w;

  //hazard
  logic full_stall, addr_dep;
  assign passive_stall = full_stall | addr_dep;

  logic [SET_BITS-1:0] cur_set, miss_set;
  logic [TAG_BITS-1:0] cur_tag, miss_tag;

  assign cur_set = addr_in[SET_BITS+1:2];
  assign miss_set = mshr_addr_out[SET_BITS+1:2];
  assign cur_tag = addr_in[31:32-TAG_BITS];
  assign miss_tag = mshr_addr_out[31:32-TAG_BITS];

  //registered cpu outputs
  logic next_full_stall, next_addr_dep, next_hit_ack, next_miss_send, next_load_done_stall;
  logic [4:0] next_regD_out;
  logic [31:0] next_load_data;

  always_comb begin
    cache_payload_we = 1'b0;
    cache_valid_we = 1'b0;
    cache_dirty_we = 1'b0;
    cache_mru_we = 1'b0;
    cache_set_w = '0;
    cache_way_w = 1'b0;
    cache_payload_w = '0;
    cache_valid_w = 1'b0;
    cache_dirty_w = 1'b0;
    cache_mru_w = 1'b0;

    //CPU defaults
    next_hit_ack = 0;
    next_miss_send = 0;
    next_regD_out = '0;
    next_load_data = '0;

    //Hazard to CPU
    next_load_done_stall = 0;
    next_full_stall = 0;
    next_addr_dep = 0;

    //MSHR defaults
    addr_evict = '0;
    addr_load = '0;
    evict_data = '0;
    mshr_regD_in = '0;
    load_valid = 0;
    evict_valid = 0;
    load_way_in = 0;

    //IF MSHR DONE PULSE AND SEND PULSE SAME CYCLE
    //mem goes into rec state whenever it reqs dcache but dcache might not have processed send pulse since mshr_done_pulse has prio over it
    //solution is to have load_done_stall logic in rec state, and req dcache again (next_state = req) if load_done_stall since ex outputs will be the same
    
    if (mshr_done_pulse) begin //mshr done / send to CPU / replace cache val
      //cache replacement
      cache_set_w = miss_set;
      cache_way_w = load_way_out;
      cache_payload_we = 1'b1;
      cache_valid_we = 1'b1;
      cache_dirty_we = 1'b1;
      cache_mru_we = 1'b1;
      cache_payload_w = {miss_tag, mshr_data_out};
      cache_valid_w = 1'b1;
      cache_dirty_w = 1'b0;
      cache_mru_w = load_way_out;
      
      //inject load instructions into pipeline
      next_load_done_stall = 1'b1;
      next_regD_out = mshr_regD_out;
      next_load_data = mshr_data_out;
    end else if (send_pulse) begin //normal behavior (service CPU requests), if add more ways add more hit branches
      if (addr_in == addr1 || addr_in == addr2 || addr_in == addr3 || addr_in == addr4) begin
        next_addr_dep = 1'b1; //stall CPU
      end else if (cur_tag == payload_way1[cur_set][TAG_BITS+31:32] && valid[cur_set][1]) begin //check way1 hit
        cache_set_w = cur_set;
        cache_way_w = 1'b1;
        cache_mru_we = 1'b1;
        cache_mru_w = 1'b1;
        next_hit_ack = 1'b1;
        if (lw) begin
          next_load_data = payload_way1[cur_set][31:0];
          next_regD_out = regD_in; //may not need
        end else begin
          cache_payload_we = 1'b1;
          cache_dirty_we = 1'b1;
          cache_payload_w = {payload_way1[cur_set][TAG_BITS+31:32], store_data};
          cache_dirty_w = 1'b1;
        end
      end else if (cur_tag == payload_way0[cur_set][TAG_BITS+31:32] && valid[cur_set][0]) begin //check way0 hit
        cache_set_w = cur_set;
        cache_way_w = 1'b0;
        cache_mru_we = 1'b1;
        cache_mru_w = 1'b0;
        next_hit_ack = 1'b1;
        if (lw) begin
          next_load_data = payload_way0[cur_set][31:0];
          next_regD_out = regD_in; //may not need
        end else begin
          cache_payload_we = 1'b1;
          cache_dirty_we = 1'b1;
          cache_payload_w = {payload_way0[cur_set][TAG_BITS+31:32], store_data};
          cache_dirty_w = 1'b1;
        end
      //can only be miss now
      end else if (mshr_full) begin
        //store misses to nonvalid or clean lines don't use mshr
        if (!lw && (!dirty[cur_set][0] || !valid[cur_set][0])) begin //check way0
          cache_set_w = cur_set;
          cache_way_w = 1'b0;
          cache_payload_we = 1'b1;
          cache_valid_we = 1'b1;
          cache_dirty_we = 1'b1;
          cache_mru_we = 1'b1;
          cache_payload_w = {cur_tag, store_data};
          cache_valid_w = 1'b1;
          cache_dirty_w = 1'b1;
          cache_mru_w = 1'b0;
          next_hit_ack = 1'b1;
        end else if (!lw && (!dirty[cur_set][1] || !valid[cur_set][1])) begin //check way1
          cache_set_w = cur_set;
          cache_way_w = 1'b1;
          cache_payload_we = 1'b1;
          cache_valid_we = 1'b1;
          cache_dirty_we = 1'b1;
          cache_mru_we = 1'b1;
          cache_payload_w = {cur_tag, store_data};
          cache_valid_w = 1'b1;
          cache_dirty_w = 1'b1;
          cache_mru_w = 1'b1;
          next_hit_ack = 1'b1;
        end else begin
          next_full_stall = 1'b1;
        end
      end else begin //send stuff to MSHR
        //make CPU store dependent register
        if (lw) begin
          next_miss_send = 1'b1; //tells CPU to continue, if current is a lw CPU stores current reg for dependency logic
          load_valid = 1'b1; //pulse
          load_way_in = !mru[cur_set];
          addr_load = addr_in;
          mshr_regD_in = regD_in;
          cache_set_w = cur_set;
          cache_way_w = !mru[cur_set];
          cache_dirty_we = 1'b1;
          cache_valid_we = 1'b1;
          cache_dirty_w = 1'b0;
          cache_valid_w = 1'b0; //prevent loading potentially stale data or storing to line that will be replaced
        end else begin //store miss automatically replaces line
          next_hit_ack = 1'b1;
          cache_set_w = cur_set;
          cache_way_w = !mru[cur_set];
          cache_payload_we = 1'b1;
          cache_valid_we = 1'b1;
          cache_dirty_we = 1'b1;
          cache_mru_we = 1'b1;
          cache_payload_w = {cur_tag, store_data};
          cache_valid_w = 1'b1;
          cache_dirty_w = 1'b1;
          cache_mru_w = !mru[cur_set];
        end
        
        //eviction handling
        if (dirty[cur_set][!mru[cur_set]] && valid[cur_set][!mru[cur_set]]) begin
          evict_valid = 1'b1;
          if (mru[cur_set]) begin
            addr_evict = {payload_way0[cur_set][TAG_BITS+31:32], cur_set, 2'b0};
            evict_data = payload_way0[cur_set][31:0];
          end else begin
            addr_evict = {payload_way1[cur_set][TAG_BITS+31:32], cur_set, 2'b0};
            evict_data = payload_way1[cur_set][31:0];
          end
        end
      end
    end 
  end   

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      for (int i = 0; i < NUM_SETS; i++) begin
        mru[i] <= 0;
        for (int j = 0; j < NUM_WAYS; j++) begin
          valid[i][j] <= 0;
          dirty [i][j] <= 0;
        end
      end
      load_done_stall <= 0;
      full_stall <= 0;
      addr_dep <= 0;
      hit_ack <= 0;
      miss_send <= 0;
      load_data <= '0;
      regD_out <= '0;
    end else begin
      if (cache_mru_we) mru[cache_set_w] <= cache_mru_w;
      if (cache_valid_we) valid[cache_set_w][cache_way_w] <= cache_valid_w;
      if (cache_dirty_we) dirty[cache_set_w][cache_way_w] <= cache_dirty_w;
      load_done_stall <= next_load_done_stall;
      full_stall <= next_full_stall;
      addr_dep <= next_addr_dep;
      hit_ack <= next_hit_ack;
      miss_send <= next_miss_send;
      load_data <= next_load_data;
      regD_out <= next_regD_out;
    end
  end

  // A transaction writes at most one way. The payload memories need no reset;
  // valid is reset and suppresses every access until a complete payload write.
  always_ff @(posedge clk) begin
    if (!rst && cache_payload_we) begin
      if (cache_way_w) payload_way1[cache_set_w] <= cache_payload_w;
      else payload_way0[cache_set_w] <= cache_payload_w;
    end
  end
endmodule
