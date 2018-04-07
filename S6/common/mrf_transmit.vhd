library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.commands.all;
use work.mrf_common.all;
use work.types.all;

--! \brief Provides an engine for accepting frames from the ICB, transmitting them over the radio, and returning status over the ICB.
entity MRFTransmitOffload is
	port(
		Reset : in boolean; --! The system reset signal.
		HostClock : in std_ulogic; --! The system clock.
		ICBIn : in icb_input_t; --! The ICB data input.
		ICBOut : buffer icb_output_t; --! The ICB data output.
		IRQ : buffer boolean; --! The ICB interrupt request for transmit complete.
		ArbRequest : buffer boolean; --! The request signal to the arbiter.
		ArbGrant : in boolean; --! The grant signal from the arbiter.
		LLControl : buffer low_level_control_t; --! The control lines to the low-level module.
		LLStatus : in low_level_status_t; --! The status lines from the low-level module.
		TransmitInt : in boolean); --! The transmit complete interrupt strobe from the MRF interrupt offload engine.
end entity MRFTransmitOffload;

architecture RTL of MRFTransmitOffload is
	signal DisableStrobe : boolean;

	signal FramePending : boolean;
	signal FrameLength : natural range 0 to 255;
	signal FlushFrame : boolean;
	signal TransmitStatus : std_ulogic_vector(7 downto 0);

	type frame_buffer_port is record
		Strobe : boolean;
		Address : natural range 0 to 255;
		Data : std_ulogic_vector(7 downto 0);
	end record frame_buffer_port;

	signal FrameBufferReadPort : frame_buffer_port;
	signal FrameBufferWritePort : frame_buffer_port;
begin
	process(HostClock) is
		type frame_buffer_t is array(0 to 255) of std_ulogic_vector(7 downto 0);
		variable FrameBuffer : frame_buffer_t;
	begin
		if rising_edge(HostClock) then
			if FrameBufferReadPort.Strobe then
				FrameBufferReadPort.Data <= FrameBuffer(FrameBufferReadPort.Address);
			end if;
			if FrameBufferWritePort.Strobe then
				FrameBuffer(FrameBufferWritePort.Address) := FrameBufferWritePort.Data;
			end if;
		end if;
	end process;

	process(HostClock) is
		type state_t is (IDLE, READ_HLEN, READ_LEN, READ_DATA);
		variable State : state_t;
		variable Command : natural range 0 to 255;
		variable DataIndex : positive range 2 to 255;
	begin
		if rising_edge(HostClock) then
			ICBOut.TXStrobe <= false;
			ICBOut.TXData <= X"00";
			ICBOut.TXLast <= false;
			DisableStrobe <= false;
			FrameBufferWritePort.Strobe <= false;

			if Reset then
				State := IDLE;
				FramePending <= false;
			else
				if FlushFrame then
					FramePending <= false;
				end if;

				if ICBIn.RXStrobe = ICB_RX_STROBE_COMMAND then
					Command := to_integer(unsigned(ICBIn.RXData));
					case Command is
						when COMMAND_MRF_TX_PUSH =>
							State := READ_HLEN;

						when COMMAND_MRF_TX_GET_STATUS =>
							ICBOut.TXStrobe <= true;
							ICBOut.TXData <= TransmitStatus;
							ICBOut.TXLast <= true;
							State := IDLE;

						when COMMAND_MRF_OFFLOAD_DISABLE =>
							State := IDLE;
							DisableStrobe <= true;
							FramePending <= false;

						when others =>
							State := IDLE;
					end case;
				else
					case State is
						when IDLE =>
							null;

						when READ_HLEN =>
							if ICBIn.RXStrobe = ICB_RX_STROBE_DATA then
								FrameBufferWritePort.Strobe <= true;
								FrameBufferWritePort.Address <= 0;
								FrameBufferWritePort.Data <= ICBIn.RXData;
								State := READ_LEN;
							elsif ICBIn.RXStrobe /= ICB_RX_STROBE_NONE then
								State := IDLE;
							end if;

						when READ_LEN =>
							if ICBIn.RXStrobe = ICB_RX_STROBE_DATA then
								FrameBufferWritePort.Strobe <= true;
								FrameBufferWritePort.Address <= 1;
								FrameBufferWritePort.Data <= ICBIn.RXData;
								FrameLength <= to_integer(unsigned(ICBIn.RXData)) + 2; -- HLEN(1) + LEN(1)
								State := READ_DATA;
								DataIndex := 2;
							elsif ICBIn.RXStrobe /= ICB_RX_STROBE_NONE then
								State := IDLE;
							end if;

						when READ_DATA =>
							if ICBIn.RXStrobe = ICB_RX_STROBE_DATA then
								FrameBufferWritePort.Strobe <= true;
								FrameBufferWritePort.Address <= DataIndex;
								FrameBufferWritePort.Data <= ICBIn.RXData;
								DataIndex := DataIndex + 1;
								if DataIndex = FrameLength then
									State := IDLE;
									FramePending <= true;
								end if;
							elsif ICBIn.RXStrobe /= ICB_RX_STROBE_NONE then
								State := IDLE;
							end if;
					end case;
				end if;
			end if;
		end if;
	end process;

	process(HostClock) is
		type state_t is (IDLE, WRITE_FRAME, WAIT_INT, WAIT_ARB, READ_TXSTAT);
		variable State : state_t;
		variable NextDataIndex : natural range 0 to 255;
	begin
		if rising_edge(HostClock) then
			IRQ <= false;
			LLControl.Strobe <= false;
			FlushFrame <= false;

			if Reset or DisableStrobe then
				State := IDLE;
			else
				case State is
					when IDLE =>
						NextDataIndex := 0;
						if FramePending then
							State := WRITE_FRAME;
						end if;

					when WRITE_FRAME =>
						if ArbGrant and not LLStatus.Busy then
							LLControl.Strobe <= true;
							LLControl.OpType <= WRITE;
							if NextDataIndex = FrameLength then
								LLControl.RegType <= SHORT;
								LLControl.Address <= 16#1B#; -- TXNCON
								LLControl.WriteData <= "00000101"; -- TXNACKREQ=1, TXNTRIG=1
								FlushFrame <= true;
								State := WAIT_INT;
							else
								LLControl.RegType <= LONG;
								LLControl.Address <= NextDataIndex;
								LLControl.WriteData <= FrameBufferReadPort.Data;
								NextDataIndex := NextDataIndex + 1;
							end if;
						end if;

					when WAIT_INT =>
						NextDataIndex := 0;
						if TransmitInt then
							State := WAIT_ARB;
						end if;

					when WAIT_ARB =>
						if ArbGrant and not LLStatus.Busy then
							LLControl.Strobe <= true;
							LLControl.RegType <= SHORT;
							LLControl.OpType <= READ;
							LLControl.Address <= 16#24#; -- TXSTAT
							State := READ_TXSTAT;
						end if;

					when READ_TXSTAT =>
						if not LLStatus.Busy then
							IRQ <= true;
							TransmitStatus <= LLStatus.ReadData;
							State := IDLE;
						end if;
				end case;
			end if;
		end if;

		case State is
			when IDLE => ArbRequest <= false;
			when WRITE_FRAME => ArbRequest <= true;
			when WAIT_INT => ArbRequest <= false;
			when WAIT_ARB => ArbRequest <= true;
			when READ_TXSTAT => ArbRequest <= false;
		end case;

		FrameBufferReadPort.Strobe <= true;
		FrameBufferReadPort.Address <= NextDataIndex;
	end process;
end architecture RTL;
