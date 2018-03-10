-- Purpose of the ClockGen entity: generates 5 clock signals and a logic ready signal for the entities in 
-- the 'common' folder. There are 1MHz, 8MHz, 10MHz (x2), and 80MHz clocks

library ieee;
library unisim;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use unisim.vcomponents.all;
use work.types.all;

-- Input(s): Oscillator
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
	-- IBUFG = global input clock buffer
    -- This block's purpose is to route the input Oscillator signal through a buffer (IBUFG)
	InputGlobalBuffer : IBufG
	port map(
		I => Oscillator,
		O => OscillatorBuffered);

	-- Input from the oscillator is 8 MHz.???? how, the ESC-3953 outputs a 50MHz signal
	-- CLKFX output (PLLInputClock) is 8 × 5 = 40 MHz.
	StepUpDCM : DCM 
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

	PLLReset <= StepUpDCMStatus(2) or not StepUpDCMLocked;

	-- PLLInputClock is 40 MHz.
	-- VCO is 40 × 16 = 640 MHz.
	-- Take the PLL base frequency of 40MHz and use to create 4 clocks 
	-- generic mapping: passes information to the entity, in this case divide values are defined
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

	-- connects pins
	-- this block connects the PLL output signals to the appropriate output clock
	-- port map syntax: port_name => signal_name
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

	-- matches the PLL outputs (the various clock outputs) to the global buffer and then outputs the buffered PLL outputs
	BufferGs : for Index in PLLOutputs'range generate
		BufferG : BUFG
		port map(
			I => PLLOutputs(Index),
			O => BufferedPLLOutputs(Index));
	end generate;

	-- assigns buffered PLL clock outputs to the matching desired clocks
	Clock8MHz <= BufferedPLLOutputs(0);
	Clock10MHz <= BufferedPLLOutputs(1);
	Clock10MHzI <= BufferedPLLOutputs(2);
	Clock80MHz <= BufferedPLLOutputs(3);

	-- DCM takes input at 8 MHz from PLL and produces output at 1 MHz.
	-- this is PLL driving DCM formn (other form is DCM driving PLL). This option reduces clock jitter
	StepDownDCMReset <= not PLLLocked;
	-- DCM does not exist in S7s

	-- generic mapping for the frequency step down block: takes 8MHz as an input and outputs a 1MHz signal
	-- syntax for generic mapping names = instance_name : component_name
	-- for this block, StepDownDCM is the instance name of the DCM_SP
	-- DCM_SP is a primitive. The other DCM primitive for S6s is DCM_CLKGEN. 
	-- DCM_SP is the traditional primitive, and DCM_CLKGEN is used for more advanced DFS (digital frequency synthesizer) properties
	-- In the S7, MMCM and PLL have two primitives each: E2_BASE and E2_ADV (ex:MMCME2_BASE)
	StepDownDCM : DCM_SP
	generic map(
		CLKIN_PERIOD => 1.0e9 / 8.0e6,
		CLK_FEEDBACK => "1X",
		CLKDV_DIVIDE => 8.0)
	-- maps the DCM ports with the signals (again, port => signal)
	port map(
		CLKIN => BufferedPLLOutputs(0),
		CLKFB => StepDownDCMFeedbackBuffered,
		RST => StepDownDCMReset,
		CLK0 => StepDownDCMFeedback,
		CLKDV => StepDownDCMOut,
		LOCKED => StepDownDCMLocked);
	
	-- maps feedback buffer ports with signals
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
