module edge_detector (
    input logic clk, rst,
    input logic sig_in,
    output logic edge_out
);
    logic s1_reg, s2_reg, s3_reg;

    assign edge_out = s2_reg && !s3_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            s1_reg <= 0;
            s2_reg <= 0;
            s3_reg <= 0;
        end else begin
            s1_reg <= sig_in;
            s2_reg <= s1_reg;
            s3_reg <= s2_reg;
        end
    end

endmodule