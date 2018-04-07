library ieee;
use ieee.std_logic_1164.all;
use work.mrf_common.all;
use work.types.all;

--! \brief Ties together all the modules that access the MRF24J40.
entity MRF is
	port(
		Reset : in boolean; --! The system reset signal.
		HostClock : in std_ulogic; --! The system clock.
		BusClock : in std_ulogic; --! The SPI bus clock.
		ICBIn : in icb_input_t; --! The ICB data input.
		ICBOut : buffer icb_outputs_t(0 to 2); --! The ICB data outputs from the three engines.
		DAIRQ : buffer boolean; --! The ICB interrupt request for direct access complete.
		RXIRQ : buffer boolean; --! The ICB interrupt request for receive complete.
		TXIRQ : buffer boolean; --! The ICB interrupt request for transmit complete.
		RXFCSFailIRQ : buffer boolean; --! The ICB interrupt request for frame with bad FCS received.
		CSPin : buffer std_ulogic; --! The chip select wire to the MRF.
		ClockOE : buffer boolean; --! The output enable signal for the SPI clock wire to the MRF.
		MOSIPin : buffer std_ulogic; --! The MOSI wire to the MRF.
		MISOPin : in std_ulogic; --! the MISO wire from the MRF.
		IntPin : in std_ulogic; --! The interrupt wire from the MRF.
		ResetPin : buffer std_ulogic; --! The reset wire to the MRF.
		WakePin : buffer std_ulogic); --! The wake wire to the MRF.
end entity MRF;

architecture RTL of MRF is
	signal ArbRequests, ArbGrants : boolean_vector(0 to 3);

	signal LLControls : low_level_control_vector_t(0 to 3);
	signal LLControlsCombined : low_level_control_t;
	signal LLStatus : low_level_status_t;

	signal ReceiveInt, TransmitInt : boolean;
begin
	DirectAccess : entity work.MRFDirectAccess(RTL)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		ICBIn => ICBIn,
		ICBOut => ICBOut(0),
		IRQ => DAIRQ,
		ArbRequest => ArbRequests(0),
		ArbGrant => ArbGrants(0),
		LLControl => LLControls(0),
		LLStatus => LLStatus,
		MRFIntPin => IntPin,
		MRFResetPin => ResetPin,
		MRFWakePin => WakePin);

	Interrupt : entity work.MRFInterruptOffload(RTL)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		ICBIn => ICBIn,
		ArbRequest => ArbRequests(1),
		ArbGrant => ArbGrants(1),
		LLControl => LLControls(1),
		LLStatus => LLStatus,
		MRFIntPin => IntPin,
		ReceiveInt => ReceiveInt,
		TransmitInt => TransmitInt);

	Receive : entity work.MRFReceiveOffload(RTL)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		ICBIn => ICBIn,
		ICBOut => ICBOut(1),
		ReceiveIRQ => RXIRQ,
		FCSFailIRQ => RXFCSFailIRQ,
		ArbRequest => ArbRequests(2),
		ArbGrant => ArbGrants(2),
		LLControl => LLControls(2),
		LLStatus => LLStatus,
		ReceiveInt => ReceiveInt);

	Transmit : entity work.MRFTransmitOffload(RTL)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		ICBIn => ICBIn,
		ICBOut => ICBOut(2),
		IRQ => TXIRQ,
		ArbRequest => ArbRequests(3),
		ArbGrant => ArbGrants(3),
		LLControl => LLControls(3),
		LLStatus => LLStatus,
		TransmitInt => TransmitInt);

	Arbiter : entity work.Arbiter(RTL)
	generic map(
		Width => ArbRequests'length)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		Request => ArbRequests,
		Grant => ArbGrants);

	LLControlsCombined <= low_level_control_combine(LLControls);

	LowLevel : entity work.MRFLowLevel(RTL)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		BusClock => BusClock,
		Control => LLControlsCombined,
		Status => LLStatus,
		CSPin => CSPin,
		ClockOE => ClockOE,
		MOSIPin => MOSIPin,
		MISOPin => MISOPin);
end architecture RTL;
