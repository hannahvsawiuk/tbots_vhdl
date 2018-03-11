library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.motor_common.all;
use work.types.all;

--! Measures the speed of a motor by counting Hall sensor edges.
entity MotorHallSpeed is
	port(
		HostClock : in std_ulogic; --! The system clock.
		Hall : in boolean_vector(0 to 2); --! The Hall sensor states.
		Value : buffer hall_count); --! The accumulated count.
end entity MotorHallSpeed;

architecture RTL of MotorHallSpeed is
	signal CountInternal : hall_count;
	signal OldHall : boolean_vector(0 to 2);

	pure function IsForward(constant Hall : boolean_vector(0 to 2); constant OldHall : boolean_vector(0 to 2)) return boolean is
		variable HallBits : std_ulogic_vector(5 downto 0);
	begin
		for I in 0 to 2 loop
			HallBits(I) := to_stdulogic(Hall(I));
			HallBits(I + 3) := to_stdulogic(OldHall(I));
		end loop;
		if HallBits = "100110" then
			return true;
		elsif HallBits = "110010" then
			return true;
		elsif HallBits = "010011" then
			return true;
		elsif HallBits = "011001" then
			return true;
		elsif HallBits = "001101" then
			return true;
		elsif HallBits = "101100" then
			return true;
		else
			return false;
		end if;
	end function IsForward;
begin
	process(HostClock) is
	begin
		if rising_edge(HostClock) then
			if Hall /= OldHall then
				if IsForward(Hall, OldHall) then
					Value <= Value + 1;
				elsif IsForward(OldHall, Hall) then
					Value <= Value - 1;
				end if;
			end if;
			OldHall <= Hall;
		end if;
	end process;
end architecture RTL;
