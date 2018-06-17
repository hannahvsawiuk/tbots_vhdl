library ieee;
use ieee.std_logic_1164.all;
use work.motor_common.all;
use work.types.all;

--! \brief Generates a commutation pattern given Hall sensor inputs and a desired direction.
entity MotorCommutator is
	port(
		Reset : in boolean; --! The system reset signal.
		HostClock : in std_ulogic; --! The system clock.
		Direction : in commutation_direction; --! The desired drive direction.
		Hall : in boolean_vector(0 to 2); --! The Hall sensor readings.
		HallValid : in boolean; --! Whether the Hall sensor readings are valid.
		Phases : buffer phase_drive_mode_vector(0 to 2); --! The phase drive pattern.
		StuckHigh : buffer boolean; --! Whether all Hall sensors are stuck high.
		StuckLow : buffer boolean); --! Whether all Hall sensors are stuck low.
end entity MotorCommutator;

architecture RTL of MotorCommutator is
	signal StuckHighNow, StuckLowNow : boolean;
	signal StuckHighBits, StuckLowBits : boolean_vector(0 to 2);
	signal Swapped : boolean_vector(0 to 2);
	signal NPhase : boolean_vector(0 to 2);
	signal PPhase : boolean_vector(0 to 2);
begin
	-- Check for stuck Hall sensors. If we see all three sensors in the same
	-- state (which is an invalid encoding), we consider a stuck sensor to exist.
	-- We consider the stuck sensor to have cleared once every sensor has been
	-- observed in the opposite state at least once.
	StuckHighNow <= Hall(0) and Hall(1) and Hall(2);
	StuckLowNow <= (not Hall(0)) and (not Hall(1)) and (not Hall(2));
	process(HostClock) is
		variable I : natural range 0 to 2;
	begin
		if rising_edge(HostClock) then
			if not HallValid then
				StuckHighBits <= (false, false, false);
				StuckLowBits <= (false, false, false);
			else
				for I in 0 to 2 loop
					StuckHighBits(I) <= (StuckHighBits(I) and Hall(I)) or StuckHighNow;
					StuckLowBits(I) <= (StuckLowBits(I) and not Hall(I)) or StuckLowNow;
				end loop;
			end if;
		end if;
	end process;
	StuckHigh <= StuckHighBits(0) or StuckHighBits(1) or StuckHighBits(2);
	StuckLow <= StuckLowBits(0) or StuckLowBits(1) or StuckLowBits(2);

	Swapped <= Hall when Direction = REVERSE else not Hall;

	process(HallValid, Swapped, StuckHighNow, StuckLowNow) is
	begin
		for I in Phases'range loop
			if (not HallValid) or StuckHighNow or StuckLowNow then
				Phases(I) <= FLOAT;
			elsif not Swapped(I) and Swapped((I + 1) mod 3) then
				Phases(I) <= LOW;
			elsif not (Swapped((I + 1) mod 3) or not Swapped(I)) then
				Phases(I) <= PWM;
			else
				Phases(I) <= FLOAT;
			end if;
		end loop;
	end process;
end architecture RTL;
