library ieee;
use ieee.std_logic_1164.all;

--! \brief Miscellaneous objects used across the MRF subsystem.
package mrf_common is
	--! \brief The namespace in which a register lives.
	type reg_type_t is (SHORT, LONG);

	--! \brief An operation to perform on a register.
	type op_type_t is (READ, WRITE);

	--! \brief The control signals into the MRF low-level module.
	--!
	--! \param[in] Strobe when \c true, starts a register operation\n
	--! The application may set this signal \c true as little as combinational delay after \ref Busy becomes \c false.
	--! The application must hold this signal \c true across exactly one system clock edge.
	--!
	--! \param[in] RegType the address space (short or long) in which the register lives\n
	--! The application must hold this value as long as \ref Strobe is \c true.
	--!
	--! \param[in] OpType whether to read or write the register\n
	--! The application must hold this value as long as \ref Strobe is \c true.
	--!
	--! \param[in] Address the address of the register to access\n
	--! The application must hold this value as long as \ref Strobe is \c true.
	--!
	--! \param[in] WriteData the data to write to the register\n
	--! The application must hold this value as long as \ref Strobe is \c true.
	--! For read accesses, this value is ignored.
	type low_level_control_t is record
		Strobe : boolean;
		RegType : reg_type_t;
		OpType : op_type_t;
		Address : natural range 0 to 16#3FF#;
		WriteData : std_ulogic_vector(7 downto 0);
	end record low_level_control_t;

	--! \brief An array of \ref low_level_control_t records.
	type low_level_control_vector_t is array(integer range <>) of low_level_control_t;

	--! \brief Combines an array of \ref low_level_control_t records based on which record's Strobe wire is asserted.
	function low_level_control_combine(Controls : low_level_control_vector_t) return low_level_control_t;

	--! \brief The status signals out of the MRF low-level module.
	--!
	--! \param[in] Busy indicates whether an operation is in progress\n
	--! The latency for this signal to become \c true after \ref Strobe becomes \c true is combinational.
	--!
	--! \param[in] ReadData the data read from the register in the last completed operation\n
	--! This value is valid if \ref Busy is \c false and the last operation was a read.
	type low_level_status_t is record
		Busy : boolean;
		ReadData : std_ulogic_vector(7 downto 0);
	end record low_level_status_t;
end package mrf_common;

package body mrf_common is
	function low_level_control_combine(Controls : low_level_control_vector_t) return low_level_control_t is
		variable Result : low_level_control_t;
	begin
		Result.Strobe := false;
		for I in Controls'range loop
			if Controls(I).Strobe then
				Result := Controls(I);
			end if;
		end loop;
		return Result;
	end function low_level_control_combine;
end package body mrf_common;
