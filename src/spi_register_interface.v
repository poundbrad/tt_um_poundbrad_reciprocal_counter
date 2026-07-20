/*
 * Copyright (c) 2026 Brad Pound
 * SPDX-License-Identifier: Apache-2.0
 *
 * Area-optimized SPI register interface
 *
 * Protocol:
 *   Byte 0: command
 *           8'h00 = write
 *           8'h01 = read
 *   Byte 1: register address
 *   Byte 2: data[31:24]
 *   Byte 3: data[23:16]
 *   Byte 4: data[15:8]
 *   Byte 5: data[7:0]
 *
 * SPI mode:
 *   CPOL = 0
 *   CPHA = 0
 *   MOSI sampled on rising SCLK edges
 *   MISO changed on falling SCLK edges
 *   MSB first
 *
 * All SPI inputs are synchronized into the clk domain. Therefore, spi_sclk
 * must be substantially slower than clk. With clk = 7.2 MHz, an initial
 * maximum spi_sclk of 500 kHz is recommended.
 *
 * Area reductions relative to the original implementation:
 *   - reg_addr is used directly as the 8-bit address shift register.
 *   - reg_wdata is shared as the 32-bit write-input/read-output shift register.
 *   - The full 8-bit command shift register is replaced by a one-bit prefix
 *     check plus the two decoded command flags.
 *
 * The external 48-bit SPI protocol and internal register-bus interface are
 * unchanged.
 */

`default_nettype none

module spi_register_interface (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        spi_sclk,
    input  wire        spi_mosi,
    input  wire        spi_cs_n,
    output wire        spi_miso,

    output reg         reg_write,
    output reg  [7:0]  reg_addr,
    output reg  [31:0] reg_wdata,
    input  wire [31:0] reg_rdata
);

    /*
     * Synchronizers
     *
     * CS_n is reset high because the inactive SPI state is high.
     * SCLK and MOSI are reset low.
     */
    reg [1:0] spi_sclk_sync;
    reg [1:0] spi_mosi_sync;
    reg [1:0] spi_cs_n_sync;

    reg spi_sclk_previous;

    wire spi_sclk_internal = spi_sclk_sync[1];
    wire spi_mosi_internal = spi_mosi_sync[1];
    wire spi_cs_n_internal = spi_cs_n_sync[1];

    wire spi_sclk_rising =
        spi_sclk_internal && !spi_sclk_previous;

    wire spi_sclk_falling =
        !spi_sclk_internal && spi_sclk_previous;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_sclk_sync     <= 2'b00;
            spi_mosi_sync     <= 2'b00;
            spi_cs_n_sync     <= 2'b11;
            spi_sclk_previous <= 1'b0;
        end else begin
            spi_sclk_sync <= {
                spi_sclk_sync[0],
                spi_sclk
            };

            spi_mosi_sync <= {
                spi_mosi_sync[0],
                spi_mosi
            };

            spi_cs_n_sync <= {
                spi_cs_n_sync[0],
                spi_cs_n
            };

            spi_sclk_previous <= spi_sclk_internal;
        end
    end

    /*
     * Transaction state
     *
     * bit_count is the number of rising-edge SPI bits already received.
     *
     *   0  through 7  : command
     *   8  through 15 : address
     *   16 through 47 : data
     */
    reg [5:0] bit_count;

    /*
     * Only command values 8'h00 and 8'h01 are implemented. Both require the
     * first seven command bits to be zero. This one-bit accumulator therefore
     * replaces the original eight-bit command shift register.
     */
    reg command_prefix_nonzero;
    reg command_is_write;
    reg command_is_read;

    /*
     * MISO is enabled only during the data portion of a read transaction.
     * reg_wdata doubles as the read-data shift register during reads.
     *
     * The physical Tiny Tapeout wrapper may still drive its dedicated MISO
     * output pin continuously. When SPI is idle or the transaction is not a
     * read, this module returns zero.
     */
    assign spi_miso =
        (!spi_cs_n_internal &&
         command_is_read &&
         (bit_count >= 6'd16) &&
         (bit_count <= 6'd48))
        ? reg_wdata[31]
        : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_count              <= 6'd0;
            command_prefix_nonzero <= 1'b0;
            command_is_write       <= 1'b0;
            command_is_read        <= 1'b0;

            reg_write              <= 1'b0;
            reg_addr               <= 8'd0;
            reg_wdata              <= 32'd0;
        end else begin
            /* reg_write is a one-clk pulse. */
            reg_write <= 1'b0;

            /*
             * Raising CS_n aborts or completes the transaction and prepares
             * the interface for the next command. reg_addr and reg_wdata are
             * intentionally left unchanged until the next transaction uses
             * them.
             */
            if (spi_cs_n_internal) begin
                bit_count              <= 6'd0;
                command_prefix_nonzero <= 1'b0;
                command_is_write       <= 1'b0;
                command_is_read        <= 1'b0;
            end else begin
                /* SPI mode 0: sample MOSI on each rising SCLK edge. */
                if (spi_sclk_rising) begin
                    if (bit_count < 6'd7) begin
                        /* Accumulate command bits [7:1]. */
                        command_prefix_nonzero <=
                            command_prefix_nonzero |
                            spi_mosi_internal;
                    end else if (bit_count == 6'd7) begin
                        /*
                         * The final command bit is command[0]. A valid zero
                         * prefix plus command[0]=0 selects write; command[0]=1
                         * selects read. Any nonzero prefix is invalid.
                         */
                        command_is_write <=
                            !command_prefix_nonzero &&
                            !spi_mosi_internal;

                        command_is_read <=
                            !command_prefix_nonzero &&
                            spi_mosi_internal;
                    end else if (bit_count < 6'd16) begin
                        /*
                         * Shift the address directly into the register-bus
                         * address output, eliminating a duplicate register.
                         */
                        reg_addr <= {
                            reg_addr[6:0],
                            spi_mosi_internal
                        };
                    end else if ((bit_count < 6'd48) &&
                                 command_is_write) begin
                        /*
                         * Shift write data directly into reg_wdata. On the
                         * final bit, reg_write is asserted. The register file
                         * observes the completed reg_wdata value with the
                         * one-clock reg_write pulse on the following clk edge.
                         */
                        reg_wdata <= {
                            reg_wdata[30:0],
                            spi_mosi_internal
                        };

                        if (bit_count == 6'd47) begin
                            reg_write <= 1'b1;
                        end
                    end

                    if (bit_count < 6'd48) begin
                        bit_count <= bit_count + 6'd1;
                    end
                end

                /*
                 * SPI mode 0: update MISO on falling SCLK edges.
                 *
                 * After the address byte has been received, reg_addr has had
                 * time to propagate through the asynchronous register-file
                 * read mux. Load reg_rdata before the first data bit is
                 * sampled by the SPI controller.
                 */
                if (spi_sclk_falling && command_is_read) begin
                    if (bit_count == 6'd16) begin
                        reg_wdata <= reg_rdata;
                    end else if ((bit_count > 6'd16) &&
                                 (bit_count <= 6'd48)) begin
                        reg_wdata <= {
                            reg_wdata[30:0],
                            1'b0
                        };
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
