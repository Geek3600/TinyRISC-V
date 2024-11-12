 /*                                                                      
 Copyright 2019 Blue Liang, liangkangnan@163.com
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
 Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */

`include "defines.v"

// PC寄存器模块
module pc_reg(

    input wire clk,
    input wire rst,

    input wire jump_flag_i,                 // 跳转标志
    input wire[`InstAddrBus] jump_addr_i,   // 跳转地址，即跳转到该地址
    input wire[`Hold_Flag_Bus] hold_flag_i, // 流水线暂停标志，即pc值保持不变
    input wire jtag_reset_flag_i,           // 复位标志

    output reg[`InstAddrBus] pc_o           // PC指针指

    );


    always @ (posedge clk) begin
        // 复位
        // 外部复位或者是jtag引发的复位
        if (rst == `RstEnable || jtag_reset_flag_i == 1'b1) begin
            pc_o <= `CpuResetAddr;// 一个全0地址
        
        // 跳转
        // 如果跳转，则将输入的跳转目标地址作为pc值
        end else if (jump_flag_i == `JumpEnable) begin
            pc_o <= jump_addr_i;
        
        // 暂停
        // pc值保持不变
        end else if (hold_flag_i >= `Hold_Pc) begin
            pc_o <= pc_o;
        
        // 地址加4
        // 如果上面的情况都不满足，则顺序取指，pc值自增
        end else begin
            pc_o <= pc_o + 4'h4;
        end
    end

endmodule
