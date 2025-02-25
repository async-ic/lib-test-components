
module source_clock( clk, reset_B, ctl_in, ctl_out, source_done_out, source_done_in);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

parameter FILE_PATH="clk.csv";
parameter SOURCE_NAME = "clock source";
parameter real clk_pulse = 4;

localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;


output reg clk;

input reset_B, source_done_in;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
output wire source_done_out;

integer file, ignore;
reg next_step, step_done;
integer init;

assign ctl_out = ctl_in;
assign source_done_out = (source_done_in & step_done);

// init
initial begin
	open_file;
	next_step = 0;
	step_done = 0;
	clk = 0;
end

// next
always @ (ctl_in, negedge reset_B)
begin
	if( reset_B == 0 || $time == 0)	begin
		clk = 0;
	end	else begin
		ignore = $rewind(file);
		step_done = 0;
		while (~step_done) begin
			next_line;
		end
	end
end

task open_file();
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("%s: file not found: %s",SOURCE_NAME,FILE_PATH);
		$finish;
    end
end
endtask

task next_line();
reg [8:0] char;
reg clk_send;
integer success;
reg new_clk;
reg [CTL_BUS_MINUS_ONE:0] new_step;
begin
	new_clk = 0;
	new_step = 0;
	clk_send = 0;
	while ((~step_done) && (~clk_send)) begin
				success = $fscanf(file, {"%b",CSV_SEPERATOR,"%d",CSV_NEWLINE},new_clk,new_step);
				if(success!=2) begin
						step_done = 1'b1;
				end
				if (new_step == ctl_in) begin
						clk = new_clk;
						#clk_pulse;
						clk = 0;
						#clk_pulse;
						$display("%s: send %b in step %0d",SENDER_NAME,new_clk,new_step);
				end
		end
end
endtask
endmodule





module check_bd_template(req, data, ack, reset_B, print_in, print_out, error, valid, complete_in, complete_out, ctl_in, ctl_out);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

parameter FILE_PATH="data.csv";
parameter CHECK_NAME = "bd check";
parameter integer MAX_CHECKS = 1000000;
parameter integer ENFORCE_ORDER = 0;
parameter integer STOP_ON_ERROR = 0;

localparam integer DATA_WIDTH_MINUS_ONE = 31;
localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;
localparam real delay_data_low = 0.01;
localparam real delay_data_high = 0.01;

integer file, ignore, init;
reg done, next;

input reset_B, print_in, req;
input [DATA_WIDTH_MINUS_ONE:0] data;
output reg ack, error, valid;

output wire print_out;
assign print_out = print_in;

input complete_in;
output wire complete_out;
assign complete_out = (complete_in & done);

output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
assign ctl_out = ctl_in;

integer number_tests = 0;
integer number_in = 0;
integer number_tests_step = 0;
integer number_in_step = 0;
integer number_errors = 0;


reg [DATA_WIDTH_MINUS_ONE:0] expected_vector[MAX_CHECKS:0];
reg used[MAX_CHECKS:0];

// init
initial begin
	error=0;
	ack=0;
	done = 0;
    clear_used;
	open_file;
end

// step 1
always @ (posedge req, negedge reset_B)
begin
	if(reset_B==0 || $time == 0)	begin
		ack=0;
	end
	else begin
		#delay_data_high;
		wait(next == 0);
		$display("%s: recived: %b",CHECK_NAME,data);
		evaluate_input;
		ack=1'b1;
	end

end

// step 2
always @ (negedge req, negedge reset_B)
begin
	if(reset_B==0 || $time == 0) begin
		ack=0;
	end
	else begin
		#delay_data_low;
		ack=0;
	end
end


// next
always @ (ctl_in, negedge reset_B)
begin
	next = 1;
	if(reset_B==0 || $time == 0) begin
		ack=1'b0;
	end
	else begin
		done = 0;
		number_tests = number_tests + number_tests_step;
        number_tests_step = 0;
		number_in = number_in + number_in_step;
        number_in_step = 0;
        //clear_used;
		ignore = $rewind(file);
		read_step;
	end
	next = 0;
end

// print
always @ (posedge print_in)
begin
 	print_result;
end

task open_file();
integer success;
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("file not found: %s",FILE_PATH);
		error=1;
		$finish;
    end
end
endtask

task read_step();
integer success, i;
reg [DATA_WIDTH_MINUS_ONE:0] new_data;
reg [CTL_BUS_MINUS_ONE:0] new_step;
reg eof, ignore1,ignore2;
begin
	success = 0;
	new_data= 0;
	eof = 0;
	i = 0;
	while ((~eof)) begin
		success = 0;
		success = $fscanf(file, {"%d",CSV_SEPERATOR,"%b",CSV_NEWLINE},new_step,new_data);
		if(success!=2) begin
			$display("%s: %0d expected vectors in step %0d", CHECK_NAME, number_tests_step, ctl_in);
			eof = 1;
		end else begin
			if (new_step == ctl_in) begin
				expected_vector[number_tests_step] = new_data;
				used[number_tests_step] = 0;
				number_tests_step = number_tests_step+1;
			end
		end
	end
	if (number_tests_step == 0) begin
		done = 1'b1;
	end
end
endtask

task evaluate_input();
integer i;
reg match;
begin
	number_in_step = number_in_step+1;
	if (ENFORCE_ORDER) begin
		if (data != expected_vector[number_in_step-1]) begin
			$display("***************** CHECK FAILED *****************");
			$display("%s: ERROR: check %0d errored:\n expected \n%b \n got \n%b",
							CHECK_NAME,
							number_in,
							expected_vector[number_in_step-1],
							data);
			$display("***********************************************");
			error=1;
			if (STOP_ON_ERROR) begin
				$finish;
			end else begin
				number_errors = number_errors + 1;
			end
		end
	end else begin
		match = 0;
		for (i = 0; i < number_tests_step; i = i+1) begin : loop_match
			if((~match)&(~used[i])&(expected_vector[i] == data)) begin
				used[i]=1;
				match=1;
				disable loop_match;
			end
		end
		if (~match) begin
				$display("***************** CHECK FAILED *****************");
				$display("%s: ERROR: check %0d not found:\n got %b",
								CHECK_NAME,
								number_in_step,
								data);
				$display("***********************************************");
				error=1;
				if (STOP_ON_ERROR) begin
					$finish;
				end else begin
					number_errors = number_errors + 1;
				end
		end
	end
    if (number_in_step == number_tests_step) begin
		done = 1'b1;
	end
end
endtask


task print_result();
integer i;
begin
		number_tests = number_tests + number_tests_step;
        number_tests_step = 0;
		number_in = number_in + number_in_step;
        number_in_step = 0;
   		ack=1'b0;
		$display("***************** %s STATS *****************", CHECK_NAME);
		$display("Total vectors:  %d \nVectors passed: %d \nVectors failed: %d \nVectors missed: %d",
						number_tests,
						number_in-number_errors,
						number_errors,
						number_tests-number_in);
		$display("*************************************************");
		$fclose(file);
		if (number_errors+number_tests-number_in != 0) begin
					error=1;
		end
end
endtask

task clear_used();
begin
	for (init = 0; init <= MAX_CHECKS; init=init+1) begin
		expected_vector[init]=0;
		used[init]=1;
	end
end
endtask
endmodule


module power ( vss, vdd );

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

output reg vdd;
output reg vss;

initial
begin

vss = 0;
vdd = 0;
# 0.4
vdd = 1;
end
endmodule



module source_aMx1of2_template(data_f, data_t, ack, reset_B, ctl_in, ctl_out, source_done_in, source_done_out);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

parameter FILE_PATH="data.csv";
parameter SOURCE_NAME = "awMx1of2 source";

localparam integer DATA_WIDTH_MINUS_ONE = 31;
localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;
localparam real delay_data_low = 0.01;
localparam real delay_data_high = 0.01;

input ack, reset_B, source_done_in;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
output reg [DATA_WIDTH_MINUS_ONE:0] data_f, data_t;

output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
output wire source_done_out;

integer file, ignore;
reg next, done;


assign ctl_out = ctl_in;
assign source_done_out = (source_done_in & done);

// init
initial begin
	open_file;
	data_t = 0;
	data_f = 0;
	next = 0;
	done = 0;
end



// step 1
always @ (negedge ack,negedge reset_B)
begin
	if( reset_B == 0 || $time == 0)	begin
		data_t = 0;
		data_f = 0;
	end
	else if (next == 0) begin
		next_line;
	end
end

// step 2
always @ (posedge ack,negedge reset_B)
begin
	if( reset_B == 0 || $time == 0) begin
		data_t = 0;
		data_f = 0;
	end
	else begin
		#delay_data_low;
		data_t = 0;
		data_f = 0;
	end
end

// next
always @ (ctl_in, negedge reset_B)
begin
	next = 1;
	if( reset_B==0 || $time == 0)	begin
		data_t = 0;
		data_f = 0;
	end
	else begin
		done = 0;
		ignore = $rewind(file);
		next_line;
	end
	next = 0;
end


task open_file();
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("%s: file not found: %s",SOURCE_NAME,FILE_PATH);
		$finish;
    end
end
endtask


task next_line();
reg [8:0] char;
reg data_send;
integer success;
reg [DATA_WIDTH_MINUS_ONE:0] new_data;
reg [CTL_BUS_MINUS_ONE:0] new_step;
begin
	new_data = 0;
	new_step = 0;
	data_send = 0;
	while ((~done) && (~data_send)) begin
				success = $fscanf(file, {"%b",CSV_SEPERATOR,"%d",CSV_NEWLINE},new_data,new_step);
				if(success!=2) begin
						data_t=0;
						data_f=0;
						done = 1'b1;
				end
				if (new_step == ctl_in) begin
						data_send = 1;
						#delay_data_high;
						data_t=new_data;
						data_f=~new_data;
						$display("%s: send %b in step %0d",SOURCE_NAME,new_data,new_step);
				end

	end
end
endtask
endmodule



module end_source_daisychain (ctl_in, source_done_out, true);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

localparam CTL_BUS_MINUS_ONE = 31;
output wire source_done_out;
input true;
input [CTL_BUS_MINUS_ONE:0] ctl_in;

assign source_done_out = true;
endmodule


module source_fifo(clk, data, reset_B, ctl_in, ctl_out, source_done_out, source_done_in);

parameter FILE_PATH="data.csv";
parameter SOURCE_NAME = "serial source";
parameter real half_clock_pulse = 4;

localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;


output reg data, clk;

input reset_B, source_done_in;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
output wire source_done_out;

integer file, ignore;
reg next_step, step_done;
integer init;

assign ctl_out = ctl_in;
assign source_done_out = (source_done_in & step_done);

// init
initial begin
	open_file;
	next_step = 0;
	step_done = 0;
	data = 0;
	clk = 0;
end

// next
always @ (ctl_in, negedge reset_B)
begin
	if( reset_B == 0 || $time == 0)	begin
		data = 0;
		clk = 0;
	end	else begin
		ignore = $rewind(file);
		step_done = 0;
		while (~step_done) begin
			next_line;
		end
	end
end

task open_file();
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("%s: file not found: %s",SOURCE_NAME,FILE_PATH);
		$finish;
    end
end
endtask

task next_line();
reg [8:0] char;
reg data_send;
integer success;
reg new_data;
reg [CTL_BUS_MINUS_ONE:0] new_step;
begin
	new_data = 0;
	new_step = 0;
	data_send = 0;
	while ((~step_done) && (~data_send)) begin
				success = $fscanf(file, {"%b",CSV_SEPERATOR,"%d",CSV_NEWLINE},new_data,new_step);
				if(success!=2) begin
						step_done = 1'b1;
				end
				if (new_step == ctl_in) begin
						#half_clock_pulse;
						data = new_data;
						#half_clock_pulse;
						clk = 1'b1;
						#half_clock_pulse;
						data = 0;
						#half_clock_pulse;
						clk = 0;
						$display("%s: send %b in step %0d",SENDER_NAME,new_data,new_step);
				end
		end
end
endtask
endmodule


module source_awMx1of2_template(data_f, data_t, ack, valid, reset_B, ctl_in, ctl_out, source_done_in, source_done_out);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

parameter FILE_PATH="data.csv";
parameter SOURCE_NAME = "awMx1of2 source";

localparam integer DATA_WIDTH_MINUS_ONE = 31;
localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;
localparam real delay_data_low = 0.01;
localparam real delay_data_high = 0.01;

input ack, reset_B, valid, source_done_in;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
output reg [DATA_WIDTH_MINUS_ONE:0] data_f, data_t;

output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
output wire source_done_out;

integer file, ignore;
reg next, done;


assign ctl_out = ctl_in;
assign source_done_out = (source_done_in & done);

// init
initial begin
	open_file;
	data_t = 0;
	data_f = 0;
	next = 0;
	done = 0;
end



// step 1
always @ (negedge ack,negedge reset_B)
begin
	if( reset_B == 0 || $time == 0)	begin
		data_t = 0;
		data_f = 0;
	end
	else if (next == 0) begin
		next_line;
	end
end

// step 2
always @ (posedge ack,negedge reset_B)
begin
	if( reset_B == 0 || $time == 0) begin
		data_t = 0;
		data_f = 0;
	end
	else begin
		#delay_data_low;
		data_t = 0;
		data_f = 0;
	end
end

// next
always @ (ctl_in, negedge reset_B)
begin
	next = 1;
	if( reset_B==0 || $time == 0)	begin
		data_t = 0;
		data_f = 0;
	end
	else begin
		done = 0;
		ignore = $rewind(file);
		next_line;
	end
	next = 0;
end


task open_file();
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("%s: file not found: %s",SOURCE_NAME,FILE_PATH);
		$finish;
    end
end
endtask


task next_line();
reg [8:0] char;
reg data_send;
integer success;
reg [DATA_WIDTH_MINUS_ONE:0] new_data;
reg [CTL_BUS_MINUS_ONE:0] new_step;
begin
	new_data = 0;
	new_step = 0;
	data_send = 0;
	while ((~done) && (~data_send)) begin
				success = $fscanf(file, {"%b",CSV_SEPERATOR,"%d",CSV_NEWLINE},new_data,new_step);
				if(success!=2) begin
						data_t=0;
						data_f=0;
						done = 1'b1;
				end
				if (new_step == ctl_in) begin
						data_send = 1;
						#delay_data_high;
						data_t=new_data;
						data_f=~new_data;
						$display("%s: send %b in step %0d",SOURCE_NAME,new_data,new_step);
				end

	end
end
endtask
endmodule




module check_awMx1of2_template(data_f, data_t, ack, reset_B, print_in, print_out, error, valid, complete_in, complete_out, ctl_in, ctl_out);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

parameter FILE_PATH="data.csv";
parameter CHECK_NAME = "awMx1of2 check";
parameter integer MAX_CHECKS = 1000000;
parameter integer ENFORCE_ORDER = 0;
parameter integer STOP_ON_ERROR = 0;

localparam integer DATA_WIDTH_MINUS_ONE = 31;
localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;
localparam real delay_data_low = 0.01;
localparam real delay_data_high = 0.01;

integer file, ignore, init;
reg done, next;

input reset_B, print_in;
input [DATA_WIDTH_MINUS_ONE:0] data_f, data_t;
output reg ack, error, valid;


output wire print_out;
assign print_out = print_in;

input complete_in;
output wire complete_out;
assign complete_out = (complete_in & done);

output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
assign ctl_out = ctl_in;

integer number_tests = 0;
integer number_in = 0;
integer number_tests_step = 0;
integer number_in_step = 0;
integer number_errors = 0;

wire weak_valid, week_invalid;
assign weak_valid = &(data_f ^ data_t);
assign week_invalid = &(~(data_f | data_t));

reg [DATA_WIDTH_MINUS_ONE:0] expected_vector[MAX_CHECKS:0];
reg used[MAX_CHECKS:0];

// init
initial begin
	error=0;
	ack=0;
	valid=0;
	done = 0;
    clear_used;
	open_file;
end

// step 1
always @ (posedge weak_valid,negedge reset_B)
begin
	if(reset_B==0 || $time == 0)	begin
		ack=0;
	end
	else begin
		#delay_data_high;
		valid=1;
		#delay_data_high;
		wait(next == 0);
		$display("%s: recived: %b",CHECK_NAME,data_t);
		evaluate_input;
		ack=1'b1;
	end

end

// step 2
always @ (posedge week_invalid,negedge reset_B)
begin
	if(reset_B==0 || $time == 0) begin
		ack=0;
	end
	else begin
		#delay_data_high;
		valid=0;
		#delay_data_low;
		ack=0;
	end
end


// next
always @ (ctl_in, negedge reset_B)
begin
	next = 1;
	if(reset_B==0 || $time == 0) begin
		ack=1'b0;
	end
	else begin
		done = 0;
		number_tests = number_tests + number_tests_step;
		number_tests_step = 0;
		number_in = number_in + number_in_step;
		number_in_step = 0;
        //clear_used;
		ignore = $rewind(file);
		read_step;
	end
	next = 0;
end

// print
always @ (posedge print_in)
begin
 	print_result;
end

task open_file();
integer success;
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("file not found: %s",FILE_PATH);
		error=1;
		$finish;
    end
end
endtask

task read_step();
integer success, i;
reg [DATA_WIDTH_MINUS_ONE:0] new_data;
reg [CTL_BUS_MINUS_ONE:0] new_step;
reg eof, ignore1,ignore2;
begin
	success = 0;
	new_data= 0;
	eof = 0;
	i = 0;
	while ((~eof)) begin
		success = 0;
		success = $fscanf(file, {"%d",CSV_SEPERATOR,"%b",CSV_NEWLINE},new_step,new_data);
		if(success!=2) begin
			$display("%s: %0d expected vectors in step %0d", CHECK_NAME, number_tests_step, ctl_in);
			eof = 1;
		end else begin
			if (new_step == ctl_in) begin
				expected_vector[number_tests_step] = new_data;
				used[number_tests_step] = 0;
				number_tests_step = number_tests_step+1;
			end
		end
	end
	if (number_tests_step == 0) begin
		done = 1'b1;
	end
end
endtask

task evaluate_input();
integer i;
reg match;
begin
	number_in_step = number_in_step+1;
	if (ENFORCE_ORDER) begin
		if (data_t != expected_vector[number_in_step-1]) begin
			$display("***************** CHECK FAILED *****************");
			$display("%s: ERROR: check %0d errored:\n expected \n%b \n got \n%b",
							CHECK_NAME,
							number_in,
							expected_vector[number_in_step-1],
							data_t);
			$display("***********************************************");
			error=1;
			if (STOP_ON_ERROR) begin
				$finish;
			end else begin
				number_errors = number_errors + 1;
			end
		end
	end else begin
		match = 0;
		for (i = 0; i < number_tests_step; i = i+1) begin : loop_match
			if((~match)&(~used[i])&(expected_vector[i] == data_t)) begin
				used[i]=1;
				match=1;
				disable loop_match;
			end
		end
		if (~match) begin
				$display("***************** CHECK FAILED *****************");
				$display("%s: ERROR: check %0d not found:\n got %b",
								CHECK_NAME,
								number_in_step,
								data_t);
				$display("***********************************************");
				error=1;
				if (STOP_ON_ERROR) begin
					$finish;
				end else begin
					number_errors = number_errors + 1;
				end
		end
	end
    if (number_in_step == number_tests_step) begin
		done = 1'b1;
	end
end
endtask


task print_result();
integer i;
begin
		number_tests = number_tests + number_tests_step;
        number_tests_step = 0;
		number_in = number_in + number_in_step;
        number_in_step = 0;
   		ack=1'b0;
		$display("***************** %s STATS *****************", CHECK_NAME);
		$display("Total vectors:  %d \nVectors passed: %d \nVectors failed: %d \nVectors missed: %d",
						number_tests,
						number_in-number_errors,
						number_errors,
						number_tests-number_in);
		$display("*************************************************");
		$fclose(file);
		if (number_errors+number_tests-number_in != 0) begin
					error=1;
		end
end
endtask

task clear_used();
begin
	for (init = 0; init <= MAX_CHECKS; init=init+1) begin
		expected_vector[init]=0;
		used[init]=1;
	end
end
endtask
endmodule



module control (reset_B, ctl, source_done_in, check_done_in, print, true);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

parameter real  TIMEOUT = 100000000;
parameter integer  TIMEOUT_ACTIVE = 1;
parameter real SEND_DONE_TIMEOUT = 10000;
parameter real WAIT_FOR_PRINT = 10;
parameter integer LAST_CTL = 2000000;
localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;
parameter FILE_PATH="data.csv";

integer last_step, file;
integer startstep = 1;
integer wait_for = 0;
reg file_enable = 1;


reg [MAX_LINE_LENGTH*8:0] test_suit_name;
reg [MAX_LINE_LENGTH*8:0] step_name;
output reg reset_B, print, true;
output reg [CTL_BUS_MINUS_ONE:0] ctl;
input source_done_in, check_done_in;
wire step_done_in;
assign step_done_in = source_done_in & check_done_in;

initial begin

  reset_B=1'b0;
  true=1'b0;
  ctl=1'b0;
  print = 1'b0;
  open_file;

  #3;
	$display("**********************************************");
	$display("CONTROL: starting testsuite %0s", test_suit_name);
	$display("**********************************************");
	$display("CONTROL: step 0 - reset"); 
  #3 reset_B=1'b1;

  #3
  true=1'b1;
  ctl = ctl + 1;
  read_line;
  $display("**********************************************");
  $display("CONTROL: step %0d %0s", ctl, step_name);

end

//init, open and read file
initial begin
	if ( TIMEOUT_ACTIVE == 1) begin
		#  TIMEOUT;
 		print = 1'b1;
  		# WAIT_FOR_PRINT;
  		$finish;
	end
end

always @ (posedge step_done_in) begin
  if (ctl < last_step) begin
		if (step_done_in == 1) begin
			if (wait_for > 0) begin
				$display("CONTROL: waiting for %0d ns", wait_for);
				# wait_for;
				wait_for = 0;
			end
      		ctl = ctl + 1;
			read_line;
	        $display("**********************************************");
			$display("CONTROL: step %0d %0s", ctl, step_name);
   		end
  end
  else begin
	$display("**********************************************");
	$display("CONTROL: test suite ends");
    # SEND_DONE_TIMEOUT;
	if (step_done_in == 1) begin
      print = 1'b1;
      # WAIT_FOR_PRINT;
      $finish;
    end
  end
end


task open_file();
integer success, simstep;
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("CONTROL: file not found: %s", FILE_PATH);
		$finish;
    end else begin
		success = $fscanf(file, {"%d"},simstep);
		if(success == 1) begin 
			last_step = simstep;
			success = $fgets(test_suit_name,file);
		end else begin
				$display("CONTROL: cant interpret timestep file content, need <end step>[,<test name>] in first line");
				$finish;
		end
	end
end
endtask

task read_line();
integer success,new_wait,step;
begin
	success = 0;
	success = $fscanf(file, {"%d",CSV_SEPERATOR,"%d"},step,new_wait);
	if(success == 2) begin 
		if (step == ctl) begin
			wait_for = wait_for + new_wait;
			success = $fgets(step_name,file);
		end else begin
			$display("*****************************************************");
			$display("CONTROL: ERROR: assending order required: %0d != %d",ctl,step);
			$display("*****************************************************");
			print = 1'b1;
      		# WAIT_FOR_PRINT;
      		$finish;
		end
	end else begin
		$display("*****************************************************");
		$display("CONTROL: ERROR: missing instruction: step %0d", ctl);
		$display("*****************************************************");
		print = 1'b1;
   		# WAIT_FOR_PRINT;
   		$finish;
	end
end
endtask

endmodule



module end_check_daisychain (print_in, ctl_in, check_done_out, true);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

localparam CTL_BUS_MINUS_ONE = 31;
output wire check_done_out;
input true, print_in;
input [CTL_BUS_MINUS_ONE:0] ctl_in;

assign check_done_out = true;
endmodule


module source_bd_template(req, data, ack, valid, reset_B, ctl_in, ctl_out, source_done_in, source_done_out);

parameter FILE_PATH="data.csv";
parameter SOURCE_NAME = "awMx1of2 source";

localparam integer DATA_WIDTH_MINUS_ONE = 31;
localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;
localparam real delay_data_low = 0.01;
localparam real delay_data_high = 0.01;

input ack, reset_B, valid, source_done_in;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
output reg [DATA_WIDTH_MINUS_ONE:0] data;
output reg req;

output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
output wire source_done_out;

integer file, ignore;
reg next, done;


assign ctl_out = ctl_in;
assign source_done_out = (source_done_in & done);

// init
initial begin
	open_file;
	data = 0;
	req = 0;
	next = 0;
	done = 0;
end



// step 1
always @ (negedge ack,negedge reset_B)
begin
	if( reset_B == 0 || $time == 0)	begin
		data = 0;
		req = 0;
	end
	else if (next == 0) begin
		next_line;
	end
end

// step 2
always @ (posedge ack,negedge reset_B)
begin
	if( reset_B == 0 || $time == 0) begin
		data = 0;
		req = 0;
	end
	else begin
		req = 0;
		#delay_data_low;
		data = 0;
		
	end
end

// next
always @ (ctl_in, negedge reset_B)
begin
	next = 1;
	if( reset_B==0 || $time == 0)	begin
		data = 0;
		req = 0;
	end
	else begin
		done = 0;
		ignore = $rewind(file);
		next_line;
	end
	next = 0;
end


task open_file();
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("%s: file not found: %s",SOURCE_NAME,FILE_PATH);
		$finish;
    end
end
endtask


task next_line();
reg [8:0] char;
reg data_send;
integer success;
reg [DATA_WIDTH_MINUS_ONE:0] new_data;
reg [CTL_BUS_MINUS_ONE:0] new_step;
begin
	new_data = 0;
	new_step = 0;
	data_send = 0;
	while ((~done) && (~data_send)) begin
				success = $fscanf(file, {"%b",CSV_SEPERATOR,"%d",CSV_NEWLINE},new_data,new_step);
				if(success!=2) begin
						data=0;
						req=0;
						done = 1'b1;
				end
				if (new_step == ctl_in) begin
						data_send = 1;
						data=new_data;
						#delay_data_high;
						req = 1'b1;
						$display("%s: send %b in step %0d",SOURCE_NAME,new_data,new_step);
				end

	end
end
endtask
endmodule


module source_bool_M_template( data, reset_B, ctl_in, ctl_out, source_done_out, source_done_in);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

parameter FILE_PATH="data.csv";
parameter SOURCE_NAME = "bool M source";
parameter real data_pulse = 4;


localparam integer DATA_WIDTH_MINUS_ONE = 31;
localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;


output reg [DATA_WIDTH_MINUS_ONE:0] data;

input reset_B, source_done_in;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
output wire source_done_out;

integer file, ignore;
reg next_step, step_done;
integer init;

assign ctl_out = ctl_in;
assign source_done_out = (source_done_in & step_done);

// init
initial begin
	open_file;
	next_step = 0;
	step_done = 0;
	data = 0;
end

// next
always @ (ctl_in, negedge reset_B)
begin
	if( reset_B == 0 || $time == 0)	begin
		data = 0;
	end	else begin
		ignore = $rewind(file);
		step_done = 0;
		while (~step_done) begin
			next_line;
		end
	end
end

task open_file();
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("%s: file not found: %s",SOURCE_NAME,FILE_PATH);
		$finish;
    end
end
endtask

task next_line();
reg [8:0] char;
reg data_send;
integer success;
reg [DATA_WIDTH_MINUS_ONE:0] new_data;
reg [CTL_BUS_MINUS_ONE:0] new_step;
begin
	new_data = 0;
	new_step = 0;
	data_send = 0;
	while ((~step_done) && (~data_send)) begin
				success = $fscanf(file, {"%b",CSV_SEPERATOR,"%d",CSV_NEWLINE},new_data,new_step);
				if(success!=2) begin
						step_done = 1'b1;
				end
				if (new_step == ctl_in) begin
						data = new_data;
						#data_pulse;
						$display("%s: send %b in step %0d",SENDER_NAME,new_data,new_step);
				end
		end
end
endtask
endmodule




module check_aMx1of2_template(data_f, data_t, ack, reset_B, print_in, print_out, error, complete_in, complete_out, ctl_in, ctl_out);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

parameter FILE_PATH="data.csv";
parameter CHECK_NAME = "awMx1of2 check";
parameter integer MAX_CHECKS = 1000000;
parameter integer ENFORCE_ORDER = 0;
parameter integer STOP_ON_ERROR = 0;

localparam integer DATA_WIDTH_MINUS_ONE = 31;
localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;
localparam real delay_data_low = 0.01;
localparam real delay_data_high = 0.01;

integer file, ignore, init;
reg done, next;

input reset_B, print_in;
input [DATA_WIDTH_MINUS_ONE:0] data_f, data_t;
output reg ack, error;


output wire print_out;
assign print_out = print_in;

input complete_in;
output wire complete_out;
assign complete_out = (complete_in & done);

output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
assign ctl_out = ctl_in;

integer number_tests = 0;
integer number_in = 0;
integer number_tests_step = 0;
integer number_in_step = 0;
integer number_errors = 0;

wire weak_valid, week_invalid;
assign weak_valid = &(data_f ^ data_t);
assign week_invalid = &(~(data_f | data_t));

reg [DATA_WIDTH_MINUS_ONE:0] expected_vector[MAX_CHECKS:0];
reg used[MAX_CHECKS:0];

// init
initial begin
	error=0;
	ack=0;
	done = 0;
    clear_used;
	open_file;
end

// step 1
always @ (posedge weak_valid,negedge reset_B)
begin
	if(reset_B==0 || $time == 0)	begin
		ack=0;
	end
	else begin
		#delay_data_high;
		wait(next == 0);
		$display("%s: recived: %b",CHECK_NAME,data_t);
		evaluate_input;
		ack=1'b1;
	end

end

// step 2
always @ (posedge week_invalid,negedge reset_B)
begin
	if(reset_B==0 || $time == 0) begin
		ack=0;
	end
	else begin
		#delay_data_low;
		ack=0;
	end
end


// next
always @ (ctl_in, negedge reset_B)
begin
	next = 1;
	if(reset_B==0 || $time == 0) begin
		ack=1'b0;
	end
	else begin
		done = 0;
		number_tests = number_tests + number_tests_step;
		number_tests_step = 0;
		number_in = number_in + number_in_step;
		number_in_step = 0;
        //clear_used;
		ignore = $rewind(file);
		read_step;
	end
	next = 0;
end

// print
always @ (posedge print_in)
begin
 	print_result;
end

task open_file();
integer success;
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("file not found: %s",FILE_PATH);
		error=1;
		$finish;
    end
end
endtask

task read_step();
integer success, i;
reg [DATA_WIDTH_MINUS_ONE:0] new_data;
reg [CTL_BUS_MINUS_ONE:0] new_step;
reg eof, ignore1,ignore2;
begin
	success = 0;
	new_data= 0;
	eof = 0;
	i = 0;
	while ((~eof)) begin
		success = 0;
		success = $fscanf(file, {"%d",CSV_SEPERATOR,"%b",CSV_NEWLINE},new_step,new_data);
		if(success!=2) begin
			$display("%s: %0d expected vectors in step %0d", CHECK_NAME, number_tests_step, ctl_in);
			eof = 1;
		end else begin
			if (new_step == ctl_in) begin
				expected_vector[number_tests_step] = new_data;
				used[number_tests_step] = 0;
				number_tests_step = number_tests_step+1;
			end
		end
	end
	if (number_tests_step == 0) begin
		done = 1'b1;
	end
end
endtask

task evaluate_input();
integer i;
reg match;
begin
	number_in_step = number_in_step+1;
	if (ENFORCE_ORDER) begin
		if (data_t != expected_vector[number_in_step-1]) begin
			$display("***************** CHECK FAILED *****************");
			$display("%s: ERROR: check %0d errored:\n expected \n%b \n got \n%b",
							CHECK_NAME,
							number_in,
							expected_vector[number_in_step-1],
							data_t);
			$display("***********************************************");
			error=1;
			if (STOP_ON_ERROR) begin
				$finish;
			end else begin
				number_errors = number_errors + 1;
			end
		end
	end else begin
		match = 0;
		for (i = 0; i < number_tests_step; i = i+1) begin : loop_match
			if((~match)&(~used[i])&(expected_vector[i] == data_t)) begin
				used[i]=1;
				match=1;
				disable loop_match;
			end
		end
		if (~match) begin
				$display("***************** CHECK FAILED *****************");
				$display("%s: ERROR: check %0d not found:\n got %b",
								CHECK_NAME,
								number_in_step,
								data_t);
				$display("***********************************************");
				error=1;
				if (STOP_ON_ERROR) begin
					$finish;
				end else begin
					number_errors = number_errors + 1;
				end
		end
	end
    if (number_in_step == number_tests_step) begin
		done = 1'b1;
	end
end
endtask


task print_result();
integer i;
begin
		number_tests = number_tests + number_tests_step;
        number_tests_step = 0;
		number_in = number_in + number_in_step;
        number_in_step = 0;
   		ack=1'b0;
		$display("***************** %s STATS *****************", CHECK_NAME);
		$display("Total vectors:  %d \nVectors passed: %d \nVectors failed: %d \nVectors missed: %d",
						number_tests,
						number_in-number_errors,
						number_errors,
						number_tests-number_in);
		$display("*************************************************");
		$fclose(file);
		if (number_errors+number_tests-number_in != 0) begin
					error=1;
		end
end
endtask

task clear_used();
begin
	for (init = 0; init <= MAX_CHECKS; init=init+1) begin
		expected_vector[init]=0;
		used[init]=1;
	end
end
endtask
endmodule

module source_a1of1_template(req, ack, valid, reset_B, ctl_in, ctl_out, source_done_in, source_done_out);

// Copyright 2025 Ole Richter - Yale University
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor,
//  Boston, MA  02110-1301, USA.

parameter FILE_PATH="data.csv";
parameter SOURCE_NAME = "awMx1of2 source";

localparam integer MAX_LINE_LENGTH = 256;
localparam CSV_SEPERATOR = ",";
localparam CSV_NEWLINE = 8'd10;
localparam CTL_BUS_MINUS_ONE = 31;
localparam real delay_data_low = 0.01;
localparam real delay_data_high = 0.01;

input ack, reset_B, valid, source_done_in;
input [CTL_BUS_MINUS_ONE:0] ctl_in;
output reg req;

output wire [CTL_BUS_MINUS_ONE:0] ctl_out;
output wire source_done_out;

integer file, ignore;
reg next, done;


assign ctl_out = ctl_in;
assign source_done_out = (source_done_in & done);

// init
initial begin
	open_file;
	req = 0;
	next = 0;
	done = 0;
end



// step 1
always @ (negedge ack,negedge reset_B)
begin
	if( reset_B == 0 || $time == 0)	begin
		req = 0;
	end
	else if (next == 0) begin
		next_line;
	end
end

// step 2
always @ (posedge ack,negedge reset_B)
begin
	if( reset_B == 0 || $time == 0) begin
		req = 0;
	end
	else begin
		#delay_data_low;
		req = 0;
		
	end
end

// next
always @ (ctl_in, negedge reset_B)
begin
	next = 1;
	if( reset_B==0 || $time == 0)	begin
		req = 0;
	end
	else begin
		done = 0;
		ignore = $rewind(file);
		next_line;
	end
	next = 0;
end


task open_file();
begin
    file = $fopen(FILE_PATH,"r");
    if(file==0) begin
		$display("%s: file not found: %s",SOURCE_NAME,FILE_PATH);
		$finish;
    end
end
endtask


task next_line();
reg [8:0] char;
reg data_send;
integer success;
reg new_data;
reg [CTL_BUS_MINUS_ONE:0] new_step;
begin
	new_data = 0;
	new_step = 0;
	data_send = 0;
	while ((~done) && (~data_send)) begin
				success = $fscanf(file, {"%b",CSV_SEPERATOR,"%d",CSV_NEWLINE},new_data,new_step);
				if(success!=2) begin
						req=0;
						done = 1'b1;
				end
				if (new_step == ctl_in) begin
						data_send = 1;
						#delay_data_high;
						req = 1'b1;
						$display("%s: send 1 in step %0d",SOURCE_NAME,new_data,new_step);
				end

	end
end
endtask
endmodule

