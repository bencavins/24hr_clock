/*
 * Top-level module for 24 hour clock.
 */
module clock_24hr(clk5MHz, sw0, sw1, sw2, sw3, btn0, btn1, btn2, ssd3, ssd2, ssd1, ssd0, alarm_set, leds);
	input clk5MHz;  // 5 MHz Clock
	input sw0;      // Hr:Min / Min:Sec
	input sw1;      // Set Clock
	input sw2;      // Set Alarm
	input sw3;      // Toggle Alarm
	input btn0;     // Stop Alarm
	input btn1;     // Increment Minutes / Stop Alarm
	input btn2;     // Incrememt Hours / Stop Alarm 
	output [6:0] ssd0, ssd1, ssd2, ssd3;  // 7 Segment Displays
	output alarm_set;  // Is Alarm On or Off?
	output [9:0] leds; // Ten LED lights
	wire clk100;    // 100 Hz Clock
	wire clk1;      // 1 Hz Clock
	wire aset;      // Is Alarm Set?
	wire aring;     // Is Alarm Ringing?
	wire [1:0] ssd_mode;  // Display Mode
	wire [31:0] centiseconds;  // Total centiseconds (0.01 seconds)
	wire [31:0] alarm;         // Alarm time
	wire [3:0] d3, d2, d1, d0; // SSD Digits
	
	Clock100and1 clock (clk5MHz, 1, 1, 1, clk100, clk1);
	
	clockFSM fsm (clk100, sw0, sw1, sw2, sw3, btn0, btn1, btn2, ssd_mode, centiseconds, alarm, aset, aring);
	
	secondsToDigits s2d (centiseconds, alarm, ssd_mode, d3, d2, d1, d0);
	
	assign alarm_set = ~aset;
	
	blinkLEDs blinker (clk1, aring, leds);
	
	ssdd seg3 (d3, ssd3);
	ssdd seg2 (d2, ssd2);
	ssdd seg1 (d1, ssd1);
	ssdd seg0 (d0, ssd0);
endmodule

/*
 * Module for blinking the LEDs. 
 * 
 * Lights will blink in time with the clk input. If blinking is 1, 
 * the lights will blink. Otherwise, they will be off. 
 */
module blinkLEDs(clk, blinking, leds);
	input clk;       // Clock for timing blinks
	input blinking;  // Blink if 1, off if 0
	output reg [9:0] leds;  // LED lights
	
	always @(posedge clk) begin
		if (blinking) begin
			if (leds == 10'b0000000000) 
				leds = 10'b1111111111;
			else
				leds = 10'b0000000000;
		end else begin
			leds = 10'b0000000000;
		end
	end
endmodule

/*
 * Finite State Machine for the 24 hr Clock.
 *
 * Time is kept in centi-seconds (0.01 seconds)
 */
module clockFSM(clk100hz, sw0, sw1, sw2, sw3, b0, b1, b2, ssd_mode, csec_counter, alarm, is_alarm_set, is_alarm_ringing);
	input clk100hz;  // 100 Hz clock
	input sw0;  // hh/mm : mm/ss toggle
	input sw1;  // set clock
	input sw2;  // set alarm
	input sw3;  // alarm on/off
	input b0;   // stop alarm
	input b1;   // increment minutes / stop alarm
	input b2;   // increment hours / stop alarm
	output reg [1:0] ssd_mode;  // display mode
	output reg [31:0] csec_counter = 32'b0;  // centi-second counter for clock
	output reg [31:0] alarm = 31'b0;         // centi-second counter for alarm
	output reg is_alarm_set = 1'b0;          // 1 if alarm is set
	output reg is_alarm_ringing = 1'b0;      // 1 if alarm is ringing
	parameter [1:0] A=2'b00,B=2'b01,C=2'b10,D=2'b11;
	parameter [1:0] HHMM=2'b00,MMSS=2'b01,CSET=2'b10,ASET=2'b11;
	parameter [31:0] MAX = 8640000;
	reg [1:0] y, Y;
	
	always @(sw3) begin
		if (sw3) is_alarm_set = 1'b1;
		else is_alarm_set = 1'b0;
	end
	
	always @(sw0, sw1, sw2, y) begin
		case (y)
			A:  if (sw0)      Y=B;
			    else if (sw1) Y=C;
				 else if (sw2) Y=D;
				 else          Y=A;
			B:  if (~sw0)     Y=A;
			    else          Y=B;
			C:  if (~sw1)     Y=A;
			    else          Y=C;
			D:  if (~sw2)     Y=A;
			    else          Y=D;
			default:          Y=2'bxx;
		endcase
	end
	
	reg old_b0 = 1;
	reg old_b1 = 1;
	always @(posedge clk100hz) begin
		if (y == C) begin
			if (b0 == 0 && old_b0 == 1) begin
				csec_counter = csec_counter + 6000;
				old_b0 = 0;
			end else if (b0 == 1 && old_b0 == 0) begin
				old_b0 = 1;
			end else if (b1 == 0 && old_b1 == 1) begin
				csec_counter = csec_counter + 360000;
				old_b1 = 0;
			end else if (b1 == 1 && old_b1 == 0) begin
				old_b1 = 1;
			end
		end else if (y == D) begin
			if (b0 == 0 && old_b0 == 1) begin
				alarm = alarm + 6000;
				old_b0 = 0;
			end else if (b0 == 1 && old_b0 == 0) begin
				old_b0 = 1;
			end else if (b1 == 0 && old_b1 == 1) begin
				alarm = alarm + 360000;
				old_b1 = 0;
			end else if (b1 == 1 && old_b1 == 0) begin
				old_b1 = 1;
			end
		end
		csec_counter = csec_counter+1;
		csec_counter = csec_counter % MAX;
		if (is_alarm_set) begin
			if ((csec_counter / 100) == (alarm / 100)) begin
				is_alarm_ringing = 1'b1;
			end
		end
		if (is_alarm_ringing) begin
			if (~b0 || ~b1 || ~b2) begin 
				is_alarm_ringing = 1'b0;
			end
		end
		y <= Y;
	end
	
	always @(y, sw0, sw1) begin
		case (y)
			A: begin
				ssd_mode = HHMM;
				end
			B: begin
				ssd_mode = MMSS;
				end
			C: begin
				ssd_mode = CSET;
				end
			D: begin
				ssd_mode = ASET;
				end
		endcase
	end
endmodule 

/*
 * Module for converting centiseconds to hours, minutes, and
 * seconds BCDs. These can be used for SSDs. 
 */
module secondsToDigits(centiseconds, alarm, mode, dig3, dig2, dig1, dig0);
	input [31:0] centiseconds;  // Time in centi-seconds
	input [31:0] alarm;         // Alarm time in centi-seconds
	input [1:0] mode;           // Display mode
	output reg [3:0] dig3, dig2, dig1, dig0;  // Output digits
	integer hrs, mins, secs;     // hrs, mins, secs for clock
	integer ahrs, amins, asecs;  // hrs, mins, secs for alarm
	parameter [31:0] SECSINHR = 3600;
	parameter [31:0] SECSINMIN = 60;
	parameter [31:0] CSECSINSEC = 100;
	parameter [1:0] HHMM=2'b00,MMSS=2'b01,CSET=2'b10,ASET=2'b11;
	
	always @(mode, centiseconds, alarm) begin
		hrs = (centiseconds / SECSINHR / CSECSINSEC) % 24;
		mins = (centiseconds / SECSINMIN / CSECSINSEC) % 60;
		secs = (centiseconds / CSECSINSEC) % 60;
		
		ahrs = (alarm / SECSINHR / CSECSINSEC) % 24;
		amins = (alarm / SECSINMIN / CSECSINSEC) % 60;
		asecs = (alarm / CSECSINSEC) % 60;

		if (mode == HHMM) begin
			dig3 = (hrs / 10) % 10;
			dig2 = hrs % 10;
			dig1 = (mins / 10) % 10;
			dig0 = mins % 10;
		end else if (mode == MMSS) begin
			dig3 = (mins / 10) % 10;
			dig2 = mins % 10;
			dig1 = (secs / 10) % 10;
			dig0 = secs % 10;
		end else if (mode == ASET) begin
			dig3 = (ahrs / 10) % 10;
			dig2 = ahrs % 10;
			dig1 = (amins / 10) % 10;
			dig0 = amins % 10;
		end else if (mode == CSET) begin
			dig3 = (hrs / 10) % 10;
			dig2 = hrs % 10;
			dig1 = (mins / 10) % 10;
			dig0 = mins % 10;
		end else begin
			dig3 = 4'd8;
			dig2 = 4'd8;
			dig1 = 4'd8;
			dig0 = 4'd8;
		end
	end
endmodule
