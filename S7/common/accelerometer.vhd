-- LIS3DH MEMS digital output motion sensor: ultra-low-power high-performance 3-axis "nano" accelerometer

-- *******************************************************************************************************************
-- Electronics
-- purpose	: accelerometer
-- I/O		
--	Input	: 
-- 			- ACCEL_CS : SPI enable, 1: SPI Idle mode and IC^2 comm enabled, 0: SPI comm mode and IC^2 disabled
--          - ACCEL_CLK : SPI serial port clock (SPC)
--          - ACCEL_MOSI : SPI serial data input (SDI)
-- 	Outputs	: 
--          - ACCEL_MISO : SPI serial data output (SDO)
--          - ACCEL_INT : Inertial interrupt 1
-- *******************************************************************************************************************

-- *******************************************************************************************************************
-- Purpose: to generate 5 clock signals (1MHz, 8MHz, 2x10MHz, 80MHz) and 
-- 			a logic ready signal from a 40MHz external oscillator. 
-- 			The outputs of this entity are used by the files in 'common' folder. 
-- *******************************************************************************************************************

-- libraries
library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.types.all;