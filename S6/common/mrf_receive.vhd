library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.commands.all;
use work.mrf_common.all;
use work.types.all;

--! \brief Provides an engine for receiving frames from the radio and passing them over the ICB.
entity MRFReceiveOffload is
	port(
		Reset : in boolean; --! The system reset signal.
		HostClock : in std_ulogic; --! The system clock.
		ICBIn : in icb_input_t; --! The ICB data input.
		ICBOut : buffer icb_output_t; --! The ICB data output.
		ReceiveIRQ : buffer boolean; --! The ICB interrupt request for frame received.
		FCSFailIRQ : buffer boolean; --! The ICB interrupt request for frame received with bad FCS.
		ArbRequest : buffer boolean; --! The request signal to the arbiter.
		ArbGrant : in boolean; --! The grant signal from the arbiter.
		LLControl : buffer low_level_control_t; --! The control lines to the low-level module.
		LLStatus : in low_level_status_t; --! The status lines from the low-level module.
		ReceiveInt : in boolean); --! The receive complete interrupt strobe from the MRF interrupt offload engine.
end entity MRFReceiveOffload;

architecture RTL of MRFReceiveOffload is
	constant FCS_FAIL_RETRY_COUNT : natural := 8;

	signal EnableEngine : boolean;
	signal FramePending : boolean;
	signal PendingFrameLength : positive range 1 to 255;
	signal FlushFrame : boolean;

	signal FrameBuffer : byte_vector(0 to 255);

	signal FrameBufferWriteStrobe : boolean;
	signal FrameBufferReadAddress : natural range 0 to 255 := 1;
	signal FrameBufferWriteAddress : natural range 0 to 255;
	signal FrameBufferReadData, FrameBufferWriteData : byte;

	signal CRCReset : boolean;
	signal CRCData : std_ulogic_vector(7 downto 0);
	signal CRCStrobe : boolean;
	signal CRCResult : std_ulogic_vector(15 downto 0);
	signal CRCBusy : boolean;
	signal CRCZeroTwoBytesAgo : boolean;
begin
	process(HostClock) is
	begin
		if rising_edge(HostClock) then
			FrameBufferReadData <= FrameBuffer(FrameBufferReadAddress);
			if FrameBufferWriteStrobe then
				FrameBuffer(FrameBufferWriteAddress) <= FrameBufferWriteData;
			end if;
		end if;
	end process;

	process(HostClock) is
		type state_t is (IDLE, SEND_DATA);
		variable State : state_t;
		variable Command : natural range 0 to 255;
	begin
		if rising_edge(HostClock) then
			ICBOut.TXStrobe <= false;
			ICBOut.TXData <= X"00";
			ICBOut.TXLast <= false;
			FlushFrame <= false;

			if Reset then
				State := IDLE;
				EnableEngine <= false;
			elsif ICBIn.RXStrobe = ICB_RX_STROBE_COMMAND then
				Command := to_integer(unsigned(ICBIn.RXData));
				case Command is
					when COMMAND_MRF_OFFLOAD =>
						EnableEngine <= true;

					when COMMAND_MRF_RX_GET_SIZE =>
						ICBOut.TXStrobe <= true;
						if FramePending then
							ICBOut.TXData <= std_ulogic_vector(to_unsigned(PendingFrameLength, 8));
						else
							ICBOut.TXData <= X"00";
						end if;
						ICBOut.TXLast <= true;
						State := IDLE;

					when COMMAND_MRF_RX_READ =>
						-- PendingFrameLength will never be 1 so no need to check for that and set TXLast.
						if FramePending then
							ICBOut.TXData <= FrameBufferReadData;
							ICBOut.TXStrobe <= true;
							State := SEND_DATA;
							FrameBufferReadAddress <= 1;
						else
							State := IDLE;
						end if;

					when COMMAND_MRF_OFFLOAD_DISABLE =>
						State := IDLE;
						EnableEngine <= false;

					when others =>
						State := IDLE;
				end case;
			else
				case State is
					when IDLE =>
						FrameBufferReadAddress <= 0;

					when SEND_DATA =>
						if ICBIn.TXReady then
							ICBOut.TXStrobe <= true;
							ICBOut.TXData <= FrameBufferReadData;
							if FrameBufferReadAddress + 1 = PendingFrameLength then
								ICBOut.TXLast <= true;
								State := IDLE;
								FlushFrame <= true;
							end if;
							FrameBufferReadAddress <= FrameBufferReadAddress + 1;
						end if;
				end case;
			end if;
		end if;
	end process;

	process(HostClock) is
		type state_t is (WAIT_INT, WAIT_ARB, SET_RXDECINV, READ_LENGTH, READ_DATA);
		variable State : state_t;
		variable ReceiveIntLatch : boolean;
		variable ReadOffset : natural range 0 to 255;
		variable TriesLeft : natural range 0 to FCS_FAIL_RETRY_COUNT - 1;
	begin
		if rising_edge(HostClock) then
			ReceiveIRQ <= false;
			FCSFailIRQ <= false;
			LLControl.Strobe <= false;
			FrameBufferWriteStrobe <= false;
			CRCReset <= false;
			CRCStrobe <= false;
			CRCData <= LLStatus.ReadData;

			if not EnableEngine then
				State := WAIT_INT;
				ReceiveIntLatch := false;
				FramePending <= false;
			else
				if ReceiveInt then
					ReceiveIntLatch := true;
				end if;

				if FlushFrame then
					FramePending <= false;
				end if;

				case State is
					when WAIT_INT =>
						if ReceiveIntLatch and not FramePending then
							State := WAIT_ARB;
							ReceiveIntLatch := false;
							TriesLeft := FCS_FAIL_RETRY_COUNT - 1;
						end if;

					when WAIT_ARB =>
						if ArbGrant and not LLStatus.Busy then
							LLControl.Strobe <= true;
							LLControl.RegType <= SHORT;
							LLControl.OpType <= WRITE;
							LLControl.Address <= 16#39#; -- BBREG1
							LLControl.WriteData <= "00000100"; -- RXDECINV = 1
							State := SET_RXDECINV;
						end if;

					when SET_RXDECINV =>
						if not LLStatus.Busy then
							LLControl.Strobe <= true;
							LLControl.RegType <= LONG;
							LLControl.OpType <= READ;
							LLControl.Address <= 16#300#;
							State := READ_LENGTH;
						end if;

					when READ_LENGTH =>
						CRCReset <= true;
						if not LLStatus.Busy then
							PendingFrameLength <= to_integer(unsigned(LLStatus.ReadData)) + 2; -- LQI(1) + RSSI(1)
							LLControl.Strobe <= true;
							LLControl.RegType <= LONG;
							LLControl.OpType <= READ;
							LLControl.Address <= 16#301#;
							ReadOffset := 0;
							State := READ_DATA;
						end if;

					when READ_DATA =>
						if not LLStatus.Busy then
							FrameBufferWriteStrobe <= true;
							FrameBufferWriteAddress <= ReadOffset;
							FrameBufferWriteData <= LLStatus.ReadData;
							ReadOffset := ReadOffset + 1;
							if ReadOffset = PendingFrameLength then
								if CRCZeroTwoBytesAgo then
									ReceiveIRQ <= true;
									FramePending <= true;
									LLControl.Strobe <= true;
									LLControl.RegType <= SHORT;
									LLControl.OpType <= WRITE;
									LLControl.Address <= 16#39#; -- BBREG1
									LLControl.WriteData <= "00000000"; -- RXDECINV = 0
									State := WAIT_INT;
								elsif TriesLeft /= 0 then
									TriesLeft := TriesLeft - 1;
									LLControl.Strobe <= true;
									LLControl.RegType <= LONG;
									LLControl.OpType <= READ;
									LLControl.Address <= 16#300#;
									State := READ_LENGTH;
								else
									FCSFailIRQ <= true;
									LLControl.Strobe <= true;
									LLControl.RegType <= SHORT;
									LLControl.OpType <= WRITE;
									LLControl.Address <= 16#39#; -- BBREG1
									LLControl.WriteData <= "00000000"; -- RXDECINV = 0
									State := WAIT_INT;
								end if;
							else
								LLControl.Strobe <= true;
								LLControl.RegType <= LONG;
								LLControl.OpType <= READ;
								LLControl.Address <= 16#301# + ReadOffset;
							end if;
							-- This is two bytes ago, because:
							-- This byte we have only just received and strobed into the CRC module.
							-- The last byte has just appeared in CRCResult and is now being written into CRCZeroTwoBytesAgo.
							-- So when *reading* CRCZeroTwoBytesAgo in this process, we see its value before the write, which was two bytes ago.
							CRCZeroTwoBytesAgo <= CRCResult = X"0000";
							CRCStrobe <= true;
						end if;
				end case;
			end if;
		end if;

		case State is
			when WAIT_INT => ArbRequest <= false;
			when WAIT_ARB => ArbRequest <= true;
			when SET_RXDECINV => ArbRequest <= true;
			when READ_LENGTH => ArbRequest <= true;
			when READ_DATA => ArbRequest <= true;
		end case;
	end process;

	CRC : entity work.MRFCRC(RTL)
	port map(
		Reset => CRCReset,
		Clock => HostClock,
		Data => CRCData,
		Strobe => CRCStrobe,
		CRC => CRCResult,
		Busy => CRCBusy);
end architecture RTL;
