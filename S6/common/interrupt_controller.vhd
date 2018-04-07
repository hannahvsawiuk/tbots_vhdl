library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.commands.all;
use work.types.all;

--! \brief A simple interrupt controller that aggregates interrupts and reports them over the ICB.
entity InterruptController is
	generic(
		Count : natural); --! The number of interrupt requests in the system.
	port(
		Reset : in boolean; --! The system reset signal.
		HostClock : in std_ulogic; --! The system clock.
		ICBIn : in icb_input_t; --! The ICB data input.
		ICBOut : buffer icb_output_t; --! The ICB data output.
		InterruptPin : buffer std_ulogic; --! The ICB interrupt pin.

		--! \brief The interrupt requests.
		--!
		--! These are all pulse-sensitive.
		--! For an IRQ to be accepted, the driving peripheral must hold the IRQ line at \c true for at least one clock cycle.
		--! The line should be deasserted back to \c false within a few cycles.
		IRQs : in boolean_vector(0 to Count - 1));
end entity InterruptController;

architecture RTL of InterruptController is
	constant ByteCount : natural := (Count + 7) / 8;
	signal Latch : boolean_vector(0 to Count - 1);
	signal Bytes : byte_vector(0 to ByteCount - 1);
	signal AtomicReadClearStrobe : boolean;
begin
	-- Pad the latched bits out to a multiple of a byte.
	process(Latch) is
		variable IRQIndex : natural;
	begin
		for ByteIndex in Bytes'range loop
			for BitIndex in 0 to 7 loop
				IRQIndex := ByteIndex * 8 + BitIndex;
				if IRQIndex < Count then
					if Latch(IRQIndex) then
						Bytes(ByteIndex)(BitIndex) <= '1';
					else
						Bytes(ByteIndex)(BitIndex) <= '0';
					end if;
				else
					Bytes(ByteIndex)(BitIndex) <= '0';
				end if;
			end loop;
		end loop;
	end process;

	-- Instantiate a ReadableRegister to provide the ICB infrastructure.
	RReg : entity work.ReadableRegister(RTL)
	generic map(
		Command => COMMAND_GET_CLEAR_IRQS,
		Length => ByteCount)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		ICBIn => ICBIn,
		ICBOut => ICBOut,
		Value => Bytes,
		AtomicReadClearStrobe => AtomicReadClearStrobe);

	-- Update the latch based on incoming IRQs and the atomic read-and-clear strobe.
	process(HostClock) is
	begin
		if rising_edge(HostClock) then
			for IRQIndex in Latch'range loop
				if AtomicReadClearStrobe then
					Latch(IRQIndex) <= IRQs(IRQIndex);
				else
					Latch(IRQIndex) <= Latch(IRQIndex) or IRQs(IRQIndex);
				end if;
			end loop;
		end if;
	end process;

	-- Control the output pin.
	process(Latch) is
	begin
		InterruptPin <= '0';
		for I in 0 to Count - 1 loop
			if Latch(I) then
				InterruptPin <= '1';
			end if;
		end loop;
	end process;
end architecture RTL;
