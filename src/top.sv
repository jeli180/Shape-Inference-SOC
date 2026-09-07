module top (
  input  logic        clk_25mhz,

  input  logic [6:0]  btn,
  input  logic [3:0]  sw,
  output logic [7:0]  led,

  inout  wire  [27:0] gp,
  inout  wire  [27:0] gn,

  input logic ftdi_txd,
  output logic ftdi_rxd
);

  logic rst;

  logic [1:0] led_ctrl;

  assign rst = ~btn[0];

  // No physical display is attached to this UART-only wrapper.
  assign gp = 28'bz;
  assign gn = 28'bz;

  // Divide the board clock for the SoC and button edge detection.
  logic clk_12_5mhz;
  logic soc_clk;

  clock_divider clk_div (
    .clk_25mhz(clk_25mhz),
    .rst(rst),
    .clk_12_5mhz(clk_12_5mhz),
    .clk_1_25mhz()
  );

  // The cache datapath closes timing below 25 MHz. Keep the complete SoC and
  // UART in this single 12.5 MHz domain.
  assign soc_clk = clk_12_5mhz;

  //button edges
  logic [6:0] btn_edge;
  genvar i;
  generate
    for (i = 0; i < 7; i++) begin : btn_edge_det
      edge_detector i0 (
        .clk(clk_12_5mhz),
        .rst(rst),
        .sig_in(btn[i]),
        .edge_out(btn_edge[i])
      );
    end
  endgenerate

  //========= io config
  always_comb begin
    led = '0;
    led[7] = btn[0];
    led[1:0] = led_ctrl[1:0];
  end

  //========= instantiations

  // CPU <-> MMIO
  logic cpu_req, cpu_lw;
  logic [31:0] cpu_addr, cpu_write_data, cpu_read_data;
  logic [4:0] cpu_regD_in, cpu_regD_done;
  logic cpu_hit, cpu_miss, cpu_load_done_stall, cpu_passive_stall;

  // MMIO <-> data cache
  logic ca_req, ca_lw, ca_hit, ca_miss;
  logic ca_load_done_stall, ca_passive_stall;
  logic [31:0] ca_addr, ca_write_data, ca_read_data;
  logic [4:0] ca_regD_in, ca_regD_out;

  // Data cache <-> MSHR
  logic load_valid, evict_valid, load_way_in, load_way_out;
  logic mshr_done_pulse, mshr_full;
  logic [4:0] mshr_regD_in, mshr_regD_out;
  logic [31:0] evict_addr, load_addr, evict_data;
  logic [31:0] mshr_addr_out, mshr_data_out;
  logic [31:0] mshr_addr1, mshr_addr2, mshr_addr3, mshr_addr4;

  // MMIO <-> drawing peripheral
  logic dp_req, dp_lw, dp_ack;
  logic [31:0] dp_addr, dp_write_data, dp_read_data;

  assign led_ctrl = {dp_ack, dp_req};

  // MMIO <-> tensor controller <-> systolic array
  logic tc_req, tc_lw, tc_ack, array_clear, array_en;
  logic [31:0] tc_addr, tc_write_data, tc_read_data;
  logic signed [7:0] row0_in, row1_in, row2_in, row3_in;
  logic signed [7:0] col0_in, col1_in, col2_in, col3_in;
  logic signed [31:0] mac00, mac01, mac02, mac03;
  logic signed [31:0] mac10, mac11, mac12, mac13;
  logic signed [31:0] mac20, mac21, mac22, mac23;
  logic signed [31:0] mac30, mac31, mac32, mac33;

  cpu cpu0 (
    .clk(soc_clk),
    .rst(rst),
    .req(cpu_req),
    .lw(cpu_lw),
    .addr(cpu_addr),
    .data_write(cpu_write_data),
    .regD_out(cpu_regD_in),
    .hit_ack(cpu_hit),
    .miss_store(cpu_miss),
    .load_done_stall(cpu_load_done_stall),
    .passive_stall(cpu_passive_stall),
    .regD_done(cpu_regD_done),
    .data_read(cpu_read_data)
  );

  mmio mmio0 (
    .req(cpu_req),
    .lw(cpu_lw),
    .addr(cpu_addr),
    .data_write(cpu_write_data),
    .regD_in(cpu_regD_in),
    .hit_ack(cpu_hit),
    .miss_store(cpu_miss),
    .load_done_stall(cpu_load_done_stall),
    .passive_stall(cpu_passive_stall),
    .regD_done(cpu_regD_done),
    .data_read(cpu_read_data),
    .ca_regD_in(ca_regD_in),
    .ca_addr_in(ca_addr),
    .ca_write_data(ca_write_data),
    .ca_req(ca_req),
    .ca_lw(ca_lw),
    .ca_hit(ca_hit),
    .ca_miss_send(ca_miss),
    .ca_load_done_stall(ca_load_done_stall),
    .ca_passive_stall(ca_passive_stall),
    .ca_regD_out(ca_regD_out),
    .ca_read_data(ca_read_data),
    .dp_req(dp_req),
    .dp_lw(dp_lw),
    .dp_addr(dp_addr),
    .dp_write_data(dp_write_data),
    .dp_ack(dp_ack),
    .dp_read_data(dp_read_data),
    .tc_req(tc_req),
    .tc_lw(tc_lw),
    .tc_addr(tc_addr),
    .tc_data_write(tc_write_data),
    .tc_ack(tc_ack),
    .tc_read_data(tc_read_data)
  );

  dcache dcache0 (
    .clk(soc_clk),
    .rst(rst),
    .regD_in(ca_regD_in),
    .addr_in(ca_addr),
    .store_data(ca_write_data),
    .send_pulse(ca_req),
    .lw(ca_lw),
    .hit_ack(ca_hit),
    .miss_send(ca_miss),
    .regD_out(ca_regD_out),
    .load_data(ca_read_data),
    .load_done_stall(ca_load_done_stall),
    .passive_stall(ca_passive_stall),
    .addr1(mshr_addr1),
    .addr2(mshr_addr2),
    .addr3(mshr_addr3),
    .addr4(mshr_addr4),
    .mshr_regD_out(mshr_regD_out),
    .mshr_addr_out(mshr_addr_out),
    .mshr_data_out(mshr_data_out),
    .mshr_done_pulse(mshr_done_pulse),
    .load_way_out(load_way_out),
    .addr_evict(evict_addr),
    .addr_load(load_addr),
    .evict_data(evict_data),
    .mshr_regD_in(mshr_regD_in),
    .load_valid(load_valid),
    .evict_valid(evict_valid),
    .load_way_in(load_way_in),
    .mshr_full(mshr_full)
  );

  mshr mshr0 (
    .clk(soc_clk),
    .rst(rst),
    .addr_evict(evict_addr),
    .addr_load(load_addr),
    .evict_data(evict_data),
    .regD_in(mshr_regD_in),
    .load_valid(load_valid),
    .evict_valid(evict_valid),
    .load_way_in(load_way_in),
    .addr1(mshr_addr1),
    .addr2(mshr_addr2),
    .addr3(mshr_addr3),
    .addr4(mshr_addr4),
    .addr_out(mshr_addr_out),
    .data_out(mshr_data_out),
    .regD_out(mshr_regD_out),
    .load_way_out(load_way_out),
    .done_pulse(mshr_done_pulse),
    .full(mshr_full)
  );

  // The tower owns ingress_buffer -> uart_reciever and
  // egress_buffer -> uart_transmitter. Do not duplicate those instances here.
  uart_tower #(
    .CLK_HZ(12_500_000)
  ) uart0 (
    .clk(soc_clk),
    .rst(rst),
    .req(dp_req),
    .read(dp_lw),
    .addr(dp_addr),
    .write_data(dp_write_data),
    .ack(dp_ack),
    .read_data(dp_read_data),
    .uart_rx(ftdi_txd),
    .uart_tx(ftdi_rxd)
  );

  tensor_controller tensor0 (
    .clk(soc_clk),
    .rst(rst),
    .mmio_req(tc_req),
    .mmio_lw(tc_lw),
    .mmio_addr(tc_addr),
    .mmio_data_write(tc_write_data),
    .mmio_ack(tc_ack),
    .mmio_data_read(tc_read_data),
    .clear(array_clear),
    .en(array_en),
    .row0_in(row0_in),
    .row1_in(row1_in),
    .row2_in(row2_in),
    .row3_in(row3_in),
    .col0_in(col0_in),
    .col1_in(col1_in),
    .col2_in(col2_in),
    .col3_in(col3_in),
    .mac00(mac00), .mac01(mac01), .mac02(mac02), .mac03(mac03),
    .mac10(mac10), .mac11(mac11), .mac12(mac12), .mac13(mac13),
    .mac20(mac20), .mac21(mac21), .mac22(mac22), .mac23(mac23),
    .mac30(mac30), .mac31(mac31), .mac32(mac32), .mac33(mac33)
  );

  systolic_array array0 (
    .clk(soc_clk),
    .rst(rst),
    .en(array_en),
    .clear(array_clear),
    .row0_in(row0_in),
    .row1_in(row1_in),
    .row2_in(row2_in),
    .row3_in(row3_in),
    .col0_in(col0_in),
    .col1_in(col1_in),
    .col2_in(col2_in),
    .col3_in(col3_in),
    .mac00(mac00), .mac01(mac01), .mac02(mac02), .mac03(mac03),
    .mac10(mac10), .mac11(mac11), .mac12(mac12), .mac13(mac13),
    .mac20(mac20), .mac21(mac21), .mac22(mac22), .mac23(mac23),
    .mac30(mac30), .mac31(mac31), .mac32(mac32), .mac33(mac33)
  );

endmodule
