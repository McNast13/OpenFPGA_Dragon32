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
