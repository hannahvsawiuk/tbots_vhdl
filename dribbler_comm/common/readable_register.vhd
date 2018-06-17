library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.types.all;

--! \brief A block of bytes that can be read by the MCU over the ICB.
--!
--! When the MCU requests the value of the register, all bytes are captured in a single, atomic operation.
--! It is also possible for the data source to detect exactly when the capture occurs, to provide an atomic test-and-clear operation to the MCU.
entity ReadableRegister is
	generic(
		--! \brief The command that triggers the register to be read out.
		Command : natural;

		--! \brief The number of bytes in the register.
		Length : positive);
	port(
		--! \brief System reset.
		Reset : in boolean;

		--! \brief FPGA system clock.
		HostClock : in std_ulogic;

		--! \brief Inputs from the ICB transceiver.
		ICBIn : in icb_input_t;

		--! \brief Outputs to the ICB transceiver.
		ICBOut : buffer icb_output_t;

		--! \brief The current value of the register.
		Value : in byte_vector(0 to Length - 1);

		--! \brief A strobe indicating when the data capture is about to occur.
		--!
		--! This signal is asserted whenever, at the next rising_edge(HostClock), the register value will be captured for readout.
		--! Thus, atomic test-and-clear can be implemented by clearing the external registers on rising_edge(HostClock) when this signal is asserted.
		--! This guarantees the data is transferred into ReadableRegister and cleared on the same clock edge.
		--!
		--! Of course, if the value would be changed on that clock edge, the application must take care not to lose that change.
		--! It could include the effect of the change combinationally in Value, or it could include the change after the clear on the clock edge.
		AtomicReadClearStrobe : buffer boolean);
end entity ReadableRegister;

architecture RTL of ReadableRegister is
	type state_t is (IDLE, RESPOND);
	signal State : state_t;
	signal BytesSent : natural range 0 to Length - 1;
	signal Latch : byte_vector(Value'range);
begin
	process(HostClock) is
	begin
		if rising_edge(HostClock) then
			ICBOut.TXStrobe <= false;
			ICBOut.TXData <= X"00";
			ICBOut.TXLast <= false;

			if Reset then
				State <= IDLE;
			elsif ICBIn.RXStrobe = ICB_RX_STROBE_COMMAND then
				if to_integer(unsigned(ICBIn.RXData)) = Command then
					State <= RESPOND;
					BytesSent <= 0;
					Latch <= Value;
				else
					State <= IDLE;
				end if;
			elsif State = RESPOND and ICBIn.TXReady then
				ICBOut.TXStrobe <= true;
				ICBOut.TXData <= Latch(0);
				if BytesSent = Length - 1 then
					ICBOut.TXLast <= true;
					State <= IDLE;
				else
					ICBOut.TXLast <= false;
					BytesSent <= BytesSent + 1;
				end if;
				Latch <= Latch(1 to Latch'high) & X"00";
			end if;
		end if;
	end process;

	AtomicReadClearStrobe <= ICBIn.RXStrobe = ICB_RX_STROBE_COMMAND and to_integer(unsigned(ICBIn.RXData)) = Command;
end architecture RTL;
