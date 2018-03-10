library ieee;
use ieee.std_logic_1164.all;

--! \brief Provides an engine for calculating IEEE 802.15.4 CRCs.
entity MRFCRC is
	port(
		Reset : in boolean; --! \brief Clears the CRC.
		Clock : in std_ulogic; --! \brief The system clock.
		Data : in std_ulogic_vector(7 downto 0); --! \brief The data byte to add to the accumulated CRC.
		Strobe : in boolean; --! \brief Marks when new data is available.
		CRC : buffer std_ulogic_vector(15 downto 0); --! \brief The computed CRC value.
		Busy : buffer boolean); --! \brief Indicates whether the engine is ready to accept a new data byte.
end entity MRFCRC;

architecture RTL of MRFCRC is
	signal BitsLeft : natural range 0 to 8 := 0;
	signal Shifter : std_ulogic_vector(7 downto 0);
begin
	process(Clock) is
		variable Carry : std_ulogic;
		variable I : natural;
	begin
		if rising_edge(Clock) then
			if Reset then
				CRC <= X"0000";
				BitsLeft <= 0;
			elsif Strobe then
				BitsLeft <= 8;
				Shifter <= Data;
			elsif BitsLeft /= 0 then
				Carry := Shifter(0) xor CRC(0);
				for I in CRC'range loop
					if I = CRC'high then
						CRC(I) <= Carry;
					elsif I = 3 or I = 10 then
						CRC(I) <= CRC(I + 1) xor Carry;
					else
						CRC(I) <= CRC(I + 1);
					end if;
				end loop;
				BitsLeft <= BitsLeft - 1;
				Shifter <= "0" & Shifter(7 downto 1);
			end if;
		end if;
	end process;

	Busy <= Strobe or BitsLeft /= 0;
end architecture RTL;
