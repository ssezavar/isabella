# Sara 9/4/26: regression tests for the assembler and timer fixes.
# no YAML dependency on purpose, the example is rebuilt inline below so this
# runs on a bare Julia install. run it with:
#     julia --project=. test/runtests.jl

include("../src/Isabella.jl")
using .Isabella
using Test

# the shipped controller_with_shift.yaml, as a Dict
function demo()
    cmds = [Dict("name"=>n,"databytes"=>b,"verilog"=>"") for (n,b) in [
        ("LED_CLEAR",0), ("LED_SET_LOW_BYTE",1), ("LED_SET_HIGH_BYTE",1),
        # 9/12/26 Sara: renamed in the example, they AND
        #("LED_OR_LOW_BYTE",1), ("LED_OR_HIGH_BYTE",1), ("LED_NAND_LOW_BYTE",1),
        #("LED_NAND_HIGH_BYTE",1), ("LED_FLOOD",0), ("LED_RIGHT_SHIFT",0),
        ("LED_OR_LOW_BYTE",1), ("LED_OR_HIGH_BYTE",1), ("LED_AND_LOW_BYTE",1),
        ("LED_AND_HIGH_BYTE",1), ("LED_FLOOD",0), ("LED_RIGHT_SHIFT",0),
        ("LED_LEFT_SHIFT",0)]]
    # sara 9/5: the port fields, needed once the guard called the generator
    return Dict{String,Any}("module"=>"led_controller_with_shift",
                            "hex_prefix"=>8,
                            "commands"=>cmds,
                            "program"=>"",
                            "inputs"=>"  // none\n",
                            "outputs"=>"  output reg [15:0] led\n",
                            "initial"=>"led = 0;\n",
                            "rst"=>"led <= 0;\n")
end

function assemble(prog)
    d = demo()
    d["program"] = prog
    Isabella.generate_command_codes!(d)
    return split(Isabella.translate_program(d, Isabella.command_code_dict(d)), "\n")
end


@testset "Isabella G1-G5" begin

    @testset "G5 command codes" begin
        d = demo()
        Isabella.generate_command_codes!(d)
        @test [c["hex"] for c in d["commands"]] ==
              ["80","81","82","83","84","85","86","87","88","89"]

        # 11th command used to come out as "810"
        push!(d["commands"], Dict("name"=>"LED_EXTRA","databytes"=>0,"verilog"=>""))
        Isabella.generate_command_codes!(d)
        @test d["commands"][11]["hex"] == "8A"
        @test length(d["commands"][11]["hex"]) == 2

        # past 16 there is no nibble left
        big = demo()
        big["commands"] = [Dict("name"=>"C$i","databytes"=>0,"verilog"=>"") for i in 1:17]
        @test_throws ErrorException Isabella.generate_command_codes!(big)
    end

    @testset "G3 padding" begin
        # $readmemh(...,0,255) wants 256 bytes. this used to give 254.
        # sara 9/25: bare bytes are refused now, the old lines stay as comments
        out = assemble("""
  0:\tLED_SET_LOW_BYTE  # set 0-7
  #1:\t01\t\t  # one light on
  1:\t'h01\t\t  # one light on
  2:\tLED_SET_HIGH_BYTE # set 8-16
  #3:\t00\t\t  # no lights on
  3:\t'h00\t\t  # no lights on
  4:\tLED_LEFT_SHIFT\t  # rotate light
  5:\tSLEEP_MS \t  # pause
  #6:\t20     \t\t  # 20ms
  6:\t'h20     \t\t  # 20ms
  7: \tJUMP   \t\t  # loop back
  #8:\t04      \t  # to left shift cmd
  8:\t'd4      \t  # to left shift cmd
""")
        @test length(out) == 256
        @test out[1:9] == ["81","01","82","00","89","02","20","04","04"]
        @test all(b -> b == "00", out[10:end])
    end

    @testset "G1 lines without trailing text" begin
        # every one of these used to be silently dropped
        out = assemble("""
  0:\tLED_CLEAR
  1:\tLED_FLOOD
  2:\tSLEEP_MS
  #3:\t0x14
  3:\t'h14
""")
        @test out[1:4] == ["80","87","02","14"]
        @test length(out) == 256
    end

    @testset "G2 address labels" begin
        # label has to match the byte offset now
        @test_throws ErrorException assemble("""
  0:\tLED_CLEAR
  5:\tLED_FLOOD
""")
        @test_throws ErrorException assemble("""
  1:\tLED_CLEAR
""")
        # in-order still fine
        @test assemble("  0:\tLED_CLEAR\n  1:\tLED_FLOOD\n")[1:2] == ["80","87"]
    end

    @testset "G4 data byte radix" begin
        # Sara 9/25/26: F10, verilog literals only. 0x, # and bare all refused
        #@test Isabella.parse_data_byte("0x14")  == "14"
        @test Isabella.parse_data_byte("0x14")  === nothing
        @test Isabella.parse_data_byte("8'h14") == "14"
        @test Isabella.parse_data_byte("8'd20") == "14"   # 20 decimal
        #@test Isabella.parse_data_byte("#20")   == "14"
        @test Isabella.parse_data_byte("#20")   === nothing
        @test Isabella.parse_data_byte("zz")    === nothing
        #@test Isabella.parse_data_byte("0xFF")  == "FF"
        @test Isabella.parse_data_byte("0xFF")  === nothing
        @test Isabella.parse_data_byte("'hFF")  == "FF"

        # bare digits still read as hex, but they warn now
        #@test (@test_logs (:warn,) Isabella.parse_data_byte("20")) == "20"
        # Sara (9/17): hex is the default now, per Dr. Winstead. no warning,
        # and verilog literals with or without the size
        #@test (@test_logs Isabella.parse_data_byte("20")) == "20"
        # sara 9/25: and now not at all, his 9/25 answer
        @test Isabella.parse_data_byte("20")    === nothing
        @test Isabella.parse_data_byte("'h14")       == "14"
        @test Isabella.parse_data_byte("'d20")       == "14"
        @test Isabella.parse_data_byte("'b10100")    == "14"
        @test Isabella.parse_data_byte("8'b00010100") == "14"
        @test_throws ErrorException Isabella.parse_data_byte("'d256")
        @test Isabella.parse_data_byte("16'h14")     === nothing

        # junk in the program is an error instead of a corrupt ROM
        @test_throws ErrorException assemble("  0:\tNOT_A_COMMAND\n")

        # sara (9/25): the old forms stop the build and say what to write.
        # "19" is the case that started this, 19 to him and 25 to us.
        @test_throws r"write 'h19 for hex or 'd19 for decimal" assemble("\tJUMP\n\t19\n")
        @test_throws r"write 'h14$" assemble("\tSLEEP_MS\n\t0x14\n")
        @test_throws r"write 'd170$" assemble("\tSLEEP_MS\n\t170\n")
        @test_throws r"write 'h0A$" assemble("\tSLEEP_MS\n\t0A\n")
        # no hint when there is nothing sensible to suggest
        @test_throws r"not a known command or a valid byte" assemble("\tSLEEP_MS\n\t256\n")
        @test_throws r"not a known command or a valid byte" assemble("\tSLEEP_MS\n\tFF\n")
        # the literal forms of the same bytes are fine
        @test assemble("\tJUMP\n\t'd1\n")[1:2] == ["04","01"]
        @test assemble("\tSLEEP_MS\n\t'd170\n")[1:2] == ["02","AA"]
    end

    # sara 9/5/26: not behaviour, just that our edits survived. the timer is
    # Verilog inside a string, so nothing else would notice it reverting.
    @testset "our fixes are still present" begin
        tsrc = Isabella.timer_source()

        # sara (9/5): once 99 became US_TICKS-1 the old string survived only in
        # a comment, so this passed while checking nothing. grep the live line.
        #@test occursin("clkcount == 99", tsrc)
        @test occursin("clkcount == US_TICKS-1", tsrc)
        @test occursin("localparam US_TICKS = CLK_HZ / 1000000", tsrc)
        @test occursin("parameter CLK_HZ", tsrc)
        @test occursin("uscount == 999", tsrc)
        @test occursin("mscount == 999", tsrc)
        @test occursin("uscount + 1 == duration", tsrc)
        @test occursin("duration == 0", tsrc)

        # and his originals should be gone from the live code path
        @test !occursin("\n\t if (clkcount == 100) begin", tsrc)

        # G6, the shadowed local. if this regressed the call below would throw
        d = demo()
        d["program"] = "  0:\tLED_CLEAR\n"
        out = Isabella.generate_controller_project(d)
        @test any(f -> f["filename"] == "src/timer.sv", out)
        #@test length(out) == 10   # sara 9/10: was 8, before top/ and sim/
        #@test length(out) == 11   # sara 9/14, the listing file
        @test length(out) == 13   # 9/20 sara, his two register command files

        # H8, the clock has to reach the timer from the yaml
        ctrl = filter(f -> f["filename"] == "src/led_controller_with_shift.sv", out)[1]
        @test occursin("timer #(.CLK_HZ(100000000)) T1", ctrl["contents"])
        d2 = demo(); d2["program"] = "  0:\tLED_CLEAR\n"; d2["clk_hz"] = 50000000
        out2 = Isabella.generate_controller_project(d2)
        ctrl2 = filter(f -> f["filename"] == "src/led_controller_with_shift.sv", out2)[1]
        @test occursin("timer #(.CLK_HZ(50000000)) T1", ctrl2["contents"])
    end

    # Sara, 9/6/26: the generator used to accept all of these
    @testset "F5 validation" begin
        dup = demo()
        push!(dup["commands"], Dict("name"=>"LED_CLEAR","databytes"=>0,"verilog"=>""))
        @test_throws ErrorException Isabella.generate_command_codes!(dup)

        res = demo()
        push!(res["commands"], Dict("name"=>"JUMP","databytes"=>0,"verilog"=>""))
        @test_throws ErrorException Isabella.generate_command_codes!(res)

        bad = demo()
        bad["commands"][1]["databytes"] = -1
        @test_throws ErrorException Isabella.generate_command_codes!(bad)

        # a command swallowing the next mnemonic as its data byte
        @test_throws ErrorException assemble("  0:\tLED_SET_LOW_BYTE\n  1:\tLED_CLEAR\n")
        # and running out of program mid command
        @test_throws ErrorException assemble("  0:\tLED_SET_LOW_BYTE\n")
        # the correct version still assembles
        #@test assemble("  0:\tLED_SET_LOW_BYTE\n  1:\t0x01\n")[1:2] == ["81","01"]
        @test assemble("  0:\tLED_SET_LOW_BYTE\n  1:\t'h01\n")[1:2] == ["81","01"]   # 9/25 sara, F10

        # a jump off the end warns, it does not refuse
        #@test (@test_logs (:warn,) assemble("  0:\tJUMP\n  1:\t0x40\n"))[1:2] == ["04","40"]
        @test (@test_logs (:warn,) assemble("  0:\tJUMP\n  1:\t'h40\n"))[1:2] == ["04","40"]
    end

    # Sara, 9/7/26: labels by name, so nobody counts jump targets by hand
    @testset "F3 symbolic labels" begin
        out = assemble("""
start:\tLED_SET_LOW_BYTE
#\t0x01
\t'h01
loop:\tLED_LEFT_SHIFT
\tJUMP
\tloop
""")
        @test out[1:5] == ["81","01","89","04","02"]   # loop is address 2

        # forward reference
        fwd = assemble("""
\tJUMP
\tdone
\tLED_CLEAR
done:\tLED_LEFT_SHIFT
""")
        @test fwd[1:4] == ["04","03","80","89"]

        # a label defined twice
        @test_throws ErrorException assemble("a:\tLED_CLEAR\na:\tLED_CLEAR\n")

        # numeric labels keep their meaning and are still checked
        @test assemble("  0:\tLED_CLEAR\n  1:\tLED_FLOOD\n")[1:2] == ["80","87"]
        @test_throws ErrorException assemble("  0:\tLED_CLEAR\n  9:\tLED_FLOOD\n")

        # and the label is optional entirely
        @test assemble("\tLED_CLEAR\n\tLED_FLOOD\n")[1:2] == ["80","87"]
    end

    # Sara 9/10/26: port parsing, and the generated top module and testbench
    @testset "F6/F7 top module and testbench" begin
        ports = Isabella.analyze_ports(Dict("inputs"=>"  input btn
",
                                            "outputs"=>"  output reg [15:0] led,
  output reg busy
"))
        @test length(ports) == 3
        @test ports[1]["name"] == "btn"    && ports[1]["width"] == 1
        @test ports[2]["name"] == "led"    && ports[2]["width"] == 16
        @test ports[3]["name"] == "busy"   && ports[3]["width"] == 1
        @test ports[1]["direction"] == "input"
        @test ports[2]["direction"] == "output"

        d = demo(); d["program"] = "  0:	LED_CLEAR
"
        Isabella.generate_command_codes!(d)

        top = Isabella.generate_top_module(d)
        @test occursin("module led_controller_with_shift_top", top)
        @test occursin("output [15:0] led", top)
        @test occursin(".led(led),", top)
        @test !occursin("led;", top)          # a port list takes commas, not semicolons

        tb = Isabella.generate_testbench(d)
        @test occursin("module tb_led_controller_with_shift", tb)
        @test occursin("wire [15:0] led;", tb)
        @test occursin("\$finish", tb)       # dollars survived the julia string
        @test occursin("\$realtime", tb)

        out = Isabella.generate_controller_project(d)
        names = [f["filename"] for f in out]
        @test "top/led_controller_with_shift_top.sv" in names
        @test "sim/tb_led_controller_with_shift.sv" in names
    end

    @testset "program length guard" begin
        #long = join(["  $(i):\tLED_CLEAR" for i in 0:255], "\n")
        #@test_throws ErrorException assemble(long)
        # 9/25/26 sara: 256 is a full rom, not an overflow. his
        # led_controller_bigger is exactly 256 bytes and it is valid.
        long = join(["  $(i):\tLED_CLEAR" for i in 0:256], "\n")
        @test_throws ErrorException assemble(long)
        ok = join(["  $(i):\tLED_CLEAR" for i in 0:254], "\n")
        @test length(assemble(ok)) == 256
        # a program that exactly fills the rom, no padding left
        full = join(["  $(i):\tLED_CLEAR" for i in 0:255], "\n")
        out  = assemble(full)
        @test length(out) == 256
        @test all(b -> b == "80", out)
    end
    # Sara 9/13/26: byte for byte against the saved baseline
    @testset "golden output" begin
        gold(f) = read(joinpath(@__DIR__,"golden",f), String)
        prog = replace(gold("led_controller_with_shift_program.asm"),
                       "\r\n" => "\n")
        want = replace(gold("led_controller_with_shift_program.mem"),
                       "\r\n" => "\n")
        got  = join(assemble(prog), "\n")
        @test got == want
        @test length(split(got,"\n")) == 256
    end

    # sara 9/14/26: the listing has to agree with the .mem, byte for byte
    @testset "listing file" begin
        d = demo()
        #d["program"] = "  0:\tLED_SET_LOW_BYTE\n  1:\t0x0F\n"
        d["program"] = "  0:\tLED_SET_LOW_BYTE\n  1:\t'h0F\n"   # sara 9/25/26
        Isabella.generate_command_codes!(d)
        cc  = Isabella.command_code_dict(d)
        lst = Isabella.program_listing(d,cc)
        mem = split(Isabella.translate_program(d,cc), "\n")

        rows = [l for l in split(lst,"\n") if startswith(l,"  ")]
        @test length(rows) == 2
        for (k,r) in enumerate(rows)
            @test split(r)[2] == mem[k]
        end

        out = Isabella.generate_controller_project(d)
        @test any(f -> endswith(f["filename"],"_program.lst"), out)

        # a named target gets its own section
        d2 = demo()
        d2["program"] = "  top:\tLED_CLEAR\n  JUMP\n  top\n"
        Isabella.generate_command_codes!(d2)
        l2 = Isabella.program_listing(d2,Isabella.command_code_dict(d2))
        @test occursin("# labels", l2)
        @test occursin("top", l2)
    end

    # sara 09/15: ++ is SystemVerilog. it crept in from three generators,
    # so the guard is on the output, not on any one of them.
    @testset "generated source is verilog 2001" begin
        d = demo()
        #d["program"] = "  0:\tLED_SET_LOW_BYTE\n  1:\t0x0F\n"
        d["program"] = "  0:\tLED_SET_LOW_BYTE\n  1:\t'h0F\n"
        for f in Isabella.generate_controller_project(d)
            endswith(f["filename"], ".md") && continue
            #live = [l for l in split(f["contents"], "\n") if !startswith(strip(l), "//")]
            # sara (9/20): his localparam table says "// B++" at the end of a line
            live = [replace(l, r"//.*$" => "") for l in split(f["contents"], "\n")]
            @test !any(l -> occursin("++", l), live)
        end
    end

    # Sara 9/21/26: his register commands from 83b8440, merged with fixes.
    # the fsm side is test/tb_register.sv, this is the assembler side.
    @testset "register commands" begin
        # the ten names assemble to his codes
        out = assemble("""
\tLOAD_A
\t'd5
\tLOAD_B
\t'd3
\tINCR_B
\tDECR_B
\tADD_AB
\tSUB_AB
\tSWAP_AB
\tJZ
\t'd0
\tJLZ
\t'd0
\tJGZ
\t'd0
""")
        @test out[1:15] == ["11","05","12","03","13","14","15","16","17",
                            "18","00","19","00","1A","00"]

        # a conditional jump takes a label, like JUMP does
        loop = assemble("""
\tLOAD_B
\t'd3
body:\tLED_LEFT_SHIFT
\tDECR_B
\tJGZ
\tbody
\tNULL_CMD
""")
        @test loop[1:7] == ["12","03","89","14","1A","02","00"]

        # and gets the same off the end warning, naming itself
        #@test_logs (:warn, r"^JZ at address") assemble("\tJZ\n\t0x40\n")
        @test_logs (:warn, r"^JZ at address") assemble("\tJZ\n\t'h40\n")

        # LOAD_A owes a byte, INCR_B does not
        @test_throws ErrorException assemble("\tLOAD_A\n\tLED_CLEAR\n")
        @test assemble("\tINCR_B\n\tLED_CLEAR\n")[1:2] == ["13","80"]

        # the names are reserved now
        res = demo()
        push!(res["commands"], Dict("name"=>"LOAD_A","databytes"=>1,"verilog"=>""))
        @test_throws ErrorException Isabella.generate_command_codes!(res)

        # and so are the prefixes they live under
        for p in (0, 1, 16, "0", "1", "10")
            bad = demo(); bad["hex_prefix"] = p
            @test_throws ErrorException Isabella.generate_command_codes!(bad)
        end
        ok = demo(); ok["hex_prefix"] = "f"
        Isabella.generate_command_codes!(ok)
        @test ok["commands"][1]["hex"] == "F0"

        # what lands in the generated project
        d = demo(); d["program"] = "\tLED_CLEAR\n"
        prj  = Isabella.generate_controller_project(d)
        byname(n) = filter(f -> f["filename"] == n, prj)[1]["contents"]
        regs  = byname("inc/register_commands.sv")
        codes = byname("inc/register_command_codes.sv")
        ctrl  = byname("src/led_controller_with_shift.sv")
        @test occursin("localparam JGZ     = 8'h1A;", codes)
        @test occursin("\$signed(_B) < 0", regs)
        @test occursin("\$signed(_B) > 0", regs)
        # the not taken branch has its own arm now
        @test count("else if (data_bytes == 1) begin", regs) == 3
        @test occursin("reg [7:0]         _A, _B;", ctrl)
        @test occursin("`include \"inc/register_commands.sv\"", ctrl)
        @test occursin("`include \"inc/register_command_codes.sv\"", ctrl)
        @test occursin("_A <= 0;", ctrl)   # on rst
    end

end
