library ieee;
library unisim;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use unisim.vcomponents.all;
use work.commands.all;
use work.types.all;

entity Top is
	port(
		OscillatorPin : in std_ulogic;

		ICBCSPin : in std_ulogic;
		ICBClockPin : in std_ulogic;
		ICBMOSIPin : in std_ulogic;
		ICBMISOPin : buffer std_ulogic;
		ICBInterruptPin : buffer std_ulogic;

		IDPin : in std_ulogic_vector(2 downto 0);
		ChannelPin : in std_ulogic_vector(1 downto 0);

		MRFCSPin : buffer std_ulogic;
		MRFClockPin : out std_ulogic;
		MRFMOSIPin : buffer std_ulogic;
		MRFMISOPin : in std_ulogic;
		MRFResetPin : buffer std_ulogic;
		MRFWakePin : buffer std_ulogic;
		MRFInterruptPin : in std_ulogic;

		TestLEDsPin : buffer std_ulogic_vector(2 downto 0);

		AccelCSPin : buffer std_ulogic;
		AccelClockPin : out std_ulogic;
		AccelMOSIPin : buffer std_ulogic;
		AccelMISOPin : in std_ulogic;
		AccelInterruptPin : in std_ulogic;

		GyroCSPin : buffer std_ulogic;
		GyroClockPin : out std_ulogic;
		GyroMOSIPin : buffer std_ulogic;
		GyroMISOPin : in std_ulogic;
		GyroInterruptPin : in std_ulogic;

		EncodersPin : in encoders_pin_t;

		MotorsPhasesHPin : buffer motors_phases_pin_t;
		MotorsPhasesLPin : buffer motors_phases_pin_t;

		HallsPin : in halls_pin_t);
end entity Top;

architecture Main of Top is
	signal Clock1MHz, Clock8MHz, Clock10MHz, Clock10MHzI, Clock80MHz : std_ulogic;
	signal ClocksReady : boolean;

	signal Reset : boolean; -- active high reset

	constant ICB_OUTPUT_COUNT : natural := 11;
	signal ICBInput : icb_input_t;
	signal ICBOutput : icb_outputs_t(0 to ICB_OUTPUT_COUNT - 1);

	constant ICB_INTERRUPT_COUNT : natural := 5;
	signal ICBInterrupts : boolean_vector(0 to ICB_INTERRUPT_COUNT - 1);

	signal DeviceDNA : std_ulogic_vector(54 downto 0);
	signal DeviceDNAReady : boolean;

	signal TestLEDsMode : std_ulogic_vector(7 downto 0);
	signal TestLEDsValue : std_ulogic_vector(7 downto 0);

	signal MRFClockOE : boolean;
	signal AccelClockOE : boolean;
	signal GyroClockOE : boolean;

	type hall_filter_widths_t is array(0 to 4) of positive;
	constant HALL_FILTER_WIDTHS : hall_filter_widths_t := (80, 80, 80, 80, 800);
	signal HallsPinFiltered : halls_pin_t;
	signal HallsPinFilteredValid : halls_pin_valid_t;
begin
	-- Generate system clocks.
	ClockGen : entity work.ClockGen(Behavioural)
	port map(
		Oscillator => OscillatorPin,
		Clock1MHz => Clock1MHz,
		Clock8MHz => Clock8MHz,
		Clock10MHz => Clock10MHz,
		Clock10MHzI => Clock10MHzI,
		Clock80MHz => Clock80MHz,
		Ready => ClocksReady);

	-- Assert system reset for 16 cycles of the slowest clock after all clocks have started up, then release.
	-- This needs to be enough cycles to fill the majority detector shift registers with zeroes.
	-- Those detectors run at 80 MHz.
	-- The largest detector width is 800.
	-- So, that means we need 10 cycles of the 1 MHz clock.
	-- 16 cycles is plenty.
	process(ClocksReady, Clock1MHz) is
		variable ResetShifter : std_ulogic_vector(15 downto 0) := X"0000";
	begin
		if not ClocksReady then
			ResetShifter := X"0000";
		elsif rising_edge(Clock1MHz) then
			ResetShifter := '1' & ResetShifter(15 downto 1);
		end if;
		Reset <= not to_boolean(ResetShifter(0));
	end process;

	-- Instantiate the inter-chip bus transceiver.
	ICB : entity work.ICB(RTL)
	generic map(
		EndpointCount => ICB_OUTPUT_COUNT)
	port map(
		HostClock => Clock80MHz,
		BusClock => ICBClockPin,
		CSPin => ICBCSPin,
		MOSIPin => ICBMOSIPin,
		MISOPin => ICBMISOPin,
		Input => ICBInput,
		Outputs => ICBOutput,
		CRCErrorIRQ => ICBInterrupts(3));

	-- Instantiate the interrupt controller.
	InterruptController : entity work.InterruptController(RTL)
	generic map(
		Count => ICB_INTERRUPT_COUNT)
	port map(
		Reset => Reset,
		HostClock => Clock80MHz,
		ICBIn => ICBInput,
		ICBOut => ICBOutput(0),
		InterruptPin => ICBInterruptPin,
		IRQs => ICBInterrupts);

	-- Instantiate the device DNA reader.
	DNA : entity work.DeviceDNA(RTL)
	port map(
		Reset => Reset,
		Clock1MHz => Clock1MHz,
		Ready => DeviceDNAReady,
		Value => DeviceDNA);
	DNAReader : entity work.ReadableRegister(RTL)
	generic map(
		Command => COMMAND_READ_DNA,
		Length => 7)
	port map(
		Reset => Reset,
		HostClock => Clock80MHz,
		ICBIn => ICBInput,
		ICBOut => ICBOutput(1),
		Value(0) => DeviceDNA(7 downto 0),
		Value(1) => DeviceDNA(15 downto 8),
		Value(2) => DeviceDNA(23 downto 16),
		Value(3) => DeviceDNA(31 downto 24),
		Value(4) => DeviceDNA(39 downto 32),
		Value(5) => DeviceDNA(47 downto 40),
		Value(6)(7) => to_stdulogic(DeviceDNAReady),
		Value(6)(6 downto 0) => DeviceDNA(54 downto 48),
		AtomicReadClearStrobe => open);

	-- Instantiate the configuration DIP switch reader.
	SwitchReader : entity work.ReadableRegister(RTL)
	generic map(
		Command => COMMAND_READ_SWITCHES,
		Length => 2)
	port map(
		Reset => Reset,
		HostClock => Clock80MHz,
		ICBIn => ICBInput,
		ICBOut => ICBOutput(2),
		Value(0)(7 downto 3) => "00000",
		Value(0)(2 downto 0) => IDPin,
		Value(1)(7 downto 2) => "000000",
		Value(1)(1) => ChannelPin(1),
		Value(1)(0) => ChannelPin(0),
		AtomicReadClearStrobe => open);

	-- Instantiate the LED driver.
	LEDWriter : entity work.WritableRegister(RTL)
	generic map(
		Command => COMMAND_WRITE_LEDS,
		Length => 2,
		ResetValue => (X"00", X"07"))
	port map(
		Reset => Reset,
		HostClock => Clock80MHz,
		ICBIn => ICBInput,
		Value(0) => TestLEDsMode,
		Value(1) => TestLEDsValue);
	process(TestLEDsMode, TestLEDsValue, HallsPinFiltered, ICBInterrupts) is
		variable I : natural;
	begin
		if TestLEDsMode(0) = '0' then
			TestLEDsPin <= TestLEDsValue(2 downto 0);
		else
			for I in 0 to 2 loop
				TestLEDsPin(I) <= HallsPinFiltered(to_integer(unsigned(TestLEDsValue(2 downto 0))))(I);
			end loop;
		end if;
	end process;

	-- Instantiate the MRF SPI transceiver.
	MRF : entity work.MRF(RTL)
	port map(
		Reset => Reset,
		HostClock => Clock80MHz,
		BusClock => Clock10MHz,
		ICBIn => ICBInput,
		ICBOut => ICBOutput(3 to 5),
		DAIRQ => ICBInterrupts(0),
		RXIRQ => ICBInterrupts(1),
		TXIRQ => ICBInterrupts(2),
		RXFCSFailIRQ => ICBInterrupts(4),
		CSPin => MRFCSPin,
		ClockOE => MRFClockOE,
		MOSIPin => MRFMOSIPin,
		MISOPin => MRFMISOPin,
		IntPin => MRFInterruptPin,
		ResetPin => MRFResetPin,
		WakePin => MRFWakePin);
	MRFClockODDR2 : ODDR2
	generic map(
		DDR_ALIGNMENT => "NONE",
		INIT => '0',
		SRTYPE => "SYNC")
	port map(
		D0 => to_stdulogic(MRFClockOE),
		D1 => '0',
		C0 => Clock10MHz,
		C1 => Clock10MHzI,
		CE => '1',
		R => to_stdulogic(Reset),
		S => '0',
		Q => MRFClockPin);

	-- Instantiate the Hall sensor filters and the motors.
	WheelHallFilters : for Motor in HallsPin'range generate
		Pins : for Pin in HallsPin(Motor)'range generate
			Majority : entity work.Majority(RTL)
			generic map(
				Width => HALL_FILTER_WIDTHS(Motor))
			port map(
				Reset => Reset,
				Clock => Clock80MHz,
				Input => HallsPin(Motor)(Pin),
				Output => HallsPinFiltered(Motor)(Pin),
				OutputValid => HallsPinFilteredValid(Motor)(Pin));
		end generate;
	end generate;
	Motors : entity work.Motors(RTL)
	port map(
		Reset => Reset,
		HostClock => Clock80MHz,
		PWMClock => Clock8MHz,
		ICBIn => ICBInput,
		ICBOut => ICBOutput(6 to 7),
		HallsFiltered => HallsPinFiltered,
		HallsFilteredValid => HallsPinFilteredValid,
		PhasesHPin => MotorsPhasesHPin,
		PhasesLPin => MotorsPhasesLPin);

	-- Instantiate the accelerometer.
	Accelerometer : entity work.Accelerometer(RTL)
	generic map(command => COMMAND_SENSORS_GET_ACCEL)
	port map(
		Reset => Reset,
		HostClock => Clock80MHz,
		BusClock => Clock10MHz,
		ICBIn => ICBInput,
		ICBOut => ICBOutput(8),
		ClockOE => AccelClockOE,
		CSPin => AccelCSPin,
		MOSIPin => AccelMOSIPin,
		MISOPin => AccelMISOPin);
	AccelClockODDR2 : ODDR2
	generic map(
		DDR_ALIGNMENT => "NONE",
		INIT => '1',
		SRTYPE => "SYNC")
	port map(
		D0 => to_stdulogic(not AccelClockOE),
		D1 => '1',
		C0 => Clock10MHz,
		C1 => Clock10MHzI,
		CE => '1',
		R => '0',
		S => to_stdulogic(Reset),
		Q => AccelClockPin);

	-- Instantiate the gyro.
	Gyro : entity work.Gyro(RTL)
	generic map(
		Command => COMMAND_SENSORS_GET_GYRO)
	port map(
		Reset => Reset,
		HostClock => Clock80MHz,
		BusClock => Clock10MHz,
		ICBIn => ICBInput,
		ICBOut => ICBOutput(9),
		ClockOE => GyroClockOE,
		CSPin => GyroCSPin,
		MOSIPin => GyroMOSIPin,
		MISOPin => GyroMISOPin);
		
	GyroClockODDR2 : ODDR2
	generic map(
		DDR_ALIGNMENT => "NONE",
		INIT => '1',
		SRTYPE => "SYNC")
	port map(
		D0 => to_stdulogic(not GyroClockOE),
		D1 => '1',
		C0 => Clock10MHz,
		C1 => Clock10MHzI,
		CE => '1',
		R => '0',
		S => to_stdulogic(Reset),
		Q => GyroClockPin);

	-- Instantiate the magic number value.
	MagicNumber : entity work.ReadableRegister(RTL)
	generic map(
		Command => COMMAND_GET_MAGIC,
		Length => 4)
	port map(
		Reset => Reset,
		HostClock => Clock80MHz,
		ICBIn => ICBInput,
		ICBOut => ICBOutput(10),
		Value => (X"55", X"AA", X"CC", X"11"),
		AtomicReadClearStrobe => open);
end architecture Main;
