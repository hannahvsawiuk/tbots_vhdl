-- *******************************************************************************************************************
-- Brief: A lightweight round-robin arbiter. 
-- Round robin arbitration: in its basic form, is a simple time slice scheduling, 
--       allowing each requestor an equal share of the time in accessing a memory 
--      or a limited processing resource in a circular order. 
-- RRA are suitable for a small amount of requesters
-- *******************************************************************************************************************

-- libraries
library ieee;
use ieee.std_logic_1164.all;
use work.types.all;

-- *******************************************************************************************************************
-- purpose	: define the entity, the entity's ports, and the port types
-- I/O		
--	Input	: 
-- 			- Reset : arbiter's reset signal
--          - HostClock : the system's clock --> 80MHz clock (see top and clock_gen)
--          - Request: incoming requests for resources
--              + Each user must be assigned an element in this vector.
--              + When the user requires use of the arbitrated resource, it must set its element \c true
--              + The element must remain \c true as long as the resource is in use.
--              + When the element is brought \c false, the resource is released.
-- 	Outputs	: 
--          - Grant : The outgoing resource grants to the users.
--              + Whenever an element of this vector is \c true, the specified user may use the arbitrated resource.
--              + Once the resource is granted, the grant will not be revoked until the user stops requesting it.
--              + Latency from the rising edge of a \ref Request line to the rising edge of the corresponding Grant line ranges from combinational to arbitrarily many cycles.
--              + Latency from the falling edge of a \ref Request line to the falling edge of the corresponding Grant line is always combinational.
--  Generics : Width : The number of users of the arbiter.
-- *******************************************************************************************************************

-- entity Arbiter is
-- 	generic(
-- 		Width : in positive
--     );
-- 	port(
-- 		Reset : in boolean;
-- 		HostClock : in std_ulogic;
-- 		Request : in boolean_vector(0 to Width - 1)
--     	Grant : buffer boolean_vector(0 to Width - 1)
--     );
-- end entity Arbiter;
-- *******************************************************************************************************************
-- purpose	: define the processes associated with the Arbiter entity
-- I/O		
-- *******************************************************************************************************************



architecture RTL of Arbiter is
	signal Spinner : boolean_vector(0 to Width - 1);
begin