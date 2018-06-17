library ieee;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;


--! \brief top level entity for ICB transceiver.
--!
--! Implements an SPI slave transceiver with correct clock crossings
--! and CRC checking. Outgoing data is latched on the last bus clock
--! of the previous byte. It is therefore impossible to send anything
--! other than zero for the first word.
entity ICB is
	generic(
		--! \brief The number of endpoints communicating over the ICB.
		EndpointCount : natural;

		--! \brief CRC generator polynomial.
		--!
		--! Generator polynomial for the CRC unit, value should be in normal form
		CRCPolynomial : std_ulogic_vector := X"04C11DB7";

		--! \brief CRC reset value.
		CRCReset : std_ulogic_vector := X"FFFFFFFF";

		--! \brief CRC check value.
		--! 
		--! Value which the CRC will take on upon reception of the data stream including the CRC itself.
		CRCExpectedValue : std_ulogic_vector := X"00000000");
	port(
		--! \brief FPGA system clock.
		HostClock : in std_ulogic;

		--! \brief SPI bus clock.
		BusClock : in std_ulogic;

		--! \brief SPI chip select pin.
		CSPin : in std_ulogic;

		--! \brief SPI MOSI pin.
		MOSIPin : in std_ulogic;

		--! \brief SPI MISO pin.
		MISOPin : buffer std_ulogic;

		--! \brief Outputs from ICB transceiver to bus endpoints.
		Input : buffer icb_input_t;

		--! \brief Inputs from bus endpoints to ICB transceiver.
		Outputs : in icb_outputs_t(0 to EndpointCount - 1);

		--! \brief CRC error interrupt.
		--!
		--! Asserted for one host clock cycle when an incoming transaction ends with a bad CRC.
		CRCErrorIRQ : buffer boolean);
end entity ICB;

architecture RTL of ICB is
	-- These may have the wrong bit ordering (e.g. be to instead of downto) in the generic parmaeters.
	constant CRCPolynomialNorm : std_ulogic_vector(CRCPolynomial'length - 1 downto 0) := CRCPolynomial;
	constant CRCResetNorm : std_ulogic_vector(CRCReset'length - 1 downto 0) := CRCReset;
	constant CRCExpectedValueNorm : std_ulogic_vector(CRCExpectedValue'length - 1 downto 0) := CRCExpectedValue;

	signal Output : icb_output_t;
begin
	Output <= icb_output_combine(Outputs);

	Receiver : entity work.ICBReceiver
	generic map(
		CRCPolynomial => CRCPolynomialNorm,
		CRCReset => CRCResetNorm,
		CRCExpectedValue => CRCExpectedValueNorm)
	port map(
		HostClock => HostClock,
		BusClock => BusClock,
		CSPin => CSPin,
		MOSIPin => MOSIPin,
		Strobe => Input.RXStrobe,
		Data => Input.RXData);

	Transmitter : entity work.ICBTransmitter
	generic map(
		CRCPolynomial => CRCPolynomialNorm,
		CRCReset => CRCResetNorm)
	port map(
		HostClock => HostClock,
		BusClock => BusClock,
		CSPin => CSPin,
		MISOPin => MISOPin,
		Strobe => Output.TXStrobe,
		Data => Output.TXData,
		Last => Output.TXLast,
		Ready => Input.TXReady);

	CRCErrorIRQ <= Input.RXStrobe = ICB_RX_STROBE_EOT_CORRUPT;
end architecture RTL;
