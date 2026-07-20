// A measurement begins on a synchronized rising edge and completes after
// gate_cycles additional rising edges, representing gate_cycles full periods.
//
// Example for gate_cycles = 4:
//
//     E0 ---- E1 ---- E2 ---- E3 ---- E4
//     start    1       2       3       4 / complete
//
// The completion edge is not reused as the start edge of the next measurement.
// The next measurement therefore begins at E5.
//
// Configuration inputs are captured at measurement start so changes made while
// active apply to the next measurement.
//
// A timeout or reference-counter overflow discards the partial measurement.
// The last valid measured_ref_count remains unchanged.

`default_nettype none

module reciprocal_channel (
    input wire          clk,                    //Reference-clock
    input wire          rst_n,                  //Active low synchronous reset
    input wire          signal_in,              //Asynchronous singal being measured
    
    input wire [31:0]   gate_cycles,            //Number of complete periods measured.  gate_cycles == 0 disables the channel
    input wire [31:0]   timeout_refcount,       //Maximum reference-clock cycles allowed for one measurement. Value 0 disables timeout monitoring.
    
    input wire          clear_timeout_latched,  //Clear controls, to be driven by the register interface.
    input wire          clear_timeout_count,
    input  wire         clear_overflow_latched,

    output reg [31:0]   measured_ref_count,     //Latest valid reference-clock count
    output reg [31:0]   completed_count,        //Number of valid completed measurements
    output reg [31:0]   timeout_count,          //Number of discarded timeout measurements

    output reg          measurement_valid,      //High for a clock cycle for every measured_ref_count udpate
    output reg          timeout_latched,        //Sticky timeout indication
    output reg          overflow_latched,       // Sticky reference-counter overflow indication
    output reg          active                  //High while measurment is active
);

    // ------------------------------------------------------------------------
    // Input synchronizer and edge detector
    // ------------------------------------------------------------------------

    reg    signal_sync_ff1;
    reg    signal_sync_ff2;
    reg    signal_sync_delayed;

    wire   signal_rising_edge;

    assign signal_rising_edge = signal_sync_ff2 && !signal_sync_delayed;

    // ------------------------------------------------------------------------
    // Local measurement registers
    // ------------------------------------------------------------------------

    reg [31:0] reference_count;
    reg [31:0] period_count;
    reg [31:0] active_gate_cycles;
    reg [31:0] active_timeout_refcount;

    // ------------------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------------------

    always @(posedge clk) begin
        if (!rst_n) begin
            signal_sync_ff1     <= 1'b0;
            signal_sync_ff2     <= 1'b0;
            signal_sync_delayed <= 1'b0;
    
            measured_ref_count  <= 32'b0;
            measurement_valid   <= 1'b0;
            active              <= 1'b0;

            reference_count     <= 32'd0;
            period_count        <= 32'b0;
            active_gate_cycles  <= 32'b0;
            completed_count     <= 32'd0;

            timeout_count           <= 32'd0;
            timeout_latched         <= 1'b0;
            overflow_latched        <= 1'b0;
            active_timeout_refcount <= 32'd0;
        end else begin
            // Synchronize the asynchronous input to clk domain
            signal_sync_ff1      <= signal_in;
            signal_sync_ff2      <= signal_sync_ff1;
            signal_sync_delayed  <= signal_sync_ff2; 

            //Default low; asserted only when a valid result is written.
            //measurment_valid is one clock pulse.
            measurement_valid    <= 1'b0;
            
            if (clear_overflow_latched) begin
                overflow_latched <= 1'b0;
            end

            // Sticky diagnostic clears. A new fault later in this block
            // takes priority over a simultaneous clear request.
            if (clear_timeout_latched) begin
                timeout_latched <= 1'b0;
            end

            if (clear_timeout_count) begin
                timeout_count <= 32'd0;
            end

            if (!active) begin
                reference_count <= 32'd0;
                period_count    <= 32'b0;

                if ((gate_cycles != 32'd0) && signal_rising_edge) begin
                    active                      <= 1'b1;                
                    active_gate_cycles          <= gate_cycles;         //Freeze the value of gate_cycles for this measurment cycle
                    active_timeout_refcount     <= timeout_refcount;    //Freeze the value of timeout_refcount for this measurement cycle
                end else begin
                    active      <= 1'b0;
                end
            end else begin
                reference_count <= reference_count + 32'd1;

                // Event priority:
                // 1. Valid completion
                // 2. Timeout
                // 3. Reference-counter overflow
                // 4. Intermediate input edge
                if (signal_rising_edge &&
                    ((period_count + 32'd1) >= active_gate_cycles)) begin

                    measured_ref_count <= reference_count + 32'd1;
                    measurement_valid  <= 1'b1;
                    completed_count    <= completed_count + 32'd1;

                    active             <= 1'b0;
                    period_count       <= 32'd0;
                    reference_count    <= 32'd0;

                end else if ((active_timeout_refcount != 32'd0) &&
                             ((reference_count + 32'd1) >=
                              active_timeout_refcount)) begin

                    // Discard the partial measurement and preserve the
                    // previous valid measured_ref_count.
                    timeout_latched <= 1'b1;
                    timeout_count   <= timeout_count + 32'd1;

                    active          <= 1'b0;
                    period_count    <= 32'd0;
                    reference_count <= 32'd0;

                end else if (reference_count == 32'hFFFF_FFFF) begin
                // Do not allow the running counter to wrap.
                    overflow_latched <= 1'b1;

                    active           <= 1'b0;
                    period_count     <= 32'd0;
                    reference_count  <= 32'd0;

                end else if (signal_rising_edge) begin

                    // One more complete input period has elapsed.
                    period_count <= period_count + 32'd1;
                end
            end
        end
    end

endmodule

`default_nettype wire
