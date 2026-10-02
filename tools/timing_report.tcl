# Detailed timing reports (docs/SPEED_PLAN.md step 1). Run after a full
# compile, from src/fpga:  quartus_sta -t ../../tools/timing_report.tcl
# Writes output_files/timing_*.txt (picked up by the quartus-reports
# artifact). Uses quartus_sta's default operating conditions (the slow
# corner - the one that fails).
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist

report_clocks -file output_files/timing_clocks.txt
# TNS split by clock
create_timing_summary -setup -file output_files/timing_tns_by_clock.txt
# One line per path, worst first - which modules fail, and how many
report_timing -setup -npaths 1000 -detail summary -file output_files/timing_setup_summary.txt
report_timing -hold  -npaths 300  -detail summary -file output_files/timing_hold_summary.txt
# Every cell/net of the worst few, with launch/latch edges - shows whether
# a path is a half-cycle (posedge -> negedge) one
report_timing -setup -npaths 25 -detail full_path -file output_files/timing_setup_worst_detail.txt

project_close
