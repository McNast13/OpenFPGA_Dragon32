#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|dp1|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|dp1|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

# dragon_pll (ic|dp1) is a second, independent PLL for the Dragon 32 machine
# clock - its two outputs above were missing from this file entirely until
# now, which is what actually caused CI runs #5/#6/#7's "timing violation":
# without being declared here, Quartus's STA analyzed dp1's clock as if it
# needed synchronous timing against clk_74a/mf_pllbase's clocks, which isn't
# a real relationship - see BUILD_LOG.md. 

# --- docs/SPEED_PLAN.md step 2: multicycle for the 6809 at 57.272727 MHz ---
#
# mc6809i.v's architectural registers (a/b/x/y/s/u/pc/cc/dp/tmp/addr/ea/
# CpuState/Inst*...) only update on the clk edge right after E falls, and
# its interrupt-sample registers only right after Q falls - each once per
# CPU cycle = 64 clk_dragon cycles, with Q-fall and E-fall >= 16 clocks
# apart. So paths between them have many clocks to settle, not one. The
# step 1 timing report showed the worst of them need ~27 ns (~1.6 periods).
#
# Deliberately NOT covered: e_r and q_r - they sample E/Q every clock and
# generate the once-per-cycle update enable, so paths from them must stay
# single-cycle. (A blanket -from/-to {cpu|*}, as the ZX core does for its
# T80, would wrongly relax those.)
set cpu_all   [get_registers {ic|dragon|cpu|*}]
set cpu_edges [get_registers {ic|dragon|cpu|e_r ic|dragon|cpu|q_r}]
set cpu_regs  [remove_from_collection $cpu_all $cpu_edges]
set_multicycle_path -from $cpu_regs -to $cpu_regs -setup 4
set_multicycle_path -from $cpu_regs -to $cpu_regs -hold 3

# CPU outputs (address/data/R-W, from the same once-per-cycle registers)
# to the rest of the machine. Everything outside the CPU that reacts to
# them is gated by the SAM's spd_ena: the first such enable after E falls
# is 4 clocks later at normal speed but only 2 in the SAM's fast mode, and
# the CPU registers change half a clock after E falls (negedge) - so 1.5
# periods is the real budget, i.e. -setup 2 from a negedge launch. Not 4:
# the PIAs' read strobes have side effects (clearing IRQ flags) and can
# fire on that first enable, so they must see a settled address.
# Checked consumers: ram1 (writes only while E is high), pia/pia1
# (clk_ena = spd_ena), SAM WRITE_CR (spd_ena, late-cycle we_n_s), SAM
# fast_slow latch (state 0010, >= 2 enables later), dragoncoco's data
# latches (clk_enable-gated); s_device_select_reg is assigned but unused.
set dragon_other [remove_from_collection [get_keepers {ic|dragon|*}] [get_keepers {ic|dragon|cpu|*}]]
set_multicycle_path -from $cpu_regs -to $dragon_other -setup 2
set_multicycle_path -from $cpu_regs -to $dragon_other -hold 1

# Read-data latches (dragoncoco.sv: ram_dout, rom8_dout2, romC_dout2,
# pia_dout2, pia1_dout2, rom8_64_1_2) -> the CPU. They load on the
# clk_enable tick after SAM raises RAS at state 1101, i.e. state 1110; E
# falls one SAM state later and the CPU captures on the following negedge:
# 4.5 periods later at normal speed, 2.5 in SAM fast mode. Posedge ->
# negedge, so -setup 3 = 2.5 periods.
set cpu_rd_latches [get_registers {ic|dragon|ram_dout[*] ic|dragon|rom8_dout2[*] ic|dragon|romC_dout2[*] ic|dragon|pia_dout2[*] ic|dragon|pia1_dout2[*] ic|dragon|rom8_64_1_2[*]}]
set_multicycle_path -from $cpu_rd_latches -to $cpu_regs -setup 3
set_multicycle_path -from $cpu_rd_latches -to $cpu_regs -hold 2
