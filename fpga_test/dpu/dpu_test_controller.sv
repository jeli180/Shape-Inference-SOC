//acts as CPU
//and controlled by FPA buttons
//shows state/errors with leds

/* ======== DPU control flow

    1: DPU IDLE
    2: CPU initializes by writing anything to addr 4
    3: DPU sends startup sequence, allows drawing, once > 480 is touched
       drawing is done and starts sending pixel data
    4: *CPU should be polling 4 to see when read_data[30] is high* 
        - also WRITE TO 4 AFTER it gets read_data so DPU can continue
        - repeat for 480 presses until all data sent to CPU
    5. DPU waits for shape classifications from CPU
    6. CPU writes fake shape classification data to addr 8
    7. DPU clears screen, draws shapes
    8. DPU waits for user to touch > 480, then resets and sets full_done (for CPU to read from 8)
    9. *CPU should be polling 8 for full_done*
    10. Once CPU reads full_done high, writes to addr 4 to acknowledge and start next round
    11. User can draw new shapes

    leds use:
    led[0] used for unexpected acks from DPU (either misc or missing)
    led[1] for unexpected pixel_data[31] 
    led[2:5] to track DPU state (driven by top currently unconnected)
    led[6] unused
    led[7] wired to ~rst in top level
    
    button use:
    btn[0] reserved for rst
    btn[1] for initialization (flow 2)
    btn[2] for continuation (flow 10)
    btn[3:4] for different fake shape classes
        - 3: q4 square | q3 circle | q2 line | q1 square
        - 4: q4 line | q3 square | q2 square | q1 circle

    other buttons unused 

    wiring
    rd: 27
    wr: 26
    cs: 25
    rs: 24
    int: 23
    reset: 22

    db[0:7]: 14-21

========== */

module dpu_test_controller (
    input logic clk, rst,

    //fpga interface
    input logic [6:0] btn_edge,
    output logic [6:0] led,
    
    //dpu interface
    input logic ack,
    input logic [31:0] read_data,

    output logic req, load,
    output logic [31:0] addr, write_data
);

    localparam logic [2:0] square = 3'b010;
    localparam logic [2:0] circle = 3'b100;
    localparam logic [2:0] line = 3'b001;

    logic [6:0] next_led;
    logic [8:0] pixel_num, next_pixel_num; 

    typedef enum { 
        IDLE,
        INIT,
        INIT_ACK,
        POLL_PIXEL,
        READ_PIXEL,
        ACK_PIXEL,
        ACK_PIXEL_LAST,
        ACK_PIXEL_ACK,
        ACK_PIXEL_LAST_ACK,
        SEND_CLASS,
        SEND_CLASS_ACK,
        POLL_FULL,
        READ_FULL,
        ACK_FULL,
        ACK_FULL_ACK
    } state_t;

    state_t state, next_state;

    always_comb begin
        req = 0;
        load = 0;
        addr = '0;
        write_data = '0;
        next_led = led;
        next_state = state;
        next_pixel_num = pixel_num;

        case (state) 
            IDLE: begin
                if (btn_edge[1]) next_state = INIT;
                if (ack) next_led[0] = 1'b1;
            end
            INIT: begin
                req = 1'b1;
                addr = 32'h4;
                next_state = INIT_ACK;

                if (ack) next_led[0] = 1'b1;
            end
            INIT_ACK: begin
                if (!ack) next_led[0] = 1'b1;
                next_state = POLL_PIXEL;
            end
            POLL_PIXEL: begin
                req = 1'b1;
                load = 1'b1;
                addr = 32'h4;
                next_state = READ_PIXEL;

                if (ack) next_led[0] = 1'b1;
            end
            READ_PIXEL: begin
                if (read_data[30]) begin
                    if (read_data[31]) begin //last pixel case
                        if (pixel_num < 479) next_led[1] = 1'b1;
                        else begin //pixel_num == 479 
                            next_pixel_num = '0;
                            next_state = ACK_PIXEL_LAST;
                        end
                    end else if (pixel_num == 479) next_led[1] = 1'b1;
                    else begin //intermediary pixel
                        next_pixel_num = pixel_num + 1;
                        next_state = ACK_PIXEL;
                    end
                end else next_state = POLL_PIXEL; //poll unsuccessful

                if (!ack) next_led[0] = 1'b1;
            end
            ACK_PIXEL: begin
                req = 1'b1;
                addr = 32'h4;
                next_state = ACK_PIXEL_ACK;

                if (ack) next_led[0] = 1'b1;
            end
            ACK_PIXEL_LAST: begin
                req = 1'b1;
                addr = 32'h4;
                next_state = ACK_PIXEL_LAST_ACK;

                if (ack) next_led[0] = 1'b1;
            end
            ACK_PIXEL_ACK: begin
                if (!ack) next_led[0] = 1'b1;
                next_state = POLL_PIXEL;
            end
            ACK_PIXEL_LAST_ACK: begin
                if (!ack) next_led[0] = 1'b1;
                next_state = SEND_CLASS;
            end
            SEND_CLASS: begin
                if (btn_edge[3]) begin //q4-1 sq ci li sq
                    req = 1'b1;
                    addr = 32'h8;
                    write_data = {16'b0, 4'b1111, square, circle, line, square};
                    next_state = SEND_CLASS_ACK;
                end else if (btn_edge[4]) begin //q4-1 li sq sq ci
                    req = 1'b1;
                    addr = 32'h8;
                    write_data = {16'b0, 4'b1111, line, square, square, circle};
                    next_state = SEND_CLASS_ACK;
                end

                if (ack) next_led[0] = 1'b1;
            end
            SEND_CLASS_ACK: begin
                if (!ack) next_led[0] = 1'b1;
                next_state = POLL_FULL;
            end
            POLL_FULL: begin
                req = 1'b1;
                addr = 32'h8;
                load = 1'b1;
                next_state = READ_FULL;

                if (ack) next_led[0] = 1'b1;
            end
            READ_FULL: begin
                if (read_data == 32'd1) next_state = ACK_FULL;
                else next_state = POLL_FULL;

                if (!ack) next_led[0] = 1'b1;
            end
            ACK_FULL: begin //through button 2 press
                if (btn_edge[2]) begin
                    req = 1'b1;
                    addr = 32'h4;
                    next_state = ACK_FULL_ACK;
                end

                if (ack) next_led[0] = 1'b1;
            end
            ACK_FULL_ACK: begin
                if (!ack) next_led[0] = 1'b1;
                next_state = POLL_PIXEL;
            end
            default:;
        endcase
    end

    always_ff @(posedge clk, posedge rst) begin //state led, pixel_num
        if (rst) begin
            state <= IDLE;
            led <= '0;
            pixel_num <= '0;
        end else begin
            state <= next_state;
            led <= next_led;
            pixel_num <= next_pixel_num;
        end
    end

endmodule

