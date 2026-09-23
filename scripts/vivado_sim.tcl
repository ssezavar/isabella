# ============================================================================
# vivado_sim.tcl
#
# Runs a generated Isabella project under Vivado's own simulator, xsim, in
# batch. The point is that everything we have verified so far has been verified
# with Icarus, which is a different tool with different opinions.
#
#   vivado -mode batch -source scripts/vivado_sim.tcl -tclargs <projdir> <module>
#
# for example, after
#   julia --project=. scripts/isabella.jl examples/seven_segment.yaml
#
#   vivado -mode batch -source scripts/vivado_sim.tcl -tclargs seven_segment seven_segment
#
# UNRUN. Vivado is not installed on the machine this was written on, so this
# script has never been executed. It is written from the documented behaviour
# of these commands, not from a passing run. Expect to correct it the first
# time it is used, and please correct it here when you do.
#
# sara 9/16/26
# ============================================================================

if {[llength $argv] < 2} {
    puts "usage: -tclargs <project_dir> <module_name>"
    exit 1
}

set projdir [lindex $argv 0]
set module  [lindex $argv 1]

if {![file isdirectory $projdir]} {
    puts "ERROR no such directory: $projdir"
    exit 1
}

# xsim inherits the working directory, and the controller does
#   $readmemh("programs/<module>_program.mem", ...)
# with a relative path, so the simulation has to run from inside the project
# or the ROM comes up as x. This is the same trap as the vvp one in
# docs/troubleshooting.md.
cd $projdir

set part "xc7a35tcpg236-1"       ;# Basys3. harmless for simulation only

create_project -in_memory -part $part

add_files [list src/timer.sv src/$module.sv]
add_files -fileset sim_1 [list sim/tb_$module.sv]

# the controller does `include "inc/...", resolved against the directory
# ABOVE inc, which is the project root we just cd'd into
set_property include_dirs [list [pwd]] [get_filesets sources_1]
set_property include_dirs [list [pwd]] [get_filesets sim_1]

set_property top tb_$module [get_filesets sim_1]
update_compile_order -fileset sim_1

puts ""
puts "=== xsim: $module ==="
puts ""

launch_simulation
run all

puts ""
puts "=== xsim finished ==="
puts ""

close_sim
exit 0
