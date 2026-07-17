#Reserved bits - TCR (bits 7:2 and 31:12)
coverage exclude -togglenode /test_bench/dut/regs/tcr_out\[7:2\]
coverage exclude -togglenode /test_bench/dut/regs/tcr_out\[31:12\]

#Reserved bits - THCSR (bits 31:2)
coverage exclude -togglenode /test_bench/dut/regs/thcsr_out\[31:2\]

#Reserved bits - TIER (bits 31:1)
coverage exclude -togglenode /test_bench/dut/regs/tier_out\[31:1\]
coverage exclude -togglenode /test_bench/dut/regs/tier_pre\[31:1\]

#Reserved bits - TISR (bits 31:1)
coverage exclude -togglenode /test_bench/dut/slave/wait_cnt\[1\]

#Counter default branch - unreachable (prohibit_div blocks div_val > 8)
coverage exclude -scope /test_bench/dut/cnt -line 28 -item b 1
coverage exclude -scope /test_bench/dut/cnt -line 28 -item s 1

coverage save IP.ucdb
exit 
