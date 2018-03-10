library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

library work;
use work.types.all;
use work.utils.all;

--! \brief Receiver SubModule for the ICB
entity ICBReceiver is
	generic(
		--! \brief CRC generator polynomial.
		--!
		--! Generator polynomial for the CRC unit, value should be in normal form
		CRCPolynomial : std_ulogic_vector;

		--! \brief CRC reset value.
		CRCReset : std_ulogic_vector;

		--! \brief CRC check value.
		--! 
		--! Value which the CRC will take on upon reception of the data stream including the CRC itself.
		CRCExpectedValue : std_ulogic_vector);
	port(
		--! \brief FPGA system clock.
		HostClock : in std_ulogic;

		--! \brief SPI bus clock.
		BusClock : in std_ulogic;

		--! \brief SPI chip select pin.
		CSPin : in std_ulogic;

		--! \brief SPI MOSI pin.
		MOSIPin : in std_ulogic;

		--! \brief Receive strobe.
		Strobe : buffer icb_rx_strobe_t;

		--! \brief Received data word.
		Data : buffer byte);
end entity ICBReceiver;

architecture RTL of ICBReceiver is
	--! \brief The type of data maintained by the bus clock domain.
	type bus_domain_t is record
		--! \brief The CRC of everything received so far, updated as bits come in the bus.
		CRC : std_ulogic_vector(CRCPolynomial'range);
		--! \brief The bits of the current byte received so far.
		Shifter : byte;
		--! \brief The number of bits left to receive in the current byte.
		ShiftCounter : natural range 0 to 7;
	end record bus_domain_t;

	--! \brief The data maintained by the bus clock domain.
	signal BusDomain : bus_domain_t := (
		CRC => CRCReset,
		Shifter => X"00",
		ShiftCounter => 0);

	--! \brief The type of data plane crossing the clock domains.
	type cross_domain_t is record
		--! \brief The complete byte most recently received.
		Data : byte;
		--! \brief Whether or not the most recent byte brought the CRC to its final value.
		CRCOK : boolean;
	end record cross_domain_t;

	--! \brief The data crossing the clock domains, presented by the bus clock.
	signal CrossDomain : cross_domain_t := (
		Data => X"00",
		CRCOK => true);

	--! \brief A flag that toggles every time a byte is received, presented by the bus clock.
	signal CrossDomainToggleBus : boolean := false;

	--! \brief A flag that toggles every time a byte is received, reclocked onto the host clock.
	signal CrossDomainToggleHost : boolean := false;

	--! \brief The possible states for the host clock domain state machine.
	type host_state_t is (
		--! \brief Host is waiting for the command byte.
		HOST_STATE_COMMAND,
		--! \brief Host is waiting for a byte of parameter data.
		HOST_STATE_OUT_DATA,
		--! \brief Host is discarding bytes because transmitter is sending parameter data.
		HOST_STATE_IN_DATA,
		--! \brief Host is discarding bytes because an in transaction header was corrupt.
		HOST_STATE_FLUSH_CORRUPT);

	--! \brief The type of the byte buffer.
	subtype host_bytebuffer_t is byte_vector(0 to (CRCPolynomial'high + 1) / 8 - 1);

	--! \brief The type of data maintained by the host clock domain.
	type host_domain_t is record
		--! \brief The current state of the host.
		State : host_state_t;
		--! \brief The last seen state of the cross-domain toggle.
		LastToggle : boolean;
		--! \brief A delay path for received bytes.
		--!
		--! Received bytes are pushed into this buffer.
		--! Bytes are only examined and forwarded to endpoints as they exit the buffer.
		--! The buffer is sized to be equal to the size of a CRC.
		--! This means that, for an in transaction, the command byte is exiting the buffer just as the last byte of the CRC enters it.
		--! This allows the system to verify the CRC before sending the command byte to the endpoint.
		ByteBuffer : host_bytebuffer_t;
		--! \brief The number of bytes left to discard from ByteBuffer.
		--!
		--! If this is zero, when a byte is pushed, the popped byte is sent to the endpoints.
		--! If this is nonzero, when a byte is pushed, the popped byte is discarded because it was garbage from a prior transaction.
		DiscardCount : natural range 0 to host_bytebuffer_t'high + 1;
	end record host_domain_t;

	--! \brief The data maintained by the host clock domain.
	signal HostDomain : host_domain_t := (
		State => HOST_STATE_COMMAND,
		LastToggle => false,
		ByteBuffer => (others => X"00"),
		DiscardCount => host_bytebuffer_t'high + 1);
Begin
	--! \brief The bus clock domain.
	process(CSPin, BusClock) is
	begin
		if CSPin = '1' then
			BusDomain.CRC <= CRCReset;
			BusDomain.ShiftCounter <= 0;
		else
			if rising_edge(BusClock) then
				BusDomain.CRC <= crc_step(BusDomain.CRC, CRCPolynomial, MOSIPin);
				BusDomain.Shifter <= BusDomain.Shifter(6 downto 0) & MOSIPin;
				BusDomain.ShiftCounter <= (BusDomain.ShiftCounter - 1) mod 8;
			end if;
			if falling_edge(BusClock) then
				if BusDomain.ShiftCounter = 0 then
					CrossDomainToggleBus <= not CrossDomainToggleBus;
					CrossDomain.Data <= BusDomain.Shifter;
					CrossDomain.CRCOK <= BusDomain.CRC = CRCExpectedValue;
				end if;
			end if;
		end if;
	end process;

	--! \brief Reclock the domain-crossing toggle flag.
	CrossDomainToggleHost <= CrossDomainToggleBus when rising_edge(HostClock);

	--! \brief The host clock domain.
	process(HostClock) is
	begin
		if rising_edge(HostClock) then
			Strobe <= ICB_RX_STROBE_NONE;
			if CSPin = '1' then
				case HostDomain.State is
					when HOST_STATE_COMMAND =>
						null;

					when HOST_STATE_OUT_DATA =>
						if CrossDomain.CRCOK then
							Strobe <= ICB_RX_STROBE_EOT_OK;
						else
							Strobe <= ICB_RX_STROBE_EOT_CORRUPT;
						end if;

					when HOST_STATE_IN_DATA =>
						Strobe <= ICB_RX_STROBE_EOT_OK;

					when HOST_STATE_FLUSH_CORRUPT =>
						Strobe <= ICB_RX_STROBE_EOT_CORRUPT;
				end case;
				HostDomain.State <= HOST_STATE_COMMAND;
				HostDomain.DiscardCount <= host_bytebuffer_t'high + 1;
			else
				if CrossDomainToggleHost /= HostDomain.LastToggle then
					if HostDomain.DiscardCount /= 0 then
						HostDomain.DiscardCount <= HostDomain.DiscardCount - 1;
					else
						case HostDomain.State is
							when HOST_STATE_COMMAND =>
								if HostDomain.ByteBuffer(0)(7) = '1' then
									if CrossDomain.CRCOK then
										Strobe <= ICB_RX_STROBE_COMMAND;
										HostDomain.State <= HOST_STATE_IN_DATA;
									else
										HostDomain.State <= HOST_STATE_FLUSH_CORRUPT;
									end if;
								else
									Strobe <= ICB_RX_STROBE_COMMAND;
									HostDomain.State <= HOST_STATE_OUT_DATA;
								end if;

							when HOST_STATE_OUT_DATA =>
								Strobe <= ICB_RX_STROBE_DATA;

							when HOST_STATE_IN_DATA =>
								null;

							when HOST_STATE_FLUSH_CORRUPT =>
								null;
						end case;
					end if;
					Data <= HostDomain.ByteBuffer(0);
					HostDomain.ByteBuffer <= HostDomain.ByteBuffer(1 to HostDomain.ByteBuffer'high) & CrossDomain.Data;
				end if;
			end if;
			HostDomain.LastToggle <= CrossDomainToggleHost;
		end if;
	end process;
end architecture;
