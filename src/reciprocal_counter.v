/*
 * Copyright (c) 2026 Brad Pound
 * SPDX-License-Identifier: Apache-2.0
 *
 * Two-channel reciprocal counter with a 32-bit SPI register interface.
 * Area-optimized internal widths are used for the Tiny Tapeout 1x2 tile.
 */

`default_nettype none

module reciprocal_counter (
    input  wire clk,
    input  wire rst_n,

    input  wire ch0_signal_in,
    input  wire ch1_signal_in,

    // SPI mode-0 register interface
    input  wire spi_sclk,
    input  wire spi_mosi,
    input  wire spi_cs_n,
    output wire spi_miso
);

    /* Internal register bus */
    wire        reg_write;
    wire [7:0]  reg_addr;
    wire [31:0] reg_wdata;
    wire [31:0] reg_rdata;

    /* Channel configuration */
    wire [17:0] ch0_gate_cycles;
    wire [27:0] ch0_timeout_refcount;
    wire [17:0] ch1_gate_cycles;
    wire [27:0] ch1_timeout_refcount;

    /* Channel 0 measurement and status */
    wire [27:0] ch0_measured_ref_count;
    wire [31:0] ch0_completed_count;
    wire [31:0] ch0_timeout_count;
    wire        ch0_timeout_latched;
    wire        ch0_overflow_latched;
    wire        ch0_active;

    /* Channel 1 measurement and status */
    wire [27:0] ch1_measured_ref_count;
    wire [31:0] ch1_completed_count;
    wire [31:0] ch1_timeout_count;
    wire        ch1_timeout_latched;
    wire        ch1_overflow_latched;
    wire        ch1_active;

    /* Clear commands from the register file */
    wire ch0_clear_timeout_latched;
    wire ch0_clear_timeout_count;
    wire ch0_clear_overflow_latched;
    wire ch1_clear_timeout_latched;
    wire ch1_clear_timeout_count;
    wire ch1_clear_overflow_latched;

    spi_register_interface spi_interface (
        .clk       (clk),
        .rst_n     (rst_n),

        .spi_sclk  (spi_sclk),
        .spi_mosi  (spi_mosi),
        .spi_cs_n  (spi_cs_n),
        .spi_miso  (spi_miso),

        .reg_write (reg_write),
        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_rdata (reg_rdata)
    );

    reciprocal_channel ch0 (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .signal_in              (ch0_signal_in),

        .gate_cycles            (ch0_gate_cycles),
        .timeout_refcount       (ch0_timeout_refcount),

        .clear_timeout_latched  (ch0_clear_timeout_latched),
        .clear_timeout_count    (ch0_clear_timeout_count),
        .clear_overflow_latched (ch0_clear_overflow_latched),

        .measured_ref_count     (ch0_measured_ref_count),
        .completed_count        (ch0_completed_count),
        .timeout_count          (ch0_timeout_count),

        // This pulse is not currently exposed through the register map.
        .measurement_valid      (),
        .timeout_latched        (ch0_timeout_latched),
        .overflow_latched       (ch0_overflow_latched),
        .active                 (ch0_active)
    );

    reciprocal_channel ch1 (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .signal_in              (ch1_signal_in),

        .gate_cycles            (ch1_gate_cycles),
        .timeout_refcount       (ch1_timeout_refcount),

        .clear_timeout_latched  (ch1_clear_timeout_latched),
        .clear_timeout_count    (ch1_clear_timeout_count),
        .clear_overflow_latched (ch1_clear_overflow_latched),

        .measured_ref_count     (ch1_measured_ref_count),
        .completed_count        (ch1_completed_count),
        .timeout_count          (ch1_timeout_count),

        // This pulse is not currently exposed through the register map.
        .measurement_valid      (),
        .timeout_latched        (ch1_timeout_latched),
        .overflow_latched       (ch1_overflow_latched),
        .active                 (ch1_active)
    );

    register_file registers (
        .clk                        (clk),
        .rst_n                      (rst_n),

        .reg_write                  (reg_write),
        .reg_addr                   (reg_addr),
        .reg_wdata                  (reg_wdata),
        .reg_rdata                  (reg_rdata),

        .ch0_gate_cycles            (ch0_gate_cycles),
        .ch1_gate_cycles            (ch1_gate_cycles),
        .ch0_timeout_refcount       (ch0_timeout_refcount),
        .ch1_timeout_refcount       (ch1_timeout_refcount),

        .ch0_count                  (ch0_measured_ref_count),
        .ch1_count                  (ch1_measured_ref_count),
        .ch0_measurement_count      (ch0_completed_count),
        .ch1_measurement_count      (ch1_completed_count),

        .ch0_active                 (ch0_active),
        .ch1_active                 (ch1_active),
        .ch0_timeout_latched        (ch0_timeout_latched),
        .ch1_timeout_latched        (ch1_timeout_latched),
        .ch0_overflow_latched       (ch0_overflow_latched),
        .ch1_overflow_latched       (ch1_overflow_latched),

        .ch0_clear_timeout_latched  (ch0_clear_timeout_latched),
        .ch1_clear_timeout_latched  (ch1_clear_timeout_latched),
        .ch0_clear_overflow_latched (ch0_clear_overflow_latched),
        .ch1_clear_overflow_latched (ch1_clear_overflow_latched),

        .ch0_timeout_count          (ch0_timeout_count),
        .ch1_timeout_count          (ch1_timeout_count),

        .ch0_clear_timeout_count    (ch0_clear_timeout_count),
        .ch1_clear_timeout_count    (ch1_clear_timeout_count)
    );

endmodule

`default_nettype wire
