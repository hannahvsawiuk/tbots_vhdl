library ieee;
use ieee.std_logic_1164.all;

--! A majority-detection filter.
entity Majority is
	generic(
		Width : positive); --! The number of samples to filter across.
	port(
		Reset : in boolean; --! The system reset signal, which must be asserted for at least Width clock cycles at startup.
		Clock : in std_ulogic; --! The sample clock.
		Input : in std_ulogic; --! The new input data.
		Output : buffer std_ulogic; --! The output of the filter.
		OutputValid : buffer boolean); --! Whether the output has reached proper levels yet.
end entity Majority;

architecture RTL of Majority is
	signal Counter : natural range 0 to Width;
	signal ValidCounter : natural range 0 to Width + 2;
	signal ShiftRegister : std_ulogic_vector(0 to Width - 1);
	signal InputFiltered : std_ulogic;
begin
	process(Clock) is
	begin
		if rising_edge(Clock) then
			if Reset then
				Counter <= 0;
				ValidCounter <= 0;
				ShiftRegister <= ShiftRegister(1 to Width - 1) & '0';
			else
				if InputFiltered = '1' and ShiftRegister(0) = '0' then
					Counter <= Counter + 1;
				elsif InputFiltered = '0' and ShiftRegister(0) = '1' then
					Counter <= Counter - 1;
				end if;
				if ValidCounter /= Width + 2 then
					ValidCounter <= ValidCounter + 1;
				end if;
				ShiftRegister <= ShiftRegister(1 to Width - 1) & InputFiltered;
			end if;
			InputFiltered <= Input;
		end if;
	end process;

	Output <= '1' when Counter >= Width / 2 else '0';
	OutputValid <= ValidCounter = Width + 2;
end architecture RTL;
