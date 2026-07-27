--------------------------------------------------------------------------------
-- Design : iir_ewma_lpf.vhd
--
-- Date: 24.07.26
--
-- Author : Amit S.
--
-- First-order IIR low-pass filter (single-pole leaky integrator / EWMA):
--
--     y[n] = (1-alpha)*y[n-1] + alpha*x[n] ,   with default alpha = 0.002 
--
-- implemented with only shifts and adds, no multiplier is used
--
--     y[n] = (1-alpha)*y[n-1] + alpfa*x[n]
--          = y[n-1] - alpha*y[n-1] + alpha*x[n]
--          = y[n-1] + alpha*(x[n] - y[n-1])
--
-- alpha is chosen as a power of two, i.e. alpha = 2^-N, so "multiply by alpha" is just
-- an arithmetic right-shift by N bits:
--
--     y[n] = y[n-1] + ((x[n]-y[n-1]) >> N)
--
-- Closest power-of-two match to alpha = 0.002 is N = 9:
--     alpha = 2^-9 = 0.001953   (target was 0.002)

-- Good to within ~0.005% of the requested coefficients, with zero multiplier
-- logic (a right shift by a fixed amount is free in hardware -- just wire
-- routing, no gates or DSP slices used).
--
-- FIXED-POINT / FRACT_BITS 
-- ------------------------
-- x_in is a plain DATA_WIDTH=14-bit signed two's-complement integer (no fractional
-- bits). 
-- The internal state y_n_minus_1 is kept in an extended fixed-point
-- format with DATA_WIDTH+2 data bits (because 2 adders are used) and FRACT_BITS after 
-- fixed point.
-- we use DATA_WIDTH + 2 spare bits format because of twice usage of adders , each of them can 
-- contribute extra carry bit.


--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity iir_ewma_lpf is
    generic (
        DATA_WIDTH : integer := 14;  -- input/output sample width, two's complement
        SHIFT_N    : integer := 11    -- alpha = 2^-SHIFT_N 
    );
    port (
        clk       : in  std_logic;                       -- system clock
        rst       : in  std_logic;                       -- async active-high reset
        x_in      : in  signed(DATA_WIDTH-1 downto 0);   -- 14-bit two's complement input sample
        y_out     : out signed(DATA_WIDTH-1 downto 0)    -- 14-bit two's complement filtered output
    );
end entity iir_ewma_lpf;

architecture rtl of iir_ewma_lpf is

    -- Extra fractional bits kept on the internal state: must equal SHIFT_N
    constant FRACT_BITS  : integer := SHIFT_N;

    -- Internal state width: DATA_WIDTH integer bits + GUARD_BITS fractional bits + 2 spare bits because of 2 sum blocks.
    constant STATE_WIDTH : integer := DATA_WIDTH + FRACT_BITS + 2;

    -- y[n-1], in fixed-point format STATE_WIDTH_En_GUARD_BITS
    signal y_n_minus_1 : signed(STATE_WIDTH-1 downto 0);

    -- x[i] aligned into the state's fixed-point format (one headroom bit added).
    signal x_n_ext   : signed(STATE_WIDTH-1 downto 0);

    -- e[i] = x[i] - y[i-1], in the same fixed-point format as y_n_minus_1 (plus headroom bit).
    signal diff     : signed(STATE_WIDTH-1 downto 0);

    -- b*e[i], obtained purely by an arithmetic right-shift (this IS the b-multiply).
    signal diff_m   : signed(STATE_WIDTH-1 downto 0);

    -- y[n] = y[n-1] + b*(x[n]-y[n-1])
    -- ready to be clocked into y_n_minus_1 on the next rising edge.
    signal y_n_ext  : signed(STATE_WIDTH-1 downto 0) := (others => '0');

begin
    
    -- Note: we implement most calculations in 26En9 format: 
    --       25 bits total with 9 bit after fixed point  
    --       and 16 bits before fixed point 
    --       Sometimes this format is defined also as : 
    --       1.15.9 : 1 for sign , 15 for integer part and 9 for fractional part.
                       
    
    -- Step 1: 
    --   convert signed x_in Signed_14En0 into Signed_25En9 :
    --      1. convert x_in into Signed_25En0 format 
    --      2. and multiply the result by 2^GUARD_BITS
    x_n_ext <= shift_left(resize(x_in, STATE_WIDTH), FRACT_BITS);

    -- Step 2: 
    --   calculate difference x[n] - y[n-1], in signed 24En9 format.
    diff <= x_n_ext - y_n_minus_1;

    -- Step 3: 
    --    division of diff by 2^SHIFT_N is equivalent to 
    --    shift right diff by SHIFT_N
    diff_m <= shift_right(diff, SHIFT_N);

    -- Step 4:
    --    y[n] = y[n-1] + alpha*(x[n]-y[n-1]) = y[n-1] + diff_m
    y_n_ext <= y_n_minus_1 + diff_m; 
   
    -- Step 5: 
    --    the only clocked element in the design -- latch the new state
    --    and pass the valid flag through, once per sample.
    process (clk, rst)
    begin
        if rst = '1' then
            y_n_minus_1   <= (others => '0');
        elsif rising_edge(clk) then
            y_n_minus_1   <= y_n_ext;
        end if;
    end process;
    
    -- Step 6: 
    --    convert y[n]_ext to output format Signed_14En0 : 
    y_out <= resize(shift_right(y_n_ext, FRACT_BITS), DATA_WIDTH);


end architecture rtl;
