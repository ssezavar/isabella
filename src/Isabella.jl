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

    # 9/4/26 sara: cmd 10 came out as "810", not a legal 8'h literal
    pfxn = isa(pfx,Integer) ? pfx : parse(Int,string(pfx),base=16)
    if (length(data["commands"]) > 16)
        error("too many commands (",length(data["commands"]),"). only 16 fit under hex_prefix ",pfx)
    end

    # Sara 9/6: a command named JUMP used to silently replace the builtin
    seen = Set{String}()
    for x in data["commands"]
        nm = string(x["name"])
        if (nm in RESERVED_NAMES)
            error("command name \"",nm,"\" is reserved for a built-in command")
        end
        if (nm in seen)
            error("command \"",nm,"\" is defined more than once")
        end
        push!(seen,nm)
        nb = x["databytes"]
        if (!isa(nb,Integer) || nb < 0 || nb > 255)
            error("command \"",nm,"\" has a bad databytes value: ",nb)
        end
    end

    for x in data["commands"]
        #x["hex"] = string(pfx,n)
        x["hex"] = uppercase(string((pfxn<<4)+n,base=16,pad=2))
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


# sara, 09/06: names nobody may reuse
const RESERVED_NAMES = Set(["NULL_CMD","SLEEP_US","SLEEP_MS","SLEEP_S","JUMP"])


# how many data bytes each command expects, built-ins plus the user's
function command_databytes(data)
    n = Dict{String,Int}("NULL_CMD"=>0,"SLEEP_US"=>1,"SLEEP_MS"=>1,
                         "SLEEP_S"=>1,"JUMP"=>1)
    for x in data["commands"]
        n[string(x["name"])] = x["databytes"]
    end
    return n
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


# Sara, 09/04/26: .mem is hex, so a bare "20" meant 32. explicit radix now.
#   0x14 / 8'h14 hex,  8'd20 / #20 decimal,  bare digits still hex but warn
function parse_data_byte(tok)
    t = strip(tok)
    v = nothing

    if occursin(r"^0[xX][0-9a-fA-F]{1,2}$", t)
        v = parse(Int,t[3:end],base=16)
    elseif occursin(r"^8'[hH][0-9a-fA-F]{1,2}$", t)
        v = parse(Int,t[4:end],base=16)
    elseif occursin(r"^8'[dD][0-9]{1,3}$", t)
        v = parse(Int,t[4:end],base=10)
    elseif occursin(r"^#[0-9]{1,3}$", t)
        v = parse(Int,t[2:end],base=10)
    elseif occursin(r"^[0-9a-fA-F]{1,2}$", t)
        v = parse(Int,t,base=16)
        @warn "byte \"$t\" has no radix, reading it as hex ($v decimal). write 0x$t or #$v"
    else
        return nothing
    end

    if (v < 0 || v > 255)
        error("data byte out of range: ",t)
    end
    return uppercase(string(v,base=16,pad=2))
end


# Sara (9/7/26): labels may be names now, so no hand counted addresses.
# numeric labels still work, and the label is optional.
# one program line: optional label, then exactly one token
const PROGRAM_LINE = Regex("^[[:space:]]*(?:([A-Za-z_][A-Za-z_0-9]*|[[:digit:]]+)[[:space:]]*:)?[[:space:]]*([^[:space:]]+)[[:space:]]*\$")


function scan_labels(data)
    labels = Dict{String,Int}()
    addr   = 0
    for x in split(data["program"],"\n")
        line = replace(x, r"#.*$" => "")
        m = match(PROGRAM_LINE, line)
        m === nothing && continue
        lbl = m.captures[1]
        if (lbl !== nothing && match(r"^[[:digit:]]+$", lbl) === nothing)
            if (haskey(labels,lbl))
                error("label \"",lbl,"\" is defined twice")
            end
            labels[lbl] = addr
        end
        addr = addr + 1
    end
    return labels
end


function translate_program(data,d)
    s=String("")
    a=data["program"]
    p=split(a,"\n")
    nbytes=0   # sara: bytes written, not lines read

    # 9/6/26 sara: a missing data byte used to eat the next mnemonic
    nb      = command_databytes(data)
    pending = 0
    owed_by = ""
    lastcmd = ""
    jumps   = Vector{Tuple{Int,Int}}()
    labels  = scan_labels(data)   # sara 9/7

    for x in p
        # 09/04/26 Sara: strip the comment first, the old regex needed one
        line=replace(x, r"#.*$" => "")
        #r=Regex("([[:digit:]]+):[[:space:]]+([A-Z_0-9]+)[[:space:]]+(.*)")
        #r=Regex("([[:digit:]]+):[[:space:]]+([^[:space:]]+)[[:space:]]*(.*)")
        # sara 09/07: shared with scan_labels so the two cannot drift
        r=PROGRAM_LINE
        m=match(r,line,1)

        if (m!=nothing)
            c=m.captures;

            # sara 9/4/26, the label was read and then ignored.
            # 9/7 sara: only a numeric one asserts an address, a name is a target.
            #addr=parse(Int,c[1])
            if (c[1] !== nothing && match(r"^[[:digit:]]+$", c[1]) !== nothing)
                addr=parse(Int,c[1])
                if (addr != nbytes)
                    error("program line \"",strip(x),"\": label says ",addr," but byte offset is ",nbytes)
                end
            end

            if (haskey(d,c[2]))
                if (pending > 0)
                    error("program line \"",strip(x),"\": ",owed_by," still needs ",
                          pending," more data byte(s), found command ",c[2])
                end
                s=string(s,d[c[2]],"\n")
                lastcmd = string(c[2])
                pending = get(nb,lastcmd,0)
                owed_by = lastcmd
            else
                #s=string(s,c[2],"\n")
                # sara, 9/7: a bare name is a jump target
                if (haskey(labels,string(c[2])))
                    tgt = labels[string(c[2])]
                    if (pending > 0 && lastcmd == "JUMP")
                        push!(jumps,(nbytes,tgt))
                        pending = pending - 1
                    end
                    s=string(s,uppercase(string(tgt,base=16,pad=2)),"\n")
                    nbytes=nbytes+1
                    continue
                end
                b=parse_data_byte(c[2])
                if (b == nothing)
                    error("program line \"",strip(x),"\": \"",c[2],"\" is not a known command or a valid byte")
                end
                if (pending > 0)
                    if (lastcmd == "JUMP")
                        push!(jumps,(nbytes,parse(Int,b,base=16)))
                    end
                    pending = pending - 1
                end
                s=string(s,b,"\n")
            end
            nbytes=nbytes+1
        end
    end

    # sara, 09/07: a command left hanging would read its data from the padding
    if (pending > 0)
        error("program ends while ",owed_by," is still waiting for ",pending,
              " data byte(s)")
    end

    # a jump past the end lands in padding and stops. legal, almost certainly a
    # typo, so warn rather than refuse.
    for (at,target) in jumps
        if (target >= nbytes)
            @warn "JUMP at address $(at-1) targets $target, past the end of this $(nbytes) byte program. it lands in padding and stops."
        end
    end

    if (nbytes > 255)
        error("program is ",nbytes," bytes, 255 is the limit")
    end
    #for n in 1:(255-length(p))
    for n in 1:(256-nbytes-1)
        s=string(s,"00\n")
    end
    s=string(s,"00")
    return s
end


# Sara (9/4): from Dr. W's commit 1458a1a, copied as is
function timer_source()
    """
`timescale 1ns/1ps

// timer: trigger alarm after given number of clock cycles

// sara (9/5/26): 100 MHz was baked in. parameter now, fed from the yaml.
module timer #(parameter CLK_HZ = 100000000) (
	      input 	  clk,
	      input 	  clr,
	      input [1:0] scale, // 0(us),1(ms),2(s)
	      input [7:0] duration,
	      output reg  t
	 );

   // one microsecond of clocks. integer divide, so a clock that is not a
   // whole number of MHz rounds down and every delay runs slightly short.
   localparam US_TICKS = CLK_HZ / 1000000;

   //reg [7:0] 		 clkcount;   // sara 09/05, 8 bits capped at 100 MHz
   reg [15:0] 		 clkcount;
   reg [9:0] 		 uscount;
   reg [9:0] 		 mscount;
   reg [7:0] 		 scount;
   
   initial begin
      t = 0;
      clkcount = 0;
      uscount = 0;
      mscount = 0;
      scount = 0;
   end

   always @(posedge clk) begin
      if (clr) begin
	 // Reset behavior:
	 t        <= 0;
	 clkcount <= 0;
	 uscount  <= 0;
	 mscount  <= 0;
	 scount   <= 0;
	 
      end
      else begin
	 // Normal behavior:
	 // sara, 9/4: 0..100 is 101 clocks, so every "us" ran 1% long
	 //if (clkcount == 100) begin
	 //if (clkcount == 99) begin   // Sara (9/5): only right at 100 MHz
	 if (clkcount == US_TICKS-1) begin
	    clkcount <= 0;

	    // 9/4/26 sara: uscount is read before it increments, so every sleep ran
	    // a tick long. duration=1 gave 2us. ms and s roll over, already fine.
	    //if ((scale == 0) && (uscount == duration) ||
	    //	(scale == 1) && (mscount == duration) ||
	    //	(scale == 2) && (scount == duration)
	    //	) begin
	    if ((scale == 0) && ((duration == 0) || (uscount + 1 == duration)) ||
		(scale == 1) && (mscount == duration) ||
		(scale == 2) && (scount == duration)
		) begin
	       t <= 1;	       
	    end
	    // Sara 9/4/26  same off by one, that was 1001 ticks per ms
	    //else if (uscount == 1000) begin
	    else if (uscount == 999) begin
	       uscount <= 0;
	       // sara 09/04, and again for seconds
	       //if (mscount == 1000) begin
	       if (mscount == 999) begin
		  mscount <= 0;		  
		  scount <= scount + 1;
	       end
	       else
		 mscount <= mscount + 1;
	    end	    	      
	    else begin
	       uscount++;	       
	    end
	 end
	 else begin
	    clkcount++;	    
	 end
      end
   end
   

endmodule
    """
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

   //timer T1
   // 09/05/26 sara, clock rate from the yaml (clk_hz:, default 100 MHz)
   timer #(.CLK_HZ(""",string(get(data,"clk_hz",100000000)),""")) T1
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




# 9/9/26 sara: lifted from the abandoned src/Isabella.jl~ in his repo, via
#     git -C Dr_Winstead_git show origin/main:src/Isabella.jl~
# his read x.name off a Dict, compared a String numerically, and parsed a depth
# it never used. all three fixed here.
function parse_downto(s)
    n = 1
    if (s !== nothing)
        m = match(r"\[([[:digit:]]+):0\]", s)
        if (m !== nothing)
            n = 1 + parse(Int, m.captures[1])
        end
    end
    return n
end


function parse_port_declaration(s)
    r = r"(input|output)[[:space:]]+(reg|wire)?[[:space:]]*(\[[^[:space:]]+\])?[[:space:]]*([A-Za-z_][A-Za-z_0-9]*)"
    m = match(r, s)
    m === nothing && return nothing
    return Dict{String,Any}("direction" => m.captures[1],
                            "name"      => m.captures[4],
                            "width"     => parse_downto(m.captures[3]))
end


# pull the user's ports out of the raw inputs/outputs blocks in the yaml
function analyze_ports(data)
    ports = Vector{Dict{String,Any}}()
    for key in ("inputs", "outputs")
        for line in split(string(get(data, key, "")), "\n")
            stripped = replace(line, r"//.*$" => "")
            d = parse_port_declaration(stripped)
            d !== nothing && push!(ports, d)
        end
    end
    return ports
end


function port_declarations(ports, kind)
    s = ""
    for p in ports
        w = p["width"] > 1 ? string("[", p["width"]-1, ":0] ") : ""
        s = string(s, "   ", kind, " ", w, p["name"], ";\n")
    end
    return s
end


# sara, 9/9: port_declarations ends on semicolons, wrong in a module header
function port_list(ports)
    parts = String[]
    for p in ports
        w = p["width"] > 1 ? string("[", p["width"]-1, ":0] ") : ""
        push!(parts, string("   output ", w, p["name"]))
    end
    # Sara 09/09, julia eats the newline after a triple quote, so end on one
    return join(parts, ",
") * "
"
end


function port_connections(ports)
    s = ""
    for p in ports
        s = string(s, "      .", p["name"], "(", p["name"], "),\n")
    end
    return s
end


# F7. a top module skeleton wiring the controller to the board, and a testbench
# that actually runs it. Neither existed before; docs/basys3.md had to describe
# the top module in prose and tell people to write it themselves.
function generate_top_module(data)
    ports = analyze_ports(data)
    outs  = filter(p -> p["direction"] == "output", ports)
    return string("""
`timescale 1ns/1ps
//
// Top module skeleton for """, data["module"], """.
// Generated by Isabella. Edit freely, it is a starting point.
//
// btnC resets, btnU starts the routine at address 0. btnU is NOT debounced,
// so holding it restarts the routine every clock. Fine for a first test.
//
module """, data["module"], """_top
  (
   input clk,
   input btnC,
   input btnU,
""", port_list(outs), """
   );

   wire ready;

""", "   ", data["module"], """ ctrl
     (
      .clk(clk),
      .rst(btnC),
      .intr(btnU),
      .iadr(8'd0),
""", port_connections(outs), """
      .ready(ready)
      );

endmodule
""")
end


function generate_testbench(data)
    ports = analyze_ports(data)
    outs  = filter(p -> p["direction"] == "output", ports)
    watch = isempty(outs) ? "ready" : outs[1]["name"]
    return string("""
`timescale 1ns/1ps
//
// Testbench for """, data["module"], """, generated by Isabella.
//
//   iverilog -g2012 -I. -o sim.vvp sim/tb_""", data["module"], """.sv \\
//            src/timer.sv src/""", data["module"], """.sv
//   vvp sim.vvp
//
// Run vvp from the directory holding programs/, the .mem path is resolved at
// runtime. Change RUN_US or the start address to suit your program.
//
module tb_""", data["module"], """;

   localparam RUN_US = 200;      // how long to let the program run

   reg          clk  = 0;
   reg          rst  = 1;
   reg          intr = 0;
   reg [7:0]    iadr = 0;
   wire         ready;
""", port_declarations(outs, "   wire"), """
   """, data["module"], """ dut
     (
      .clk(clk),
      .rst(rst),
      .intr(intr),
      .iadr(iadr),
""", port_connections(outs), """
      .ready(ready)
      );

   always #5 clk = ~clk;         // 100 MHz, change with clk_hz in the yaml

   always @(""", watch, """)
     if (\$realtime > 0)
       \$display("  %10.3f us   """, watch, """ = %h", \$realtime/1000.0, """, watch, """);

   initial begin
      \$display("");
      \$display("=== """, data["module"], """ ===");
      \$display("");

      repeat (4) @(posedge clk);
      rst = 0;
      repeat (2) @(posedge clk);

      // start the routine at address 0
      @(negedge clk); iadr = 0; intr = 1;
      @(negedge clk); intr = 0;

      #(RUN_US * 1000);

      \$display("");
      \$display("finished, ready = %b", ready);
      \$display("");
      \$finish;
   end

endmodule
""")
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
    

        
    # Include timer module source
    # sara, 9/4/26: a local of the same name shadowed the function it calls
    #timer_source = Dict{String}{String}("filename"=>"src/timer.sv",
    #                                    "contents"=>timer_source())
    timer_src = Dict{String}{String}("filename"=>"src/timer.sv",
                                     "contents"=>timer_source())

    # Generate controller source
    controller_source = Dict{String}{String}("filename"=>string("src/",data["module"],".sv"),
                                       "contents"=>generate_verilog(data))

    
    # Print command table as localparam definitions
    command_param_table = Dict{String}{String}("filename"=>string("inc/",data["module"],"_command_codes.sv"),
                                               "contents"=>print_command_code_parameters(data) )


    
    # Generate Verilog implementation of commands in case block
    command_implementation = Dict{String}{String}("filename"=>string("inc/",data["module"],"_commands.sv"),
                                                  "contents"=>generate_command_source(data) )

    


    # sara 9/10/26: neither existed, the docs described them in prose
    top_module = Dict{String}{String}("filename"=>string("top/",data["module"],"_top.sv"),
                                      "contents"=>generate_top_module(data))

    testbench = Dict{String}{String}("filename"=>string("sim/tb_",data["module"],".sv"),
                                     "contents"=>generate_testbench(data))

    # Generate source for control flow control commands
    control_flow_source = Dict{String}{String}("filename"=>string("inc/flow_commands.sv"),
                                               "contents"=>flow_command_source() )


    # Generate localparam definitions for flow control commands
    control_flow_param_table = Dict{String}{String}("filename"=>string("inc/flow_command_codes.sv"),
                                                    "contents"=>flow_command_codes() )


    return [codetable,    
            program_rom,
            timer_src,
            controller_source,
            command_param_table,
            command_implementation,
            control_flow_source,
            control_flow_param_table,
            top_module,
            testbench
            ]    
end


export flow_command_codes 
export flow_command_source
export generate_command_codes!
export print_command_code_table
export command_code_dict
export translate_program
export generate_verilog
export timer_source
export generate_command_source
export print_command_code_parameters
export generate_top_module
export generate_testbench
export analyze_ports
export generate_controller_project

end
