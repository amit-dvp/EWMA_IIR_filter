// -----------------------------------------------------------------------------
// tb_iir_ewma_lpf.v
//
// 
//
// Testbench for iir_ewma_lpf.v (see that file for the filter theory).
//
// What it does:
//   1. Resets the DUT.
//   2. Holds x_in = 0 for a few cycles.
//   3. Holds x_in = INIT_VALUE for a while (settles toward a negative level).
//   4. Applies a step input x_in = STEP_VALUE and holds it for the rest of
//      the run, so the step response can be observed (e.g. in a waveform
//      viewer) after the settle window.
//
// Time constant of the filter (in samples) is tau = 1/alpha = 2^SHIFT_N,
// so with SHIFT_N = 9, tau = 512 samples; 10*tau = 5120 samples is used
// as the settling window before the final step is applied/observed.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_iir_ewma_lpf;

    localparam DATA_WIDTH = 14;
    localparam SHIFT_N    = 9;
    localparam CLK_PERIOD = 10; // ns

    // Step input amplitude: full positive scale of the 14-bit two's
    // complement range (-8192..8191).
    localparam signed [DATA_WIDTH-1:0] STEP_VALUE = 8191;

    localparam signed [DATA_WIDTH-1:0] INIT_VALUE = -8191;

    // How many samples to run: settle time (10*tau) plus margin.
    localparam TAU_SAMPLES    = 2**SHIFT_N;        // 512
    localparam SETTLE_SAMPLES = 20 * TAU_SAMPLES;  // 5120
    localparam TOTAL_SAMPLES  = SETTLE_SAMPLES + 200;

    reg                          clk;
    reg                          rst;
    reg  signed [DATA_WIDTH-1:0] x_in;
    wire signed [DATA_WIDTH-1:0] y_out;

    //--------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------
    iir_ewma_lpf #(
        .DATA_WIDTH (DATA_WIDTH),
        .SHIFT_N    (SHIFT_N)
    ) dut (
        .clk   (clk),
        .rst   (rst),
        .x_in  (x_in),
        .y_out (y_out)
    );

    //--------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //--------------------------------------------------------------------
    // Stimulus: reset, then zero input for a few cycles, then INIT_VALUE
    // for a while, then a step to STEP_VALUE held for the rest of the run.
    //--------------------------------------------------------------------
    initial begin
        // hold reset for a few clock periods
        rst  = 1'b1;
        x_in = {DATA_WIDTH{1'b0}};
        #(CLK_PERIOD*5);

        rst = 1'b0;
        @(posedge clk);
        #(CLK_PERIOD*500);
        @(posedge clk);

        // a few thousand cycles at INIT_VALUE before the step, so the
        // "settling toward a negative level" part of the response is
        // visible too
        x_in = INIT_VALUE;
        #(CLK_PERIOD*5000);
        @(posedge clk);

        // apply the step and hold it for the rest of the run
        x_in = STEP_VALUE;

        #(CLK_PERIOD*TOTAL_SAMPLES);

        $finish;
    end

endmodule
