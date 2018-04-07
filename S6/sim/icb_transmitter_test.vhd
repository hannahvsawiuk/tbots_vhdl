library ieee;
use ieee.std_logic_1164.all;

library work;
use work.types.all;
use work.utils.all;

entity icb_transmitter_test is
end entity icb_transmitter_test;

architecture Behavioural of icb_transmitter_test is
	constant HostPeriod : time := (1 us / 80);
	constant BusPeriod : time := (1 us / 42);
	constant CRCPolynomial : std_ulogic_vector(31 downto 0) := X"04C11DB7";
	constant CRCReset : std_ulogic_vector(31 downto 0) := X"FFFFFFFF";
	constant CRCExpectedValue : std_ulogic_vector(31 downto 0) := X"00000000";

	type controls_t is record
		CSPin : std_ulogic;
		Strobe : boolean;
		Data : byte;
		Last : boolean;
		EnableBusClockCycles : positive;
		EnableBusClockCyclesToggle : boolean;
		ClearResults : boolean;
	end record controls_t;

	signal Controls : controls_t := (
		CSPin => '1',
		Strobe => false,
		Data => (others => '0'),
		Last => false,
		EnableBusClockCycles => 1,
		EnableBusClockCyclesToggle => false,
		ClearResults => false);
	signal EnableHostClock, EnableBusClock : boolean := false;
	signal HostClock, BusClock : std_ulogic := '0';

	type results_t is record
		Bits : std_ulogic_vector(0 to 256 * 8 - 1);
		BitCount : natural;
	end record results_t;

	signal Results : results_t;
	signal MISOPin : std_ulogic;
	signal Ready : boolean;

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

	procedure enable_bus_clock(Cycles : in natural; signal C : out controls_t) is
	begin
		assert not EnableBusClock severity failure;
		C.EnableBusClockCycles <= Cycles;
		C.EnableBusClockCyclesToggle <= not Controls.EnableBusClockCyclesToggle;
	end procedure enable_bus_clock;

	procedure send_byte(Data : in byte; Last : in boolean; signal Controls : out controls_t) is
	begin
		while not Ready loop
			wait until rising_edge(HostClock);
		end loop;
		Controls.Data <= Data;
		Controls.Last <= Last;
		Controls.Strobe <= true;
		wait until rising_edge(HostClock);
		Controls.Strobe <= false;
	end procedure send_byte;

	procedure test_in(Data : in byte_vector; DataLength : in natural; signal Controls : out controls_t) is
		variable ExpectedCRC : std_ulogic_vector(31 downto 0);
	begin
		-- Wipe the data input to avoid possible contamination of waveforms or off-position sampling.
		Controls.Data <= X"FF";

		-- Clear accumulated results.
		-- We have to do this in the bus clock domain, so run the bus clock.
		-- Since CS is deasserted, this should not affect the UUT.
		enable_bus_clock(1, Controls);
		Controls.ClearResults <= true;
		wait until rising_edge(BusClock);
		Controls.ClearResults <= false;
		wait until not EnableBusClock;

		-- Let CS idle high for a few bit times.
		wait for BusPeriod * 2;

		-- Assert CS.
		Controls.CSPin <= '0';

		-- Let CS idle low for a few bit times.
		wait for BusPeriod * 2;

		-- Run the bus clock for five bytes (1 command plus 4 CRC).
		-- Do nothing during this time.
		enable_bus_clock(5 * 8, Controls);
		wait until not EnableBusClock;

		-- Run the bus clock for the padding byte, data, and CRC.
		-- Delay one host clock before starting sending data to simulate the latency of the ICB receiver notifying an endpoint.
		enable_bus_clock((1 + DataLength + 4) * 8, Controls);
		wait for HostPeriod;
		for I in 0 to DataLength - 1 loop
			send_byte(Data(I), I = DataLength - 1, Controls);
		end loop;

		-- Wait for the bus clock to stop.
		wait until not EnableBusClock;

		-- Let CS idle low for a few bit times.
		wait for BusPeriod * 2;

		-- Deassert CS.
		Controls.CSPin <= '1';

		-- Let CS idle high for a few bit times.
		wait for BusPeriod * 2;

		-- Verify that the right thing happened.
		assert Results.BitCount = (6 + DataLength + 4) * 8 severity failure;
		for ByteIndex in 0 to DataLength - 1 loop
			for BitIndex in 7 downto 0 loop
				assert Results.Bits((6 + ByteIndex) * 8 + (7 - BitIndex)) = Data(ByteIndex)(BitIndex) severity failure;
			end loop;
		end loop;
		ExpectedCRC := crc_bytes(Data(0 to DataLength - 1));
		for BitIndex in 31 downto 0 loop
			assert Results.Bits((6 + DataLength) * 8 + (31 - BitIndex)) = ExpectedCRC(BitIndex) severity failure;
		end loop;
	end procedure test_in;

	signal BytesOut : natural;
begin
	BytesOut <= Results.BitCount / 8;
	UUT : entity work.ICBTransmitter(RTL)
	generic map(
		CRCPolynomial => CRCPolynomial,
		CRCReset => CRCReset)
	port map(
		HostClock => HostClock,
		BusClock => BusClock,
		CSPin => Controls.CSPin,
		MISOPin => MISOPin,
		Strobe => Controls.Strobe,
		Data => Controls.Data,
		Last => Controls.Last,
		Ready => Ready);

	process(BusClock) is
	begin
		if rising_edge(BusClock) then
			if Controls.ClearResults then
				Results.BitCount <= 0;
			else
				Results.Bits(Results.BitCount) <= MISOPin;
				Results.BitCount <= Results.BitCount + 1;
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
		variable Cycles : natural := 0;
		variable LastToggle : boolean := false;
	begin
		while true loop
			wait for BusPeriod / 2;
			if Cycles /= 0 then
				BusClock <= '1';
				Cycles := Cycles - 1;
			end if;
			wait for BusPeriod / 2;
			BusClock <= '0';
			if Cycles = 0 then
				EnableBusClock <= false;
				wait until Controls.EnableBusClockCyclesToggle /= LastToggle;
				Cycles := Controls.EnableBusClockCycles;
				LastToggle := Controls.EnableBusClockCyclesToggle;
				EnableBusClock <= true;
			end if;
		end loop;
	end process;

	process is
		constant BYTES : byte_vector(0 to 7) := (X"01", X"02", X"03", X"04", X"05", X"06", X"07", X"08");
	begin
		wait for HostPeriod * 2;
		EnableHostClock <= true;
		wait for HostPeriod * 2;
		for ByteCount in 1 to 7 loop
			test_in(BYTES, ByteCount, Controls);
		end loop;
		wait for HostPeriod * 2;
		EnableHostClock <= false;
		wait for HostPeriod * 2;
		wait;
	end process;
end architecture Behavioural;
