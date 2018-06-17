library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.types.all;

entity WritableRegister is
	generic(
		Command : natural;
		Length : positive;
		ResetValue : byte_vector);
	port(
		Reset : in boolean;
		HostClock : in std_ulogic;
		ICBIn : in icb_input_t;
		Value : buffer byte_vector(0 to Length - 1));
end entity WritableRegister;

architecture RTL of WritableRegister is
	type state_t is (IDLE, ACCEPT);
	signal State : state_t;
	signal Shifter : byte_vector(0 to Length - 1);
begin
	process(HostClock) is
	begin
		if rising_edge(HostClock) then
			if Reset then
				State <= IDLE;
				Value <= ResetValue;
			elsif ICBIn.RXStrobe = ICB_RX_STROBE_COMMAND then
				if to_integer(unsigned(ICBIn.RXData)) = Command then
					State <= ACCEPT;
				else
					State <= IDLE;
				end if;
			elsif State = ACCEPT then
				case ICBIn.RXStrobe is
					when ICB_RX_STROBE_DATA =>
						Shifter <= Shifter(1 to Length - 1) & ICBIn.RXData;
					when ICB_RX_STROBE_EOT_OK =>
						Value <= Shifter;
						State <= IDLE;
					when ICB_RX_STROBE_EOT_CORRUPT =>
						State <= IDLE;
					when others =>
						null;
				end case;
			end if;
		end if;
	end process;
end architecture RTL;
