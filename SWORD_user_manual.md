# SWORD 用户指导手册

## 1 概要

SWORD 是一款面向系统能力的计算机系统课程贯通教学实验平台。结合 Xilinx 的 Kintex-7 系列 FPGA 丰富的逻辑资源、板载层次完整的存储结构（包括 SRAM、DRAM 和 Flash）、以及丰富多样的接口（包括 GPIO、UART、 音频、视频、USB、SATA、网络、光纤、Pmod），计算机相关专业的教师和学生可在该平台上开展各类专业课程的实验教学，如计算机体系结构/组成原理、计算机网络通信、计算机图像处理、数字信号处理、嵌入式系统等。

SWORD 平台具体硬件功能包括：

- 主芯片
    - Xilinx Kintex™-7 XC7K160T-1FFG676 FPGA
    - 162,240 个逻辑单元  
    - 11,700 Kb 容量的片内存储器
    - 600 个 DSP 快速乘法器  
    - 1 个 PCIe 2.0 硬核控制器
    - 8 个 12.5Gbps GTX 高速串行收发器
- 配置方式：
    - USB-JTAG
    - SPI Flash
- 存储器
    - 512M Byte DDR3 存储器（数据位宽 32bit）  
    - 32M Byte NOR FLASH 存储器（数据位宽 32bit）  
    - 6M Byte SRAM 存储器（数据位宽 48bit）
- 主要接口
    - 1 路 10M/100M/1000M 网口（RJ45）  
    - 1 路 UART 接口  
    - 1 路 12 位 VGA 接口（RGB656）  
    - 1 路 USB-OTG 接口（可接电脑，鼠标，键盘，记忆棒）
    - 2 路 USB 转 PS2 接口（可接鼠标，键盘）  
    - 1 路 SD 卡插槽  
    - 1 路 HDMI 输入接口（1080P/30fps）  
    - 1 路 HDMI 输出接口（1080P/30fps）  
    - 5 个 Pmod 接口（其中一个接到 FPGA 内部 AD 转换器）  
    - 1 组 Arduino 接口  
    - 1 路 JTAG 接口（烧录 FPGA 程序和调试用）
- 其他
    - 16 个单色 LED  
    - 16 个拨码开关   
    - 17 个按键开关（16 个用户自定义按键开关+1 个复位按键开关）  
    - 8 个七段数码显示管  
    - 2 个三色 LED  
    - 1 个三轴加速度计  
    - 1 个温度传感器  
    - 1 个扬声器放大器  
    - 1 个数字麦克风
- 软件
    - ISE Design Suite 14.7   
    - Vivado Design Suite 2014.3 及以上版本

## 2 SWORD 平台功能详述

### 2.1 电源输入及开关

SWORD 平台可接两路电源输入：一路是标配的电源适配器提供的 12V/2A 的电源（CN1）；一路是 6Pin 的 ATX 电源提供的 12V 电源（CN2）。当接入电源时，电源指示灯（LD19）会被点亮，拨动开关（DSW16）切换 SWORD 平台的开关状态。整个平台的电源分布如所示。

**注意事项：**
1. 两路电源不可同时接入，只能单路接入！  
2. 电源接口仅可接标示 12V 电压的电源，请勿将其他非 12V 电源接入电源接口！

### 2.2 Xilinx Kintex™-7 FPGA XC7K160T-1FFG676C

SWORD 平台的主芯片采用的是 Xilinx Kintex™-7 系列的 XC7K160T FPGA，为 FFG676 球形阵列封装，速度等级为 1，工作环境温度为 0 到 85 摄氏度。其内部包含 Xilinx 7 系列FPGA 所有的功能资源，如逻辑资源 CLB、存储资源 BRAM、时钟资源 CMT、DSP 资源、I/O 资源、高速串行收发器 MGT 等。

如所示，SWORD 平台采用的 FPGA 为 Kintex-7 系列里面的中档芯片，其资源规模非常丰富，足够实现架构完整，功能复杂的数字电路系统、嵌入式系统或通信电路系统。完全覆盖目前高校电子、计算机和通信专业课程教学和工程实训的内容。

Kintex-7 FPGA 资源列表如下表。

||XC7K70T|XC7K160T (SWORD)|XC7K325T|
|-----|-----|-----|-----|
|Logic Cells|65,600|162,240|326,080|
|BlockRAM (Kb)|4,860|11,700|16,020|
|DSP Slices|240|600|840|
|PCIe Gen2 Blocks|1|1|1|
|GTX Transceivers (12.5 Gb/s Max Rate)|8|8|16|
|I/O Pins|300|400|500|

### 2.3 时钟

SWORD 平台板载 100M 时钟振荡器（U38），单端接入到 FPGA 的 AC18 管脚（位于Bank32 的一个 MRCC 输入），该输入时钟能够驱动 FPGA 内部的时钟资源如 MMCM 单元或 PLL 单元以产生各种频率和相关相位的时钟信号供 FPGA 内部逻辑和外部 I/O 接口器件使用（如 Memory、网络和 SFP 光模块等）。用户如需更详细的 Kintex™-7 的时钟资源功能描述，请参考 Xilinx 官方的《7 Series FPGAs Clocking Resources User Guide》PDF 资料。

### 2.4 SRAM 静态存储器

SWORD 平台板载了 3 片型号为 CY7C1061DV33 的 SRAM，每片容量为 16Mb，位宽为16 位，总共组成了1Mx48bit（总容量为 6MB）的存储阵列供 FPGA 内部逻辑访问。注意，此 SRAM 为异步 SRAM，即由电平触发的使能信号控制，具体详情请参考 Cypress 官方的CY7C1061DV33 的 Datasheet。

### 2.5 DDR3 SDRAM 动态存储器

SWORD 平台板载了 2 片型号为 MT41J128M16JT-125 的 DDR3 SDRAM，每片容量为2Gb，位宽为 16 位，总共组成了 128Mx32bit（总容量 512MB）的存储阵列供 FPGA 内部逻辑访问。该 DDR3 存储器的最高运行频率为 800MHz（即 DDR3-1600），向下兼容666MHz 和 533MHz，具体详情请参考 Micron 官方的 MT41J128M16JT 的 Datasheet。

### 2.6 NOR 型并行闪存

SWORD 平台板载了 2 片型号为 S29GL128S 的 NOR Flash，每片容量为 128 Mbit，位宽为 16 位，总共组成了 8Mx32bit（总容量 32MB）的存储阵列供 FPGA 内部逻辑访问。该闪存仅作为用户数据存储使用，接口符合 CFI（Common Flash Interface）。具体详情请参考Spansion 官方的 S29GL128S 的 Datasheet。

注：不可作为 FPGA 的配置存储器使用，FPGA 的配置存储器为 W25Q64F（U35，参见2.14）。

### 2.7 RS232

SWORD 平台通过 ST3232 提供了 2 个 RS232 接口，其中一个通过 DB9 端子连接（CN15），另一个通过跳线连接（JP17）。

### 2.8 MicroSD

SWORD 平台提供了一个 MicroSD 接口（CN4），该接口最大支持 32GB 容量（更大容量未测试），支持 FAT 文件系统格式，该接口仅作为用户数据存储使用，暂不支持通过MicroSD 卡来配置 FPGA。

### 2.9 USB

SWORD 平台提供了 3 个 USB 接口，其中 USB-HOST A 接口（CN3）能连接 USB 存储设备，USB-HOST B 接口（CN22）和 USB-HOST C 接口（CN23）均能连接 USB-HID 设备。当用户需要连接 USB 接口的鼠标和键盘时，建议将鼠标连接到 USB-HOST B 接口，将键盘连接到 USB-HOST C 接口。

### 2.10 10M/100M/100M 以太网

SWORD 平台带有一个 RTL8211E-VL-CG 的三模以太网 PHY，能提供 10M/100M/1000M三种模式的以太网数据收发，配合 FPGA 部分实现的以太网 IP，能够实现网络应用。

### 2.11 GPIO

SWORD 平台提供了 4 种 GPIO 接口：4X4 按键矩阵、16 位滑动开关、16 位 LED、8 位 7段数码管。其中为了节省 I/O，仅 16 位的滑动开关采用了和 FPGA 直连的方式，其余三种接口均采用了 I/O 编码和并行转串行的方式：4X4 按键矩阵采用了 I/O 编码、16 位 LED 和 8位 7 段数码管采用了 SN74LV164 移位寄存器进行串行转并行的处理。

### 2.12 12 位色 VGA

SWORD 平台提供通过电阻网络实现 RGB444 的 VGA 输出。

### 2.13 HDMI 输入/输出

SWORD 平台通过 2 片 TMDS141 实现了 FPGA 芯片的 HDMI 输入和 HDMI 输出。

### 2.14 FPGA 配置（USB-JTAG/SPI 闪存）

SWORD 平台提供了两种 FPGA 配置方式：USB-JTAG 和 SPI Flash。其中 USB-JTAG 接口兼容 Digilent 的 JTAG 下载线（JP11）和 Xilinx 的 Platform USB Cable（CN7）。

SWORD 上的 SPI Flash 为 W25Q64F，容量为 64Mb，可通过 iMPACT 组件烧写 MCS 格式配置文件。

### 2.15 Pmod 扩展口

SWORD 一共提供了 5 个 Pmod 扩展口（CN16\~CN20），可接所有符合 Pmod 接口规范的扩展模块。