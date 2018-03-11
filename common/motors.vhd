library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.commands.all;
use work.motor_common.all;
use work.types.all;

--! Ties all the motors together and provides an ICB interface.
entity Motors is
	port(
		Reset : in boolean; --! The system reset signal.
		HostClock : in std_ulogic; --! The system clock.
		PWMClock : in std_ulogic; --! The PWM timebase clock.
		ICBIn : in icb_input_t; --! The ICB data input.
		ICBOut : buffer icb_outputs_t(0 to 1); --! The ICB data outputs.
		HallsFiltered : in halls_pin_t; --! The filtered signals from the Hall sensors.
		HallsFilteredValid : in halls_pin_valid_t; --! Whether the Hall sensor data is valid.
		PhasesHPin : buffer motors_phases_pin_t; --! The wires to the high-side motor phase drivers.
		PhasesLPin : buffer motors_phases_pin_t); --! The wires to the low-side motor phase drivers.
end entity Motors;

architecture RTL of Motors is
	constant MotorCount : positive := 5;

	constant SETTINGS_RAW_RESET_VALUE : byte_vector(0 to MotorCount * 2 - 1) := (others => X"00");

	signal SettingsRaw : byte_vector(0 to MotorCount * 2 - 1);
	signal DriveModes : motor_drive_mode_vector(0 to MotorCount - 1);

	signal StuckLow, StuckLowLatch, StuckHigh, StuckHighLatch : boolean_vector(0 to MotorCount - 1);
	signal StuckRaw : byte_vector(0 to (MotorCount + 7) / 8 * 2 - 1);
	signal FlushStuck : boolean;

	signal HallCounts : hall_count_vector(DriveModes'range);
	signal HallCountsRaw : byte_vector(0 to MotorCount * 2 - 1);
begin
	-- Instantiate a writable register to receive new motor settings from the MCU.
	SettingsWR : entity work.WritableRegister(RTL)
	generic map(
		Command => COMMAND_MOTORS_SET,
		Length => SettingsRaw'length,
		ResetValue => SETTINGS_RAW_RESET_VALUE)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		ICBIn => ICBIn,
		Value => SettingsRaw);

	-- Unpack the motor settings into useful structures.
	process(SettingsRaw) is
		variable MotorWord : byte_vector(0 to 1);
	begin
		for I in 0 to MotorCount - 1 loop
			MotorWord := SettingsRaw(I * 2 to I * 2 + 1);
			case MotorWord(0)(1 downto 0) is
				when "00" => DriveModes(I).Mode <= COAST; DriveModes(I).Direction <= FORWARD;
				when "01" => DriveModes(I).Mode <= BRAKE; DriveModes(I).Direction <= REVERSE;
				when "10" => DriveModes(I).Mode <= DRIVE; DriveModes(I).Direction <= FORWARD;
				when others => DriveModes(I).Mode <= DRIVE; DriveModes(I).Direction <= REVERSE;
			end case;
			DriveModes(I).DutyCycle <= to_integer(unsigned(MotorWord(1)));
		end loop;
	end process;

	-- Pack the Hall sensor counts into a block of bytes.
	process(HallCounts) is
		variable MotorWord : byte_vector(0 to 1);
	begin
		for I in 0 to MotorCount - 1 loop
			MotorWord(0) := std_ulogic_vector(HallCounts(I)(7 downto 0));
			MotorWord(1) := std_ulogic_vector(HallCounts(I)(15 downto 8));
			HallCountsRaw(I * 2 to I * 2 + 1) <= MotorWord;
		end loop;
	end process;

	-- Instantiate a readable register to send Hall sensor counts to the MCU.
	HallCountsRR : entity work.ReadableRegister(RTL)
	generic map(
		Command => COMMAND_MOTORS_GET_HALL_COUNT,
		Length => HallCountsRaw'length)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		ICBIn => ICBIn,
		ICBOut => ICBOut(0),
		Value => HallCountsRaw,
		AtomicReadClearStrobe => open);

	-- Latch stuck Hall sensor flags.
	process(HostClock) is
	begin
		if rising_edge(HostClock) then
			for I in StuckLow'range loop
				if Reset or FlushStuck then
					StuckLowLatch(I) <= StuckLow(I);
				else
					StuckLowLatch(I) <= StuckLowLatch(I) or StuckLow(I);
				end if;
			end loop;
			for I in StuckHigh'range loop
				if Reset or FlushStuck then
					StuckHighLatch(I) <= StuckHigh(I);
				else
					StuckHighLatch(I) <= StuckHighLatch(I) or StuckHigh(I);
				end if;
			end loop;
		end if;
	end process;

	-- Pack the Hall sensor failure flags into a block of bytes.
	process(StuckLowLatch, StuckHighLatch) is
	begin
		StuckRaw <= (others => X"00");
		for I in 0 to MotorCount - 1 loop
			if StuckLowLatch(I) then
				StuckRaw(I / 8)(I mod 8) <= '1';
			end if;
			if StuckHighLatch(I) then
				StuckRaw((MotorCount + 7) / 8 + I / 8)(I mod 8) <= '1';
			end if;
		end loop;
	end process;

	-- Instantiate a readable register to send Hall sensor failure flags to the MCU.
	StuckRR : entity work.ReadableRegister(RTL)
	generic map(
		Command => COMMAND_MOTORS_GET_CLEAR_STUCK_HALLS,
		Length => StuckRaw'length)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		ICBIn => ICBIn,
		ICBOut => ICBOut(1),
		Value => StuckRaw,
		AtomicReadClearStrobe => FlushStuck);

	-- Instantiate a set of motor drivers.
	Motors : for I in DriveModes'range generate
		Motor : entity work.Motor(RTL)
		generic map(
			PWMPhase => I * 255 / MotorCount)
		port map(
			Reset => Reset,
			HostClock => HostClock,
			PWMClock => PWMClock,
			DriveMode => DriveModes(I),
			HallCount => HallCounts(I),
			StuckLow => StuckLow(I),
			StuckHigh => StuckHigh(I),
			HallFiltered => HallsFiltered(I),
			HallFilteredValid => HallsFilteredValid(I)(0),
			PhasesHPin => PhasesHPin(I),
			PhasesLPin => PhasesLPin(I));
	end generate;
end architecture RTL;
