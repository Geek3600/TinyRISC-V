iverilog -s tinyriscv_core_tb -o out.vvp -I ..\rtl tinyriscv_core_tb.v ..\rtl\defines.v ..\rtl\ex.v ..\rtl\id.v ..\rtl\tinyriscv_core.v ..\rtl\pc_reg.v ..\rtl\regs.v ..\rtl\sim_ram.v ..\rtl\if_id.v ..\rtl\div.v
vvp out.vvp
