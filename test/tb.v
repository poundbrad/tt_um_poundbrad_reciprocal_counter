`default_nettype none
`timescale 1ns / 1ps

/*
 * RTL testbench for the Tiny Tapeout wrapper.
 *
 * Scalar signals are provided for cocotb convenience, but every functional
 * input still passes through the actual Tiny Tapeout ui_in pin mapping.
 */
module tb ();

  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] uio_in;

  // Convenient scalar stimulus signals for cocotb.
  reg ch0_signal_in;
  reg ch1_signal_in;
  reg spi_sclk;
  reg spi_mosi;
  reg spi_cs_n;

  /*
   * Tiny Tapeout dedicated-input mapping:
   *
   * ui_in[0] = CH0 pressure oscillator
   * ui_in[1] = CH1 temperature oscillator
   * ui_in[2] = SPI SCLK
   * ui_in[3] = SPI MOSI
   * ui_in[4] = SPI CS_N
   * ui_in[7:5] unused
   */
  wire [7:0] ui_in = {
    3'b000,
    spi_cs_n,
    spi_mosi,
    spi_sclk,
    ch1_signal_in,
    ch0_signal_in
  };

  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  // Tiny Tapeout dedicated-output mapping.
  wire spi_miso = uo_out[0];

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  tt_um_poundbrad_reciprocal_counter user_project (
`ifdef GL_TEST
      .VPWR   (VPWR),
      .VGND   (VGND),
`endif
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

endmodule

`default_nettype wire
