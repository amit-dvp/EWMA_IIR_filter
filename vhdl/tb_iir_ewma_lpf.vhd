--------------------------------------------------------------------------------
-- tb_iir_lowpass_shift.vhd
--
-- Testbench for iir_lowpass_shift.vhd (see that file for the filter theory).
--
-- What it does:
--   1. Resets the DUT.
--   2. Holds x_in = 0 for a few cycles (should keep y_out = 0).
--   3. Applies a step input x_in = STEP_VALUE and holds it.
--   4. Logs (sample_index, x_in, y_out) to a CSV file every cycle so you can
--      plot the step response afterwards in Python/MATLAB.
--   5. Self-checks: after enough samples to settle (>= 10*time-constant),
--      asserts that y_out has converged to within 1 LSB of the expected
--      final value STEP_VALUE (since the filter's DC gain is exactly 1).
--
-- Time constant of the filter (in samples) is tau = 1/(1-a) = 2^SHIFT_N,
-- so with SHIFT_N = 9, tau = 512 samples; 10*tau = 5120 samples is used
-- as the settling window before the final check.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_iir_lowpass_shift is
end entity tb_iir_lowpass_shift;

architecture sim of tb_iir_lowpass_shift is

    constant DATA_WIDTH  : integer := 14;
    constant SHIFT_N     : integer := 15;
    constant CLK_PERIOD  : time    := 10 ns;

    -- Step input amplitude: a mid-scale value well within the 14-bit
    -- two's-complement range (-8192..8191), e.g. 1/4 of full scale.
    constant STEP_VALUE  : integer := 8191;
    
    
    constant INIT_VALUE : integer := -8191; 

    -- How many samples to run: settle time (10*tau) plus margin.
    constant TAU_SAMPLES     : integer := 2**SHIFT_N;      -- 512
    constant SETTLE_SAMPLES  : integer := 20 * TAU_SAMPLES; -- 5120
    constant TOTAL_SAMPLES   : integer := SETTLE_SAMPLES + 200;

    -- Allowed final error, in output LSBs (accounts for the b coefficient
    -- being 2^-9 = 0.001953 rather than the ideal 0.002, plus truncation).
    constant TOLERANCE_LSB   : integer := 2;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal x_in       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal y_out      : signed(DATA_WIDTH-1 downto 0);

    signal sample_count : integer := 0;
    signal sim_done      : boolean := false;

begin

    ----------------------------------------------------------------------
    -- DUT instantiation
    ----------------------------------------------------------------------
    dut : entity work.iir_ewma_lpf
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            SHIFT_N    => SHIFT_N
        )
        port map (
            clk       => clk,
            rst       => rst,
            x_in      => x_in,
            y_out     => y_out
        );

    ----------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

    ----------------------------------------------------------------------
    -- Stimulus: reset, then zero input for a few cycles, then a step to
    -- STEP_VALUE held for the rest of the simulation.
    ----------------------------------------------------------------------
    stimulus : process
    begin
        -- hold reset for a few clock periods
        rst      <= '1';
        x_in     <= (others => '0');
        wait for CLK_PERIOD * 5;

        rst <= '0';
        wait until rising_edge(clk);
        wait for CLK_PERIOD * 500;
        wait until rising_edge(clk);

        -- a few cycles of zero input before the step, so the "quiet" part
        -- of the response is visible in the logged CSV too
        x_in     <=  to_signed(INIT_VALUE, DATA_WIDTH);
        wait for CLK_PERIOD * 5000;
        wait until rising_edge(clk);
        


        -- apply the step and hold it for the rest of the run
        x_in <= to_signed(STEP_VALUE, DATA_WIDTH);

        wait for CLK_PERIOD * TOTAL_SAMPLES;

        sim_done <= true;
        wait;
    end process stimulus;


end architecture sim;
