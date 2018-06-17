library ieee;
use ieee.std_logic_1164.all;

entity SPIMaster is
	generic(
		MaxWidth : positive;
		CPhase : natural range 0 to 1);
	port(
		Reset : in boolean;
		HostClock : in std_ulogic;
		BusClock : in std_ulogic;
		Strobe : in boolean;
		Width : in positive range 1 to MaxWidth;
		WriteData : in std_ulogic_vector(MaxWidth - 1 downto 0);
		ReadData : buffer std_ulogic_vector(MaxWidth - 1 downto 0);
		Busy : buffer boolean;
		ClockOE : buffer boolean;
		MOSIPin : buffer std_ulogic;
		MISOPin : in std_ulogic);
end entity SPIMaster;

architecture RTL of SPIMaster is
	signal StrobeHost : boolean;
	signal StrobeBus : boolean;
	signal ShiftCount : natural range 0 to MaxWidth;
	signal MISOBuffer : std_ulogic;
begin
	process(HostClock) is
	begin
		if rising_edge(HostClock) then
			if Strobe then
				StrobeHost <= not StrobeBus;
			end if;
		end if;
	end process;

	process(BusClock) is
	begin
		if falling_edge(BusClock) then
			if Reset then
				ShiftCount <= 0;
			elsif StrobeHost /= StrobeBus then
				ShiftCount <= Width;
				ReadData <= WriteData;
			elsif ShiftCount /= 0 then
				ShiftCount <= ShiftCount - 1;
				ReadData <= ReadData(MaxWidth - 2 downto 0) & MISOBuffer;
			end if;
			StrobeBus <= StrobeHost;
		end if;
	end process;

	CPhase0 : if CPhase = 0 generate
		MOSIPin <= ReadData(MaxWidth - 1);
		MISOBuffer <= MISOPin when rising_edge(BusClock);
	end generate;
	CPhase1 : if CPhase = 1 generate
		MOSIPin <= ReadData(MaxWidth - 1) when rising_edge(BusClock);
		MISOBuffer <= MISOPin;
	end generate;

	ClockOE <= ShiftCount /= 0;
	Busy <= (ShiftCount /= 0) or (StrobeHost /= StrobeBus) or Strobe;
end architecture RTL;
