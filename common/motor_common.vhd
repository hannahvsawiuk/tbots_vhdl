library ieee;
use ieee.numeric_std.all;

--! \brief Miscellaneous objects used across the motors subsystem.
package motor_common is
	--! \brief The commutation mode options.
	type commutation_mode is (COAST, BRAKE, DRIVE);

	--! \brief The commutation direction options for Hall sensor control.
	type commutation_direction is (FORWARD, REVERSE);

	--! \brief The phase drive modes for a motor phase.
	type phase_drive_mode is (FLOAT, PWM, LOW, HIGH);
	type phase_drive_mode_vector is array(integer range <>) of phase_drive_mode;

	--! \brief The decoded motor parameter block for a motor.
	type motor_drive_mode is record
		Mode : commutation_mode;
		Direction : commutation_direction;
		DutyCycle : natural range 0 to 255;
	end record motor_drive_mode;
	type motor_drive_mode_vector is array(integer range <>) of motor_drive_mode;

	--! \brief The type of a Hall sensor counter value.
	subtype hall_count is unsigned(15 downto 0);
	type hall_count_vector is array(integer range<>) of hall_count;
end package motor_common;
