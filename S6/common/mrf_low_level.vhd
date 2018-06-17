library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.mrf_common.all;
use work.types.all;

--! \brief Implements low-level register operations to the MRF24J40.
entity MRFLowLevel is
	port(
		Reset : in boolean; --! The system reset signal.
		HostClock : in std_ulogic; --! The system clock.
		BusClock : in std_ulogic; --! The SPI bus clock.
		Control : in low_level_control_t; --! The control lines.
		Status : buffer low_level_status_t; --! The status lines.
		CSPin : buffer std_ulogic; --! The SPI chip select pin.
		ClockOE : buffer boolean; --! The output enable signal for the SPI clock.
		MOSIPin : buffer std_ulogic; --! The SPI MOSI pin.
		MISOPin : in std_ulogic); --! The SPI MISO pin.
end entity MRFLowLevel;

architecture RTL of MRFLowLevel is
	signal ControlLatched : low_level_control_t;

	signal StateMachineBusy : boolean;

	signal SPIStrobe : boolean;
	signal SPIWidth : positive range 1 to 24;
	signal SPIWriteData : std_ulogic_vector(23 downto 0);
	signal SPIReadData : std_ulogic_vector(23 downto 0);
	signal SPIBusy : boolean;
begin
	-- The main state machine.
	process(HostClock) is
		constant CS_DELAY_TICKS : positive := 4;

		type state_t is (IDLE, ASSERT_CS_WAIT, DATA, PRE_DEASSERT_CS_WAIT);
		variable State : state_t;

		variable CSDelayTicks : natural range 0 to CS_DELAY_TICKS - 1;
	begin
		-- State machine.
		if rising_edge(HostClock) then
			SPIStrobe <= false;
			if Reset then
				State := IDLE;
				CSDelayTicks := 0;
			elsif Control.Strobe then
				State := ASSERT_CS_WAIT;
				ControlLatched <= Control;
				ControlLatched.Strobe <= false;
				CSDelayTicks := CS_DELAY_TICKS - 1;
			else
				if CSDelayTicks /= 0 then
					CSDelayTicks := CSDelayTicks - 1;
				end if;
				case State is
					when IDLE =>
						null;
					when ASSERT_CS_WAIT =>
						if CSDelayTicks = 0 then
							SPIStrobe <= true;
							State := DATA;
						end if;
					when DATA =>
						if not SPIBusy then
							State := PRE_DEASSERT_CS_WAIT;
							CSDelayTicks := CS_DELAY_TICKS - 1;
						end if;
					when PRE_DEASSERT_CS_WAIT =>
						if CSDelayTicks = 0 then
							State := IDLE;
							CSDelayTicks := CS_DELAY_TICKS - 1;
						end if;
				end case;
			end if;
		end if;

		StateMachineBusy <= State /= IDLE or CSDelayTicks /= 0;
		CSPin <= to_stdulogic(State = IDLE);
	end process;

	-- Combinationally compute some SPI master control lines.
	process(ControlLatched) is
		variable OpTypeBit : std_ulogic;
	begin
		if ControlLatched.OpType = READ then
			OpTypeBit := '0';
		else
			OpTypeBit := '1';
		end if;
		case ControlLatched.RegType is
			when SHORT =>
				SPIWidth <= 16;
				SPIWriteData <= "0" & std_ulogic_vector(to_unsigned(ControlLatched.Address, 6)) & OpTypeBit & ControlLatched.WriteData & X"00";
			when LONG =>
				SPIWidth <= 24;
				SPIWriteData <= "1" & std_ulogic_vector(to_unsigned(ControlLatched.Address, 10)) & OpTypeBit & "0000" & ControlLatched.WriteData;
		end case;
	end process;

	-- Compute the busy signal to include when Strobe is first asserted.
	Status.Busy <= StateMachineBusy or Control.Strobe;

	-- The last eight bits shifted on the bus always appear at the bottom of the SPI read data vector, and are the read data in case of a register read.
	Status.ReadData <= SPIReadData(7 downto 0);

	-- An SPI master transceiver is the bottom level of talking to the MRF24J40.
	SPI : entity work.SPIMaster(RTL)
	generic map(
		MaxWidth => 24,
		CPhase => 0)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		BusClock => BusClock,
		Strobe => SPIStrobe,
		Width => SPIWidth,
		WriteData => SPIWriteData,
		ReadData => SPIReadData,
		Busy => SPIBusy,
		ClockOE => ClockOE,
		MOSIPin => MOSIPin,
		MISOPin => MISOPin);
end architecture RTL;
