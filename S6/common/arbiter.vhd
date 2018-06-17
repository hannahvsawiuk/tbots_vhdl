library ieee;
use ieee.std_logic_1164.all;
use work.types.all;

--! \brief A lightweight round-robin arbiter.
--!
--! This arbiter is suitable for use with relatively small numbers of users.
--! For a large number of users, it will introduce undue delay.
entity Arbiter is
	generic(
		--! \brief The number of users of the arbiter.
		Width : in positive);
	port(
		--! \brief The system reset signal.
		Reset : in boolean;

		--! \brief The system clock.
		HostClock : in std_ulogic;

		--! \brief The incoming requests for resources.
		--!
		--! Each user must be assigned an element in this vector.
		--! When the user requires use of the arbitrated resource, it must set its element \c true.
		--! The element must remain \c true as long as the resource is in use.
		--! When the element is brought \c false, the resource is released.
		Request : in boolean_vector(0 to Width - 1);

		--! \brief The outgoing resource grants to the users.
		--!
		--! Whenever an element of this vector is \c true, the specified user may use the arbitrated resource.
		--! Once the resource is granted, the grant will not be revoked until the user stops requesting it.
		--!
		--! Latency from the rising edge of a \ref Request line to the rising edge of the corresponding Grant line ranges from combinational to arbitrarily many cycles.
		--! Latency from the falling edge of a \ref Request line to the falling edge of the corresponding Grant line is always combinational.
		Grant : buffer boolean_vector(0 to Width - 1));
end entity Arbiter;

architecture RTL of Arbiter is
	signal Spinner : boolean_vector(0 to Width - 1);
begin
	process(HostClock) is
		variable AnyGrant : boolean;
	begin
		if rising_edge(HostClock) then
			if Reset then
				Spinner <= (0 => true, others => false);
			else
				AnyGrant := false;
				for I in Grant'range loop
					AnyGrant := AnyGrant or Grant(I);
				end loop;

				if not AnyGrant then
					Spinner <= Spinner(Width - 1) & Spinner(0 to Width - 2);
				end if;
			end if;
		end if;
	end process;

	process(Request, Spinner) is
	begin
		for I in Request'range loop
			Grant(I) <= Request(I) and Spinner(I);
		end loop;
	end process;
end architecture RTL;
