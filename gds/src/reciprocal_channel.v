/*
 * Copyright (c) 2026 Brad Pound
 * SPDX-License-Identifier: Apache-2.0
 *
 * Area-optimized reciprocal measurement channel for the Tiny Tapeout 1x2 tile.
 *
 * Supported internal ranges:
 *   gate_cycles      : 18 bits, 0 to 262143
 *   reference count  : 28 bits, 0 to 268435455
 *
 * The first synchronized rising edge starts a measurement. The channel then
 * counts gate_cycles additional rising edges, representing gate_cycles full
 * input periods.
 *
 * Configuration values are used directly while a measurement is active. The
 * register file prevents nonzero configuration changes during a measurement.
 * Writing gate_cycles = 0 is permitted and aborts the active measurement.
 */

`default_nettype none

module reciprocal_channel #(
    parameter [27:0] REF_COUNT_MAX = 28'h0FFF_FFFF
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        signal_in,

    input  wire [17:0] gate_cycles,
    input  wire [27:0] timeout_refcount,

    input  wire        clear_timeout_latched,
    input  wire        clear_timeout_count,
    input  wire        clear_overflow_latched,

    output reg  [27:0] measured_ref_count,
    output reg  [31:0] completed_count,
    output reg  [31:0] timeout_count,

    output reg         measurement_valid,
    output reg         timeout_latched,
    output reg         overflow_latched,
    output reg         active
);

    /*
     * Synchronize the asynchronous measurement input into the clk domain,
     * then detect synchronized rising edges.
     */
    reg signal_meta;
    reg signal_sync;
    reg signal_sync_delayed;

    wire signal_rising_edge = signal_sync && !signal_sync_delayed;

    always @(posedge clk) begin
        if (!rst_n) begin
            signal_meta         <= 1'b0;
            signal_sync         <= 1'b0;
            signal_sync_delayed <= 1'b0;
        end else begin
            signal_meta         <= signal_in;
            signal_sync         <= signal_meta;
            signal_sync_delayed <= signal_sync;
        end
    end

    /* Measurement state */
    reg [27:0] reference_count;
    reg [17:0] period_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            measured_ref_count <= 28'd0;
            completed_count    <= 32'd0;
            timeout_count      <= 32'd0;

            measurement_valid <= 1'b0;
            timeout_latched   <= 1'b0;
            overflow_latched  <= 1'b0;
            active            <= 1'b0;

            reference_count <= 28'd0;
            period_count    <= 18'd0;
        end else begin
            // measurement_valid is a one-clock pulse.
            measurement_valid <= 1'b0;

            // Sticky flags and diagnostic counters are write-one-to-clear.
            if (clear_timeout_latched) begin
                timeout_latched <= 1'b0;
            end

            if (clear_overflow_latched) begin
                overflow_latched <= 1'b0;
            end

            if (clear_timeout_count) begin
                timeout_count <= 32'd0;
            end

            if (!active) begin
                reference_count <= 28'd0;
                period_count    <= 18'd0;

                // gate_cycles == 0 disables the channel.
                if ((gate_cycles != 18'd0) && signal_rising_edge) begin
                    active <= 1'b1;
                end
            end else if (gate_cycles == 18'd0) begin
                /*
                 * A zero gate-cycle write is the software-controlled abort
                 * mechanism. Discard the partial measurement without setting
                 * timeout or overflow status.
                 */
                active          <= 1'b0;
                period_count    <= 18'd0;
                reference_count <= 28'd0;
            end else begin
                /*
                 * Check the current count before adding one. This prevents
                 * the completion expression from wrapping on the exact
                 * reference-counter overflow boundary.
                 */
                if (reference_count == REF_COUNT_MAX) begin
                    overflow_latched <= 1'b1;
                    active           <= 1'b0;
                    period_count     <= 18'd0;
                    reference_count  <= 28'd0;
                end else begin
                    reference_count <= reference_count + 28'd1;

                    /*
                     * Configuration is held stable by register_file while
                     * active, so equality comparisons are sufficient and are
                     * smaller than greater-than-or-equal comparisons.
                     */
                    if (signal_rising_edge &&
                        ((period_count + 18'd1) == gate_cycles)) begin

                        measured_ref_count <= reference_count + 28'd1;
                        measurement_valid  <= 1'b1;
                        completed_count    <= completed_count + 32'd1;

                        active          <= 1'b0;
                        period_count    <= 18'd0;
                        reference_count <= 28'd0;
                    end else if ((timeout_refcount != 28'd0) &&
                                 ((reference_count + 28'd1) ==
                                  timeout_refcount)) begin

                        timeout_latched <= 1'b1;
                        timeout_count   <= timeout_count + 32'd1;

                        active          <= 1'b0;
                        period_count    <= 18'd0;
                        reference_count <= 28'd0;
                    end else if (signal_rising_edge) begin
                        period_count <= period_count + 18'd1;
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
