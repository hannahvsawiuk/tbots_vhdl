library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.commands.all;
use work.mrf_common.all;
use work.types.all;

--! \brief Provides reading and decoding of the MRF24J40 INTSTAT register.
entity MRFInterruptOffload is
	port(
		Reset : in boolean; --! The system reset signal.
		HostClock : in std_ulogic; --! The system clock.
		ICBIn : in icb_input_t; --! The ICB data input.
		ArbRequest : buffer boolean; --! The request signal to the arbiter.
		ArbGrant : in boolean; --! The grant signal from the arbiter.
		LLControl : buffer low_level_control_t; --! The control lines to the low-level module.
		LLStatus : in low_level_status_t; --! The status lines from the low-level module.
		MRFIntPin : in std_ulogic; --! The hardware interrupt wire from the radio.
		ReceiveInt : buffer boolean; --! Whether a receive interrupt just occurred.
		TransmitInt : buffer boolean); --! Whether a transmit complete interrupt just occurred.
end entity MRFInterruptOffload;

architecture RTL of MRFInterruptOffload is
	signal MRFIntBuffered : std_ulogic;
begin
	MRFIntBuffered <= MRFIntPin when rising_edge(HostClock);

	process(HostClock) is
		type state_t is (DISABLED, IDLE, ARB, READ);
		variable State : state_t;
	begin
		if rising_edge(HostClock) then
			LLControl.Strobe <= false;
			ReceiveInt <= false;
			TransmitInt <= false;

			if Reset or (ICBIn.RXStrobe = ICB_RX_STROBE_COMMAND and to_integer(unsigned(ICBIn.RXData)) = COMMAND_MRF_OFFLOAD_DISABLE) then
				State := DISABLED;
			else
				case State is
					when DISABLED =>
						if ICBIn.RXStrobe = ICB_RX_STROBE_COMMAND and to_integer(unsigned(ICBIn.RXData)) = COMMAND_MRF_OFFLOAD then
							State := IDLE;
						end if;

					when IDLE =>
						if MRFIntBuffered = '1' then
							State := ARB;
						end if;

					when ARB =>
						if ArbGrant and not LLStatus.Busy then
							LLControl.Strobe <= true;
							State := READ;
						end if;

					when READ =>
						if not LLStatus.Busy then
							ReceiveInt <= to_boolean(LLStatus.ReadData(3));
							TransmitInt <= to_boolean(LLStatus.ReadData(0));
							State := IDLE;
						end if;
				end case;
			end if;
		end if;

		case State is
			when DISABLED => ArbRequest <= false;
			when IDLE => ArbRequest <= false;
			when ARB => ArbRequest <= true;
			when READ => ArbRequest <= false;
		end case;
	end process;

	LLControl.RegType <= SHORT;
	LLControl.OpType <= READ;
	LLControl.Address <= 16#31#; -- INTSTAT
end architecture RTL;
