library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.types.all;
use work.utils.all;

--! \brief ICB transmitter.
entity ICBTransmitter is
	generic(
		--! \brief Generator polynomial for CRC unit.
		CRCPolynomial : std_ulogic_vector;

		--! \brief CRC reset value.
		CRCReset : std_ulogic_vector);
	port(
		--! \brief FPGA system clock.
		HostClock : in std_ulogic;

		--! \brief SPI bus clock.
		BusClock : in std_ulogic;

		--! \brief SPI bus chip select pin.
		CSPin : in std_ulogic;

		--! \brief SPI MISO pin.
		MISOPin : buffer std_ulogic;

		--! \brief Data write stobe.
		--!
		--! Assert to have the transmitter capture presented data.
		Strobe : in boolean;

		--! \brief Data byte to capture when strobing.
		Data : in byte;

		--! \brief Whether the currently strobed byte is the last one in the parameter block.
		Last : in boolean;

		--! \brief Ready for data.
		--!
		--! Asserted if the transmitter allows a write strobe. Only assert strobe if Ready is asserted.
		Ready : buffer boolean);
end entity ICBTransmitter;

architecture RTL of ICBTransmitter is
	--! \brief The type of data maintained by the bus clock domain.
	type bus_domain_t is record
		--! \brief How many bits left in the transaction header.
		HeaderBitCount : natural range 0 to 6 * 8;
		--! \brief The CRC of everything transmitted so far, updated as bits go out the bus.
		CRC : std_ulogic_vector(CRCPolynomial'range);
		--! \brief The data byte currently being shifted out.
		--!
		--! This signal takes on undefined values during CRC shifting.
		Shifter : byte;
		--! \brief The bit index of the bit currently being driven to MISO.
		--!
		--! This is not used as an index into Shifter.
		--! Shifter is a shift register, so Shifter(7) is always driven to MISO.
		--! However, the value ShiftCounter takes on is exactly the bit index in the original data byte.
		--!
		--! This signal takes on undefined values during CRC shifting.
		ShiftCounter : natural range 0 to 7;
		--! \brief Whether we are currently shifting CRC.
		ShiftCRC : boolean;
		--! \brief Whether we will start shifting CRC at the end of this byte.
		ShiftCRCNext : boolean;
	end record bus_domain_t;

	--! \brief The data maintained by the bus clock domain.
	signal BusDomain : bus_domain_t := (
		HeaderBitCount => 6 * 8,
		CRC => CRCReset,
		Shifter => (others => '0'),
		ShiftCounter => byte'high,
		ShiftCRC => false,
		ShiftCRCNext => false);

	--! \brief The type of data crossing the clock domains from bus to host.
	type bh_cross_domain_t is record
		--! \brief A flag that toggles every time a byte is copied into the shifter.
		--!
		--! It is undefined whether this flag toggles during CRC shifting.
		Toggle : boolean;
	end record bh_cross_domain_t;

	--! \brief The data crossing the clock domains from bus to host, presented by the bus clock.
	signal BHCrossDomainBus : bh_cross_domain_t := (
		Toggle => false);

	--! \brief The data crossing the clock domains from bus to host, reclocked by the host clock.
	signal BHCrossDomainHost : bh_cross_domain_t := (
		Toggle => false);

	--! \brief The type of data crossing clock domains from host to bus.
	type hb_cross_domain_t is record
		--! \brief The next byte to load into the shifter.
		NextByte : byte;
		--! \brief Whether the next byte is the last byte in the parameter data.
		Last : boolean;
	end record hb_cross_domain_t;

	--! \brief The data crossing the clock domains from host to bus.
	signal HBCrossDomain : hb_cross_domain_t := (
		NextByte => (others => '0'),
		Last => false);

	--! \brief The type of data maintained by the host clock domain.
	type host_domain_t is record
		--! \brief The last seen state of the cross-domain toggle.
		LastToggle : boolean;
		--! \brief Whether the cross-domain buffer is full.
		--!
		--! The buffer becomes full when the endpoint strobes.
		--! The buffer becomes empty at the subsequent transition of the cross-domain toggle.
		Full : boolean;
	end record host_domain_t;

	--! \brief The data maintained by the host clock domain.
	signal HostDomain : host_domain_t := (
		LastToggle => false,
		Full => false);
Begin
	-- Traditionally, one thinks of SPI buses as sampling an incoming bit on rising edge of clock, and shifting out the next outgoing bit on falling edge.
	-- However, at our speeds, without any deskew technologies in the clock path, it is very difficult to achieve the necessary setup time for the receiver in that configuration.
	-- Instead, we exhibit a new output bit on rising edge of clock, giving us a whole extra half-period to propagate the bit out onto the I/O pin.
	-- Because time travel does not exist, this is still safe; we cannot possibly exhibit the new output bit before the SPI master has sent its rising edge of clock!
	-- The hold time requirement for the master receiver is 2.5 nanoseconds; we ensure to meet this requirement by means of the VALID constraint in the UCF.
	-- If necessary, that constraint ought to add delay to the output path in order to not send out the new bit too early.

	--! \brief The bus clock domain.
	process(CSPin, BusClock) is
	begin
		if CSPin = '1' then
			BusDomain.CRC <= CRCReset;
			BusDomain.HeaderBitCount <= 6 * 8;
			BusDomain.Shifter <= (others => '0');
			BusDomain.ShiftCounter <= BusDomain.Shifter'high;
			BusDomain.ShiftCRC <= false;
			BusDomain.ShiftCRCNext <= false;
		elsif rising_edge(BusClock) then
			-- Update the CRC.
			if BusDomain.ShiftCRC then
				-- We are shifting the CRC, so shift it.
				BusDomain.CRC <= BusDomain.CRC(BusDomain.CRC'high - 1 downto 0) & '0';
			elsif BusDomain.HeaderBitCount = 0 then
				-- We are shifting data, so add the bit to the CRC.
				-- Do not update the CRC with garbage sent during the transaction header.
				BusDomain.CRC <= crc_step(BusDomain.CRC, CRCPolynomial, MISOPin);
			end if;

			-- Advance the data shifter, some flags, and the toggle.
			-- We can safely do this whether we are shifting data or CRC.
			-- If we are shifting CRC, everything is ignored.
			if BusDomain.ShiftCounter = 0 then
				BusDomain.Shifter <= HBCrossDomain.NextByte;
				BusDomain.ShiftCRC <= BusDomain.ShiftCRCNext;
				BusDomain.ShiftCRCNext <= BusDomain.ShiftCRCNext or HBCrossDomain.Last; -- Do not allow ShiftCRCNext to be cleared!
				BHCrossDomainBus.Toggle <= not BHCrossDomainBus.Toggle;
			else
				BusDomain.Shifter <= BusDomain.Shifter(6 downto 0) & '0';
			end if;

			-- Advance the counters.
			if BusDomain.HeaderBitCount /= 0 then
				BusDomain.HeaderBitCount <= BusDomain.HeaderBitCount - 1;
			end if;
			BusDomain.ShiftCounter <= (BusDomain.ShiftCounter - 1) mod BusDomain.Shifter'length;
		end if;
	end process;

	--! \brief MISO takes on either a data bit or a CRC bit depending on what we are shifting.
	MISOPin <= BusDomain.CRC(BusDomain.CRC'high) when BusDomain.ShiftCRC else BusDomain.Shifter(BusDomain.Shifter'high);

	--! \brief Reclock the bus-to-host domain-crossing data.
	BHCrossDomainHost <= BHCrossDomainBus when rising_edge(HostClock);

	--! \brief The host clock domain.
	process(CSPin, HostClock) is
	begin
		if CSPin = '1' then
			HBCrossDomain.NextByte <= (others => '0');
			HBCrossDomain.Last <= false;
			HostDomain.Full <= false;
		elsif rising_edge(HostClock) then
			if Strobe then
				HBCrossDomain.NextByte <= Data;
				HBCrossDomain.Last <= Last;
				HostDomain.Full <= true;
			elsif BHCrossDomainHost.Toggle /= HostDomain.LastToggle then
				HostDomain.Full <= false;
			end if;
			HostDomain.LastToggle <= BHCrossDomainHost.Toggle;
		end if;
	end process;

	--! \brief Report whether ready to accept a byte.
	Ready <= not Strobe and not HostDomain.Full;
end architecture RTL;
