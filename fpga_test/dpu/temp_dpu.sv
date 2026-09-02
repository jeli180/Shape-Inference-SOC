module temp_dpu (
  input logic clk, rst,

  // from mmio
  input logic req, load,
  input logic [31:0] addr, write_data,

  // to mmio
  output logic ack,
  output logic [31:0] read_data,

  // to screen
  output logic rd, wr, rs, cs,

  // from screen
  input logic interrupt,

  input  logic [7:0] db_in,
  output logic [7:0] db_out,
  output logic db_oe,

  output logic [3:0] state_debug
);

  typedef enum logic [3:0] {
    IDLE_C        = 4'h0,
    INIT          = 4'h1,
    VERIFY        = 4'h2,
    WRITE_PATTERN = 4'h3,
    DONE          = 4'h4,
    VERIFY_MEMORY = 4'h5,
    WRITE_PIXELS  = 4'h6,
    CLEAR_BACKGROUND = 4'h7,
    WAIT_BACKGROUND  = 4'h8,
    VERIFY_WINDOW = 4'h9,
    VERIFY_BACKGROUND = 4'hA,
    ERROR_BACKGROUND = 4'hB,
    ERROR_MCLR    = 4'hC,
    ERROR_CURSOR  = 4'hD,
    ERROR_REG     = 4'hE,
    ERROR_MEMORY  = 4'hF
  } state_control;

  typedef enum logic [3:0] {
    IDLE_I,
    PREP_REG,
    PREP_REG2,
    INIT_REG,
    SEND_REG,
    END_REG,
    FINISH_REG,
    PREP_DATA,
    INIT_DATA,
    DATA,
    LAG_DATA,
    END_DATA,
    FINISH_DATA
  } state_interface;

  state_control stateC, next_stateC;
  state_interface stateI, next_stateI;

  logic [19:0] ct, next_ct;
  logic [16:0] delay_ct, next_delay_ct;
  logic if_busy, next_if_busy;
  logic [7:0] screen_reg, next_screen_reg;
  logic [7:0] screen_data, next_screen_data;
  logic screen_r, next_screen_r;
  logic verify_passed, next_verify_passed;
  logic [7:0] mem_read_first, next_mem_read_first;
  logic [7:0] mem_read_second, next_mem_read_second;
  logic [1:0] test_mode, next_test_mode;
  logic [24:0] debug_counter;

  localparam logic [16:0] DELAY_1_MS = 17'd12500;
  localparam logic [16:0] DELAY_10_MS = 17'd125000;
  localparam logic [19:0] VERIFY_STEPS = 20'd66;

  function automatic logic [7:0] scanout_reg(input logic [5:0] index);
    case (index)
      6'd0:  scanout_reg = 8'h88; // PLLC1
      6'd1:  scanout_reg = 8'h89; // PLLC2
      6'd2:  scanout_reg = 8'h10; // SYSR
      6'd3:  scanout_reg = 8'h04; // PCSR
      6'd4:  scanout_reg = 8'h14; // HDWR
      6'd5:  scanout_reg = 8'h15; // HNDFTR
      6'd6:  scanout_reg = 8'h16; // HNDR
      6'd7:  scanout_reg = 8'h17; // HSTR
      6'd8:  scanout_reg = 8'h18; // HPWR
      6'd9:  scanout_reg = 8'h19; // VDHR0
      6'd10: scanout_reg = 8'h1A; // VDHR1
      6'd11: scanout_reg = 8'h1B; // VNDR0
      6'd12: scanout_reg = 8'h1C; // VNDR1
      6'd13: scanout_reg = 8'h1D; // VSTR0
      6'd14: scanout_reg = 8'h1E; // VSTR1
      6'd15: scanout_reg = 8'h1F; // VPWR
      6'd16: scanout_reg = 8'h20; // DPCR
      6'd17: scanout_reg = 8'h24; // HOFS0
      6'd18: scanout_reg = 8'h25; // HOFS1
      6'd19: scanout_reg = 8'h26; // VOFS0
      6'd20: scanout_reg = 8'h27; // VOFS1
      6'd21: scanout_reg = 8'h30; // HSAW0
      6'd22: scanout_reg = 8'h31; // HSAW1
      6'd23: scanout_reg = 8'h32; // VSAW0
      6'd24: scanout_reg = 8'h33; // VSAW1
      6'd25: scanout_reg = 8'h34; // HEAW0
      6'd26: scanout_reg = 8'h35; // HEAW1
      6'd27: scanout_reg = 8'h36; // VEAW0
      6'd28: scanout_reg = 8'h37; // VEAW1
      6'd29: scanout_reg = 8'h40; // MWCR0
      6'd30: scanout_reg = 8'h41; // MWCR1
      6'd31: scanout_reg = 8'h52; // LTPR0
      6'd32: scanout_reg = 8'h01; // PWRR
      default: scanout_reg = 8'h00;
    endcase
  endfunction

  function automatic logic [7:0] scanout_expected(
    input logic [5:0] index,
    input logic [1:0] mode
  );
    case (index)
      6'd0:  scanout_expected = mode == 2'd0 ? 8'h07 :
                                       mode == 2'd1 ? 8'h0A : 8'h0B;
      6'd1:  scanout_expected = mode == 2'd0 ? 8'h03 : 8'h02;
      6'd2:  scanout_expected = 8'h0C;
      6'd3:  scanout_expected = mode == 2'd0 ? 8'h01 : 8'h81;
      6'd4:  scanout_expected = 8'h63;
      6'd5:  scanout_expected = mode == 2'd2 ? 8'h80 : 8'h00;
      6'd6:  scanout_expected = 8'h03;
      6'd7:  scanout_expected = 8'h03;
      6'd8:  scanout_expected = mode == 2'd3 ? 8'h8B : 8'h0B;
      6'd9:  scanout_expected = 8'hDF;
      6'd10: scanout_expected = 8'h01;
      6'd11: scanout_expected = mode == 2'd0 ? 8'h1F : 8'h20;
      6'd12: scanout_expected = 8'h00;
      6'd13: scanout_expected = 8'h16;
      6'd14: scanout_expected = 8'h00;
      6'd15: scanout_expected = mode == 2'd3 ? 8'h81 : 8'h01;
      6'd16: scanout_expected = 8'h00;
      6'd17: scanout_expected = 8'h00;
      6'd18: scanout_expected = 8'h00;
      6'd19: scanout_expected = 8'h00;
      6'd20: scanout_expected = 8'h00;
      6'd21: scanout_expected = 8'h00;
      6'd22: scanout_expected = 8'h00;
      6'd23: scanout_expected = 8'h00;
      6'd24: scanout_expected = 8'h00;
      6'd25: scanout_expected = 8'h1F;
      6'd26: scanout_expected = 8'h03;
      6'd27: scanout_expected = 8'hDF;
      6'd28: scanout_expected = 8'h01;
      6'd29: scanout_expected = 8'h00;
      6'd30: scanout_expected = 8'h00;
      6'd31: scanout_expected = 8'h00;
      6'd32: scanout_expected = 8'h80;
      default: scanout_expected = 8'h00;
    endcase
  endfunction

  function automatic logic [7:0] scanout_mask(input logic [5:0] index);
    // PWRR bit 0 is write-only; only display-enable and sleep are meaningful.
    scanout_mask = index == 6'd32 ? 8'h82 : 8'hFF;
  endfunction

  logic [7:0] db_w, next_db_w;
  logic drive, next_drive;
  logic next_rd, next_wr, next_rs, next_cs;
  logic next_ack;
  logic [31:0] next_read_data;

  assign db_out = db_w;
  assign db_oe = drive;
  // On a readback mismatch, cycle the diagnostic bytes one nibble at a time.
  always_comb begin
    state_debug = stateC;
    if (stateC == ERROR_MEMORY || stateC == ERROR_REG) begin
      case (debug_counter[24:23])
        2'b00: state_debug = mem_read_first[3:0];
        2'b01: state_debug = mem_read_first[7:4];
        2'b10: state_debug = mem_read_second[3:0];
        2'b11: state_debug = mem_read_second[7:4];
      endcase
    end
  end

  always_comb begin
    next_ack = 1'b0;
    next_read_data = read_data;

    if (req) begin
      next_ack = 1'b1;
      if (load && addr == 32'd8) begin
        next_read_data = {
          16'b0,
          screen_data,
          stateC,
          stateC == ERROR_MEMORY || stateC == ERROR_REG ? debug_counter[24] : 1'b0,
          stateC == ERROR_MEMORY || stateC == ERROR_REG ? debug_counter[23] : verify_passed,
          stateC == ERROR_BACKGROUND || stateC == ERROR_MCLR ||
            stateC == ERROR_CURSOR ||
            stateC == ERROR_REG || stateC == ERROR_MEMORY,
          stateC == DONE
        };
      end
    end

    next_ct = ct;
    next_delay_ct = delay_ct;
    next_if_busy = if_busy;
    next_screen_reg = screen_reg;
    next_screen_data = screen_data;
    next_screen_r = screen_r;
    next_verify_passed = verify_passed;
    next_mem_read_first = mem_read_first;
    next_mem_read_second = mem_read_second;
    next_test_mode = test_mode;
    next_stateC = stateC;
    next_stateI = stateI;

    case (stateC)
      IDLE_C: begin
        if (req && !load && addr == 32'd4) begin
          next_test_mode = write_data[1:0];
          next_stateC = INIT;
        end
      end

      INIT: begin
        if (!if_busy && stateI == IDLE_I) begin
          if (delay_ct != 17'd0) begin
            next_delay_ct = delay_ct - 17'd1;
          end else if (ct > 20'd39) begin
            next_ct = '0;
            next_stateC = VERIFY;
          end else begin
            next_ct = ct + 20'd1;
            next_if_busy = 1'b1;
            next_screen_r = 1'b0;

            case (ct)
              // Software reset, followed by a conservative 1 ms recovery.
              12'd0: begin
                next_screen_reg = 8'h01;
                next_screen_data = 8'h01;
                next_stateI = PREP_REG;
              end
              12'd1: begin
                next_screen_data = 8'h00;
                next_stateI = PREP_DATA;
                next_delay_ct = DELAY_1_MS;
              end

              // BTN1 uses the conservative EastRising/BuyDisplay 800x480
              // profile: 20 MHz SYS_CLK and 10 MHz PCLK.
              12'd2: begin
                next_screen_reg = 8'h88;
                // BTN2 keeps the 55 MHz SYS_CLK timing experiment; BTN3/4
                // retain the previous 60 MHz profile and polarity tests.
                next_screen_data = test_mode == 2'd0 ? 8'h07 :
                                   test_mode == 2'd1 ? 8'h0A : 8'h0B;
                next_stateI = PREP_REG;
                next_delay_ct = DELAY_1_MS;
              end
              12'd3: begin
                next_screen_reg = 8'h89;
                next_screen_data = test_mode == 2'd0 ? 8'h03 : 8'h02;
                next_stateI = PREP_REG;
                next_delay_ct = DELAY_1_MS;
              end

              // RGB565 graphics over an 8-bit 8080 MCU interface.
              12'd4: begin
                next_screen_reg = 8'h10;
                next_screen_data = 8'h0C;
                next_stateI = PREP_REG;
              end

              // BTN1 tests data captured on the rising PCLK edge. The other
              // buttons retain the reference falling-edge polarity.
              12'd5: begin
                next_screen_reg = 8'h04;
                next_screen_data = test_mode == 2'd0 ? 8'h01 : 8'h81;
                next_stateI = PREP_REG;
                next_delay_ct = DELAY_1_MS;
              end

              // 800x480 panel timing from the RA8875 reference driver.
              12'd6: begin
                next_screen_reg = 8'h14;
                next_screen_data = 8'h63;
                next_stateI = PREP_REG;
              end
              12'd7: begin
                next_screen_reg = 8'h15;
                // BTN3 tests active-low DE instead of the reference active-high.
                next_screen_data = test_mode == 2'd2 ? 8'h80 : 8'h00;
                next_stateI = PREP_REG;
              end
              12'd8: begin
                next_screen_reg = 8'h16;
                next_screen_data = 8'h03;
                next_stateI = PREP_REG;
              end
              12'd9: begin
                next_screen_reg = 8'h17;
                next_screen_data = 8'h03;
                next_stateI = PREP_REG;
              end
              12'd10: begin
                next_screen_reg = 8'h18;
                // BTN4 tests active-high HSYNC and VSYNC.
                next_screen_data = test_mode == 2'd3 ? 8'h8B : 8'h0B;
                next_stateI = PREP_REG;
              end
              12'd11: begin
                next_screen_reg = 8'h19;
                next_screen_data = 8'hDF;
                next_stateI = PREP_REG;
              end
              12'd12: begin
                next_screen_reg = 8'h1A;
                next_screen_data = 8'h01;
                next_stateI = PREP_REG;
              end
              12'd13: begin
                next_screen_reg = 8'h1B;
                next_screen_data = test_mode == 2'd0 ? 8'h1F : 8'h20;
                next_stateI = PREP_REG;
              end
              12'd14: begin
                next_screen_reg = 8'h1C;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd15: begin
                next_screen_reg = 8'h1D;
                next_screen_data = 8'h16;
                next_stateI = PREP_REG;
              end
              12'd16: begin
                next_screen_reg = 8'h1E;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd17: begin
                next_screen_reg = 8'h1F;
                next_screen_data = test_mode == 2'd3 ? 8'h81 : 8'h01;
                next_stateI = PREP_REG;
              end

              // Keep LCD output disabled until all timing is configured.
              12'd18: begin
                next_screen_reg = 8'h01;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd19: begin
                next_screen_reg = 8'h70;
                next_screen_data = 8'h80;
                next_stateI = PREP_REG;
              end
              12'd20: begin
                next_screen_reg = 8'h71;
                next_screen_data = 8'h84;
                next_stateI = PREP_REG;
              end
              12'd21: begin
                next_screen_reg = 8'hF0;
                next_screen_data = 8'h04;
                next_stateI = PREP_REG;
              end

              // Full-screen active window is (0,0) through inclusive (799,479).
              12'd22: begin
                next_screen_reg = 8'h30;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd23: begin
                next_screen_reg = 8'h31;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd24: begin
                next_screen_reg = 8'h32;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd25: begin
                next_screen_reg = 8'h33;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd26: begin
                next_screen_reg = 8'h34;
                next_screen_data = 8'h1F;
                next_stateI = PREP_REG;
              end
              12'd27: begin
                next_screen_reg = 8'h35;
                next_screen_data = 8'h03;
                next_stateI = PREP_REG;
              end
              12'd28: begin
                next_screen_reg = 8'h36;
                next_screen_data = 8'hDF;
                next_stateI = PREP_REG;
              end
              12'd29: begin
                next_screen_reg = 8'h37;
                next_screen_data = 8'h01;
                next_stateI = PREP_REG;
              end

              // Make graphics mode, cursor direction, and layer target explicit.
              12'd30: begin
                next_screen_reg = 8'h40;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd31: begin
                next_screen_reg = 8'h41;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end

              // Select one layer, zero all display offsets, and show layer 1.
              12'd32: begin
                next_screen_reg = 8'h20;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd33: begin
                next_screen_reg = 8'h24;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd34: begin
                next_screen_reg = 8'h25;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd35: begin
                next_screen_reg = 8'h26;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd36: begin
                next_screen_reg = 8'h27;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end
              12'd37: begin
                next_screen_reg = 8'h52;
                next_screen_data = 8'h00;
                next_stateI = PREP_REG;
              end

              // GPIOX is commonly wired to the TFT panel's display-enable input.
              12'd38: begin
                next_screen_reg = 8'hC7;
                next_screen_data = 8'h01;
                next_stateI = PREP_REG;
              end

              // Turn display output on last, then wait 10 ms before DDRAM.
              12'd39: begin
                next_screen_reg = 8'h01;
                next_screen_data = 8'h80;
                next_stateI = PREP_REG;
                next_delay_ct = DELAY_10_MS;
              end
              default:;
            endcase
          end
        end
      end

      VERIFY: begin
        if (!if_busy && stateI == IDLE_I) begin
          // Even steps issue a register read; odd steps check the returned byte.
          if (ct >= VERIFY_STEPS) begin
            next_stateC = ERROR_REG;
          end else if (!ct[0]) begin
            next_ct = ct + 20'd1;
            next_if_busy = 1'b1;
            next_screen_reg = scanout_reg(ct[6:1]);
            next_screen_r = 1'b1;
            next_stateI = PREP_REG;
          end else if ((screen_data & scanout_mask(ct[6:1])) !=
                       (scanout_expected(ct[6:1], test_mode) &
                        scanout_mask(ct[6:1]))) begin
            next_stateC = ERROR_REG;
          end else if (ct == VERIFY_STEPS - 20'd1) begin
            next_ct = '0;
            next_verify_passed = 1'b1;
            next_screen_r = 1'b0;
            next_stateC = CLEAR_BACKGROUND;
          end else begin
            next_ct = ct + 20'd1;
          end
        end
      end

      CLEAR_BACKGROUND: begin
        if (!if_busy && stateI == IDLE_I) begin
          next_ct = ct + 20'd1;
          next_if_busy = 1'b1;
          next_screen_r = 1'b0;

          case (ct)
            // Clear the full display to RGB565 black first.
            20'd0: begin
              next_screen_reg = 8'h60;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd1: begin
              next_screen_reg = 8'h61;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd2: begin
              next_screen_reg = 8'h62;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd3: begin
              next_screen_reg = 8'h8E;
              next_screen_data = 8'h80;
              next_stateI = PREP_REG;
              next_ct = '0;
              next_stateC = WAIT_BACKGROUND;
            end
            default: begin
              next_stateC = ERROR_MEMORY;
            end
          endcase
        end
      end

      WAIT_BACKGROUND: begin
        if (!if_busy && stateI == IDLE_I) begin
          if (ct == 20'd0) begin
            next_ct = 20'd1;
            next_if_busy = 1'b1;
            next_screen_reg = 8'h8E;
            next_screen_r = 1'b1;
            next_stateI = PREP_REG;
          end else if (screen_data[7]) begin
            next_if_busy = 1'b1;
            next_screen_reg = 8'h8E;
            next_screen_r = 1'b1;
            next_stateI = PREP_REG;
          end else begin
            next_ct = '0;
            next_screen_r = 1'b0;
            next_stateC = VERIFY_BACKGROUND;
          end
        end
      end

      VERIFY_BACKGROUND: begin
        if (!if_busy && stateI == IDLE_I) begin
          case (ct)
            // Point the read cursor at (0,0) immediately after the black clear.
            20'd0: begin
              next_ct = 20'd1;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4A;
              next_screen_data = 8'h00;
              next_screen_r = 1'b0;
              next_stateI = PREP_REG;
            end
            20'd1: begin
              next_ct = 20'd2;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4B;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd2: begin
              next_ct = 20'd3;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4C;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd3: begin
              next_ct = 20'd4;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4D;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end

            // Select MRWC, discard the dummy read, then fetch the black pixel.
            20'd4: begin
              next_ct = 20'd5;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h02;
              next_screen_r = 1'b1;
              next_stateI = PREP_REG;
            end
            20'd5: begin
              next_ct = 20'd6;
              next_if_busy = 1'b1;
              next_stateI = PREP_DATA;
            end
            20'd6: begin
              next_mem_read_first = screen_data;
              next_ct = 20'd7;
              next_if_busy = 1'b1;
              next_stateI = PREP_DATA;
            end
            20'd7: begin
              next_mem_read_second = screen_data;
              next_screen_r = 1'b0;
              next_ct = '0;
              if (mem_read_first != 8'h00 || screen_data != 8'h00) begin
                next_stateC = ERROR_BACKGROUND;
              end else begin
                next_stateC = WRITE_PATTERN;
              end
            end
            default: begin
              next_stateC = ERROR_BACKGROUND;
            end
          endcase
        end
      end

      WRITE_PATTERN: begin
        if (!if_busy && stateI == IDLE_I) begin
          next_ct = ct + 20'd1;
          next_if_busy = 1'b1;
          next_screen_r = 1'b0;

          case (ct)
            // Set a 100x100 active window from (100,100) through (199,199).
            20'd0: begin
              next_screen_reg = 8'h30;
              next_screen_data = 8'd100;
              next_stateI = PREP_REG;
            end
            20'd1: begin
              next_screen_reg = 8'h31;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd2: begin
              next_screen_reg = 8'h32;
              next_screen_data = 8'd100;
              next_stateI = PREP_REG;
            end
            20'd3: begin
              next_screen_reg = 8'h33;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd4: begin
              next_screen_reg = 8'h34;
              next_screen_data = 8'd199;
              next_stateI = PREP_REG;
            end
            20'd5: begin
              next_screen_reg = 8'h35;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd6: begin
              next_screen_reg = 8'h36;
              next_screen_data = 8'd199;
              next_stateI = PREP_REG;
            end
            20'd7: begin
              next_screen_reg = 8'h37;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
              next_ct = '0;
              next_stateC = VERIFY_WINDOW;
            end
            default: begin
              next_stateC = ERROR_MEMORY;
            end
          endcase
        end
      end

      VERIFY_WINDOW: begin
        if (!if_busy && stateI == IDLE_I) begin
          case (ct)
            // Read each active-window register back before writing pixels.
            20'd0: begin
              next_ct = 20'd1;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h30;
              next_screen_r = 1'b1;
              next_stateI = PREP_REG;
            end
            20'd1: begin
              if (screen_data != 8'd100) begin
                next_stateC = ERROR_REG;
              end else begin
                next_ct = 20'd2;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h31;
                next_stateI = PREP_REG;
              end
            end
            20'd2: begin
              if (screen_data != 8'h00) begin
                next_stateC = ERROR_REG;
              end else begin
                next_ct = 20'd3;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h32;
                next_stateI = PREP_REG;
              end
            end
            20'd3: begin
              if (screen_data != 8'd100) begin
                next_stateC = ERROR_REG;
              end else begin
                next_ct = 20'd4;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h33;
                next_stateI = PREP_REG;
              end
            end
            20'd4: begin
              if (screen_data != 8'h00) begin
                next_stateC = ERROR_REG;
              end else begin
                next_ct = 20'd5;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h34;
                next_stateI = PREP_REG;
              end
            end
            20'd5: begin
              if (screen_data != 8'd199) begin
                next_stateC = ERROR_REG;
              end else begin
                next_ct = 20'd6;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h35;
                next_stateI = PREP_REG;
              end
            end
            20'd6: begin
              if (screen_data != 8'h00) begin
                next_stateC = ERROR_REG;
              end else begin
                next_ct = 20'd7;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h36;
                next_stateI = PREP_REG;
              end
            end
            20'd7: begin
              if (screen_data != 8'd199) begin
                next_stateC = ERROR_REG;
              end else begin
                next_ct = 20'd8;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h37;
                next_stateI = PREP_REG;
              end
            end
            20'd8: begin
              if (screen_data != 8'h00) begin
                next_stateC = ERROR_REG;
              end else begin
                next_ct = 20'd9;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h46;
                next_screen_data = 8'd100;
                next_screen_r = 1'b0;
                next_stateI = PREP_REG;
              end
            end
            // Set the memory write cursor to the block's upper-left corner.
            20'd9: begin
              next_ct = 20'd10;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h47;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd10: begin
              next_ct = 20'd11;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h48;
              next_screen_data = 8'd100;
              next_stateI = PREP_REG;
            end
            20'd11: begin
              next_ct = 20'd12;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h49;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd12: begin
              // Selecting MRWC also sends the first RGB565 byte (red high byte).
              next_ct = 20'd1;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h02;
              next_screen_data = 8'hF8;
              next_stateI = PREP_REG;
              next_stateC = WRITE_PIXELS;
            end
            default: begin
              next_stateC = ERROR_REG;
            end
          endcase
        end
      end

      WRITE_PIXELS: begin
        if (!if_busy && stateI == IDLE_I) begin
          if (ct == 20'd20000) begin
            next_ct = '0;
            next_screen_r = 1'b0;
            next_stateC = VERIFY_MEMORY;
          end else begin
            // 8-bit MCU mode sends RGB565 high byte first, then low byte.
            next_ct = ct + 20'd1;
            next_if_busy = 1'b1;
            next_screen_r = 1'b0;
            next_screen_data = ct[0] ? 8'h00 : 8'hF8;
            next_stateI = PREP_DATA;
          end
        end
      end

      VERIFY_MEMORY: begin
        if (!if_busy && stateI == IDLE_I) begin
          case (ct)
            // The RA8875 has a separate read cursor. Point it inside the block.
            20'd0: begin
              next_ct = 20'd1;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4A;
              next_screen_data = 8'd100;
              next_screen_r = 1'b0;
              next_stateI = PREP_REG;
            end
            20'd1: begin
              next_ct = 20'd2;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4B;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd2: begin
              next_ct = 20'd3;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4C;
              next_screen_data = 8'd100;
              next_stateI = PREP_REG;
            end
            20'd3: begin
              next_ct = 20'd4;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4D;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end

            // Select MRWC and perform the mandatory dummy data read.
            20'd4: begin
              next_ct = 20'd5;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h02;
              next_screen_r = 1'b1;
              next_stateI = PREP_REG;
            end

            // RA8875 memory reads return the RGB565 low byte, then high byte.
            20'd5: begin
              next_ct = 20'd6;
              next_if_busy = 1'b1;
              next_stateI = PREP_DATA;
            end
            20'd6: begin
              next_mem_read_first = screen_data;
              next_ct = 20'd7;
              next_if_busy = 1'b1;
              next_stateI = PREP_DATA;
            end
            20'd7: begin
              next_mem_read_second = screen_data;
              next_screen_r = 1'b0;
              if (mem_read_first != 8'h00 || screen_data != 8'hF8) begin
                next_stateC = ERROR_MEMORY;
              end else begin
                next_ct = 20'd8;
              end
            end

            // Point the read cursor outside the block at (0,0).
            20'd8: begin
              next_ct = 20'd9;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4A;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd9: begin
              next_ct = 20'd10;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4B;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd10: begin
              next_ct = 20'd11;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4C;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end
            20'd11: begin
              next_ct = 20'd12;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4D;
              next_screen_data = 8'h00;
              next_stateI = PREP_REG;
            end

            // Read back the outside cursor before using it for DDRAM access.
            20'd12: begin
              next_ct = 20'd13;
              next_if_busy = 1'b1;
              next_screen_reg = 8'h4A;
              next_screen_r = 1'b1;
              next_stateI = PREP_REG;
            end
            20'd13: begin
              if (screen_data != 8'h00) begin
                next_screen_r = 1'b0;
                next_stateC = ERROR_CURSOR;
              end else begin
                next_ct = 20'd14;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h4B;
                next_stateI = PREP_REG;
              end
            end
            20'd14: begin
              if (screen_data != 8'h00) begin
                next_screen_r = 1'b0;
                next_stateC = ERROR_CURSOR;
              end else begin
                next_ct = 20'd15;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h4C;
                next_stateI = PREP_REG;
              end
            end
            20'd15: begin
              if (screen_data != 8'h00) begin
                next_screen_r = 1'b0;
                next_stateC = ERROR_CURSOR;
              end else begin
                next_ct = 20'd16;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h4D;
                next_stateI = PREP_REG;
              end
            end

            // Select MRWC, discard its dummy read, then read the black pixel.
            20'd16: begin
              if (screen_data != 8'h00) begin
                next_screen_r = 1'b0;
                next_stateC = ERROR_CURSOR;
              end else begin
                next_ct = 20'd17;
                next_if_busy = 1'b1;
                next_screen_reg = 8'h02;
                next_stateI = PREP_REG;
              end
            end
            20'd17: begin
              next_ct = 20'd18;
              next_if_busy = 1'b1;
              next_stateI = PREP_DATA;
            end
            20'd18: begin
              next_mem_read_first = screen_data;
              next_ct = 20'd19;
              next_if_busy = 1'b1;
              next_stateI = PREP_DATA;
            end
            20'd19: begin
              next_mem_read_second = screen_data;
              next_screen_r = 1'b0;
              if (mem_read_first != 8'h00 || screen_data != 8'h00) begin
                next_stateC = ERROR_MEMORY;
              end else begin
                next_ct = '0;
                next_stateC = DONE;
              end
            end
            default: begin
              next_stateC = ERROR_MEMORY;
            end
          endcase
        end
      end

      DONE:;
      default:;
    endcase

    // For a register-read failure, preserve the selected register address and
    // the byte returned by the RA8875 for the LED diagnostic display.
    if (stateC != ERROR_REG && next_stateC == ERROR_REG) begin
      next_mem_read_first = screen_reg;
      next_mem_read_second = screen_data;
    end

    // Keep the same 8080 interface sequencing as src/dpu.sv.
    next_rd = 1'b1;
    next_wr = 1'b1;
    next_rs = 1'b1;
    next_cs = 1'b1;
    next_drive = 1'b0;
    next_db_w = 8'b0;

    case (stateI)
      PREP_REG: begin
        next_stateI = PREP_REG2;
      end
      PREP_REG2: begin
        next_cs = 1'b0;
        next_stateI = INIT_REG;
      end
      INIT_REG: begin
        next_cs = 1'b0;
        next_wr = 1'b0;
        next_stateI = SEND_REG;
      end
      SEND_REG: begin
        next_cs = 1'b0;
        next_wr = 1'b0;
        next_drive = 1'b1;
        next_db_w = screen_reg;
        next_stateI = END_REG;
      end
      END_REG: begin
        next_cs = 1'b0;
        next_drive = 1'b1;
        next_db_w = screen_reg;
        next_stateI = FINISH_REG;
      end
      FINISH_REG: begin
        next_rs = 1'b0;
        next_stateI = PREP_DATA;
      end
      PREP_DATA: begin
        next_cs = 1'b0;
        next_rs = 1'b0;
        next_stateI = INIT_DATA;
      end
      INIT_DATA: begin
        next_cs = 1'b0;
        next_rs = 1'b0;
        if (screen_r) begin
          next_rd = 1'b0;
        end else begin
          next_wr = 1'b0;
        end
        next_stateI = DATA;
      end
      DATA: begin
        next_cs = 1'b0;
        next_rs = 1'b0;
        if (screen_r) begin
          next_rd = 1'b0;
        end else begin
          next_wr = 1'b0;
          next_drive = 1'b1;
          next_db_w = screen_data;
        end
        next_stateI = LAG_DATA;
      end
      LAG_DATA: begin
        next_cs = 1'b0;
        next_rs = 1'b0;
        if (screen_r) begin
          next_rd = 1'b0;
          next_screen_data = db_in;
        end else begin
          next_wr = 1'b0;
          next_drive = 1'b1;
          next_db_w = screen_data;
        end
        next_stateI = END_DATA;
      end
      END_DATA: begin
        next_cs = 1'b0;
        next_rs = 1'b0;
        if (!screen_r) begin
          next_drive = 1'b1;
          next_db_w = screen_data;
        end
        next_stateI = FINISH_DATA;
      end
      FINISH_DATA: begin
        next_if_busy = 1'b0;
        next_stateI = IDLE_I;
      end
      default:;
    endcase
  end

  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      ct <= '0;
      delay_ct <= '0;
      if_busy <= 1'b0;
      screen_reg <= '0;
      screen_data <= '0;
      screen_r <= 1'b0;
      verify_passed <= 1'b0;
      mem_read_first <= '0;
      mem_read_second <= '0;
      test_mode <= '0;
      stateC <= IDLE_C;
      stateI <= IDLE_I;
      ack <= 1'b0;
      read_data <= '0;
      rd <= 1'b1;
      wr <= 1'b1;
      rs <= 1'b1;
      cs <= 1'b1;
      drive <= 1'b0;
      db_w <= '0;
      debug_counter <= '0;
    end else begin
      ct <= next_ct;
      delay_ct <= next_delay_ct;
      if_busy <= next_if_busy;
      screen_reg <= next_screen_reg;
      screen_data <= next_screen_data;
      screen_r <= next_screen_r;
      verify_passed <= next_verify_passed;
      mem_read_first <= next_mem_read_first;
      mem_read_second <= next_mem_read_second;
      test_mode <= next_test_mode;
      stateC <= next_stateC;
      stateI <= next_stateI;
      ack <= next_ack;
      read_data <= next_read_data;
      rd <= next_rd;
      wr <= next_wr;
      rs <= next_rs;
      cs <= next_cs;
      drive <= next_drive;
      db_w <= next_db_w;
      if (stateC == ERROR_MEMORY || stateC == ERROR_REG) begin
        debug_counter <= debug_counter + 25'd1;
      end else begin
        debug_counter <= '0;
      end
    end
  end

endmodule
