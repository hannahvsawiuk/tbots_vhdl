library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.utils.all;
use work.types.all;

entity crc_step_test is
end entity;

architecture Behavioural of crc_step_test is
begin
	process
		subtype byte is std_ulogic_vector(7 downto 0);
		type byte_array is array(integer range<>) of byte;
		type test_case is record
			Input : byte_array(0 to 7);
			InputLength : natural range 1 to 8;
			Result : std_ulogic_vector(31 downto 0);
		end record test_case;
		type test_cases is array(integer range<>) of test_case;

		constant Polynomial : std_ulogic_vector(31 downto 0) := X"04C11DB7";
		constant Cases : test_cases := (
			((X"41", X"00", X"00", X"00", X"00", X"00", X"00", X"00"), 1, X"7E4FD274"),
			((X"41", X"42", X"00", X"00", X"00", X"00", X"00", X"00"), 2, X"AEEC82F4"),
			((X"41", X"42", X"43", X"00", X"00", X"00", X"00", X"00"), 3, X"18E654AA"),
			((X"41", X"42", X"43", X"44", X"00", X"00", X"00", X"00"), 4, X"ABCF9A63"),
			((X"41", X"42", X"43", X"44", X"45", X"00", X"00", X"00"), 5, X"36BDE573"),
			((X"41", X"42", X"43", X"44", X"45", X"46", X"00", X"00"), 6, X"5D516EE7"),
			((X"41", X"42", X"43", X"44", X"45", X"46", X"47", X"00"), 7, X"32F5EAA6"),
			((X"41", X"42", X"43", X"44", X"45", X"46", X"47", X"48"), 8, X"3AD46D31"),
			((X"42", X"00", X"00", X"00", X"00", X"00", X"00", X"00"), 1, X"730CF4AD"),
			((X"42", X"43", X"00", X"00", X"00", X"00", X"00", X"00"), 2, X"D8C6C090"),
			((X"42", X"43", X"44", X"00", X"00", X"00", X"00", X"00"), 3, X"D6D130FA"),
			((X"42", X"43", X"44", X"45", X"00", X"00", X"00", X"00"), 4, X"F96EE747"),
			((X"42", X"43", X"44", X"45", X"46", X"00", X"00", X"00"), 5, X"EB9677C3"),
			((X"42", X"43", X"44", X"45", X"46", X"47", X"00", X"00"), 6, X"52540E6A"),
			((X"42", X"43", X"44", X"45", X"46", X"47", X"48", X"00"), 7, X"379567A6"),
			((X"43", X"00", X"00", X"00", X"00", X"00", X"00", X"00"), 1, X"77CDE91A"),
			((X"43", X"44", X"00", X"00", X"00", X"00", X"00", X"00"), 2, X"14985149"),
			((X"43", X"44", X"45", X"00", X"00", X"00", X"00", X"00"), 3, X"E407FFB0"),
			((X"43", X"44", X"45", X"46", X"00", X"00", X"00", X"00"), 4, X"FF52DD60"),
			((X"43", X"44", X"45", X"46", X"47", X"00", X"00", X"00"), 5, X"C9EB00C6"),
			((X"43", X"44", X"45", X"46", X"47", X"48", X"00", X"00"), 6, X"86CD3B59"),
			((X"44", X"00", X"00", X"00", X"00", X"00", X"00", X"00"), 1, X"698AB91F"),
			((X"44", X"45", X"00", X"00", X"00", X"00", X"00", X"00"), 2, X"27963284"),
			((X"44", X"45", X"46", X"00", X"00", X"00", X"00", X"00"), 3, X"3E565F20"),
			((X"44", X"45", X"46", X"47", X"00", X"00", X"00", X"00"), 4, X"9422CDE8"),
			((X"44", X"45", X"46", X"47", X"48", X"00", X"00", X"00"), 5, X"065A388D"),
			((X"45", X"00", X"00", X"00", X"00", X"00", X"00", X"00"), 1, X"6D4BA4A8"),
			((X"45", X"46", X"00", X"00", X"00", X"00", X"00", X"00"), 2, X"F8CCD581"),
			((X"45", X"46", X"47", X"00", X"00", X"00", X"00", X"00"), 3, X"49A4B1C3"),
			((X"45", X"46", X"47", X"48", X"00", X"00", X"00", X"00"), 4, X"A070DEB7"),
			((X"46", X"00", X"00", X"00", X"00", X"00", X"00", X"00"), 1, X"60088271"),
			((X"46", X"47", X"00", X"00", X"00", X"00", X"00", X"00"), 2, X"8EE697E5"),
			((X"46", X"47", X"48", X"00", X"00", X"00", X"00", X"00"), 3, X"A19B382B"),
			((X"47", X"00", X"00", X"00", X"00", X"00", X"00", X"00"), 1, X"64C99FC6"),
			((X"47", X"48", X"00", X"00", X"00", X"00", X"00", X"00"), 2, X"64B0EB84"),
			((X"48", X"00", X"00", X"00", X"00", X"00", X"00", X"00"), 1, X"5C86227B")
		);

		function crc_byte(PreviousCRC : std_ulogic_vector(31 downto 0); Input : byte) return std_ulogic_vector is
			variable TempCRC : std_ulogic_vector(31 downto 0);
		begin
			TempCRC := PreviousCRC;
			for I in 7 downto 0 loop
				TempCRC := crc_step(TempCRC, Polynomial, Input(I));
			end loop;
			return TempCRC;
		end function crc_byte;

		variable TempCRC, TempCRC2 : std_ulogic_vector(31 downto 0);
	begin
		for I in Cases'range loop
			TempCRC := X"FFFFFFFF";
			for J in 0 to Cases(I).InputLength - 1 loop
				TempCRC := crc_byte(TempCRC, Cases(I).Input(J));
			end loop;
			assert TempCRC = Cases(I).Result severity failure;

			for J in 3 downto 0 loop
				TempCRC := crc_byte(TempCRC, Cases(I).Result(J * 8 + 7 downto J * 8));
			end loop;
			assert TempCRC = X"00000000" severity failure;
		end loop;
		wait;
	end process;
end architecture Behavioural;
