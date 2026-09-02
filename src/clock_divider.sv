module clock_divider (
  input  logic clk_25mhz,
  input  logic rst,
  output logic clk_12_5mhz,
  output logic clk_1_25mhz
);

  logic [3:0] divide_by_20_count;

  always_ff @(posedge clk_25mhz or posedge rst) begin
    if (rst) begin
      clk_12_5mhz <= 1'b0;
      clk_1_25mhz <= 1'b0;
      divide_by_20_count <= '0;
    end else begin
      clk_12_5mhz <= ~clk_12_5mhz;

      if (divide_by_20_count == 4'd9) begin
        divide_by_20_count <= '0;
        clk_1_25mhz <= ~clk_1_25mhz;
      end else begin
        divide_by_20_count <= divide_by_20_count + 4'd1;
      end
    end
  end

endmodule
