library ieee;
use ieee.std_logic_1164.all;

library work;
use work.types.all;
use work.utils.all;

entity icb_receiver_test is
end entity icb_receiver_test;

architecture Behavioural of icb_receiver_test is
	constant HostPeriod : time := (1 us / 80);
	constant BusPeriod : time := (1 us / 42);
	constant CRCPolynomial : std_ulogic_vector(31 downto 0) := X"04C11DB7";
	constant CRCReset : std_ulogic_vector(31 downto 0) := X"FFFFFFFF";
	constant CRCExpectedValue : std_ulogic_vector(31 downto 0) := X"00000000";

	type controls_t is record
		CSPin : std_ulogic;
		MOSIPin : std_ulogic;
		EnableBusClock : boolean;
		ClearResults : boolean;
	end record controls_t;

	signal Controls : controls_t := (
		CSPin => '1',
		MOSIPin => '0',
		EnableBusClock => false,
		ClearResults => false);
	signal EnableHostClock : boolean := false;
	signal HostClock, BusClock : std_ulogic := '0';
	signal Strobe : icb_rx_strobe_t;
	signal Data : byte;

	type event_t is record
		Strobe : icb_rx_strobe_t;
		Data : byte;
	end record event_t;

	type events_t is array(integer range<>) of event_t;

	type results_t is record
		Events : events_t(0 to 127);
		EventCount : natural range 0 to 127;
	end record results_t;

	signal Results : results_t;

	procedure send_byte(Data : in byte; signal Controls : out controls_t) is
	begin
		for I in 7 downto 0 loop
			Controls.MOSIPin <= Data(I);
			wait until rising_edge(BusClock);
			wait until falling_edge(BusClock);
		end loop;
	end procedure send_byte;

	procedure send_bytes(Data : in byte_vector; signal Controls : out controls_t) is
	begin
		for I in Data'range loop
			send_byte(Data(I), Controls);
		end loop;
	end procedure send_bytes;

	function crc_byte(Data : in byte; Old : in std_ulogic_vector(31 downto 0) := CRCReset) return std_ulogic_vector is
		variable CRC : std_ulogic_vector(31 downto 0) := Old;
	begin
		for I in 7 downto 0 loop
			CRC := crc_step(CRC, CRCPolynomial, Data(I));
		end loop;
		return CRC;
	end function crc_byte;

	function crc_bytes(Data : in byte_vector; Old : in std_ulogic_vector(31 downto 0) := CRCReset) return std_ulogic_vector is
		variable CRC : std_ulogic_vector(31 downto 0) := Old;
	begin
		for I in Data'range loop
			CRC := crc_byte(Data(I), CRC);
		end loop;
		return CRC;
	end function crc_bytes;

	function crc_to_byte_vector(CRC : in std_ulogic_vector(31 downto 0)) return byte_vector is
		variable Ret : byte_vector(0 to 3);
	begin
		for I in Ret'range loop
			Ret(Ret'high - I) := CRC(I * 8 + 7 downto I * 8);
		end loop;
		return Ret;
	end function crc_to_byte_vector;

	procedure test_out(Command : in byte; Data : in byte_vector; CorruptCRC : in boolean; signal Controls : out controls_t; signal Results : in results_t) is
	begin
		-- Clear accumulated results.
		wait until rising_edge(HostClock);
		Controls.ClearResults <= true;
		wait until rising_edge(HostClock);
		Controls.ClearResults <= false;

		-- Let CS idle high for a few bit times.
		wait for BusPeriod * 2;

		-- Assert CS.
		Controls.CSPin <= '0';

		-- Let CS idle low for a few bit times.
		wait for BusPeriod * 2;

		-- Start the bus clock.
		Controls.EnableBusClock <= true;

		-- Send the data.
		send_byte(Command, Controls);
		send_bytes(Data, Controls);

		-- Send the CRC.
		if CorruptCRC then
			send_bytes(crc_to_byte_vector(not crc_bytes(Data, crc_byte(Command))), Controls);
		else
			send_bytes(crc_to_byte_vector(crc_bytes(Data, crc_byte(Command))), Controls);
		end if;

		-- Stop the bus clock.
		Controls.EnableBusClock <= false;

		-- Let CS idle low for a few bit times.
		wait for BusPeriod * 2;

		-- Deassert CS.
		Controls.CSPin <= '1';

		-- Let CS idle high for a few bit times.
		wait for BusPeriod * 2;

		-- Verify that the right thing happened.
		assert Results.EventCount = Data'length + 2 severity failure;
		assert Results.Events(0).Strobe = ICB_RX_STROBE_COMMAND severity failure;
		assert Results.Events(0).Data = Command severity failure;
		for I in Data'range loop
			assert Results.Events(I - Data'low + Results.Events'low + 1).Strobe = ICB_RX_STROBE_DATA severity failure;
			assert Results.Events(I - Data'low + Results.Events'low + 1).Data = Data(I) severity failure;
		end loop;
		if CorruptCRC then
			assert Results.Events(Data'length + 1).Strobe = ICB_RX_STROBE_EOT_CORRUPT severity failure;
		else
			assert Results.Events(Data'length + 1).Strobe = ICB_RX_STROBE_EOT_OK severity failure;
		end if;
	end procedure test_out;

	procedure test_in(Command : in byte; DataLength : in natural; CorruptCRC : in boolean; signal Controls : out controls_t; signal Results : in results_t) is
	begin
		-- Clear accumulated results.
		wait until rising_edge(HostClock);
		Controls.ClearResults <= true;
		wait until rising_edge(HostClock);
		Controls.ClearResults <= false;

		-- Let CS idle high for a few bit times.
		wait for BusPeriod * 2;

		-- Assert CS.
		Controls.CSPin <= '0';

		-- Let CS idle low for a few bit times.
		wait for BusPeriod * 2;

		-- Start the bus clock.
		Controls.EnableBusClock <= true;

		-- Send the command byte.
		send_byte(Command, Controls);

		-- Send the CRC of the command byte.
		if CorruptCRC then
			send_bytes(crc_to_byte_vector(not crc_byte(Command)), Controls);
		else
			send_bytes(crc_to_byte_vector(crc_byte(Command)), Controls);
		end if;

		-- Send the data.
		for I in 1 to DataLength + 4 loop
			send_byte(X"00", Controls);
		end loop;

		-- Stop the bus clock.
		Controls.EnableBusClock <= false;

		-- Let CS idle low for a few bit times.
		wait for BusPeriod * 2;

		-- Deassert CS.
		Controls.CSPin <= '1';

		-- Let CS idle high for a few bit times.
		wait for BusPeriod * 2;

		-- Verify that the right thing happened.
		if CorruptCRC then
			assert Results.EventCount = 1 severity failure;
			assert Results.Events(0).Strobe = ICB_RX_STROBE_EOT_CORRUPT severity failure;
		else
			assert Results.EventCount = 2 severity failure;
			assert Results.Events(0).Strobe = ICB_RX_STROBE_COMMAND severity failure;
			assert Results.Events(0).Data = Command severity failure;
			assert Results.Events(1).Strobe = ICB_RX_STROBE_EOT_OK severity failure;
		end if;
	end procedure test_in;
begin
	UUT : entity work.ICBReceiver(RTL)
	generic map(
		CRCPolynomial => CRCPolynomial,
		CRCReset => CRCReset,
		CRCExpectedValue => CRCExpectedValue)
	port map(
		HostClock => HostClock,
		BusClock => BusClock,
		CSPin => Controls.CSPin,
		MOSIPin => Controls.MOSIPin,
		Strobe => Strobe,
		Data => Data);

	process(HostClock) is
	begin
		if rising_edge(HostClock) then
			if Controls.ClearResults then
				Results.EventCount <= 0;
			else
				if Strobe /= ICB_RX_STROBE_NONE then
					Results.Events(Results.EventCount).Strobe <= Strobe;
					Results.Events(Results.EventCount).Data <= Data;
					Results.EventCount <= Results.EventCount + 1;
				end if;
			end if;
		end if;
	end process;

	process is
	begin
		while true loop
			wait for HostPeriod / 2;
			if EnableHostClock then
				HostClock <= '1';
			end if;
			wait for HostPeriod / 2;
			HostClock <= '0';
			if not EnableHostClock then
				wait until EnableHostClock;
			end if;
		end loop;
	end process;

	process is
	begin
		while true loop
			wait for BusPeriod / 2;
			if Controls.EnableBusClock then
				BusClock <= '1';
			end if;
			wait for BusPeriod / 2;
			BusClock <= '0';
			if not Controls.EnableBusClock then
				wait until Controls.EnableBusClock;
			end if;
		end loop;
	end process;

	process is
		constant EMPTY : byte_vector(0 to -1) := (others => X"00");
	begin
		wait for HostPeriod * 2;
		EnableHostClock <= true;
		wait for HostPeriod * 2;
		test_out(X"41", EMPTY, false, Controls, Results);
		test_out(X"41", EMPTY, true, Controls, Results);
		test_out(X"41", (X"42", X"43", X"44"), false, Controls, Results);
		test_out(X"41", (X"42", X"43", X"44"), true, Controls, Results);
		test_in(X"82", 3, false, Controls, Results);
		test_in(X"82", 3, true, Controls, Results);
		wait for HostPeriod * 2;
		EnableHostClock <= false;
		wait for HostPeriod * 2;
		wait;
	end process;
end architecture Behavioural;
