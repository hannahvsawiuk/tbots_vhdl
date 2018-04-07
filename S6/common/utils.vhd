library ieee;
use ieee.std_logic_1164.all;

package utils is
	function crc_step(PreviousCRC : std_ulogic_vector; GeneratorPolynomial : std_ulogic_vector; Input : std_ulogic) return std_ulogic_vector;
	function to_hstring(s: in std_ulogic_vector) return string;
end package utils;

package body utils is
	function crc_step(PreviousCRC : std_ulogic_vector; GeneratorPolynomial : std_ulogic_vector; Input : std_ulogic) return std_ulogic_vector is
		variable NextCRC : std_ulogic_vector(PreviousCRC'range);
		variable CarryBit : std_ulogic := Input xor PreviousCRC(PreviousCRC'high);
	begin
		for I in PreviousCRC'range loop
			if I = PreviousCRC'low then 
				NextCRC(I) := CarryBit;
			else
				NextCRC(I) := PreviousCRC(I - 1) xor (CarryBit and GeneratorPolynomial(I));
			end if;
		end loop;
		return NextCRC;
	end function;	

	function to_hstring(s : in std_ulogic_vector) return string is
--- Locals to make the indexing easier 
        constant s_norm : std_ulogic_vector(s'length - 1 downto 0) := s;
        variable result : string(s'length / 4 - 1 downto 0);

--- A subtype to keep the VHDL compiler happy 
--- (the rules about data types in a CASE are quite strict) 
        subtype slv4 is std_ulogic_vector(3 downto 0);
	begin
        assert (s'length mod 4) = 0 report "SLV must be a multiple of 4 bits" severity FAILURE;
 
        for i in result'range loop
                case slv4'(s_norm(i * 4 + 3 downto i * 4)) is
					when "0000" => result(i) := '0';
					when "0001" => result(i) := '1';
					when "0010" => result(i) := '2';
					when "0011" => result(i) := '3';
					when "0100" => result(i) := '4';
					when "0101" => result(i) := '5';
					when "0110" => result(i) := '6';
					when "0111" => result(i) := '7';
					when "1000" => result(i) := '8';
					when "1001" => result(i) := '9';
					when "1010" => result(i) := 'a';
					when "1011" => result(i) := 'b';
					when "1100" => result(i) := 'c';
					when "1101" => result(i) := 'd';
					when "1110" => result(i) := 'e';
					when "1111" => result(i) := 'f';
					when others => result(i) := 'X';
                end case;
        end loop;
 
        return result;
	end;
end package body utils;
