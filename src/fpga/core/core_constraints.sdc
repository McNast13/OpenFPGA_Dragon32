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
