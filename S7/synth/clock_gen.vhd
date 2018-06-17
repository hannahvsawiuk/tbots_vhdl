-- *******************************************************************************************************************
-- Purpose: to generate 5 clock signals (1MHz, 8MHz, 2x10MHz, 80MHz) and 
-- 			a logic ready signal from a 40MHz external oscillator. 
-- 			The outputs of this entity are used by the files in 'common' folder. 
-- *******************************************************************************************************************

-- libraries
library ieee;
library unisim;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use unisim.vcomponents.all;
use work.types.all;

-- *******************************************************************************************************************
-- purpose	: define the entity, the entity's ports, and the port types
-- I/O		
--	Input	: 
-- 			- Oscillator = an 40MHz oscillation
-- 			- Input from the external oscillator is 40MHz -> 25ns period
-- 			- From .ucf file: "timespec "TSOscillator" = PERIOD "Oscillator" 25 ns INPUT_JITTER 1.375 ps"
-- 	Outputs	: ClockXMHz = clock
-- 		      Ready 	= logical operator used to report to the higher level (top entity) whether all clocks are ready to use
-- *******************************************************************************************************************
entity ClockGen is
	port(
		Oscillator 	: in std_ulogic;
		Clock1MHz 	: buffer std_ulogic;
		Clock8MHz 	: buffer std_ulogic;
		Clock10MHz 	: buffer std_ulogic;
		Clock10MHzI : buffer std_ulogic;
		Clock80MHz 	: buffer std_ulogic;
		Ready 		: buffer boolean);
end entity ClockGen;

-- *******************************************************************************************************************
-- purpose	: define the behaviour of the ClockGen entity (the architecture)
-- info		:
-- 			- architecture blocks are like always blocks in Verilog
-- 			- statements in architecture blocks are not necessarily sequential: the behaviour is defined by data dependecies
-- *******************************************************************************************************************
architecture Behavioural of ClockGen is
	-- signal declarations
	signal PLLInputClock 				: std_ulogic;
	signal PLLOutputs 					: std_ulogic_vector(0 to 5);
	signal PLLFeedbackClock 			: std_ulogic;
	signal PLLLocked 					: std_ulogic;
	signal BufferedPLLOutputs 			: std_ulogic_vector(PLLOutputs'range);
	signal StepDownMMCMFeedback 		: std_ulogic;
	signal StepDownMMCMFeedbackBuffered : std_ulogic;
	signal StepDownMMCMReset 			: std_ulogic;
	signal StepDownMMCMOut 				: std_ulogic;
	signal StepDownMMCMLocked 			: std_ulogic;
begin
-- *******************************************************************************************************************
-- purpose	: buffers the output from the external oscillator
-- info		: IBUFG primitive is a clock-capable input buffer
-- *******************************************************************************************************************
	 -- need to keep MMCM to enable IBUFG as input??? no section on PLL input signal restrictions in resources guide
	
	-- IBUFG = global input clock buffer
	InBufferG : IBufG
	port map (
		I => Oscillator,
		O => PLLInputClock
	);
	
-- -- *******************************************************************************************************************
-- -- purpose	: Configure a locked in
-- -- info		:
-- -- 			- Configuration using MMCM advanced primitives 
-- -- 			- The 40MHz signal is fed into a PLL block to generate the 8,10, and 80MHz clocks
-- -- *******************************************************************************************************************
-- 	StepUpMMCM : MMCM 
-- 	generic map (
-- 		CLKIN1_PERIOD 	=> 1.0e9 / 40.0e6, 	-- 40MHz
-- 		CLK_FEEDBACK 	=> "NONE",
-- 		mult 	=> 1, 				
-- 		 div   => 1,				
-- 		BANDWIDTH		=> "LOW" 		    -- reduce clock jitter by setting the BANDWIDTH attribute low
-- 	) 

-- -- =====================================================================================================================
-- -- The LOCKED MMCM/PLL Attribute
-- -- 	LOCKED indicates when the MMCM/PLL has achieved phase alignment 
-- -- 	1: outputs are valid, 0: outputs are invalid
-- -- 	MMCM/PLL automatically locks after power on. No extra reset is required
-- -- 	LOCKED will be deasserted if the input clock stops or the phase alignment is violated
-- -- 	The MMCM/PLL must be reset after LOCKED is deasserted.
-- -- =====================================================================================================================.										
-- 	port map (
-- 		CLKIN1 		=> OscillatorBuffered,
-- 		RST 		=> '0',
-- 		CLKINSEL 	=> '1', 				-- select CLKIN1
-- 		CLKOUT0 	=> PLLInputClock,
-- 		LOCKED 		=> StepUpMMCMLocked
-- 	)

-- 	PLLReset <= not StepUpMMCMLocked; 		-- active high rst so not the LOCKED attribute value



-- *******************************************************************************************************************
-- purpose	: Take the PLL base frequency of 40MHz and create 4 clocks: 8MHz, 2x10MHz, 80MHz
-- info		:
-- 			- VCO is 40 × 16 = 640 MHz.
-- 			- Configuration using PLL attributes
-- *******************************************************************************************************************
	MainPLL : PLLE2_BASE 
	generic map (
		CLKOUT0_DIVIDE 	=> 80, 		-- CLKOUT0 is 640 ÷ 80 = 8
		CLKOUT0_PHASE 	=> 0.0,
		CLKOUT1_DIVIDE 	=> 64, 		-- CLKOUT1 is 640 ÷ 64 = 10
		CLKOUT1_PHASE 	=> 0.0,
		CLKOUT2_DIVIDE	=> 64, 		-- CLKOUT2 is 640 ÷ 64 = 10
		CLKOUT2_PHASE 	=> 180.0,
		CLKOUT3_DIVIDE	=> 8,  		-- CLKOUT3 is 640 ÷ 8  = 80
		CLKOUT3_PHASE 	=> 0.0,
		CLKFBOUT_MULT 	=> 16,		-- all output multiplier
		CLKIN1_PERIOD 	=> 1.0e9 / 40.0e6,	-- 40 MHz input
		BANDWIDTH		=> "OPTIMIZED"  	
	)

-- *******************************************************************************************************************
-- purpose	: Connect the PLL output signals to the appropriate output clock
-- info		: See PLLE2_BASE port list
-- ******************************************************************************************************************* 
	
-- =====================================================================================================================
-- The RST Attribute
-- RST is an active HIGH asynchronous reset
-- PLL will synchronously re-enable itself when this signal is released
-- A reset is required when the input clock conditions change
-- =====================================================================================================================.
	
	port map (
		CLKIN1 		=> PLLInputClock,
		CLKFBIN 	=> PLLFeedbackClock,
		RST 		=> '0',				-- keep reset deasserted
		CLKOUT0 	=> PLLOutputs(0),
		CLKOUT1 	=> PLLOutputs(1),
		CLKOUT2 	=> PLLOutputs(2),
		CLKOUT3 	=> PLLOutputs(3),
		CLKOUT4 	=> PLLOutputs(4),
		CLKOUT5 	=> PLLOutputs(5),
		CLKFBOUT 	=> PLLFeedbackClock,
		LOCKED		=> PLLLocked
	);

	-- purpose: matches the PLL outputs (the various clock outputs) to the global buffer and then outputs the buffered PLL outputs
	BufferGs : for Index in PLLOutputs'range generate
		BufferG : BUFG
		port map (
			I => PLLOutputs(Index),
			O => BufferedPLLOutputs(Index)
		);
	end generate;

	-- assigns buffered PLL clock outputs to the matching desired clocks
	Clock8MHz 	<= BufferedPLLOutputs(0);
	Clock10MHz 	<= BufferedPLLOutputs(1);
	Clock10MHzI <= BufferedPLLOutputs(2);
	Clock80MHz 	<= BufferedPLLOutputs(3);

	-- MMCM takes input at 40 MHz from PLL and produces output at 1 MHz.
	StepDownMMCMReset <= not PLLLocked;

	-- generic mapping for the frequency step down block: takes 40MHz as an input and outputs a 1MHz signal
	StepDownMMCM : MMCME2_ADV
	generic map (
		CLKIN1_PERIOD 	=> 1.0e9 / 40.0e6,
		COMPENSATION	=> "INTERNAL",
		CLKOUT_DIVIDE 	=> 40.0
	)

	port map (
		CLKIN1 		=> BufferedPLLOutputs(0),
		CLKINSEL 	=> '1',
		CLKFBIN 	=> StepDownMMCMFeedbackBuffered,
		RST 		=> StepDownMMCMReset,
		CLKFBOUTB 	=> StepDownMMCMFeedback,
		CLKOUT0 	=> StepDownMMCMOut,
		LOCKED 		=> StepDownMMCMLocked
	);
	
	-- maps feedback buffer ports with signals. Need to buffer the feedback signals before feeding them back to the MMCM
	StepDownMMCMFeedbackBufferG : BUFG
	port map (
		I => StepDownMMCMFeedback,
		O => StepDownMMCMFeedbackBuffered
	);

	StepDownMMCMOutBufferG : BUFG
	port map (
		I => StepDownMMCMOut,
		O => Clock1MHz
	);

	-- Report to the higher level whether all clocks are ready to use.
	Ready <= to_boolean(PLLLocked and StepDownMMCMLocked);
end architecture Behavioural;



end