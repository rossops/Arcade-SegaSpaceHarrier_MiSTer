# Report the worst setup/hold paths per clock to output_files/sta_paths.txt
# so they can be read on the Mac. Run by build.bat after the normal flow:
#   quartus_sta -t tools/sta_paths.tcl Arcade-SegaSpaceHarrier
set prj [lindex $quartus(args) 0]
project_open $prj
create_timing_netlist
read_sdc
update_timing_netlist
set fh [open "output_files/sta_paths.txt" w]
foreach_in_collection c [get_clocks] {
    set clk [get_clock_info -name $c]
    puts $fh "==== setup, clock: $clk"
    foreach_in_collection p [get_timing_paths -to_clock $c -npaths 6 -setup] {
        set from [get_node_info -name [get_path_info -from $p]]
        set to   [get_node_info -name [get_path_info -to $p]]
        puts $fh [format "slack %.3f  levels %s  from %s  to %s" \
            [get_path_info -slack $p] [get_path_info -num_logic_levels $p] $from $to]
    }
}
# the Z80 core: its own worst paths, with the raw data delay so a path that
# only passes thanks to an exception still shows its true length
# (the instance is soundsys|T80s:z80 or soundsys|tv80s_cen:z80; skip if neither is in the build)
set z80regs [get_registers -nowarn {*soundsys*:z80|*}]
if {[get_collection_size $z80regs] == 0} { set z80paths [list] } else {
    set z80paths [list "setup, to the Z80" [get_timing_paths -to $z80regs -npaths 12 -setup] \
                       "setup, from the Z80" [get_timing_paths -from $z80regs -npaths 8 -setup] \
                       "hold, to the Z80" [get_timing_paths -to $z80regs -npaths 6 -hold]]
}
foreach {label coll} $z80paths {
    puts $fh "==== $label"
    foreach_in_collection p $coll {
        puts $fh [format "slack %.3f  data %.3f ns  levels %s  from %s  to %s" \
            [get_path_info -slack $p] [expr {[get_path_info -arrival_time $p] - [get_path_info -launch_time $p]}] \
            [get_path_info -num_logic_levels $p] \
            [get_node_info -name [get_path_info -from $p]] [get_node_info -name [get_path_info -to $p]]]
    }
}
puts $fh "==== worst hold (all clocks)"
foreach_in_collection p [get_timing_paths -npaths 5 -hold] {
    puts $fh [format "slack %.3f  from %s  to %s" [get_path_info -slack $p] \
        [get_node_info -name [get_path_info -from $p]] [get_node_info -name [get_path_info -to $p]]]
}
close $fh
project_close
