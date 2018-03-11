library ieee;
use ieee.std_logic_1164.all;

--! A simple PWM generator.
entity MotorPWM is
	generic(
		Phase : in natural range 0 to 255); --! The reset value of the PWM counter.
	port(
		Reset : in boolean; --! The system reset signal.
		PWMClock : in std_ulogic; --! The PWM timebase clock.
		DutyCycle : in natural range 0 to 255; --! The current requested duty cycle.
		Output : buffer boolean); --! Whether the output is active.
end entity MotorPWM;

architecture RTL of MotorPWM is
	signal Count : natural range 0 to 254;
	signal DutyCycleShadow : natural range 0 to 255;
begin
	process(PWMClock) is
	begin
		if rising_edge(PWMClock) then
			if Reset then
				Count <= Phase;
				DutyCycleShadow <= DutyCycle;
			elsif Count = 254 then
				Count <= 0;
				DutyCycleShadow <= DutyCycle;
			else
				Count <= Count + 1;
			end if;
		end if;
	end process;

	Output <= Count < DutyCycleShadow;
end architecture RTL;
