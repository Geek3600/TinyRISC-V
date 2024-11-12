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

// 通用寄存器模块
// 有三个读端口，分别位rs1，rs2，jtag
// 读寄存器请求来自于译码阶段，读出的数据也会返回给译码模块
// 写寄存器请求来自于执行阶段
module regs(

    input wire clk,
    input wire rst,

    // from ex
    input wire we_i,                      // 写寄存器标志，来自执行模块的写使能
    input wire[`RegAddrBus] waddr_i,      // 写寄存器地址，来自执行模块的写地址
    input wire[`RegBus] wdata_i,          // 写寄存器数据，来自执行模块的写数据

    // from jtag
    input wire jtag_we_i,                 // 写寄存器标志，来自jtag模块的写使能
    input wire[`RegAddrBus] jtag_addr_i,  // 读、写寄存器地址，来自jtag模块的读写地址
    input wire[`RegBus] jtag_data_i,      // 写寄存器数据，来自jtag模块的写数据

    // from id
    input wire[`RegAddrBus] raddr1_i,     // 来自译码模块的源寄存器1的读地址，读寄存器1地址

    // to id
    output reg[`RegBus] rdata1_o,         // 送往译码模块的源寄存器1的读数据，读寄存器1数据

    // from id
    input wire[`RegAddrBus] raddr2_i,     // 来自译码模块的源寄存器的2读地址，读寄存器2地址

    // to id
    output reg[`RegBus] rdata2_o,         // 送往译码模块的源寄存器2的读数据，读寄存器2数据

    // to jtag
    output reg[`RegBus] jtag_data_o       // 送往jtag模块的读数据，读寄存器数据

    );

    reg[`RegBus] regs[0:`RegNum - 1]; // 通用寄存器组，32个通用寄存器，每个32位



    // 写寄存器
    // 只有写使能有效，并且不是写0寄存器时才能写入
    always @ (posedge clk) begin
        if (rst == `RstDisable) begin
            // 优先ex模块写操作
            // 如果执行模块要写寄存器，并且不是写0寄存器
            if ((we_i == `WriteEnable) && (waddr_i != `ZeroReg)) begin
                regs[waddr_i] <= wdata_i;
            // 如果jtag模块要写寄存器，而且不是写0寄存器
            end else if ((jtag_we_i == `WriteEnable) && (jtag_addr_i != `ZeroReg)) begin
                regs[jtag_addr_i] <= jtag_data_i;
            end
        end
    end




    // 读寄存器1
    always @ (*) begin
        // 如果要读零寄存器，则直接输出常数0
        if (raddr1_i == `ZeroReg) begin
            rdata1_o = `ZeroWord;

        // 如果读地址等于写地址，并且正在写操作，则直接返回写数据，解决RAW相关
        end else if (raddr1_i == waddr_i && we_i == `WriteEnable) begin
            rdata1_o = wdata_i;
        
        // 正常情况下，根据读地址，索引通用寄存器组取出数据    
        end else begin
            rdata1_o = regs[raddr1_i];
        end
    end

    // 读寄存器2，与读寄存器1一样的操作
    always @ (*) begin
        if (raddr2_i == `ZeroReg) begin
            rdata2_o = `ZeroWord;
        // 如果读地址等于写地址，并且正在写操作，则直接返回写数据，解决RAW相关
        end else if (raddr2_i == waddr_i && we_i == `WriteEnable) begin
            rdata2_o = wdata_i;
        end else begin
            rdata2_o = regs[raddr2_i];
        end
    end

    // jtag读寄存器
    always @ (*) begin
        if (jtag_addr_i == `ZeroReg) begin
            jtag_data_o = `ZeroWord;
        end else begin
            jtag_data_o = regs[jtag_addr_i];
        end
    end

endmodule
