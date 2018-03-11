library ieee;
use ieee.std_logic_1164.all;

--! \brief A collection of useful types and a few functions to manipulate them.
package types is
	--! \brief An array of booleans.
	type boolean_vector is array(integer range<>) of boolean;

	--! \brief A byte.
	subtype byte is std_ulogic_vector(7 downto 0);

	--! \brief An array of bytes.
	type byte_vector is array(integer range<>) of byte;

	--! \brief The possible activities of the ICB receiver.
	type icb_rx_strobe_t is (
		--! \brief No activity is happening on this clock edge.
		ICB_RX_STROBE_NONE,
		--! \brief On this clock edge, RXData contains a command byte.
		ICB_RX_STROBE_COMMAND,
		--! \brief On this clock edge, RXData contains a parameter byte.
		ICB_RX_STROBE_DATA,
		--! \brief The transaction has ended intact.
		ICB_RX_STROBE_EOT_OK,
		--! \brief The transaction has ended with an invalid CRC.
		--!
		--! This status is strobed for both out and in transactions that fail received CRC.
		ICB_RX_STROBE_EOT_CORRUPT
	);

	--! \brief The inputs from the ICB to a bus endpoint.
	type icb_input_t is record
		--! \brief What receive activity is happening on this clock edge.
		RXStrobe : icb_rx_strobe_t;
		--! \brief The command or data byte being received.
		RXData : byte;
		--! \brief Whether the transmit buffer is able to accept data on the next clock edge.
		TXReady : boolean;
	end record icb_input_t;

	--! \brief The outputs from a bus endpoint to the ICB.
	type icb_output_t is record
		--! \brief Whether to push a byte of data into the transmit buffer on the next clock edge.
		TXStrobe : boolean;
		--! \brief The byte of data to push.
		TXData : byte;
		--! \brief Whether the byte of data currently being pushed is the last byte in the parameter block.
		TXLast : boolean;
	end record icb_output_t;

	type icb_outputs_t is array(integer range<>) of icb_output_t;

	type encoders_pin_t is array(0 to 3) of std_ulogic_vector(0 to 1);

	type halls_pin_t is array(0 to 4) of std_ulogic_vector(0 to 2);

	type halls_pin_valid_t is array(0 to 4) of boolean_vector(0 to 2);

	type motors_phases_pin_t is array(0 to 4) of std_ulogic_vector(0 to 2);

	function icb_output_combine(Outputs : icb_outputs_t) return icb_output_t;

	function to_boolean(X : std_ulogic) return boolean;

	function to_stdulogic(X : boolean) return std_ulogic;
end package types;

package body types is
	function icb_output_combine(Outputs : icb_outputs_t) return icb_output_t is
		variable I : integer;
		variable Result : icb_output_t;
	begin
		Result.TXStrobe := false;
		Result.TXData := X"00";
		Result.TXLast := false;
		for I in Outputs'range loop
			Result.TXStrobe := Result.TXStrobe or Outputs(I).TXStrobe;
			Result.TXData := Result.TXData or Outputs(I).TXData;
			Result.TXLast := Result.TXLast or Outputs(I).TXLast;
		end loop;
		return Result;
	end function icb_output_combine;

	function to_boolean(X : std_ulogic) return boolean is
	begin
		return X = '1';
	end function to_boolean;

	function to_stdulogic(X : boolean) return std_ulogic is
	begin
		if X then
			return '1';
		else
			return '0';
		end if;
	end function to_stdulogic;
end package body types;
