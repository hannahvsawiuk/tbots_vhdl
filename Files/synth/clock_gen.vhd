library ieee;
library unisim;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use unisim.vcomponents.all;
use work.types.all;

entity ClockGen is
	port(
		Oscillator : in std_ulogic;
		Clock1MHz : buffer std_ulogic;
		Clock8MHz : buffer std_ulogic;
		Clock10MHz : buffer std_ulogic;
		Clock10MHzI : buffer std_ulogic;
		Clock80MHz : buffer std_ulogic;
		Ready : buffer boolean);
end entity ClockGen;

architecture Behavioural of ClockGen is
	signal OscillatorBuffered : std_ulogic;
	signal PLLInputClock : std_ulogic;
	signal StepUpDCMStatus : std_logic_vector(7 downto 0);
	signal StepUpDCMLocked : std_ulogic;
	signal PLLReset : std_ulogic;
	signal PLLOutputs : std_ulogic_vector(0 to 5);
	signal PLLFeedbackClock : std_ulogic;
	signal PLLLocked : std_ulogic;
	signal BufferedPLLOutputs : std_ulogic_vector(PLLOutputs'range);
	signal StepDownDCMFeedback : std_ulogic;
	signal StepDownDCMFeedbackBuffered : std_ulogic;
	signal StepDownDCMReset : std_ulogic;
	signal StepDownDCMOut : std_ulogic;
	signal StepDownDCMLocked : std_ulogic;
	signal Clock1MHzTemp : std_ulogic;
begin
	IBufferG : IBufG
	port map(
		I => Oscillator,
		O => OscillatorBuffered);

	-- Input from the oscillator is 8 MHz.
	-- CLKFX output (PLLInputClock) is 8 × 5 = 40 MHz.
	-- DCM_SP replaced by MMCM since DCM_SP is now obsolete for Spartan-7
	StepUpDCM : DCM_SP 
	generic map(
		CLKIN_PERIOD => 1.0e9 / 8.0e6,
		CLK_FEEDBACK => "NONE",
		CLKFX_MULTIPLY => 5,
		CLKFX_DIVIDE => 1)
	port map(
		CLKIN => OscillatorBuffered,
		RST => '0',
		CLKFX => PLLInputClock,
		STATUS => StepUpDCMStatus,
		LOCKED => StepUpDCMLocked);

	-- Status[2] 
	-- CLKFX or CLKFX180 output stopped indicator. Held in reset until the LOCKED output is asserted.
	-- 0: CLKFX and CLKFX180 outputs are toggling
	-- 1: CLKFX and CLKFX180 outputs are not toggling, even though the LOCKED output can still be High. 

	-- Locked
	-- 0: DCM is attempting to lock onto CLKIN frequency. DCM clock outputs are not valid
	-- 1: DCM is locked onto CLKIN frequency. DCM clock outputs are valid

	-- PLL RST is an (active low?) asynchronous reset
	-- PLL will synchronously re-enable itself when this signal is released
	-- A reset is required when the input clock conditions change
	PLLReset <= StepUpDCMStatus(2) or not StepUpDCMLocked;

	-- PLLInputClock is 40 MHz.
	-- VCO is 40 × 16 = 640 MHz.
	MainPLL : PLL_BASE
	generic map(
		CLKOUT0_DIVIDE => 80, -- CLKOUT0 is 640 ÷ 80 = 8
		CLKOUT0_PHASE => 0.0,
		CLKOUT1_DIVIDE => 64, -- CLKOUT1 is 640 ÷ 64 = 10
		CLKOUT1_PHASE => 0.0,
		CLKOUT2_DIVIDE => 64, -- CLKOUT2 is 640 ÷ 64 = 10
		CLKOUT2_PHASE => 180.0,
		CLKOUT3_DIVIDE => 8, -- CLKOUT3 is 640 ÷ 8 = 80
		CLKOUT3_PHASE => 0.0,
		CLKFBOUT_MULT => 16,
		CLKIN_PERIOD => 1.0e9 / 40.0e6,
		CLK_FEEDBACK => "CLKFBOUT")
	port map(
		CLKIN => PLLInputClock,
		CLKFBIN => PLLFeedbackClock,
		RST => PLLReset,
		CLKOUT0 => PLLOutputs(0),
		CLKOUT1 => PLLOutputs(1),
		CLKOUT2 => PLLOutputs(2),
		CLKOUT3 => PLLOutputs(3),
		CLKOUT4 => PLLOutputs(4),
		CLKOUT5 => PLLOutputs(5),
		CLKFBOUT => PLLFeedbackClock,
		LOCKED => PLLLocked);

	BufferGs : for Index in PLLOutputs'range generate
		BufferG : BUFG
		port map(
			I => PLLOutputs(Index),
			O => BufferedPLLOutputs(Index));
	end generate;

	Clock8MHz <= BufferedPLLOutputs(0);
	Clock10MHz <= BufferedPLLOutputs(1);
	Clock10MHzI <= BufferedPLLOutputs(2);
	Clock80MHz <= BufferedPLLOutputs(3);

	-- DCM takes input at 8 MHz from PLL and produces output at 1 MHz.
	StepDownDCMReset <= not PLLLocked;
	-- used to be DCM_SP, but obsolete for Spartan 7
	StepDownDCM : DCM_SP 
	generic map(
		CLKIN_PERIOD => 1.0e9 / 8.0e6,
		CLK_FEEDBACK => "1X",
		CLKDV_DIVIDE => 8.0)
	port map(
		CLKIN => BufferedPLLOutputs(0),
		CLKFB => StepDownDCMFeedbackBuffered,
		RST => StepDownDCMReset,
		CLK0 => StepDownDCMFeedback,
		CLKDV => StepDownDCMOut,
		LOCKED => StepDownDCMLocked);
	StepDownDCMFeedbackBufferG : BUFG
	port map(
		I => StepDownDCMFeedback,
		O => StepDownDCMFeedbackBuffered);
	StepDownDCMOutBufferG : BUFG
	port map(
		I => StepDownDCMOut,
		O => Clock1MHzTemp);
	Clock1MHz <= Clock1MHzTemp;

	-- Report to the higher level whether all clocks are ready to use.
	Ready <= to_boolean(StepUpDCMLocked and PLLLocked and StepDownDCMLocked);
end architecture Behavioural;
