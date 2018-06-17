 
module tb_motor_pwm;

reg Reset, PWMClock;
reg [7:0] DutyCycle; // 8 bit requested duty cycle 
wire [7:0] Count; // 8 bit counter
wire [7:0] DutyCycleShadow;
        signal Count : natural range 0 to 254;
	signal DutyCycleShadow : natural range 0 to 255;

endmodule 


