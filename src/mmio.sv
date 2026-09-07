module mmio (
  //from CPU
  input logic req, lw,
  input logic [31:0] addr, data_write,
  input logic [4:0] regD_in,

  //to CPU
  output logic hit_ack, miss_store, load_done_stall, passive_stall,
  output logic [4:0] regD_done,
  output logic [31:0] data_read,

  //to dcache
  output logic [4:0] ca_regD_in,
  output logic [31:0] ca_addr_in, ca_write_data,
  output logic ca_req, ca_lw,

  //from dcache
  input logic ca_hit, ca_miss_send, ca_load_done_stall, ca_passive_stall,
  input logic [4:0] ca_regD_out,
  input logic [31:0] ca_read_data,

  //to dpu
  output logic dp_req, dp_lw,
  output logic [31:0] dp_addr, dp_write_data,
  
  //from dpu
  input logic dp_ack,
  input logic [31:0] dp_read_data,

  // //to tensor_mem
  // output logic tm_wen,
  // output logic [31:0] tm_write_data, tm_addr,

  //to tensor controller
  output logic tc_req, tc_lw,
  output logic [31:0] tc_addr, tc_data_write,

  //from tensor controller
  input logic tc_ack,
  input logic [31:0] tc_read_data

);

  /*
    addr map
    - 0 not used 
    - uart: 4 -> 8
    - dcache: 12 -> 2060
    - tensor_controller: 58768 = h0 -> 58780 = hC 
  */

  //outputs to dcache 
  assign ca_req = addr > 32'd8 && addr <= 32'd2060 ? req : 1'b0;
  assign ca_lw = addr > 32'd8 && addr <= 32'd2060 ? lw : 1'b0;
  assign ca_regD_in = addr > 32'd8 && addr <= 32'd2060 ? regD_in : '0;
  assign ca_addr_in = addr > 32'd8 && addr <= 32'd2060 ? addr - 32'd12 : 32'hFFFFFFFF; //offset dcache addr to utilize first 3 addr
  assign ca_write_data = addr > 32'd8 && addr <= 32'd2060 ? data_write : '0;

  //outputs to dpu
  //if storing to dpu, block rereq on load_done_stall since dpu already recieved first store
  //if loading from dpu, need to rereq since cpu didn't take the dpu read_data
  assign dp_req = addr <= 32'd8 && ((ca_load_done_stall && lw) || !ca_load_done_stall) ? req : 1'b0; 
  assign dp_lw = addr <= 32'd8 && ((ca_load_done_stall && lw) || !ca_load_done_stall) ? lw : 1'b0;
  assign dp_addr = addr <= 32'd8 && ((ca_load_done_stall && lw) || !ca_load_done_stall) ? addr : '0;
  assign dp_write_data = addr <= 32'd8 && ((ca_load_done_stall && lw) || !ca_load_done_stall) ? data_write : '0;

  // //outputs to tensor_mem (only writes)
  // assign tm_wen = req && addr >= 32'd1036 && addr <= 32'd58766 && !lw && !ca_load_done_stall ? 1'b1 : 1'b0;
  // assign tm_addr = req && addr >= 32'd1036 && addr <= 32'd58766 && !lw && !ca_load_done_stall ? addr - 32'd1036 : 32'hFFFFFFFF;
  // assign tm_write_data = req && addr >= 32'd1036 && addr <= 32'd58766 && !lw && !ca_load_done_stall ? data_write : '0;

  //outputs to cpu
  assign hit_ack = dp_ack || ca_hit || tc_ack;
  assign miss_store = ca_miss_send;
  assign load_done_stall = ca_load_done_stall;
  assign passive_stall = ca_passive_stall;
  assign regD_done = ca_load_done_stall ? ca_regD_out : '0;
  //load_done_stall overwrites dp_read_data since CPU will rereq if reading from dpu
  assign data_read = ca_load_done_stall || ca_hit ? ca_read_data : 
                                           dp_ack ? dp_read_data : 
                                           tc_ack ? tc_read_data :
                                           '0;

  //outputs to tensor controller | block store rereq on load_done_stall | rereq load on load_done_stall 
  assign tc_req = addr >= 32'd58768 && ((ca_load_done_stall && lw) || !ca_load_done_stall) ? req : 1'b0;
  assign tc_lw = addr >= 32'd58768 && ((ca_load_done_stall && lw) || !ca_load_done_stall) ? lw : 1'b0;
  assign tc_addr = addr >= 32'd58768 && ((ca_load_done_stall && lw) || !ca_load_done_stall) ? addr - 32'd58768 : '0;
  assign tc_data_write = addr >= 32'd58768 && ((ca_load_done_stall && lw) || !ca_load_done_stall) ? data_write : '0;

endmodule