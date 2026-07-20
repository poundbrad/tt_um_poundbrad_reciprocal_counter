/*
 * Tiny Tapeout wrapper for the Project Genesis two-channel reciprocal counter.
 *
 * Pin mapping:
 *
 *   ui_in[0]  CH0_SIGNAL_IN  (pressure oscillator in the current FPGA test)
 *   ui_in[1]  CH1_SIGNAL_IN  (temperature oscillator in the current FPGA test)
 *   ui_in[2]  SPI_SCLK
 *   ui_in[3]  SPI_MOSI
 *   ui_in[4]  SPI_CS_N
 *   ui_in[7:5] unused
 *
 *   uo_out[0] SPI_MISO
 *   uo_out[7:1] unused, driven low
 *
 *   clk       reciprocal-counter reference clock
 *   rst_n     active-low reset
 *
 * The bidirectional Tiny Tapeout pins are not used.
 */

`default_nettype none

module tt_um_poundbrad_reciprocal_counter (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire spi_miso;

    reciprocal_counter reciprocal_counter_inst (
        .clk           (clk),
        .rst_n         (rst_n),

        .ch0_signal_in (ui_in[0]),
        .ch1_signal_in (ui_in[1]),

        .spi_sclk      (ui_in[2]),
        .spi_mosi      (ui_in[3]),
        .spi_cs_n      (ui_in[4]),
        .spi_miso      (spi_miso)
    );

    assign uo_out = {
        7'b0000000,
        spi_miso
    };

    // No bidirectional pins are used.
    assign uio_out = 8'b00000000;
    assign uio_oe  = 8'b00000000;

    // Prevent unused-input warnings without adding functional logic.
    wire _unused = &{
        ena,
        ui_in[7:5],
        uio_in,
        1'b0
    };

endmodule

`default_nettype wire
