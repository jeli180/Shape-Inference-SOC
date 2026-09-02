// computer and fpga communicate over built in uart

// tx/rx from fpga perspective

// uart_tower: 
//     contains ingress fifo 
//     grants credits, init signals, and shape classes through tx

//     acts as peripheral to MMIO

// computer:
//     send pixel data according to credit scheme
//     wait for shape classes, then process when it recieves
//     should have a button to replace tapping screen > 480

// packet scheme
//  tx types: 
//     - start signal (CPU writes to addr4)
//         - can just be 1 (software will also track states)
//         - msb 00
//     - credits (can just be the num of credits to grant in lower)
//         - msb 01
//     - shape classification header (msb 10)
//     - shape classification (CPU writes to addr 8)
//         - msb bits can be bottom right quadrant
//         - 01 line, 10 square, 11 circle

//  rx types:
//     - pixel data, need 4 uart frames, first frame is lsb of 32 bit word 
//     - full_done just 1 fram of h1 should be fine
//tower interfaces with ingress buffer (31 entries of 8 bits) and tx module
/*
credit scheme: 
    initially grant 31 cred
    only grant another cred when pop the fifo
    credits will naturally lag behind what is actually free in fifo
*/

module uart_tower #(
    parameter int IB_DEPTH = 31 //only value supported for now
) (
    input logic clk, rst,

    //mmio
    input logic req, read,
    input logic [31:0] addr, write_data,

    output logic ack, //next cycle ack always
    output logic [31:0] read_data, //fake data when fifo empty

    input logic uart_rx,
    output logic uart_tx
);

    function automatic logic [7:0] dec_shapes (
        input logic [11:0] val
    );
        logic [7:0] dec;
        begin
            dec = '0;
            for (int i = 0; i < 4; i++) begin
                case (val[i * 3 +: 3])
                    3'b001: dec[i * 2 +: 2] = 2'b01;
                    3'b010: dec[i * 2 +: 2] = 2'b10;
                    3'b100: dec[i * 2 +: 2] = 2'b11;
                    default: dec[i * 2 +: 2] = 2'b0;
                endcase
            end
            dec_shapes = dec;
        end
    endfunction

    logic [31:0] next_read_data;
    logic next_ack;

    //ingress_buffer interface
    //inputs 
    logic [7:0] rx_data; //wired to next entry
    logic [31:0] rx4_data;
    logic [2:0] rx4_valid; //coupled with rx_data, tracks next 4 entries (0-4)
    //outputs
    logic pop, pop4; //pulse

    //uart_tx_controller interface
    //outputs
    logic [7:0] tx_data, tx_data2;//this and valid pulse only when ready high

    logic tx_valid, tx_valid2;

    logic [$clog2(IB_DEPTH + 1) - 1 : 0] free_cred, next_free_cred;

    ingress_buffer #(IB_DEPTH) ib0 (
        .clk(clk),
        .rst(rst),
        .rx_data(rx_data),
        .rx4_data(rx4_data),
        .rx4_valid(rx4_valid),
        .pop(pop),
        .pop4(pop4),
        .uart_rx(uart_rx)
    );

    egress_buffer tx0(
        .clk(clk),
        .rst(rst),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_data2(tx_data2),
        .tx_valid2(tx_valid2),
        .uart_tx(uart_tx)
    );

    always_comb begin

        next_read_data = '0;
        pop4 = 0;
        pop = 0;
        tx_data = '0;
        tx_valid = 0;
        next_ack = 0;
        tx_data2 = '0;
        tx_valid2 = 0;

        next_free_cred = free_cred;
        
        if (req) begin
            if (read) begin
                if (addr == 32'h4) begin //send pixel data if avail
                    if (rx4_valid[2]) begin
                        next_read_data = rx4_data;
                        next_ack = 1'b1;
                        pop4 = 1'b1;
                    end else begin
                        next_ack = 1'b1;
                    end
                end else if (addr == 32'h8) begin
                    if (|rx4_valid) begin
                        next_read_data = {24'b0, rx_data};
                        next_ack = 1'b1;
                        pop = 1'b1;
                    end else begin
                        next_ack = 1'b1;
                    end
                end
            end else begin
                if (addr == 32'h4) begin
                    tx_valid = 1'b1;
                end else if (addr == 32'h8) begin //ADD shape header packet
                    tx_valid2 = 1'b1;
                    tx_data = 8'h80;
                    tx_data2 = dec_shapes(write_data[11:0]);
                end
            end
        end

        //==== credit mechanism
        //min cred to send is 8 
        //8 chosen because cpu drains 8 slower than uart sends the cred frame
        //uart_tx_controller will have depth 4 queue to prevent overflow
        //from credit messages and other messages needing to be sent
        if ((!req || req && read) && free_cred >= 8) begin
            tx_valid = 1'b1;
            tx_data = {2'b01, 1'b0, free_cred[4:0]};

            if (!pop && !pop4) next_free_cred = '0;
            else if (pop) next_free_cred = 1;
            else if (pop4) next_free_cred = 4;

        end else if (pop) next_free_cred = free_cred + 1;
        else if (pop4) next_free_cred = free_cred + 4;

    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            ack <= 0;
            read_data <= '0;
            free_cred <= 31;
        end else begin
            ack <= next_ack;
            read_data <= next_read_data;
            free_cred <= next_free_cred;
        end
    end

endmodule
