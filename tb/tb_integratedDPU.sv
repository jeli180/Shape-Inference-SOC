`timescale 1ns/1ps
module tb_integratedDPU;
  /*
    - use mmio to drive cpu side inputs
    - cpu will store pixel data in dcache/registers and we can check register values 
    - similar to in pipeline testbench
    - the read data we send into tb_dpu will have to match the register values we expect
    - print the screen transactions, including register that is specified (if there is none indicate),
      write_data, read_data, whether the transaction was done correctly or not
  */

  logic clk, rst;

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
  logic rtype_de, itype_de, load_de, store_de, branch_de, jal_de, jalr_de;
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

  //mmio
  logic mmio_req, mmio_lw, mmio_hit, mmio_miss, mmio_load_done_stall, mmio_passive_stall;
  logic [4:0] mmio_regD_in, mmio_regD_out;
  logic [31:0] mmio_addr, mmio_write_data, mmio_read_data;

  //dpu
  logic dp_req, dp_lw, dp_ack, rd, wr, rs, cs, interrupt;
  logic [31:0] dp_addr, dp_write_data, dp_read_data;
  wire [7:0] db;
  logic [7:0] dpu_db_out;
  logic dpu_db_oe;
  assign db = dpu_db_oe ? dpu_db_out : 8'hZZ;

  //dcache
  logic ca_req, ca_lw, ca_hit, ca_miss, ca_load_done_stall, ca_passive_stall;
  logic [4:0] ca_regD_in, ca_regD_out;
  logic [31:0] ca_addr, ca_write_data, ca_read_data;

  //mshr
  logic load_valid, evict_valid, load_way_in, mshr_done_pulse, load_way_out, mshr_full;
  logic [4:0] mshr_regD_in, mshr_regD_out;
  logic [31:0] evict_addr, load_addr, evict_data, mshr_addr_out, mshr_data_out, mshr_addr1, mshr_addr2, mshr_addr3, mshr_addr4;

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
    .mmio_req(mmio_req),
    .mmio_lw(mmio_lw),
    .mmio_addr(mmio_addr),
    .mmio_data_write(mmio_write_data),
    .mmio_regD(mmio_regD_in),
    
    //from mmio
    .hit_ack(mmio_hit),
    .miss_store(mmio_miss),
    .load_done_stall(mmio_load_done_stall),
    .passive_stall(mmio_passive_stall),
    .regD_done(mmio_regD_out),
    .mmio_data_read(mmio_read_data),

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

  mmio mmio0 (
    //from cpu
    .req(mmio_req),
    .lw(mmio_lw),
    .addr(mmio_addr),
    .data_write(mmio_write_data),
    .regD_in(mmio_regD_in),

    //to cpu
    .hit_ack(mmio_hit),
    .miss_store(mmio_miss),
    .load_done_stall(mmio_load_done_stall),
    .passive_stall(mmio_passive_stall),
    .regD_done(mmio_regD_out),
    .data_read(mmio_read_data),
    
    //to dcache
    .ca_regD_in(ca_regD_in),
    .ca_addr_in(ca_addr),
    .ca_write_data(ca_write_data),
    .ca_req(ca_req),
    .ca_lw(ca_lw),

    //from dcache
    .ca_hit(ca_hit),
    .ca_miss_send(ca_miss),
    .ca_load_done_stall(ca_load_done_stall),
    .ca_passive_stall(ca_passive_stall),
    .ca_regD_out(ca_regD_out),
    .ca_read_data(ca_read_data),

    //to dpu
    .dp_req(dp_req),
    .dp_lw(dp_lw),
    .dp_addr(dp_addr),
    .dp_write_data(dp_write_data),

    //from dpu
    .dp_ack(dp_ack),
    .dp_read_data(dp_read_data)
  );

  dpu dpu0 (
    .clk(clk),
    .rst(rst),

    //from mmio
    .req(dp_req),
    .load(dp_lw),
    .addr(dp_addr),
    .write_data(dp_write_data),

    //to mmio
    .ack(dp_ack),
    .read_data(dp_read_data),

    //to screen
    .rd(rd),
    .wr(wr),
    .rs(rs),
    .cs(cs),

    //from screen
    .interrupt(interrupt),

    //screen data bus
    .db_in(db),
    .db_out(dpu_db_out),
    .db_oe(dpu_db_oe)
  );

  dcache dcache0 (
    .clk(clk),
    .rst(rst),

    //from mmio
    .send_pulse(ca_req),
    .lw(ca_lw),
    .regD_in(ca_regD_in),
    .addr_in(ca_addr),
    .store_data(ca_write_data),

    //to mmio
    .hit_ack(ca_hit),
    .miss_send(ca_miss),
    .regD_out(ca_regD_out),
    .load_data(ca_read_data),
    .load_done_stall(ca_load_done_stall),
    .passive_stall(ca_passive_stall),

    //to MSHR
    .load_valid(load_valid),
    .evict_valid(evict_valid),
    .load_way_in(load_way_in),
    .mshr_regD_in(mshr_regD_in),
    .addr_evict(evict_addr),
    .addr_load(load_addr),
    .evict_data(evict_data),

    //from MSHR
    .mshr_done_pulse(mshr_done_pulse),
    .load_way_out(load_way_out),
    .mshr_regD_out(mshr_regD_out),
    .mshr_addr_out(mshr_addr_out),
    .mshr_data_out(mshr_data_out),
    .addr1(mshr_addr1),
    .addr2(mshr_addr2),
    .addr3(mshr_addr3),
    .addr4(mshr_addr4),

    //MSHR hazard
    .mshr_full(mshr_full)
  );

  mshr mshr0 (
    .clk(clk),
    .rst(rst),

    //from dcache
    .load_valid(load_valid),
    .evict_valid(evict_valid),
    .load_way_in(load_way_in),
    .regD_in(mshr_regD_in),
    .addr_evict(evict_addr),
    .addr_load(load_addr),
    .evict_data(evict_data),

    //to dcache
    .load_way_out(load_way_out),
    .done_pulse(mshr_done_pulse),
    .regD_out(mshr_regD_out),
    .addr_out(mshr_addr_out),
    .data_out(mshr_data_out),
    .addr1(mshr_addr1),
    .addr2(mshr_addr2),
    .addr3(mshr_addr3),
    .addr4(mshr_addr4),

    //hazard to dcache
    .full(mshr_full)
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

  //tri-state system for driving db on read
  //observe db directly

  logic [7:0] db_drive_val;
  logic db_drive_en;
  assign db = db_drive_en ? db_drive_val : 8'hZZ;

  logic [15:0] pixels [1:480][0:29];
  logic [9:0] xcoord [0:25];
  logic [9:0] ycoord [0:25];
  logic [9:0] refx [0:28799];
  logic [9:0] refy [0:28799];
  int coord_idx;

  //set_shape()
  logic [2:0] shape_id [0:3]; //first index is first quad, 100 is circle, 001 is line, 010 is square, initialized according to software in set_shape()
  logic [9:0] circle_centerx [0:3];
  logic [9:0] circle_centery [0:3];
  logic [7:0] circle_radius;
  logic [9:0] square_startx [0:3];
  logic [9:0] square_starty [0:3];
  logic [9:0] square_endx [0:3];
  logic [9:0] square_endy [0:3];

  logic [15:0] on_data;

  logic [7:0] pix;

  //temps to store trans task outputs
  logic s_rw, burst; //read high
  logic [7:0] s_addr, s_write_data, s_read_data;


  //16 pixels represent 1 bit
  //make the buses dpu sends back to cpu count up starting from 1 - 480 (480 registers of 30 compressed pixel bits)
  //also cycle through different ON cases (also a counter starting at 1 -> all 16 pixels on bitwise = 16'hFFFF)
  //premake 14400 16b buses

  /* DRIVE/MONITOR SUMMARY
     drive(dpu inputs from screen): db, interrupt
     monitor(dpu outputs to screen): rd, wr, rs, cs, db
     monitor(cpu regfile indicators): file_wen, file_regD, file_write_data
  */

  /* FLOW
      - CPU sends initialization signal through code, print initialization to terminal
      - Call blocking transaction reporter task (print details of 1 transaction to term) 
      - 
  */

  initial clk = 0;
  always #5 clk = ~clk;

  task reset();
    rst = 1;
    db_drive_val = '0;
    db_drive_en = 0;
    interrupt = 1'b1;
    on_data = 16'd1;
    coord_idx = 0;
    pix = '0;

    for (int i = 1; i < 481; i++) begin
      for (int j = 0; j < 30; j++) begin
        pixels[i][j] = '0;
      end
    end

    @(posedge clk);
    @(posedge clk);
    rst = 0;
  endtask

  task automatic set_shape(); //set shape reference vals
    shape_id[0] = 3'b100; //circle
    shape_id[1] = 3'b001; //line
    shape_id[2] = 3'b010;
    shape_id[3] = 3'b100;

    circle_centerx[0] = 10'b0001110111;
    circle_centerx[2] = 10'b0001110111;
    circle_centery[0] = 10'b0001110111;
    circle_centery[1] = 10'b0001110111;

    circle_centerx[1] = 10'b0101100111;
    circle_centerx[3] = 10'b0101100111;
    circle_centery[2] = 10'b0101100111;
    circle_centery[3] = 10'b0101100111;

    circle_radius = 8'b01010000;

    square_startx[0] = 10'b0000111011;
    square_startx[2] = 10'b0000111011;
    square_starty[0] = 10'b0000111011;
    square_starty[1] = 10'b0000111011;

    square_startx[1] = 10'b0100101011;
    square_startx[3] = 10'b0100101011;
    square_starty[2] = 10'b0100101011;
    square_starty[3] = 10'b0100101011;

    square_endx[0] = 10'b0010110011;
    square_endx[2] = 10'b0010110011;
    square_endy[0] = 10'b0010110011;
    square_endy[1] = 10'b0010110011;

    square_endx[1] = 10'b0110100011;
    square_endx[3] = 10'b0110100011;
    square_endy[2] = 10'b0110100011;
    square_endy[3] = 10'b0110100011;
  endtask

  task automatic set_pixels();
    logic [31:0] ref_reg;
    for (int i = 1; i < 481; i++) begin
      ref_reg = i;
      for (int j = 0; j < 30; j++) begin
        if (ref_reg[j]) begin
          pixels[i][j] = on_data;
          if (on_data == 16'hFFFF) on_data = 16'd1;
          else on_data++;
        end else pixels[i][j] = '0;
      end
    end
  endtask

  task automatic set_coords();

    /*
      fill bus with 20 random coords, including edge cases
      last coord will be in special zone so statemachine advances to DRAW
    */

    int idx = 0;
    logic [9:0] originx, originy, tempx, tempy;

    //set coords that are sent
    //set last coord
    xcoord[25] = 10'd600;
    ycoord[25] = 10'd240;

    for (int row = 0; row < 5; row++) begin
      for (int col = 0; col < 5; col++) begin
        if (row == 4) ycoord[idx] = row * 10'd120 - 1;
        else ycoord[idx] = row * 10'd120;

        if (col == 4) xcoord[idx] = col * 10'd120 - 1;
        else xcoord[idx] = col * 10'd120;

        idx++;
      end
    end

    idx = 0;
    //set ref coords (top left) of 4x4 active windows in correct order
    //NEED TO FIX
    for (int i = 0; i < 4; i++) begin
      if (i == 0) begin
        originx = 10'd0;
        originy = 10'd0;
      end else if (i == 1) begin
        originx = 10'd240;
        originy = 10'd0;
      end else if (i == 2) begin
        originx = 10'd0;
        originy = 10'd240;
      end else begin
        originx = 10'd240;
        originy = 10'd240;
      end
      for (int row = 0; row < 60; row++) begin
        for (int col = 0; col < 60; col++) begin
          refx[idx] = originx + 4 * col;
          refy[idx] = originy + 4 * row;
          idx++;
          refx[idx] = refx[idx - 1] + 10'd3;
          refy[idx] = refy[idx - 1] + 10'd3;
          idx++;
        end
      end
    end
  endtask

  task trans(
    input logic [7:0] s_read,
    output logic burst, s_rw, //read high
    output logic [7:0] s_addr, s_write //if no addr sent, s_addr will be 8'hFF
  );
    /*
      - wait for transaction to start
      - if write, check if transaction is correct and report key values
      - also output these values for initial block control
      - if read, check if transaction is correct and drive hardcoded data
      - output relevant data
    */
    burst = 1'b1;
    s_rw = 1'b0;
    s_addr = 8'hDA;
    s_write = 8'hDA;

    do begin
      @(posedge clk);
      #1;
    end while (cs);

    if (!(wr && rd)) $display("ERROR on cs pull low cycle | FIRST: wr = %d | rd = %d", wr, rd);

    //extra logic if addr is being sent before the data
    if (rs) begin
      burst = 1'b0;
      @(posedge clk);
      #1;
      if (!rd || wr || !rs || cs) $display("ERROR on wr pull cycle | ADDR: cs = %d | wr = %d | rd = %d | rs = %d", cs, wr, rd, rs);
      
      @(posedge clk);
      #1;
      if (!rd || wr || !rs || cs) $display("ERROR on addr send cycle: cs = %d | wr = %d | rd = %d | rs = %d", cs, wr, rd, rs);
      s_addr = db;

      @(posedge clk);
      #1;
      if (!rd || !wr || !rs || cs) $display("ERROR in wr raise cycle | ADDR: cs = %d | wr = %d | rd = %d | rs = %d", cs, wr, rd, rs);
    
      @(posedge clk);
      #1;
      if (!rd || !wr || rs || !cs) $display("ERROR in rs pull/cs raise cycle | ADDR: cs = %d | wr = %d | rd = %d | rs = %d", cs, wr, rd, rs);

      @(posedge clk);
      #1;
      if (!rd || !wr || rs || cs) $display("ERROR in second cs pull cycle | DATA after ADDR: cs = %d | wr = %d | rd = %d | rs = %d", cs, wr, rd, rs);
    end 

    //data read/write logic

    @(posedge clk);
    #1;
    if (rs || cs) $display("ERROR in wr or rd pull cycle | DATA: rs = %d | cs = %d", rs, cs);
    if (!wr && rd) begin : write_data

      //1st data access cycle
      @(posedge clk);
      #1;
      s_write = db;
      if (!rd || wr || rs || cs) $display("ERROR in 1st write data access cycle: cs = %d | wr = %d | rd = %d | rs = %d", cs, wr, rd, rs);

      //2nd data access cycle
      @(posedge clk);
      #1;
      if (db != s_write || !rd || wr || rs || cs) $display("ERROR in 2nd write access cycle: cs = %d | wr = %d | rd = %d | rs = %d | second data = %08b", cs, wr, rd, rs, db);

    end else if (wr && !rd) begin : read_data
      s_rw = 1'b1;
      //1st access cycle
      @(posedge clk);
      db_drive_en = 1'b1;
      db_drive_val = s_read;
      #1;
      if (rd || !wr || rs || cs) $display("ERROR in 1st read data access cycle: cs = %d | wr = %d | rd = %d | rs = %d", cs, wr, rd, rs);

      //2nd access cycle
      @(posedge clk);
      #1;
      if (rd || !wr || rs || cs) $display("ERROR in 2nd read data access cycle: cs = %d | wr = %d | rd = %d | rs = %d", cs, wr, rd, rs);

    end else begin : error_case
      $display("ERROR in wr or rd pull cycle: wr = %d | rd = %d", wr, rd);
      @(posedge clk);
      #1;
      $display("ERROR followup: cs = %d | rs = %d | wr = %d | rd = %d | data = %08b", cs, rs, wr, rd, db);
      @(posedge clk);
      #1;
      $display("ERROR followup: cs = %d | rs = %d | wr = %d | rd = %d | data = %08b", cs, rs, wr, rd, db);
    end

    //wr or rd raise cycle
    @(posedge clk);
    db_drive_en = 1'b0;
    db_drive_val = 8'hDA;
    #1;
    if (!rd || !wr || rs || cs) $display("ERROR in wr/rd raise cycle | DATA: cs = %d | rs = %d | wr = %d | rd = %d", cs, rs, wr, rd);

    //cs and rs raise cycle
    @(posedge clk);
    #1;
    if (!rd || !wr || !rs || !cs) $display("ERROR in cs and rs raise cycle | DATA: cs = %d | rs = %d | wr = %d | rd = %d", cs, rs, wr, rd);

  endtask

  task detecth4 ();
    //detects on clock cycle it is called on
    //exits task on cycle after req cycle
    #1;
    while (!(dp_req && !dp_lw && dp_addr == 32'h4)) begin
      @(posedge clk);
      #1;
    end
    $display("CPU store to h4 (start/ack signal, no data stored)");
    @(posedge clk);
  endtask

  //LINES CHANGED FOR SIM: 813, 956, 897, 995, 1167
  //assume dpu only sends 8 30b bus instead of 480, need to change dpu.sv for this tb to be valid

  initial begin
    $dumpfile("sim/waves.vcd");
    $dumpvars(0, tb_integratedDPU);

    reset();
    set_pixels();
    set_coords();
    set_shape();

    //wait for CPU to write to h4, making dpu start initialization
    detecth4();
    $display("INIT START");

    //monitor initialization commands
    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h01 || s_write_data != 8'h01) $display("ERROR: read = %d | burst = %d | exp_addr = h01 | addr = %02h | exp_write = h01 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (!burst || s_rw || s_write_data != 8'h00) $display("ERROR: read = %d | burst = %d | exp_addr = h01 | addr = %02h | exp_write = h00 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h14 || s_write_data != 8'h63) $display("ERROR: read = %d | burst = %d | exp_addr = h14 | addr = %02h | exp_write = h63 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h16 || s_write_data != 8'h1F) $display("ERROR: read = %d | burst = %d | exp_addr = h16 | addr = %02h | exp_write = h1F | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h17 || s_write_data != 8'h04) $display("ERROR: read = %d | burst = %d | exp_addr = h17 | addr = %02h | exp_write = h04 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h18 || s_write_data != 8'h0F) $display("ERROR: read = %d | burst = %d | exp_addr = h18 | addr = %02h | exp_write = h0F | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h19 || s_write_data != 8'hDF) $display("ERROR: read = %d | burst = %d | exp_addr = h19 | addr = %02h | exp_write = hDF | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h1A || s_write_data != 8'h01) $display("ERROR: read = %d | burst = %d | exp_addr = h1A | addr = %02h | exp_write = h01 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h1B || s_write_data != 8'h2C) $display("ERROR: read = %d | burst = %d | exp_addr = h1B | addr = %02h | exp_write = h2C | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h1D || s_write_data != 8'h07) $display("ERROR: read = %d | burst = %d | exp_addr = h1D | addr = %02h | exp_write = h07 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h1F || s_write_data != 8'h01) $display("ERROR: read = %d | burst = %d | exp_addr = h1F | addr = %02h | exp_write = h01 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h01 || s_write_data != 8'h80) $display("ERROR: read = %d | burst = %d | exp_addr = h01 | addr = %02h | exp_write = h80 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h70 || s_write_data != 8'h80) $display("ERROR: read = %d | burst = %d | exp_addr = h70 | addr = %02h | exp_write = h80 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h71 || s_write_data != 8'h84) $display("ERROR: read = %d | burst = %d | exp_addr = h71 | addr = %02h | exp_write = h84 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'hF0 || s_write_data != 8'h04) $display("ERROR: read = %d | burst = %d | exp_addr = hF0 | addr = %02h | exp_write = h04 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h34 || s_write_data != 8'h20) $display("ERROR: read = %d | burst = %d | exp_addr = h34 | addr = %02h | exp_write = h20 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h35 || s_write_data != 8'h03) $display("ERROR: read = %d | burst = %d | exp_addr = h35 | addr = %02h | exp_write = h03 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h36 || s_write_data != 8'hE0) $display("ERROR: read = %d | burst = %d | exp_addr = h36 | addr = %02h | exp_write = hE0 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h37 || s_write_data != 8'h01) $display("ERROR: read = %d | burst = %d | exp_addr = h37 | addr = %02h | exp_write = h01 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    $display("INIT sequence done, transition to CLEAR");
    $display("CLEAR sequence only prints register set transaction, not correct burst writes as there are too many");

    //clear state sequence
    //for (int i = 0; i < 384000; i++) begin 
    for (int i = 0; i < 10; i++) begin //reduce cycles for simulation, also changed in dpu.sv
      trans(8'hDA, burst, s_rw, s_addr, s_write_data);
      $display("CLEAR pixel %d", i);
      if (i == 0) begin //reg needs to be specified to this won't be a burst write
        if (s_rw || burst || s_addr != 8'h02 || s_write_data != 8'hFF) $display("ERROR in CLEAR addr point write: burst = %d | read = %d | addr = %02h | data = %02h", burst, s_rw, s_addr, s_write_data); 
      end else begin
        if (s_write_data != 8'hFF || s_rw || !burst) $display("ERROR in CLEAR burst write: read = %d | burst = %d | write data = %08b", s_rw, burst, s_write_data);
      end
    end

    $display("CLEAR done, go to POLL_INT");
    @(posedge clk);
    
    //iterate through coord buses to simulate drawing to screen

    for (int i = 0; i < 25; i++) begin //send first 24 indices of coord bus (last index doesn't go to DRAW, which is assumed in this loop)
      @(posedge clk);
      #1;
      interrupt = 0;
      //now COORD state, send xcoord, ycoord data
      //dpu reads 8 high of x
      trans(xcoord[i][9:2], burst, s_rw, s_addr, s_write_data);
      if (burst || !s_rw || s_addr != 8'h72) $display("ERROR in coord read: burst = %d | read = %d | expected addr = h72 | addr = %02h", burst, s_rw, s_addr);

      //dpu reads 8 high of y
      trans(ycoord[i][9:2], burst, s_rw, s_addr, s_write_data);
      if (burst || !s_rw || s_addr != 8'h73) $display("ERROR in coord read: burst = %d | read = %d | expected addr = h73 | addr = %02h", burst, s_rw, s_addr);

      //dpu reads low bits of x, y
      trans({4'b0, xcoord[i][1:0], ycoord[i][1:0]}, burst, s_rw, s_addr, s_write_data);
      if (burst || !s_rw || s_addr != 8'h74) $display("ERROR in coord read: burst = %d | read = %d | expected addr = h74 | addr = %02h", burst, s_rw, s_addr);

      //dpu writes to clear interrupt
      trans(8'hDA, burst, s_rw, s_addr, s_write_data);
      if (burst || s_rw || s_addr != 8'hF1 || s_write_data != 8'b00000100) $display("ERROR in write interrupt clear: burst = %d | read = %d | expected addr = hF1 | addr = %02h | expected writedata = h04 | write = %02h", burst, s_rw, s_addr, s_write_data);

      @(posedge clk); //clear interrupt
      interrupt = 1'b1;

      //now in DRAW
      trans(8'hDA, burst, s_rw, s_addr, s_write_data);
      if (burst || s_rw || s_addr != 8'h46 || s_write_data != xcoord[i][7:0]) $display("ERROR in DRAW: burst = %d | read = %d | expected addr = h46 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, xcoord[i][7:0], s_write_data);

      trans(8'hDA, burst, s_rw, s_addr, s_write_data);
      if (burst || s_rw || s_addr != 8'h47 || s_write_data != {6'b0, xcoord[i][9:8]}) $display("ERROR in DRAW: burst = %d | read = %d | expected addr = h47 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, {6'b0, xcoord[i][9:8]}, s_write_data);

      trans(8'hDA, burst, s_rw, s_addr, s_write_data);
      if (burst || s_rw || s_addr != 8'h48 || s_write_data != ycoord[i][7:0]) $display("ERROR in DRAW: burst = %d | read = %d | expected addr = h48 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, ycoord[i][7:0], s_write_data);

      trans(8'hDA, burst, s_rw, s_addr, s_write_data);
      if (burst || s_rw || s_addr != 8'h49 || s_write_data != {6'b0, ycoord[i][9:8]}) $display("ERROR in DRAW: burst = %d | read = %d | expected addr = h49 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, {6'b0, ycoord[i][9:8]}, s_write_data);

      trans(8'hDA, burst, s_rw, s_addr, s_write_data);
      if (burst || s_rw || s_addr != 8'h02 || s_write_data != 8'b0) $display("ERROR in DRAW: burst = %d | read = %d | expected addr = h02 | addr = %02h | expected writedata = h00 | write = %02h", burst, s_rw, s_addr, s_write_data);
    end

    $display("drawing done, sending last interrupt/coord to transition to SEND");

    //send coord where x > 480 to transition to SEND
    @(posedge clk);
    #1;
    interrupt = 0;

    trans(xcoord[25][9:2], burst, s_rw, s_addr, s_write_data);
    if (burst || !s_rw || s_addr != 8'h72) $display("ERROR in coord read: burst = %d | read = %d | expected addr = h72 | addr = %02h", burst, s_rw, s_addr);

    //dpu reads 8 high of y
    trans(ycoord[25][9:2], burst, s_rw, s_addr, s_write_data);
    if (burst || !s_rw || s_addr != 8'h73) $display("ERROR in coord read: burst = %d | read = %d | expected addr = h73 | addr = %02h", burst, s_rw, s_addr);

    //dpu reads low bits of x, y
    trans({4'b0, xcoord[25][1:0], ycoord[25][1:0]}, burst, s_rw, s_addr, s_write_data);
    if (burst || !s_rw || s_addr != 8'h74) $display("ERROR in coord read: burst = %d | read = %d | expected addr = h74 | addr = %02h", burst, s_rw, s_addr);

    //dpu writes to clear interrupt
    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'hF1 || s_write_data != 8'b00000100) $display("ERROR in write interrupt clear: burst = %d | read = %d | expected addr = h74 | addr = %02h | expected writedata = h04 | write = %02h", burst, s_rw, s_addr, s_write_data);

    @(posedge clk); //clear interrupt
    interrupt = 1'b1;

    $display("now in SEND");
    //loop through every pixel read + send
    //for (int i = 1; i < 481; i++) begin
    for (int i = 1; i < 9; i++) begin //CHANGE FOR SIM
      for (int j = 0; j < 30; j++) begin
          
        //dpu writes to set top left active window
        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h30 || s_write_data != refx[coord_idx][7:0]) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h30 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, refx[coord_idx][7:0], s_write_data);
          
        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h31 || s_write_data != {6'b0, refx[coord_idx][9:8]}) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h31 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, {6'b0, refx[coord_idx][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h32 || s_write_data != refy[coord_idx][7:0]) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h32 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, refy[coord_idx][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h33 || s_write_data != {7'b0, refy[coord_idx][8]}) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h33 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, {7'b0, refy[coord_idx][8]}, s_write_data);

        coord_idx++;

        //set bottom right of active window
        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h34 || s_write_data != refx[coord_idx][7:0]) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h34 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, refx[coord_idx][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h35 || s_write_data != {6'b0, refx[coord_idx][9:8]}) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h35 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, {6'b0, refx[coord_idx][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h36 || s_write_data != refy[coord_idx][7:0]) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h36 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, refy[coord_idx][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h37 || s_write_data != {7'b0, refy[coord_idx][8]}) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h37 | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, {7'b0, refy[coord_idx][8]}, s_write_data);

        //set mem read cursor location to top left of active window
        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h4A || s_write_data != refx[coord_idx - 1][7:0]) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h4A | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, refx[coord_idx - 1][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h4B || s_write_data != {6'b0, refx[coord_idx - 1][9:8]}) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h4B | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, {6'b0, refx[coord_idx - 1][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h4C || s_write_data != refy[coord_idx - 1][7:0]) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h4C | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, refy[coord_idx - 1][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h4D || s_write_data != {7'b0, refy[coord_idx - 1][8]}) $display("ERROR in active window set: burst = %d | read = %d | expected addr = h4D | addr = %02h | expected writedata = %02h | write = %02h", burst, s_rw, s_addr, {7'b0, refy[coord_idx - 1][8]}, s_write_data);

        coord_idx++;

        //send pixel data
        trans(8'hEE, burst, s_rw, s_addr, s_write_data); //act as dummy read

        for (int k = 0; k < 16; k++) begin
          pix = pixels[i][j][k] ? 8'h0 : 8'hFF;
          trans(pix, burst, s_rw, s_addr, s_write_data);
          if (k != 0 && (!burst || !s_rw)) $display("ERROR in SEND pixel burst read: burst = %d | s_rw = %d", burst, s_rw);
          else if (k == 0 && (burst || !s_rw || s_addr != 8'h02)) $display("ERROR in SEND pixel read addr point: burst = %d | s_rw = %d | s_addr = %02h", burst, s_rw, s_addr);
        end
      end

      //goes to WAIT_RECIEVE, dpu waits for CPU store to h4
      detecth4();
      //if (i != 481) $display("WAIT_RECIEVE transition to SEND: bus = %d", i); CHANGE FOR SIM
      if (i < 9) $display("WAIT_RECIEVE transition to SEND: bus = %d", i);
      else $display("WAIT_RECIEVE transition to WAIT_INFERENCE");
      //if last iteration of "i" for loop then exit to WAIT_INFERENCE instead of back to SEND
    end

    //WAIT_INFERENCE: dpu recieves circle for q1, line for q2, square for q3, circle for q4 (set in code)
    //transitions to PREP_CLEAR
    $display("CPU sends: q1 = circle | q2 = line | q3 = square | q4 = circle");
    $display("WAIT_INFERENCE -> PREP_CLEAR");

    //monitor active window set
    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h30 || s_write_data != 8'h00) $display("ERROR: read = %d | burst = %d | exp_addr = h30 | addr = %02h | exp_write = h00 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h31 || s_write_data != 8'h00) $display("ERROR: read = %d | burst = %d | exp_addr = h31 | addr = %02h | exp_write = h00 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h32 || s_write_data != 8'h00) $display("ERROR: read = %d | burst = %d | exp_addr = h32 | addr = %02h | exp_write = h00 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h33 || s_write_data != 8'h00) $display("ERROR: read = %d | burst = %d | exp_addr = h33 | addr = %02h | exp_write = h00 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h34 || s_write_data != 8'h20) $display("ERROR: read = %d | burst = %d | exp_addr = h34 | addr = %02h | exp_write = h20 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h35 || s_write_data != 8'h03) $display("ERROR: read = %d | burst = %d | exp_addr = h35 | addr = %02h | exp_write = h03 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h36 || s_write_data != 8'h70) $display("ERROR: read = %d | burst = %d | exp_addr = h36 | addr = %02h | exp_write = h70 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h37 || s_write_data != 8'h01) $display("ERROR: read = %d | burst = %d | exp_addr = h37 | addr = %02h | exp_write = h01 | write data = %02h", s_rw, burst, s_addr, s_write_data);

    //transition to CLEAR (write 384000 white pixels)
    $display("PREP_CLEAR -> CLEAR");
    //for (int i = 0; i < 384000; i++) begin
    for (int i = 0; i < 10; i++) begin
      trans(8'hDA, burst, s_rw, s_addr, s_write_data);
      if (i == 0) begin //reg needs to be specified to this won't be a burst write
        if (s_rw || burst || s_addr != 8'h02 || s_write_data != 8'hFF) $display("ERROR in CLEAR addr point write: burst = %d | read = %d | addr = %02h | data = %02h", burst, s_rw, s_addr, s_write_data); 
      end else begin
        if (s_write_data != 8'hFF || s_rw || !burst) $display("ERROR in CLEAR burst write: read = %d | burst = %d | write data = %08b", s_rw, burst, s_write_data);
      end
    end

    $display("CLEAR -> FIX");

    //loop through 4 shapes begin drawn
    for (int i = 0; i < 4; i++) begin
      if (shape_id[i] == 3'b100) begin //circle
        $display("Drawing circle in quadrant %d", i + 1);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h99 || s_write_data != circle_centerx[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h99 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, circle_centerx[i][7:0], s_write_data);
      
        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h9A || s_write_data != {6'b0, circle_centerx[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h9A | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, circle_centerx[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h9B || s_write_data != circle_centery[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h9B | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, circle_centery[i][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h9C || s_write_data != {6'b0, circle_centery[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h9C | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, circle_centery[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h9D || s_write_data != circle_radius) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h9D | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, circle_radius, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h45 || s_write_data != 8'b0) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h45 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, 8'b0, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h45 || s_write_data != 8'b0) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h45 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, 8'b0, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h45 || s_write_data != 8'b0) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h45 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, 8'b0, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h90 || s_write_data != 8'h40) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h90 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, 8'h40, s_write_data);
      end else if (shape_id[i] == 3'b010) begin //square
        $display("Drawing square in quadrant %d", i + 1);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h91 || s_write_data != square_startx[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h91 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, square_startx[i][7:0], s_write_data);
      
        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h92 || s_write_data != {6'b0, square_startx[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h92 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, square_startx[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h93 || s_write_data != square_starty[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h93 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, square_starty[i][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h94 || s_write_data != {6'b0, square_starty[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h94 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, square_starty[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h95 || s_write_data != square_endx[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h95 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, square_endx[i][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h96 || s_write_data != {6'b0, square_endx[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h96 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, square_endx[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h97 || s_write_data != square_endy[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h97 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, square_endy[i][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h98 || s_write_data != {6'b0, square_endy[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h98 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, square_endy[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h90 || s_write_data != 8'h90) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h90 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, 8'h90, s_write_data);
      end else begin //line
        $display("Drawing line in quadrant %d", i + 1);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h91 || s_write_data != square_startx[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h91 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, square_startx[i][7:0], s_write_data);
      
        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h92 || s_write_data != {6'b0, square_startx[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h92 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, square_startx[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h93 || s_write_data != square_starty[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h93 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, square_starty[i][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h94 || s_write_data != {6'b0, square_starty[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h94 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, square_starty[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h95 || s_write_data != square_endx[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h95 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, square_endx[i][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h96 || s_write_data != {6'b0, square_endx[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h96 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, square_endx[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h97 || s_write_data != square_endy[i][7:0]) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h97 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, square_endy[i][7:0], s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h98 || s_write_data != {6'b0, square_endy[i][9:8]}) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h98 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, {6'b0, square_endy[i][9:8]}, s_write_data);

        trans(8'hDA, burst, s_rw, s_addr, s_write_data);
        if (burst || s_rw || s_addr != 8'h90 || s_write_data != 8'h80) $display("ERROR in FIX shape draw: read = %d | burst = %d | exp addr = h90 | addr = %02h | exp data = %02h | data = %02h", s_rw, burst, s_addr, 8'h80, s_write_data);
      end

      $display("Shape %d draw commands sent, now in DONE simulating shape drawing delay", i);

      for (int j = 0; j < 5; j++) begin //simulate waiting 5 transactions before shape is done
        trans(shape_id[i][2] ? 8'h40 : 8'h80, burst, s_rw, s_addr, s_write_data);
        if (burst || !s_rw || s_addr != 8'h90) $display("ERROR in DONE poll if shape done drawing: read = %d | burst = %d | exp addr = h90 | addr = %02h", s_rw, burst, s_addr);
      end

      //now send drawing done signal

      trans(8'b0, burst, s_rw, s_addr, s_write_data);
      if (burst || !s_rw || s_addr != 8'h90) $display("ERROR in DONE sent shape done signal: read = %d | burst = %d | exp addr = h90 | addr = %02h", s_rw, burst, s_addr);

      if (i == 4) $display("DONE -> FIX");
      else $display("DONE -> POLL_INT");
    end
    $display("sending a couple interrupt events with coords in the draw box, dpu should ignore");
    //simulate sending coords not in designated area since dpu is supposed to not do anything for that
    for (int i = 22; i < 26; i++) begin
      @(posedge clk);
      #1;
      interrupt = 0;

      trans(xcoord[i][9:2], burst, s_rw, s_addr, s_write_data);
      if (burst || !s_rw || s_addr != 8'h72) $display("ERROR in COORD read: burst = %d | read = %d | expected addr = h72 | addr = %02h", burst, s_rw, s_addr);

      //dpu reads 8 high of y
      trans(ycoord[i][9:2], burst, s_rw, s_addr, s_write_data);
      if (burst || !s_rw || s_addr != 8'h73) $display("ERROR in COORD read: burst = %d | read = %d | expected addr = h73 | addr = %02h", burst, s_rw, s_addr);

      //dpu reads low bits of x, y
      trans({4'b0, xcoord[i][1:0], ycoord[i][1:0]}, burst, s_rw, s_addr, s_write_data);
      if (burst || !s_rw || s_addr != 8'h74) $display("ERROR in COORD read: burst = %d | read = %d | expected addr = h74 | addr = %02h", burst, s_rw, s_addr);

      //dpu writes to clear interrupt
      trans(8'hDA, burst, s_rw, s_addr, s_write_data);
      if (burst || s_rw || s_addr != 8'hF1 || s_write_data != 8'b00000100) $display("ERROR in COORD write interrupt clear: burst = %d | read = %d | expected addr = hF1 | addr = %02h | expected writedata = h04 | write = %02h", burst, s_rw, s_addr, s_write_data);

      @(posedge clk); //clear interrupt
      interrupt = 1'b1;
    end

    $display("COORD -> CURSOR_RST");

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h46 || s_write_data != 8'b0) $display("ERROR in CURSOR_RST: burst = %d | read = %d | exp addr = h46 | addr = %02h | exp write = h00 | write = %02h", burst, s_rw, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h47 || s_write_data != 8'b0) $display("ERROR in CURSOR_RST: burst = %d | read = %d | exp addr = h47 | addr = %02h | exp write = h00 | write = %02h", burst, s_rw, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h48 || s_write_data != 8'b0) $display("ERROR in CURSOR_RST: burst = %d | read = %d | exp addr = h48 | addr = %02h | exp write = h00 | write = %02h", burst, s_rw, s_addr, s_write_data);

    trans(8'hDA, burst, s_rw, s_addr, s_write_data);
    if (burst || s_rw || s_addr != 8'h49 || s_write_data != 8'b0) $display("ERROR in CURSOR_RST: burst = %d | read = %d | exp addr = h49 | addr = %02h | exp write = h00 | write = %02h", burst, s_rw, s_addr, s_write_data);

    @(posedge clk);

    $display("CURSOR_RST -> FULL_DONE");
    $display("END OF TESTING FOR DPU, NOW POLL REGISTER FILE WRITES TO ENSURE DATA TRANSFER SUCCESS");

    //start sequence is a write to reg 31
    do begin
      @(posedge clk);
      @(negedge clk);
    end while (!(file_wen && file_regD == 5'd31));

    //now cpu writes the register data it read from DPU to register 30
    //the data should start at 32'd1 and go to 32'd480
    //cpu needs to get rid of valid bits before it sends back to match 
    //for (int i = 1; i < 481; i++) begin
    for (int i = 1; i < 9; i++) begin
      do begin
        @(posedge clk);
        @(negedge clk);
      end while (!(file_wen && file_regD == 5'd30));

      if (file_write_data == i) $display("PASS: data = %d", i);
      else $display("FAIL: expected = %d | actual = %d", i, file_write_data);
    end
    
    @(posedge clk);

    $finish;
  end
endmodule
