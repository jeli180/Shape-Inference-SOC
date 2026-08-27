module clock_divider (
  input  logic clk_25mhz,
  input  logic rst,
  output logic clk_12_5mhz
);

  always_ff @(posedge clk_25mhz or posedge rst) begin
    if (rst) begin
      clk_12_5mhz <= 1'b0;
    end else begin
      clk_12_5mhz <= ~clk_12_5mhz;
    end
  end

endmodule
