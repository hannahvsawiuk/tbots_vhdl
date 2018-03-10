library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.types.all;

entity Gyro is
	generic(
		Command : natural);
	port(
		Reset : in boolean;
		HostClock : in std_ulogic;
		BusClock : in std_ulogic; --! SPI Clock max 10 MHz
		ICBIn : in icb_input_t;
		ICBOut : buffer icb_output_t;
		ClockOE : buffer boolean;
		CSPin : buffer std_ulogic;
		MOSIPin : buffer std_ulogic;
		MISOPin : in std_ulogic);
end entity;

architecture RTL of Gyro is
	type init_op is record
		Address : natural range 0 to 63;
		Value : std_ulogic_vector(7 downto 0);
	end record init_op;
	type init_op_vector is array(integer range<>) of init_op;
	constant INIT_OPS_COUNT : natural := 2;
	constant INIT_OPS : init_op_vector(0 to INIT_OPS_COUNT - 1) := (
		(Address => 16#0F#, Value => "10000000"), -- RANGE = { fixed = 10, range = 000 /* 2000 d/s */ }
		(Address => 16#10#, Value => "00000001")); -- BW = { bw = 0001 /* 2000 Hz ODR, 230 Hz filter */ }

	type state_t is (CHECK_CHIP_ID, SEND_INIT_OPS, READ_DATA);
	type substate_t is (START, FINISH);
	type regs is record
		State : state_t;
		Substate : substate_t;
		CurrentInitOp : natural range 0 to INIT_OPS_COUNT - 1;
		ICBData : byte_vector(0 to 6);
		AnyReadFinished : boolean;
	end record regs;
	signal CurrentRegs, NextRegs : regs;

	signal LLStrobe, LLBusy, LLWrite : boolean;
	signal LLAddress : natural range 0 to 63;
	signal LLCount : positive range 1 to 6;
	signal LLWriteData, LLReadData : byte_vector(0 to 5);
begin
	process(Reset, CurrentRegs, LLBusy, LLReadData) is
	begin
		NextRegs <= CurrentRegs;
		LLStrobe <= false;
		LLWrite <= false;
		LLAddress <= 0;
		LLCount <= 1;
		LLWriteData <= (others => X"00");
		NextRegs.ICBData(0) <= X"00";

		if Reset then
			NextRegs.State <= CHECK_CHIP_ID;
			NextRegs.Substate <= START;
			NextRegs.CurrentInitOp <= 0;
			NextRegs.AnyReadFinished <= false;
		else
			case CurrentRegs.State is
				when CHECK_CHIP_ID =>
					LLWrite <= false;
					LLAddress <= 16#00#; -- CHIP_ID
					if not LLBusy then
						case CurrentRegs.Substate is
							when START =>
								LLStrobe <= true;
								NextRegs.Substate <= FINISH;
							when FINISH =>
								NextRegs.ICBData(1) <= LLReadData(LLReadData'high);
								NextRegs.Substate <= START;
								if LLReadData(LLReadData'high) = "00001111" then
									NextRegs.State <= SEND_INIT_OPS;
								end if;
						end case;
					end if;

				when SEND_INIT_OPS =>
					LLWrite <= true;
					LLAddress <= INIT_OPS(CurrentRegs.CurrentInitOp).Address;
					LLWriteData(0) <= INIT_OPS(CurrentRegs.CurrentInitOp).Value;
					if not LLBusy then
						case CurrentRegs.Substate is
							when START =>
								LLStrobe <= true;
								NextRegs.Substate <= FINISH;
							when FINISH =>
								NextRegs.Substate <= START;
								if CurrentRegs.CurrentInitOp = INIT_OPS_COUNT - 1 then
									NextRegs.State <= READ_DATA;
								else
									NextRegs.CurrentInitOp <= CurrentRegs.CurrentInitOp + 1;
								end if;
						end case;
					end if;

				when READ_DATA =>
					LLWrite <= false;
					LLAddress <= 16#02#; -- RATE_X_LSB
					LLCount <= 6;
					if not LLBusy then
						case CurrentRegs.Substate is
							when START =>
								LLStrobe <= true;
								NextRegs.Substate <= FINISH;
							when FINISH =>
								NextRegs.ICBData(1 to 6) <= LLReadData(0 to 5);
								NextRegs.AnyReadFinished <= true;
								NextRegs.Substate <= START;
						end case;
					end if;
					if CurrentRegs.AnyReadFinished then
						NextRegs.ICBData(0) <= X"01";
					end if;
			end case;
		end if;
	end process;

	CurrentRegs <= NextRegs when rising_edge(HostClock);

	-- Instantiate low-level interface.
	LL : entity work.IMULowLevel(RTL)
	generic map(
		MultiBit6 => false,
		MaxCount => 6,
		CPhase => 1)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		BusClock => BusClock,
		Strobe => LLStrobe,
		Busy => LLBusy,
		Address => LLAddress,
		Count => LLCount,
		Write => LLWrite,
		WriteData => LLWriteData,
		ReadData => LLReadData,
		ClockOE => ClockOE,
		CSPin => CSPin,
		MOSIPin => MOSIPin,
		MISOPin => MISOPin);

	-- Instantiate ICB interface.
	ICB : entity work.ReadableRegister(RTL)
	generic map(
		Command => Command,
		Length => 7)
	port map(
		Reset => Reset,
		HostClock => HostClock,
		ICBIn => ICBIn,
		ICBOut => ICBOut,
		Value => CurrentRegs.ICBData,
		AtomicReadClearStrobe => open);
end architecture RTL;
