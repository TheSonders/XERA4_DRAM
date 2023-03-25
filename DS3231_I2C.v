`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
/*
MIT License

Copyright (c) 2023 Antonio Sánchez (@TheSonders)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

XERA4 256KiB DRAM
 
I2C Module for a DS3231 RTC with a Z80 Interface

This wrapper automatically reads the DS3231 via I2C every 85ms
and updates its internal registers,
so the Z80 only has to read as if it were RAM.
*/
//////////////////////////////////////////////////////////////////////////////////
module DS3231_I2C
	#(parameter SYS_FREQ=50_000_000)
	(input wire CLK,
	output wire SCL,
	inout wire SDA,
	input wire [2:0]Add,
	input wire wr_n,
	input wire [7:0]in_data,
	output wire [7:0]out_data
   );

`define	FALL_wr	(prev_wr_n & ~wr_n)

localparam I2C_FREQ=400_000;
localparam PRESCALER=(SYS_FREQ / (I2C_FREQ*4))-1;
localparam REFRESH=((SYS_FREQ *300)/1000)-1;
localparam WriteAddress=8'hD0;
localparam ReadAddress=8'hD1;
localparam NAK=1'b1;
localparam ACK=1'b0;

localparam wr_Idle=0;
localparam wr_Start=1;
localparam wr_Stop=113;
localparam wr_Last=114;

localparam re_IdleWrite=0;
localparam re_StartWrite=1;
localparam re_RegisterAdd=37;
localparam re_StopWrite=77;
localparam re_IdleRead=79;
localparam re_StartRead=80;
localparam re_LoadAddress=81;
localparam re_SetToOne=117;
localparam re_GetRegister=156;
localparam re_StopRead=157;
localparam re_Last=158;

assign out_data=(Add<7)?Record[Add]:{7'h0,Busy};

assign SCL=rSCL;
assign SDA=(rSDA)?1'hZ:1'h0;

reg [7:0]Record[0:6];
integer i;
initial begin
    for (i=0;i<=6;i=i+1) begin
      Record[i] = 8'h0;
    end
end

reg [$clog2(PRESCALER)-1:0] Prescaler=0;
reg [$clog2(REFRESH)-1:0] Refresh=0;
reg prev_wr_n=0;
reg [26:0]Buffer=0;
reg [8:0]ShortBuffer=0;
reg Busy=0;
reg [7:0]Stm=0;
reg rSCL=0;
reg rSDA=0;
reg Write=0;
reg [2:0]CurrentRegister=0;

always @(posedge CLK)begin
	prev_wr_n<=wr_n;
	if (`FALL_wr && Busy==0)begin
		if (Add<7)begin
			Buffer<={WriteAddress,NAK,5'h0,Add,NAK,in_data,NAK};
			Busy<=1;
			Write<=1;
			Refresh<=REFRESH;
		end
	end
	else begin
		if (Busy==0)begin
			if (Refresh!=0)begin
				Refresh<=Refresh-1;
			end
			else begin
				Refresh<=REFRESH;
				Busy<=1;
				Write<=0;
				CurrentRegister<=0;
			end
		end
	end
	if (Prescaler!=0)begin
		Prescaler<=Prescaler-1;
	end
	else begin
		Prescaler<=PRESCALER;
		Stm<=Stm+Busy;
		if (Write==1)begin
			case (Stm)
					wr_Idle:begin
						rSCL<=1;
						rSDA<=1;
					end
					wr_Start:begin
						rSDA<=0;
					end
					wr_Stop:begin
						rSCL<=1;
						rSDA<=0;
					end
					wr_Last:begin
						rSDA<=1;
						Busy<=0;
						Stm<=0;
					end
					default:begin
						if (Stm[1:0]==3)begin
							rSCL<=0;
						end
						else if(Stm[1:0]==0)begin
							rSDA<=Buffer[26];
						end
						else if(Stm[1:0]==1)begin
							rSCL<=1;
							Buffer<={Buffer[25:0],1'b1};
						end
					end
			endcase
		end //Write==1
		else begin
			case (Stm)
					re_IdleWrite:begin
						rSCL<=1;
						rSDA<=1;
						ShortBuffer<={WriteAddress,NAK};
					end
					re_StartWrite:begin
						rSDA<=0;
					end
					re_RegisterAdd:begin
						ShortBuffer<={5'h0,CurrentRegister,NAK};
						rSCL<=1;
					end
					re_StopWrite:begin
						rSCL<=1;
						rSDA<=0;
					end
					re_IdleRead:begin
						rSCL<=1;
						rSDA<=1;
					end
					re_StartRead:begin
						rSDA<=0;
					end
					re_LoadAddress:begin
						ShortBuffer<={ReadAddress,NAK};
					end
					re_SetToOne:begin
						ShortBuffer<=9'h1FF;
						rSCL<=1;
					end
					re_GetRegister:begin
						Record[CurrentRegister]<=ShortBuffer[8:1];
						rSDA<=NAK;
					end
					re_StopRead:begin
						rSCL<=1;
						rSDA<=0;
					end
					re_Last:begin
						rSDA<=1;
						Stm<=0;
						if (CurrentRegister==6) begin
							Busy<=0;
						end
						else begin
							CurrentRegister<=CurrentRegister+1;
						end
					end
					default:begin
						if (Stm[1:0]==3)begin
							rSCL<=0;
						end
						else if(Stm[1:0]==0)begin
							rSDA<=ShortBuffer[8];
						end
						else if(Stm[1:0]==1)begin
							rSCL<=1;
							ShortBuffer<={ShortBuffer[7:0],SDA};
						end
					end
			endcase
		end //Write==0
	end
end


endmodule
