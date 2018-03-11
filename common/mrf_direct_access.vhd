library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.commands.all;
use work.mrf_common.all;
use work.types.all;

--! \brief Provides direct register-level access to the radio over the ICB.
entity MRFDirectAccess is
	port(
		Reset : in boolean; --! The system reset signal.
		HostClock : in std_ulogic; --! The system clock.
		ICBIn : in icb_input_t; --! The ICB data input.
		ICBOut : buffer icb_output_t; --! The ICB data output.
		IRQ : buffer boolean; --! The ICB interrupt request.
		ArbRequest : buffer boolean; --! The request signal to the arbiter.
		ArbGrant : in boolean; --! The grant signal from the arbiter.
		LLControl : buffer low_level_control_t; --! The control lines to the low-level module.
		LLStatus : in low_level_status_t; --! The status lines from the low-level module.
		MRFIntPin : in std_ulogic; --! The interrupt wire from the MRF.
		MRFResetPin : buffer std_ulogic; --! The reset wire to the MRF.
		MRFWakePin : buffer std_ulogic); --! The wake wire to the MRF.
end entity MRFDirectAccess;

architecture RTL of MRFDirectAccess is
begin
	process(HostClock) is
		type state_t is (IDLE, ICB_ADDRESS_HIGH, ICB_ADDRESS_LOW, ICB_WRITE_DATA, MRF_WAIT_ARB, MRF_WAIT_BUSY, ICB_WRITE_AUX);
		variable State : state_t;
		variable Command : natural range 0 to 255;
		variable AddressHigh : natural range 0 to 3;
		variable LastReadData : std_ulogic_vector(7 downto 0);
	begin
		if rising_edge(HostClock) then
			ICBOut.TXStrobe <= false;
			ICBOut.TXData <= X"00";
			ICBOut.TXLast <= false;
			IRQ <= false;
			LLControl.Strobe <= false;

			if Reset then
				State := IDLE;
				MRFResetPin <= '0';
				MRFWakePin <= '0';
			elsif ICBIn.RXStrobe = ICB_RX_STROBE_COMMAND then
				AddressHigh := 0;
				Command := to_integer(unsigned(ICBIn.RXData));
				case Command is
					when COMMAND_MRF_DA_READ_SHORT =>
						LLControl.RegType <= SHORT;
						LLControl.OpType <= READ;
						State := ICB_ADDRESS_LOW;

					when COMMAND_MRF_DA_WRITE_SHORT =>
						LLControl.RegType <= SHORT;
						LLControl.OpType <= WRITE;
						State := ICB_ADDRESS_LOW;

					when COMMAND_MRF_DA_READ_LONG =>
						LLControl.RegType <= LONG;
						LLControl.OpType <= READ;
						State := ICB_ADDRESS_HIGH;

					when COMMAND_MRF_DA_WRITE_LONG =>
						LLControl.RegType <= LONG;
						LLControl.OpType <= WRITE;
						State := ICB_ADDRESS_HIGH;

					when COMMAND_MRF_DA_GET_DATA =>
						ICBOut.TXStrobe <= true;
						ICBOut.TXData <= LastReadData;
						ICBOut.TXLast <= true;
						State := IDLE;

					when COMMAND_MRF_DA_GET_INT =>
						ICBOut.TXStrobe <= true;
						ICBOut.TXData <= "0000000" & MRFIntPin;
						ICBOut.TXLast <= true;
						State := IDLE;

					when COMMAND_MRF_DA_SET_AUX =>
						State := ICB_WRITE_AUX;

					when others =>
						if State /= MRF_WAIT_ARB and State /= MRF_WAIT_BUSY then
							State := IDLE;
						end if;
				end case;
			else
				case State is
					when IDLE =>
						null;

					when ICB_ADDRESS_HIGH =>
						if ICBIn.RXStrobe = ICB_RX_STROBE_DATA then
							AddressHigh := to_integer(unsigned(ICBIn.RXData));
							State := ICB_ADDRESS_LOW;
						end if;

					when ICB_ADDRESS_LOW =>
						if ICBIn.RXStrobe = ICB_RX_STROBE_DATA then
							LLControl.Address <= AddressHigh * 256 + to_integer(unsigned(ICBIn.RXData));
							case LLControl.OpType is
								when READ =>
									State := MRF_WAIT_ARB;
								when WRITE =>
									State := ICB_WRITE_DATA;
							end case;
						end if;

					when ICB_WRITE_DATA =>
						if ICBIn.RXStrobe = ICB_RX_STROBE_DATA then
							LLControl.WriteData <= ICBIn.RXData;
							State := MRF_WAIT_ARB;
						end if;

					when MRF_WAIT_ARB =>
						if ArbGrant and not LLStatus.Busy then
							LLControl.Strobe <= true;
							State := MRF_WAIT_BUSY;
						end if;

					when MRF_WAIT_BUSY =>
						if not LLStatus.Busy then
							LastReadData := LLStatus.ReadData;
							State := IDLE;
							IRQ <= true;
						end if;

					when ICB_WRITE_AUX =>
						if ICBIn.RXStrobe = ICB_RX_STROBE_DATA then
							MRFResetPin <= ICBIn.RXData(0);
							MRFWakePin <= ICBIn.RXData(1);
							State := IDLE;
						end if;
				end case;
			end if;
		end if;

		case State is
			when IDLE => ArbRequest <= false;
			when ICB_ADDRESS_HIGH => ArbRequest <= true;
			when ICB_ADDRESS_LOW => ArbRequest <= true;
			when ICB_WRITE_DATA => ArbRequest <= true;
			when MRF_WAIT_ARB => ArbRequest <= true;
			when MRF_WAIT_BUSY => ArbRequest <= false;
			when ICB_WRITE_AUX => ArbRequest <= false;
		end case;
	end process;
end architecture RTL;
