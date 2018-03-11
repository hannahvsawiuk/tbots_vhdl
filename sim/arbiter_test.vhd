library ieee;
use ieee.std_logic_1164.all;

library work;
use work.types.all;

entity arbiter_test is
end entity arbiter_test;

architecture Behavioural of arbiter_test is
	function none_high(X : boolean_vector) return boolean is
	begin
		for I in X'range loop
			if X(I) then
				return false;
			end if;
		end loop;
		return true;
	end function none_high;

	procedure wait_cycles(signal Clock : in std_ulogic; Cycles : in natural) is
	begin
		for I in 1 to Cycles loop
			wait until rising_edge(Clock);
		end loop;
	end procedure wait_cycles;

	procedure expect_high_within(signal X : in boolean; signal Clock : in std_ulogic; Cycles : in natural) is
	begin
		for I in 1 to Cycles loop
			wait until falling_edge(Clock);
			if X then
				wait until rising_edge(Clock);
				return;
			end if;
		end loop;
		assert false severity failure;
	end procedure expect_high_within;

	constant ClockPeriod : time := 1 us;
	constant Width : positive := 4;

	signal Reset : boolean := false;
	signal Clock : std_ulogic := '0';
	signal Request : boolean_vector(0 to Width - 1) := (others => false);
	signal Grant : boolean_vector(0 to Width - 1) := (others => false);
	signal EnableClock : boolean := false;
begin
	UUT : entity work.Arbiter(RTL)
	generic map(
		Width => Width)
	port map(
		Reset => Reset,
		HostClock => Clock,
		Request => Request,
		Grant => Grant);

	process is
	begin
		while true loop
			if not EnableClock then
				wait until EnableClock;
			end if;
			Clock <= '1';
			wait for ClockPeriod / 2;
			Clock <= '0';
			wait for ClockPeriod / 2;
		end loop;
	end process;

	-- Two grants must never be high simultaneously.
	process(Grant) is
		variable Count : natural;
	begin
		Count := 0;
		for I in Grant'range loop
			if Grant(I) then
				Count := Count + 1;
			end if;
		end loop;
		assert Count <= 1 severity failure;
	end process;

	-- A grant must never be high if its request is low.
	process is
	begin
		for I in Request'range loop
			if not Request(I) then
				wait for 1 fs;
				assert not Grant(I) severity failure;
			end if;
		end loop;
		wait on Request;
	end process;

	process is
	begin
		-- At reset, all grants must be false.
		Reset <= true;
		EnableClock <= true;
		wait_cycles(Clock, 3);
		assert none_high(Grant) severity failure;
		Reset <= false;

		-- Issuing a request must result in the grant being given eventually.
		Request(2) <= true;
		expect_high_within(Grant(2), Clock, Width);

		-- The grant must stay high as long as the request does.
		for I in 0 to 3 loop
			wait until falling_edge(Clock);
			assert Grant(2) severity failure;
		end loop;

		-- Drop the request. The verification process checks that grant drops
		-- with it.
		Request(2) <= false;
		wait_cycles(Clock, 1);

		-- Issue a request and wait for it to be granted.
		Request(1) <= true;
		expect_high_within(Grant(1), Clock, Width);

		-- Issue another request while the first is granted.
		wait until rising_edge(Clock);
		Request(2) <= true;

		-- Grant(1) must stay high as long as Request(1) does. Then the
		-- verification process checks that Grant(2) does not go high.
		for I in 0 to 3 loop
			wait until falling_edge(Clock);
			assert Grant(1) severity failure;
		end loop;

		-- Drop Request(1). The verification process checks that grant drops
		-- with it. Now Request(2) must be granted shortly.
		Request(1) <= false;
		expect_high_within(Grant(2), Clock, Width);

		-- Drop Request(2) and Request(3) and Request(0) simultaneously. The
		-- verification process checks that, even when asserted simultaneously,
		-- only one request is granted.
		Request(2) <= false;
		Request(3) <= true;
		Request(0) <= true;
		wait_cycles(Clock, 4);

		-- Done tests.
		EnableClock <= false;
		wait;
	end process;
end architecture Behavioural;
