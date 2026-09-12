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
        ("LED_OR_LOW_BYTE",1), ("LED_OR_HIGH_BYTE",1), ("LED_NAND_LOW_BYTE",1),
        ("LED_NAND_HIGH_BYTE",1), ("LED_FLOOD",0), ("LED_RIGHT_SHIFT",0),
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
        out = assemble("""
  0:\tLED_SET_LOW_BYTE  # set 0-7
  1:\t01\t\t  # one light on
  2:\tLED_SET_HIGH_BYTE # set 8-16
  3:\t00\t\t  # no lights on
  4:\tLED_LEFT_SHIFT\t  # rotate light
  5:\tSLEEP_MS \t  # pause
  6:\t20     \t\t  # 20ms
  7: \tJUMP   \t\t  # loop back
  8:\t04      \t  # to left shift cmd
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
  3:\t0x14
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
        @test Isabella.parse_data_byte("0x14")  == "14"
        @test Isabella.parse_data_byte("8'h14") == "14"
        @test Isabella.parse_data_byte("8'd20") == "14"   # 20 decimal
        @test Isabella.parse_data_byte("#20")   == "14"
        @test Isabella.parse_data_byte("zz")    === nothing
        @test Isabella.parse_data_byte("0xFF")  == "FF"

        # bare digits still read as hex, but they warn now
        @test (@test_logs (:warn,) Isabella.parse_data_byte("20")) == "20"

        # junk in the program is an error instead of a corrupt ROM
        @test_throws ErrorException assemble("  0:\tNOT_A_COMMAND\n")
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
        @test length(out) == 10   # sara 9/10: was 8, before top/ and sim/

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
        @test assemble("  0:\tLED_SET_LOW_BYTE\n  1:\t0x01\n")[1:2] == ["81","01"]

        # a jump off the end warns, it does not refuse
        @test (@test_logs (:warn,) assemble("  0:\tJUMP\n  1:\t0x40\n"))[1:2] == ["04","40"]
    end

    # Sara, 9/7/26: labels by name, so nobody counts jump targets by hand
    @testset "F3 symbolic labels" begin
        out = assemble("""
start:\tLED_SET_LOW_BYTE
\t0x01
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
        long = join(["  $(i):\tLED_CLEAR" for i in 0:255], "\n")
        @test_throws ErrorException assemble(long)
        ok = join(["  $(i):\tLED_CLEAR" for i in 0:254], "\n")
        @test length(assemble(ok)) == 256
    end

end
