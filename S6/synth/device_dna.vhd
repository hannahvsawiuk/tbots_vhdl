library ieee;
library unisim;
use ieee.std_logic_1164.all;
use unisim.vcomponents.all;

entity DeviceDNA is
	port(
		Reset : in boolean;
		Clock1MHz : in std_ulogic;
		Ready : buffer boolean;
		Value : buffer std_ulogic_vector(54 downto 0));
end entity DeviceDNA;

architecture RTL of DeviceDNA is
	type state_t is (RESET_ST, LOAD, SHIFT);
	signal State : state_t;
	signal BitsLeft : natural range 0 to 56;
	signal DataOut : std_ulogic;
	signal Read : std_ulogic;
begin
	process(Clock1MHz) is
	begin
		if rising_edge(Clock1MHz) then
			if Reset then
				State <= RESET_ST;
				BitsLeft <= 56;
			elsif State = RESET_ST then
				State <= LOAD;
			elsif State = LOAD then
				State <= SHIFT;
			elsif BitsLeft /= 0 then
				Value <= Value(53 downto 0) & DataOut;
				BitsLeft <= BitsLeft - 1;
			end if;
		end if;
	end process;

	Read <= '1' when State = LOAD else '0';
	Ready <= State = SHIFT and BitsLeft = 0;

	DNAPort : DNA_PORT
	port map(
		DOUT => DataOut,
		DIN => '0',
		READ => Read,
		SHIFT => '1',
		CLK => Clock1MHz);
end architecture RTL;
