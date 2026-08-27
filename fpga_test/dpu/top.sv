module top (
  input  logic        clk_25mhz,

  input  logic [6:0]  btn,
  input  logic [3:0]  sw,
  output logic [7:0]  led,

  inout  wire  [27:0] gp,
  inout  wire  [27:0] gn
);

  logic rst;

  logic [27:0] gp_in;
  logic [27:0] gn_in;
  logic [27:0] gp_out;
  logic [27:0] gn_out;
  logic [27:0] gp_oe;
  logic [27:0] gn_oe;

  assign rst = ~btn[0];

  assign gp_in = gp;
  assign gn_in = gn;

  genvar gpio_i;
  generate
    for (gpio_i = 0; gpio_i < 28; gpio_i++) begin : gpio_tristate
      assign gp[gpio_i] = gp_oe[gpio_i] ? gp_out[gpio_i] : 1'bz;
      assign gn[gpio_i] = gn_oe[gpio_i] ? gn_out[gpio_i] : 1'bz;
    end
  endgenerate

  //clk div to 12.5 mhz
  logic clk_12_5mhz;

  clock_divider clk_div (
    .clk_25mhz(clk_25mhz),
    .rst(rst),
    .clk_12_5mhz(clk_12_5mhz)
  );

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

  //dpu logic

  logic ack, req, load, cs, rs, rd, wr;
  logic [31:0] read_data, addr, write_data;
  logic [7:0] db_out;
  logic db_oe;
  logic [6:0] led_ctrl;
  logic [3:0] dpu_state;

  //========= io config
  always_comb begin
    gp_oe = '0;
    gn_oe = '0;
    gp_out = {rd, wr, cs, rs, 1'b0, ~rst, 22'b0};
    gn_out = '0;

    led = '0;

    gp_oe[22] = 1'b1;
    gp_oe[27:24] = 4'b1111;
    gp_oe[21:14] = {8{db_oe}};
    gp_out[21:14] = db_out;

    led[7] = btn[0];
    led[1:0] = led_ctrl[1:0];
    led[5:2] = dpu_state;
  end

  //========= instantiations

  dpu_test_controller test_con (
    .clk(clk_12_5mhz),
    .rst(rst),
    .btn_edge(btn_edge),
    .led(led_ctrl),
    .ack(ack),
    .read_data(read_data),
    .req(req),
    .load(load),
    .addr(addr),
    .write_data(write_data)
  );

  dpu dpu0 (
    .clk(clk_12_5mhz),
    .rst(rst),
    .req(req),
    .load(load),
    .addr(addr),
    .write_data(write_data),
    .ack(ack),
    .read_data(read_data),

    //to screen
    .rd(rd),
    .wr(wr),
    .rs(rs),
    .cs(cs),

    //from screen
    .interrupt(gp_in[23]),
    .db_in(gp_in[21:14]),
    .db_out(db_out),
    .db_oe(db_oe),

    .state_debug(dpu_state)
  );

endmodule
