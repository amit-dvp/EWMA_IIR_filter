// -----------------------------------------------------------------------------
// Design : iir_ewma_lpf.v
//
// Date: 26.07.26
//
// Author : Amit S.
//
// First-order IIR low-pass filter (single-pole leaky integrator / EWMA):
//
//     y[n] = (1-alpha)*y[n-1] + alpha*x[n] ,   with default alpha = 0.002
//
// implemented with only shifts and adds, no multiplier is used
//
//     y[n] = (1-alpha)*y[n-1] + alpha*x[n]
//          = y[n-1] - alpha*y[n-1] + alpha*x[n]
//          = y[n-1] + alpha*(x[n] - y[n-1])
//
// alpha is chosen as a power of two, i.e. alpha = 2^-N, so "multiply by alpha"
// is just an arithmetic right-shift by N bits:
//
//     y[n] = y[n-1] + ((x[n]-y[n-1]) >>> N)
//
// Closest power-of-two match to alpha = 0.002 is N = 9:
//     alpha = 2^-9 = 0.001953   (target was 0.002)
//
// Good to within ~0.005% of the requested coefficient, with zero multiplier
// logic (a right shift by a fixed amount is free in hardware -- just wire
// routing, no gates or DSP slices used).
//
// FIXED-POINT / FRACT_BITS
// ------------------------
// x_in is a plain DATA_WIDTH=14-bit signed two's-complement integer (no
// fractional bits).
// The internal state y_n_minus_1 is kept in an extended fixed-point format
// with DATA_WIDTH+2 extra integer bits (because 2 adders are used) and
// FRACT_BITS fractional bits below the binary point.
// We use DATA_WIDTH + 2 spare bits because of the two uses of adders below,
// each of which can contribute an extra carry bit.
//
// STATE_WIDTH = DATA_WIDTH + FRACT_BITS + 2  (with defaults: 14+9+2 = 25 bits)
// -----------------------------------------------------------------------------

module iir_ewma_lpf #(
    parameter DATA_WIDTH = 14,   // input/output sample width, two's complement
    parameter SHIFT_N    = 9     // alpha = 2^-SHIFT_N
) (
    input  wire                         clk,    // system clock
    input  wire                         rst,    // async active-high reset
    input  wire signed [DATA_WIDTH-1:0] x_in,   // 14-bit two's complement input sample
    output wire signed [DATA_WIDTH-1:0] y_out   // 14-bit two's complement filtered output
);

    // Extra fractional bits kept on the internal state: must equal SHIFT_N
    localparam FRACT_BITS  = SHIFT_N;

    // Internal state width: DATA_WIDTH integer bits + FRACT_BITS fractional
    // bits + 2 spare bits because of the 2 adders below.
    localparam STATE_WIDTH = DATA_WIDTH + FRACT_BITS + 2;

    // y[n-1], in fixed-point format Signed_STATE_WIDTH_En_FRACT_BITS
    reg  signed [STATE_WIDTH-1:0] y_n_minus_1;

    // x[n] sign-extended to STATE_WIDTH width (0 fractional bits so far)
    wire signed [STATE_WIDTH-1:0] x_n_wide;

    // x[n] aligned into the state's fixed-point format (scaled by 2^FRACT_BITS)
    wire signed [STATE_WIDTH-1:0] x_n_ext;

    // e[n] = x[n] - y[n-1], in the same fixed-point format as y_n_minus_1
    wire signed [STATE_WIDTH-1:0] diff;

    // alpha*e[n], obtained purely by an arithmetic right-shift (this IS the
    // alpha-multiply)
    wire signed [STATE_WIDTH-1:0] diff_m;

    // y[n] = y[n-1] + alpha*(x[n]-y[n-1])
    // ready to be clocked into y_n_minus_1 on the next rising edge.
    wire signed [STATE_WIDTH-1:0] y_n_ext;

    // y[n] after dropping the FRACT_BITS fractional bits (still STATE_WIDTH
    // wide at this point, output stage below narrows it to DATA_WIDTH)
    wire signed [STATE_WIDTH-1:0] y_n_shifted;

    // Note: with the default parameters we implement most calculations in
    // Signed_25_En_9 format:
    //       25 bits total, 9 bits after the binary point,
    //       16 bits before the binary point (1 sign + 15 integer bits).
    //       Sometimes written as Q(15).9 / "1.15.9" notation: 1 for sign,
    //       15 for integer part, 9 for fractional part.

    // Step 1:
    //   convert signed x_in (Signed_14_En_0) into Signed_25_En_9:
    //      1. sign-extend x_in into Signed_25_En_0 format (x_n_wide)
    //      2. multiply the result by 2^FRACT_BITS (arithmetic left shift)
    assign x_n_wide = {{(STATE_WIDTH-DATA_WIDTH){x_in[DATA_WIDTH-1]}}, x_in};
    assign x_n_ext  = x_n_wide <<< FRACT_BITS;

    // Step 2:
    //   calculate difference x[n] - y[n-1], in Signed_25_En_9 format.
    assign diff = x_n_ext - y_n_minus_1;

    // Step 3:
    //    division of diff by 2^SHIFT_N is equivalent to an arithmetic
    //    right-shift of diff by SHIFT_N bits (sign-preserving, <<< / >>>
    //    are required here instead of </> to keep the shift arithmetic
    //    on signed values).
    assign diff_m = diff >>> SHIFT_N;

    // Step 4:
    //    y[n] = y[n-1] + alpha*(x[n]-y[n-1])
    assign y_n_ext = y_n_minus_1 + diff_m;

    // Step 5:
    //    the only clocked element in the design -- latch the new state
    //    once per sample.
    always @(posedge clk or posedge rst) begin
        if (rst)
            y_n_minus_1 <= {STATE_WIDTH{1'b0}};
        else
            y_n_minus_1 <= y_n_ext;
    end

    // Step 6:
    //    convert y[n]_ext back to the output format Signed_14_En_0:
    //      1. arithmetic right-shift by FRACT_BITS to drop the fractional bits
    //      2. take the low DATA_WIDTH bits (equivalent to VHDL's resize()
    //         truncation when narrowing a signed value)
    assign y_n_shifted = y_n_ext >>> FRACT_BITS;
    assign y_out       = y_n_shifted[DATA_WIDTH-1:0];

endmodule
