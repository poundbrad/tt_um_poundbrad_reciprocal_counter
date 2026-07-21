/*
 * Copyright (c) 2026 Brad Pound
 * SPDX-License-Identifier: Apache-2.0
 *
 * Area-optimized register file for the Tiny Tapeout 1x2 tile.
 *
 * The external SPI register bus remains 32 bits wide. Configuration and
 * reciprocal-result storage use only the supported internal widths and are
 * zero-extended when read through SPI.
 *
 * Configuration stability policy:
 *   - Nonzero gate-cycle writes are accepted only while the channel is idle.
 *   - A gate-cycle write of zero is always accepted and aborts/disables the
 *     channel.
 *   - Timeout-reference writes are accepted only while the channel is idle.
 *
 * This policy allows reciprocal_channel to use the configuration registers
 * directly without maintaining a second active copy of each value.
 */

`default_nettype none

module register_file (
    input  wire        clk,
    input  wire        rst_n,

    // Simple internal register bus
    input  wire        reg_write,
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Channel 0 and 1 configuration outputs
    output reg  [17:0] ch0_gate_cycles,
    output reg  [17:0] ch1_gate_cycles,
    output reg  [27:0] ch0_timeout_refcount,
    output reg  [27:0] ch1_timeout_refcount,

    // Measurement and diagnostic inputs
    input  wire [27:0] ch0_count,
    input  wire [27:0] ch1_count,
    input  wire [31:0] ch0_measurement_count,
    input  wire [31:0] ch1_measurement_count,

    // Current channel state and sticky fault inputs
    input  wire        ch0_active,
    input  wire        ch1_active,
    input  wire        ch0_timeout_latched,
    input  wire        ch1_timeout_latched,
    input  wire        ch0_overflow_latched,
    input  wire        ch1_overflow_latched,

    // Write-one-to-clear pulses for sticky status flags
    output reg         ch0_clear_timeout_latched,
    output reg         ch1_clear_timeout_latched,
    output reg         ch0_clear_overflow_latched,
    output reg         ch1_clear_overflow_latched,

    input  wire [31:0] ch0_timeout_count,
    input  wire [31:0] ch1_timeout_count,

    // Write-one-to-clear pulses for timeout diagnostic counters
    output reg         ch0_clear_timeout_count,
    output reg         ch1_clear_timeout_count
);

    localparam [7:0] ADDR_CH0_GATE_CYCLES       = 8'h00;
    localparam [7:0] ADDR_CH1_GATE_CYCLES       = 8'h04;
    localparam [7:0] ADDR_CH0_TIMEOUT_REFCOUNT  = 8'h08;
    localparam [7:0] ADDR_CH1_TIMEOUT_REFCOUNT  = 8'h0C;
    localparam [7:0] ADDR_CH0_COUNT             = 8'h10;
    localparam [7:0] ADDR_CH1_COUNT             = 8'h14;
    localparam [7:0] ADDR_CH0_MEASUREMENT_COUNT = 8'h18;
    localparam [7:0] ADDR_CH1_MEASUREMENT_COUNT = 8'h1C;
    localparam [7:0] ADDR_CH0_TIMEOUT_COUNT     = 8'h20;
    localparam [7:0] ADDR_CH1_TIMEOUT_COUNT     = 8'h24;
    localparam [7:0] ADDR_STATUS                = 8'h28;

    // Writable register storage
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ch0_gate_cycles      <= 18'd0;
            ch1_gate_cycles      <= 18'd0;
            ch0_timeout_refcount <= 28'd0;
            ch1_timeout_refcount <= 28'd0;

            ch0_clear_timeout_latched  <= 1'b0;
            ch1_clear_timeout_latched  <= 1'b0;
            ch0_clear_overflow_latched <= 1'b0;
            ch1_clear_overflow_latched <= 1'b0;

            ch0_clear_timeout_count <= 1'b0;
            ch1_clear_timeout_count <= 1'b0;
        end else begin
            // Clear commands are one-clock pulses.
            ch0_clear_timeout_latched  <= 1'b0;
            ch1_clear_timeout_latched  <= 1'b0;
            ch0_clear_overflow_latched <= 1'b0;
            ch1_clear_overflow_latched <= 1'b0;

            ch0_clear_timeout_count <= 1'b0;
            ch1_clear_timeout_count <= 1'b0;

            if (reg_write) begin
                case (reg_addr)
                    ADDR_CH0_GATE_CYCLES: begin
                        /*
                         * A zero write is always allowed so software can
                         * abort/disable an active channel. Nonzero writes are
                         * ignored until software retries while the channel is idle.
                         */
                        if (!ch0_active || (reg_wdata[17:0] == 18'd0)) begin
                            ch0_gate_cycles <= reg_wdata[17:0];
                        end
                    end

                    ADDR_CH1_GATE_CYCLES: begin
                        if (!ch1_active || (reg_wdata[17:0] == 18'd0)) begin
                            ch1_gate_cycles <= reg_wdata[17:0];
                        end
                    end

                    ADDR_CH0_TIMEOUT_REFCOUNT: begin
                        if (!ch0_active) begin
                            ch0_timeout_refcount <= reg_wdata[27:0];
                        end
                    end

                    ADDR_CH1_TIMEOUT_REFCOUNT: begin
                        if (!ch1_active) begin
                            ch1_timeout_refcount <= reg_wdata[27:0];
                        end
                    end

                    ADDR_STATUS: begin
                        ch0_clear_timeout_latched  <= reg_wdata[2];
                        ch1_clear_timeout_latched  <= reg_wdata[3];
                        ch0_clear_overflow_latched <= reg_wdata[4];
                        ch1_clear_overflow_latched <= reg_wdata[5];
                    end

                    ADDR_CH0_TIMEOUT_COUNT: begin
                        ch0_clear_timeout_count <= reg_wdata[0];
                    end

                    ADDR_CH1_TIMEOUT_COUNT: begin
                        ch1_clear_timeout_count <= reg_wdata[0];
                    end

                    default: begin
                        // Writes to unimplemented addresses have no effect.
                    end
                endcase
            end
        end
    end

    // Combinational register read decoder
    always @(*) begin
        reg_rdata = 32'h0000_0000;

        case (reg_addr)
            ADDR_CH0_GATE_CYCLES: begin
                reg_rdata = {14'd0, ch0_gate_cycles};
            end

            ADDR_CH1_GATE_CYCLES: begin
                reg_rdata = {14'd0, ch1_gate_cycles};
            end

            ADDR_CH0_TIMEOUT_REFCOUNT: begin
                reg_rdata = {4'd0, ch0_timeout_refcount};
            end

            ADDR_CH1_TIMEOUT_REFCOUNT: begin
                reg_rdata = {4'd0, ch1_timeout_refcount};
            end

            ADDR_CH0_COUNT: begin
                reg_rdata = {4'd0, ch0_count};
            end

            ADDR_CH1_COUNT: begin
                reg_rdata = {4'd0, ch1_count};
            end

            ADDR_CH0_MEASUREMENT_COUNT: begin
                reg_rdata = ch0_measurement_count;
            end

            ADDR_CH1_MEASUREMENT_COUNT: begin
                reg_rdata = ch1_measurement_count;
            end

            ADDR_CH0_TIMEOUT_COUNT: begin
                reg_rdata = ch0_timeout_count;
            end

            ADDR_CH1_TIMEOUT_COUNT: begin
                reg_rdata = ch1_timeout_count;
            end

            ADDR_STATUS: begin
                reg_rdata = {
                    26'b0,
                    ch1_overflow_latched,
                    ch0_overflow_latched,
                    ch1_timeout_latched,
                    ch0_timeout_latched,
                    ch1_active,
                    ch0_active
                };
            end

            default: begin
                reg_rdata = 32'h0000_0000;
            end
        endcase
    end

endmodule

`default_nettype wire
