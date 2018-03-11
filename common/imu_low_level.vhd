library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.types.all;

entity IMULowLevel is
	generic(
		MultiBit6 : boolean;
		MaxCount : natural;
		CPhase : in natural range 0 to 1);
	port(
		Reset : in boolean;
		HostClock : in std_ulogic;
		BusClock : in std_ulogic;
		Strobe : in boolean;
		Busy : buffer boolean;
		Address : in natural range 0 to 63;
		Count : in positive range 1 to MaxCount;
		Write : in boolean;
		WriteData : in byte_vector(0 to MaxCount - 1);
		ReadData : buffer byte_vector(0 to MaxCount - 1);
		ClockOE : buffer boolean;
		CSPin : buffer std_ulogic;
		MOSIPin : buffer std_ulogic;
		MISOPin : in std_ulogic);
end entity IMULowLevel;

architecture RTL of IMULowLevel is
	constant CS_COUNTER_MAX : natural := 7;
	type state_t is (IDLE, CS_SETUP, START_TRANSFER, TRANSFER, CS_HOLD);
	type regs is record
		State : state_t;
		CSCounter : natural range 0 to CS_COUNTER_MAX;
	end record regs;

	signal CurrentRegs, NextRegs : regs;
	signal SPIStrobe, SPIBusy : boolean;
	signal SPIWrite, SPIRead : std_ulogic_vector((MaxCount + 1) * 8 - 1 downto 0);
	signal SPIWidth : positive range 1 to SPIWrite'high + 1;
begin
	process(Reset, Strobe, Address, Count, Write, WriteData, CurrentRegs, SPIBusy, SPIRead) is
	begin
		NextRegs <= CurrentRegs;
		SPIStrobe <= false;
		Busy <= false;
		CSPin <= '1';

		SPIWrite(SPIWrite'high - 0) <= to_stdulogic(not Write);
		SPIWrite(SPIWrite'high - 1) <= to_stdulogic(MultiBit6 and Count > 1);
		SPIWrite(SPIWrite'high - 2 downto SPIWrite'high - 7) <= std_ulogic_vector(to_unsigned(Address, 6));
		for I in 0 to MaxCount - 1 loop
			SPIWrite(I * 8 + 7 downto I * 8) <= WriteData(MaxCount - 1 - I);
		end loop;

		for I in 0 to MaxCount - 1 loop
			ReadData(MaxCount - 1 - I) <= SPIRead(I * 8 + 7 downto I * 8);
		end loop;

		SPIWidth <= (Count + 1) * 8;

		if Reset then
			NextRegs.State <= IDLE;
			NextRegs.CSCounter <= CS_COUNTER_MAX;
		else
			if CurrentRegs.CSCounter /= 0 then
				NextRegs.CSCounter <= CurrentRegs.CSCounter - 1;
			end if;
			case CurrentRegs.State is
				when IDLE =>
					if CurrentRegs.CSCounter = 0 then
						if Strobe then
							NextRegs.State <= CS_SETUP;
							NextRegs.CSCounter <= CS_COUNTER_MAX;
							Busy <= true;
						else
							Busy <= false;
						end if;
					else
						Busy <= true;
					end if;

				when CS_SETUP =>
					Busy <= true;
					CSPin <= '0';
					if CurrentRegs.CSCounter = 0 then
						NextRegs.State <= START_TRANSFER;
					end if;

				when START_TRANSFER =>
					Busy <= true;
					CSPin <= '0';
					SPIStrobe <= true;
					NextRegs.State <= TRANSFER;

				when TRANSFER =>
					Busy <= true;
					CSPin <= '0';
					if not SPIBusy then
						NextRegs.State <= CS_HOLD;
						NextRegs.CSCounter <= CS_COUNTER_MAX;
					end if;

				when CS_HOLD =>
					Busy <= true;
					CSPin <= '0';
					if CurrentRegs.CSCounter = 0 then
						NextRegs.State <= IDLE;
						NextRegs.CSCounter <= CS_COUNTER_MAX;
					end if;
			end case;
		end if;
	end process;

	CurrentRegs <= NextRegs when rising_edge(HostClock);

	SPI : entity work.SPIMaster(RTL)
	generic map(
		MaxWidth => (MaxCount + 1) * 8,
		CPhase => CPhase)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		BusClock => BusClock,
		Strobe => SPIStrobe,
		Width => SPIWidth,
		WriteData => SPIWrite,
		ReadData => SPIRead,
		Busy => SPIBusy,
		ClockOE => ClockOE,
		MOSIPin => MOSIPin,
		MISOPin => MISOPin);
end architecture RTL;
