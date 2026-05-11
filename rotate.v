module Complete_MIPS(CLK, RST, HALT, Reg1_Out);
    input CLK;
    input RST;
    input HALT;
    output [7:0]Reg1_Out;
    
    wire slow_clk;
        complexDivider divider (
        .clk100Mhz(CLK),
        .reset(RST),
        .slowClk(slow_clk) // Internal slow clock signal
    );
    
    wire CS, WE;
    wire [6:0] ADDR;
    wire [31:0] Mem_Bus;
    wire [31:0]reg1_data;
	
    assign Reg1_Out = reg1_data[7:0];
    
    MIPS CPU(slow_clk, RST, CS, WE, ADDR, Mem_Bus, HALT, reg1_data);
    Memory MEM(CS, WE, slow_clk, ADDR, Mem_Bus);

endmodule

module Memory(CS, WE, CLK, ADDR, Mem_Bus);
    input CS;
    input WE;
    input CLK;
    input [6:0] ADDR;
    inout [31:0] Mem_Bus;
    
    reg [31:0] data_out;
    reg [31:0] RAM [0:127];
    
    
    initial
    begin
    /* Write your readmemh code here */
		$readmemh("PATH NAME HERE...", RAM);
    end
    
    assign Mem_Bus = ((CS == 1'b0) || (WE == 1'b1)) ? 32'bZ : data_out;
    
	//Keep this negedge. Do not change it.
    always @(negedge CLK)
    begin
        if((CS == 1'b1) && (WE == 1'b1))
            RAM[ADDR] <= Mem_Bus[31:0];
        
        data_out <= RAM[ADDR];
    end
endmodule

module REG(CLK, RegW, DR, SR1, SR2, Reg_In, ReadReg1, ReadReg2, Reg1);
    input CLK;
    input RegW;
    input [4:0] DR;
    input [4:0] SR1;
    input [4:0] SR2;
    input [31:0] Reg_In;
    output reg [31:0] ReadReg1;
    output reg [31:0] ReadReg2;
    output reg [31:0] Reg1;

    reg [31:0] REG [0:31];
 
    always @(posedge CLK) begin
        if (RegW == 1'b1) 
            REG[DR] <= Reg_In[31:0];

        ReadReg1 <= REG[SR1];
        ReadReg2 <= REG[SR2];
        Reg1 <= REG[1]; // Expose register $1
        
        
    end
endmodule

`define opcode instr[31:26]
`define sr1 instr[25:21]
`define sr2 instr[20:16]
`define f_code instr[5:0]
`define numshift instr[10:6]

module MIPS (CLK, RST, CS, WE, ADDR, Mem_Bus, HALT, Reg1_Outt);
    input CLK, RST, HALT;
    output reg CS, WE;
    output [6:0] ADDR;
    inout [31:0] Mem_Bus;
    output [31:0] Reg1_Outt;
    
    //assign Reg1_Outt = reg1_out;
    //special instructions (opcode == 000000), values of F code (bits 5-0):
    parameter MULT16 = 6'b011000;
    parameter add = 6'b100000;
    parameter sub = 6'b100010;
    parameter xor1 = 6'b100110;
    parameter and1 = 6'b100100;
    parameter or1 = 6'b100101;
    parameter slt = 6'b101010;
    parameter srl = 6'b000010;
    parameter sll = 6'b000000;
    parameter jr = 6'b001000;
    
    //non-special instructions, values of opcodes:
    parameter addi = 6'b001000;
    parameter andi = 6'b001100;
    parameter ori = 6'b001101;
    parameter lw = 6'b100011;
    parameter sw = 6'b101011;
    parameter beq = 6'b000100;
    parameter bne = 6'b000101;
    parameter j = 6'b000010;
    
    //instruction format
    parameter R = 2'd0;
    parameter I = 2'd1;
    parameter J = 2'd2;
    
    //internal signals
    reg [5:0] op, opsave;
    wire [1:0] format;
    reg [31:0] instr;
    reg [6:0] pc, npc;
    wire [31:0] imm_ext, alu_in_A, alu_in_B, reg_in, readreg1, readreg2;
    wire [31:0] alu_result_save;
    reg alu_or_mem, alu_or_mem_save, regw, writing, reg_or_imm, reg_or_imm_save;
    reg fetchDorI;
    wire [4:0] dr;
    reg [2:0] state, nstate;
    wire [31:0] reg1_out;
    //combinational
    assign imm_ext = (instr[15] == 1)? {16'hFFFF, instr[15:0]} : {16'h0000, instr[15:0]};//Sign extend immediate field
    assign dr = (format == R)? instr[15:11] : instr[20:16]; //Destination Register MUX (MUX1)
    assign alu_in_A = readreg1;
    assign alu_in_B = (reg_or_imm_save)? imm_ext : readreg2; //ALU MUX (MUX2)
    assign reg_in = (alu_or_mem_save)? Mem_Bus : alu_result_save; //Data MUX (MUX3)
    assign format = (`opcode == 6'd0)? R : ((`opcode == 6'd2)? J : I);
    assign Mem_Bus = (writing)? readreg2 : 32'bZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ;
    
    //drive memory bus only during writes
    assign ADDR = (fetchDorI)? pc : alu_result_save[6:0]; //ADDR Mux
    
    //Register file instance
    REG Register(CLK, regw, dr, `sr1, `sr2, reg_in, readreg1, readreg2, reg1_out);
    assign Reg1_Outt = reg1_out;
    //ALU instance
    ALU ALUnit(CLK, RST, opsave, instr, alu_in_A, alu_in_B, alu_result_save);
    
    always @(*)
    begin
    
        fetchDorI = 0; CS = 0; WE = 0; regw = 0; writing = 0;
        npc = pc; op = jr; reg_or_imm = 0; alu_or_mem = 0; nstate = 3'd0;
        
        case (state)
            0: 
            begin //fetch
                npc = pc + 7'd1; CS = 1; nstate = 3'd1;
                fetchDorI = 1;
            end
            
            1: 
            begin //decode
                nstate = 3'd2; reg_or_imm = 0; alu_or_mem = 0;
                if (format == J) 
                begin //jump, and finish
                    npc =  instr[6:0];
                    nstate = 3'd0;
                end
                else if (format == R) //register instructions
                    op = `f_code;
                else if (format == I) 
                begin //immediate instructions
                    reg_or_imm = 1;
                    if(`opcode == lw) 
                    begin
                        op = add;
                        alu_or_mem = 1;
                    end
                    else if ((`opcode == lw)||(`opcode == sw)||(`opcode == addi)) op = add;
                    else if ((`opcode == beq)||(`opcode == bne)) 
                    begin
                        op = sub;
                        reg_or_imm = 0;
                    end
                    else if (`opcode == andi) op = and1;
                    else if (`opcode == ori) op = or1;
                end
            end
            
            2: 
            begin //execute
                nstate = 3'd3;
                if (((alu_in_A == alu_in_B)&&(`opcode == beq)) || ((alu_in_A != alu_in_B)&&(`opcode == bne))) 
                begin
                    npc = pc + imm_ext[6:0];
                    nstate = 3'd0;
                end
                else if ((`opcode == bne)||(`opcode == beq)) nstate = 3'd0;
                else if (opsave == jr) 
                begin
                    npc = alu_in_A[6:0];
                    nstate = 3'd0;
                end
            end
            
            3: 
            begin //prepare to write to mem
                nstate = 3'd0;
                if ((format == R)||(`opcode == addi)||(`opcode == andi)||(`opcode == ori)) regw = 1;
                else if (`opcode == sw) 
                begin
                    CS = 1;
                    WE = 1;
                    writing = 1;
                    
                end
                else if (`opcode == lw) 
                begin
                    CS = 1;
                    nstate = 3'd4;
                end
            end
            
            4: 
            begin
                nstate = 3'd0;
                CS = 1;
                if (`opcode == lw) regw = 1;
            end
        endcase
    end //always
        
    always @(posedge CLK) 
    begin
    
        if (RST) 
        begin
            state <= 0; 
            pc <= 0;
            
            
        end
        
        
        else if (HALT) begin
        state <= state;
        pc<=pc;
        nstate<=nstate;
        npc<=npc;
        end
        
        
        else
        begin
            state <= nstate;
            pc <= npc;
        end
        
        if(state == 3'd0)
            instr <= Mem_Bus;
        if (state == 3'd1) 
        begin
            opsave <= op;
            reg_or_imm_save <= reg_or_imm;
            alu_or_mem_save <= alu_or_mem;
        end
        
        
    end //always

endmodule


module ALU(clk, rst, op, instr, alu_in_A, alu_in_B, alu_result);
    input clk;
    input rst;
    input [5:0] op;    
	input [31:0] instr;
    input [31:0] alu_in_A;
    input [31:0] alu_in_B;
    output reg [31:0] alu_result;
    
    parameter MULT16 = 6'b011000;
    parameter add  = 6'b100000;
    parameter sub  = 6'b100010;
    parameter xor1 = 6'b100110;
    parameter and1 = 6'b100100;
    parameter or1  = 6'b100101;
    parameter slt  = 6'b101010;
    parameter srl  = 6'b000010;
    parameter sll  = 6'b000000;
    
    
    always @(posedge clk) 
    begin
        if (rst)
            alu_result <= 0;
        else 
        begin
            if      (op == and1) alu_result <= alu_in_A & alu_in_B;
            else if (op == or1)  alu_result <= alu_in_A | alu_in_B;
            else if (op == add)  alu_result <= alu_in_A + alu_in_B;
            else if (op == sub)  alu_result <= alu_in_A - alu_in_B;
            else if (op == srl)  alu_result <= alu_in_B >> `numshift;
            else if (op == sll)  alu_result <= alu_in_B << `numshift;
            else if (op == slt)  alu_result <= (alu_in_A < alu_in_B)? 32'd1 : 32'd0;                    
            else if (op == xor1) alu_result <= alu_in_A ^ alu_in_B;	
            else if (op == MULT16) alu_result <= alu_in_A[15:0] * alu_in_B[15:0];
            else alu_result <= 0;
        end
    end
    
endmodule



module complexDivider(
    input clk100Mhz,    // Fast clock
    input reset,        // Active low async reset
    output reg slowClk   // Slow clock
);
    reg [26:0] counter; // Use 27 bits to count up to 50 million

    always @(posedge clk100Mhz) begin
            if (counter == 15_999_999) begin // Count to 50 million
                counter <= 0;                // Reset the counter
                slowClk <= ~slowClk;         // Toggle the slow clock
            end else begin
                counter <= counter + 1;      // Increment the counter
            end
        end

endmodule
