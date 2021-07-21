/*
 * Psion 5MX Display and keyboard driver
 *
 */
//`include "util.v"
`include "uart.v"
`include "spi_display.v"

`define UART_DISPLAY
module lfsr32(
        input clk,
        input reset,
        output [31:0] out
);
	parameter RESET_STATE = 32'h1;
        reg [31:0] out = RESET_STATE;

        always @(posedge clk)
                if (reset)
                        out <= 1;
                else
                if (out[0])
                        out <= (out >> 1) ^ 32'hD0000001;
                else
                        out <= (out >> 1);
endmodule


module psion_display(
	input clk,
	input reset,

	// physical
	output clk_out,
	output row_out,
	output frame_out,
	output [3:0] data_out,
	output enable_out,

	// frame buffer (to be written)
);
	parameter WIDTH = 640 / 4;
	parameter HEIGHT = 240;

	// Divide the input clock into output clock pulses
	// the output clock pulse is twice as long 
	reg [2:0] divider = 0;
	wire rising_edge = divider == 3'b000;
	wire falling_edge = divider == 3'b100;
	always @(posedge clk)
		divider <= divider + 1;

	reg clk_out = 0;
	assign enable_out = !reset;

	reg [3:0] data_out = 0;

	reg [7:0] x = 0; // up to 640/4 == 160, only need 8 bits
	reg [7:0] y = 0; // up to 240; need 8 bits

	// assert the frame output the entire time the first
	// row is being sent to match the data sheet
	reg frame_out = 0;
	reg row_out = 0;

	reg [31:0] lfsr;
	lfsr32 rand_src(clk, reset, lfsr);

	reg [7:0] fb[0:2047];
        initial $readmemh("psion.hex", fb);
	reg [7:0] fb_byte;

	always @(posedge clk)
		fb_byte <= fb[{y[6:0], x[4:1]}];

	always @(posedge clk)
	if (reset) begin
		x <= 0;
		y <= 0;
		row_out <= 0;
		frame_out <= 0;
		data_out <= 0;
		clk_out <= 0;
	end else
	if (falling_edge)
	begin
		// hold all the bits
		clk_out <= 0;
	end else
	if (rising_edge)
	begin
		if (frame_out)
		begin
			// drop the row output,
			// then drop the frame output next clock
			if (row_out)
				row_out <= 0;
			else
				frame_out <= 0;
		end else
		if (row_out)
		begin
			row_out <= 0;
		end else

		if (x == WIDTH-1)
		begin
			// end of the row
			x <= 0;
			row_out <= 1;
			if (y == HEIGHT - 1)
			begin
				frame_out <= 1;
				y <= 0;
			end else begin
				y <= y + 1;
			end
		end else begin
			clk_out <= 1;

			x <= x + 1;
			//data_out <= lfsr[3:0]; // x[3:0] + y[3:0];
			//if (x[1] ^ y[3])
			if (y < 40 ? x[0] ^ y[0] : y < 100 ? x[1] ^ y[2] : y < 160 ? x[3] ^ y[4] : x[4] ^ y[5])
				data_out <= 4'b1111; //y[3:0] ^ x[7:4];
			else
				data_out <= 4'b0000; //y[3:0] ^ x[7:4];
			//data_out <= 4'b1010; //y[3:0] ^ x[7:4];
			data_out <= !x[0] ? fb_byte[7:4] : fb_byte[3:0];
		end
	end

	// for now send a deterministic pattern

endmodule


module top(
	output serial_txd,
	input serial_rxd,
	output spi_cs,
	output led_r,
	output led_g,
	output led_b,

/*
	// SPI display input from Pi
	input gpio_34, // cs
	input gpio_43, // dc
	input gpio_36, // di
	input gpio_42, // clk
*/

	// LCD display module
	output gpio_23, // frame
	output gpio_25, // load
	output gpio_26, // clk
	output gpio_27, // !enable
	output gpio_32, // d3
	output gpio_35, // d2
	output gpio_31, // d1
	output gpio_37, // d0
	output gpio_34 // d0

/*
	// keyboard module
	output gpio_12, // row 1
	output gpio_21, // row 2
	output gpio_13, // row 3
	output gpio_19, // row 4
	output gpio_18, // row 5
	output gpio_11, // row 6
	output gpio_9, // row 7
	output gpio_6, // row 8
	input gpio_44, // col 1
	input gpio_4, // col 2
	input gpio_3, // col 3
	input gpio_48, // col 4
	input gpio_45, // col 5
	input gpio_47, // col 6
	input gpio_46, // col 7-12

	// remaining pins
	input gpio_38,
	input gpio_28,
	input gpio_2
*/
);
	assign spi_cs = 1; // it is necessary to turn off the SPI flash chip
	reg reset = 0;
	wire clk_48mhz;
	SB_HFOSC inthosc(.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(clk_48mhz));

	// 24 MHz system clock
	reg clk = 0;
	always @(posedge clk_48mhz)
		clk = !clk;

	wire psion_frame = gpio_23;
	wire [3:0] psion_data = { gpio_25, gpio_26, gpio_27, gpio_32 };
	//wire [3:0] psion_data = { gpio_32, gpio_27, gpio_26, gpio_25 };
	wire psion_clk = gpio_35;
	wire psion_row = gpio_31;
	wire psion_enable;

	assign led_r = !psion_frame;
	assign led_g = 1; //!psion_clk;
	assign led_b = 1;

	// generate a 700 Hz sync pulse for the LCD?
	reg [14:0] counter;
	assign gpio_37 = counter[14];
	always @(posedge clk)
		counter <= counter + 1;

	psion_display psion_lcd(
		.reset(1'b0),
		.clk(clk),
		.data_out(psion_data),
		.clk_out(psion_clk),
		.frame_out(psion_frame),
		.row_out(psion_row),
		.enable_out(psion_enable)
	);

endmodule
