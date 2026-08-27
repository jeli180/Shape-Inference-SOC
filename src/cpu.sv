module cpu (
  input logic clk, rst,

  //to mmio
  output logic req, lw,
  output logic [31:0] addr, data_write,
  output logic [4:0] regD_out,

  //from mmio
  input logic hit_ack, miss_store, load_done_stall, passive_stall,
  input logic [4:0] regD_done,
  input logic [31:0] data_read
);

  //hazard
  logic stall, jal_flush, branch_flush;
  logic [31:0] j_target, b_target;

  //register forwarding to execute
  logic regwrite_back_mem, regwrite_back_wb;
  logic [4:0] regD_back_mem, regD_back_wb;
  logic [31:0] regDval_back_mem, regDval_back_wb;

  //register from ex to mem for MSHR
  logic [4:0] mshr_reg1_ex, mshr_reg2_ex;

  //regfile
  logic file_wen;
  logic [4:0] file_reg1, file_reg2, file_regD;
  logic [31:0] file_write_data, file_reg1val, file_reg2val;

  //icache
  logic icache_req, icache_ack;
  logic [31:0] icache_addr, icache_inst;

  //fetch
  logic [31:0] inst_fe, pc_fe;

  //decode
  logic rtype_de, itype_de, utype_de, load_de, store_de, branch_de, jal_de, jalr_de;
  logic [4:0] reg1_de, reg2_de, regD_de;
  logic [31:0] imm_de, inst_de, pc_de, reg1val_de, reg2val_de;

  //execute
  logic regwrite_ex, load_ex, store_ex, jal_ex, jalr_ex, branch_cond_ex;
  logic [4:0] regD_ex;
  logic [31:0] target_ex, result_ex, store_data_ex;

  //mem
  logic regwrite_me, jal_me;
  logic [4:0] regD_me;
  logic [31:0] target_me, regdata_me;

  icache icache0 (
    .clk(clk),
    .rst(rst),

    //from fetch
    .addr(icache_addr),
    .send_pulse(icache_req),

    //to fetch
    .inst(icache_inst),
    .ack(icache_ack)
  );

  fetch fetch0 (
    .clk(clk),
    .rst(rst),

    //to cache
    .addr_ready(icache_req),
    .addr(icache_addr),

    //from cache
    .cache_ack(icache_ack),
    .inst(icache_inst),

    //hazards from pipeline
    .stall(stall),
    .jal(jal_flush),
    .branch(branch_flush),
    .j_target(j_target),
    .b_target(b_target),

    //to decode
    .final_pc(pc_fe),
    .final_inst(inst_fe)
  );

  decode decode0(
    .clk(clk),
    .rst(rst),

    //hazards from pipeline
    .stall(stall),
    .jal_flush(jal_flush),
    .branch_flush(branch_flush),

    //from fetch
    .inst(inst_fe),
    .pc(pc_fe),

    //to regfile
    .file_reg1(file_reg1),
    .file_reg2(file_reg2),

    //from regfile
    .file_val1(file_reg1val),
    .file_val2(file_reg2val),

    //to execute
    .rtype(rtype_de),
    .itype(itype_de),
    .utype(utype_de),
    .load(load_de),
    .store(store_de),
    .branch(branch_de),
    .jal(jal_de),
    .jalr(jalr_de),
    .imm(imm_de),
    .finalI(inst_de),
    .finalpc(pc_de),
    .reg1(reg1_de),
    .reg2(reg2_de),
    .regD(regD_de),
    .reg1val(reg1val_de),
    .reg2val(reg2val_de)
  );

  execute execute0 (
    .clk(clk),
    .rst(rst),

    //hazard
    .branch_flush(branch_flush),
    .jal_flush(jal_flush),
    .stall(stall),

    //reg forwarding
    .regD_mem(regD_back_mem),
    .regD_wb(regD_back_wb),
    .regD_val_mem(regDval_back_mem),
    .regD_val_wb(regDval_back_wb),
    .regwrite_mem(regwrite_back_mem),
    .regwrite_wb(regwrite_back_wb),
    
    //from decode
    .rtype(rtype_de),
    .itype(itype_de),
    .utype(utype_de),
    .load(load_de),
    .store(store_de),
    .branch(branch_de),
    .jal(jal_de),
    .jalr(jalr_de),
    .imm(imm_de),
    .inst(inst_de),
    .pc(pc_de),
    .reg1(reg1_de),
    .reg2(reg2_de),
    .regD(regD_de),
    .reg1val(reg1val_de),
    .reg2val(reg2val_de),

    //to mem
    .regwrite(regwrite_ex),
    .loadF(load_ex),
    .storeF(store_ex),
    .jalF(jal_ex),
    .jalrF(jalr_ex),
    .target(target_ex),
    .result(result_ex),
    .store_data(store_data_ex),
    .branch_cond(branch_cond_ex),
    .regDF(regD_ex),

    //to mem for mshr handling
    .mshr_reg1(mshr_reg1_ex),
    .mshr_reg2(mshr_reg2_ex)
  );

  mem mem0 (
    .clk(clk),
    .rst(rst),

    //register back to execute
    .regD_ex(regD_back_mem),
    .regD_val_ex(regDval_back_mem),
    .regwrite_ex(regwrite_back_mem),
    
    //registers currently in ex (for mshr)
    .reg1_ex(mshr_reg1_ex),
    .reg2_ex(mshr_reg2_ex),

    //hazard
    .jal_flush(jal_flush),
    .branch_flush(branch_flush),
    .b_target(b_target),
    .stall(stall),

    //to mmio
    .mmio_req(req),
    .mmio_lw(lw),
    .mmio_addr(addr),
    .mmio_data_write(data_write),
    .mmio_regD(regD_out),
    
    //from mmio
    .hit_ack(hit_ack),
    .miss_store(miss_store),
    .load_done_stall(load_done_stall),
    .passive_stall(passive_stall),
    .regD_done(regD_done),
    .mmio_data_read(data_read),

    //from execute
    .regwrite(regwrite_ex),
    .load(load_ex),
    .store(store_ex),
    .jal(jal_ex),
    .jalr(jalr_ex),
    .branch_cond(branch_cond_ex),
    .target(target_ex),
    .result(result_ex),
    .store_data(store_data_ex),
    .regD(regD_ex),

    //to wb
    .regwriteF(regwrite_me),
    .jalF(jal_me),
    .regDF(regD_me),
    .targetF(target_me),
    .regdataF(regdata_me)
  );

  writeback writeback0 (
    //hazard
    .jal_flush(jal_flush),
    .j_target(j_target),
    
    //register back to execute
    .regwrite_ex(regwrite_back_wb),
    .regD_ex(regD_back_wb),
    .regD_val_ex(regDval_back_wb),

    //to register file
    .wen(file_wen),
    .reg_num(file_regD),
    .write_data(file_write_data),

    //from mem
    .regwrite(regwrite_me),
    .jal(jal_me),
    .regD(regD_me),
    .target(target_me),
    .regdata(regdata_me)
  );

  regfile regfile0 (
    .clk(clk),
    .rst(rst),

    //from decode
    .reg1(file_reg1),
    .reg2(file_reg2),

    //to decode
    .reg1val(file_reg1val),
    .reg2val(file_reg2val),

    //from writeback
    .regwrite(file_wen),
    .regD(file_regD),
    .write_data(file_write_data)
  );

endmodule
