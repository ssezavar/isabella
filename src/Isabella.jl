#=
  Isabella -- a simple controller system for low-level digital design

  Named after the Bear Lake Monster.  

=#

module Isabella


function flow_command_codes() 
    s=string("""localparam NULL_CMD  = 8'h00;
localparam SLEEP_US  = 8'h01;
localparam SLEEP_MS  = 8'h02;
localparam SLEEP_S   = 8'h03;
localparam JUMP      = 8'h04;
""")
    return s
end


    
function flow_command_source()
    return string("""NULL_CMD: begin
   state <= WAIT;
end 
SLEEP_US: begin
   timerUnits <= 0;
   padr++;
   
   state <= DATA_BYTE;
end
SLEEP_MS: begin
   timerUnits <= 1;
   padr++;
   state <= DATA_BYTE;
end
SLEEP_S: begin
   timerUnits <= 2;
   padr++;
   state <= DATA_BYTE;
end 
JUMP: begin
   if (data_bytes == 1) begin
      state <= CMD_START;
      padr  <= data;
      cmd   <= pmem[data];
      data_bytes <= 0;
   end
   else begin
      padr <= padr + 1;      
      state <= DATA_BYTE;
   end
   
end
""")
end


# assign hex codes to commands
function generate_command_codes!(data)
    pfx=data["hex_prefix"]
    n=0

    for x in data["commands"]
        x["hex"] = string(pfx,n)
        n=n+1
    end
end


function print_command_code_table(data)
    s=string("")
    for x in data["commands"]
        #println(x["name"],"\t",x["hex"]
        s=string(s,x["name"],"\t",x["hex"],"\n")        
    end
    return s
end


function command_code_dict(data)
    d=Dict{String,String}()

    d["JUMP"]="04"
    d["NULL_CMD"]="00"
    d["SLEEP_US"]="01"
    d["SLEEP_MS"]="02"
    d["SLEEP_S"]="03"
    
    for x in data["commands"]
        d[x["name"]]=x["hex"]
    end
    return d
end


function translate_program(data,d)
    s=String("")
    a=data["program"]
    p=split(a,"\n")
    
    for x in p
        r=Regex("([[:digit:]]+):[[:space:]]+([A-Z_0-9]+)[[:space:]]+(.*)")
        m=match(r,x,1)
        
        if (m!=nothing)
            c=m.captures;
            if (haskey(d,c[2]))
                s=string(s,d[c[2]],"\n")
            else
                s=string(s,c[2],"\n")
            end
        end
    end
    for n in 1:(255-length(p))
        s=string(s,"00\n")
    end
    s=string(s,"00")
    return s
end


function generate_verilog(data)
    s=string("""
`timescale 1ns/1ps

module """,data["module"],"""
  (
   input 	     clk,
   input 	     rst,
   input 	     intr,
   input [7:0] 	     iadr,
   output reg 	     ready,
""",data["inputs"],data["outputs"],"""
   );
   
   // program memory
   reg [7:0] 	     pmem[255:0];

   
   reg [2:0] 	     state;
   reg [7:0] 	     padr;  // program memory address pointer
   reg [7:0] 	     cmd;   // command code register
   reg [7:0] 	     data;  // data byte register

   reg [7:0] 	     data_bytes; // count of data bytes retrieved

   // timer signals
   reg [7:0] 	     duration;
   reg 		     tclr;
   wire 	     t;
   reg [1:0] 	     timerUnits;
   
   localparam WAIT      = 0;
   localparam CMD_START = 1;
   localparam CMD_DONE  = 2;
   localparam DATA_BYTE = 3;
   localparam SLEEP     = 4;

   // import list of command codes and aliases:
   `include "inc/flow_command_codes.sv"
   `include "inc/""",data["module"],"""_command_codes.sv"

   initial begin
      state = WAIT;
      ready = 0;
      timerUnits = 0; // default micro-seconds
      \$readmemh("programs/""",data["module"],"""_program.mem",pmem,0,255);
      """,data["initial"],"""
   end   

   timer T1
     (
      .clk(clk),
      .clr(tclr),
      .duration(duration),
      .t(t),
      .scale(timerUnits)
      );
   
   
   always @(posedge clk) begin
      if (rst) begin
	 ready <= 0;
	 state <= WAIT;
	 tclr <= 1;
	 padr <= 0;
         """,data["rst"],"""
      end
      else begin
      case (state)
	WAIT: begin
	   tclr  <= 1; // Reset the timer
	   cmd   <= pmem[iadr];
	   data_bytes <= 0;
	   
	   // a new "interrupt" arrives
	   if (intr) begin
	      padr  <= iadr;

	      state <= CMD_START;
	      ready <= 0;
	   end
	   else
	     ready <= 1;
	end
	CMD_START: begin
	   ready <= 0;
	   
	   case (cmd)
	     // import program control commands
             `include "inc/flow_commands.sv"
             `include "inc/""",data["module"],"""_commands.sv"
	   endcase
	end
	CMD_DONE: begin
	   ready <= 0;
	   
	   padr       <= padr + 1;
	   cmd        <= pmem[padr + 1];
	   data_bytes <= 0;
	   state      <= CMD_START;
	end
	DATA_BYTE: begin
	   ready <= 0;
	   
	   //padr <= padr + 1;
	   data <= pmem[padr];
	   data_bytes <= data_bytes + 1;
	   if (cmd == SLEEP_US || cmd == SLEEP_MS || cmd == SLEEP_S) begin
	      state <= SLEEP;
	   end
	   else begin
	     state <= CMD_START;
           end
	end
	SLEEP: begin

	   
	   if (intr) begin
	      ready <= 0;
	      padr  <= iadr;
	      cmd   <= pmem[iadr];
	      state <= CMD_START;
	      tclr  <= 1;
	      data <= 0;
	      data_bytes <= 0;
	   end
	   else if (t) begin
	      tclr <= 1;
	      cmd <= pmem[padr+1];
              padr++;
	      data_bytes <= 0;
	      ready <= 0;	      
	      state <= CMD_START;
	   end
	   else begin
	      ready <= 1;	      
	      tclr <= 0;
	      duration <= data;
	   end
	end
      endcase
   end
   end

endmodule
""")     

    return s
end


function generate_command_source(data)
    s=string("")
    
    for x in data["commands"]
        s=string(s,x["name"],""": begin
       //padr++;
       if (data_bytes==""",x["databytes"],""") begin
""",x["verilog"],"""
      state <= CMD_DONE;
   end
   else begin
      padr++;
      state<=DATA_BYTE;
   end
end
""")
    end
    return s
end


function print_command_code_parameters(data)
    s = string("")
    for x in data["commands"]
        s = string(s,"localparam ", x["name"], " = 8'h", x["hex"],";\n")
    end
    return s
end




function generate_controller_project(data)
#    outfile=Vector{Dict{String}{String}}()
    
    generate_command_codes!(data)
    
    # Generate documentation file with command codes
    codetable = Dict{String}{String}("filename"=>string("doc/",data["module"],"_commands.md"),
                                     "contents"=>print_command_code_table(data))

    
    # Generate program ROM
    program_rom = Dict{String}{String}("filename"=>string("programs/",data["module"],"_program.mem"),
                                       "contents"=>translate_program(data,command_code_dict(data)))
    

        
    # Generate controller source
    controller_source = Dict{String}{String}("filename"=>string("src/",data["module"],".sv"),
                                       "contents"=>generate_verilog(data))

    
    # Print command table as localparam definitions
    command_param_table = Dict{String}{String}("filename"=>string("inc/",data["module"],"_command_codes.sv"),
                                               "contents"=>print_command_code_parameters(data) )


    
    # Generate Verilog implementation of commands in case block
    command_implementation = Dict{String}{String}("filename"=>string("inc/",data["module"],"_commands.sv"),
                                                  "contents"=>generate_command_source(data) )

    


    # Generate source for control flow control commands
    control_flow_source = Dict{String}{String}("filename"=>string("inc/flow_commands.sv"),
                                               "contents"=>flow_command_source() )


    # Generate localparam definitions for flow control commands
    control_flow_param_table = Dict{String}{String}("filename"=>string("inc/flow_command_codes.sv"),
                                                    "contents"=>flow_command_codes() )


    return [codetable,    
            program_rom,
            controller_source,
            command_param_table,
            command_implementation,
            control_flow_source,
            control_flow_param_table
            ]    
end


export flow_command_codes 
export flow_command_source
export generate_command_codes!
export print_command_code_table
export command_code_dict
export translate_program
export generate_verilog
export generate_command_source
export print_command_code_parameters
export generate_controller_project

end
