# UVM 写 Crossbar 接入

本文保留首次系统接入时的状态。之后已补齐 Slave 独立 Monitor 与 active/passive agent，最新组件结构及本轮验收见 [Monitor 增量报告](slave-monitor-agent.md)。

2026-11-15。本轮把既有 SystemVerilog/UVM Master 与 Slave 实现接到真实 axi_crossbar_write，默认 4×4。仍优先使用本机 Verilator 5.052 与 UVM 2020.3.2。

## 接口与模型复用

axi_write_if 新增 AW/DW/IW 参数，默认值保持旧的 AXI_ADDR_W/AXI_DATA_W/AXI_ID_W。Master 与 Slave 包分别使用 AXI_MASTER_ID_W、AXI_SLAVE_ID_W；不设置新宏时，二者都回退至原 AXI_ID_W。因此旧单模块测试不需要统一改调用方式。

Driver、Master Monitor 与 Master agent 的 virtual interface 类型明确指定对应包的地址、数据、ID 宽度。系统配置为入口 ID2、出口 ID4，同一仿真有两种真实接口类型，没有靠补零/截断的假桥接掩盖宽度差异。

Slave 记录类被发现位于 dv/tests/axi_slave_record.svh，与 Slave 包原本引用不符，已将原文件内容原样恢复到 dv/slave/axi_slave_record.svh。

系统实例包含四个既有 axi_master_agent（各有 Driver/Monitor/sequencer）、四个既有 axi_slave_driver（带字节存储），以及八个接口稳定性 checker。Slave 仍未封装为独立 active/passive agent，也没有声称其独立 Monitor 已完成。

## 新文件

- dv/tests/crossbar_uvm/top.sv：入口/出口不同 ID 位宽的 interface、4×4 RTL、checker 和 UVM 配置绑定。
- dv/tests/crossbar_uvm/crossbar_uvm_pkg.sv：并发 sequences、fabric_scoreboard 与测试组织。
- scripts/run_crossbar_uvm.py：编译、摘要防旧二进制、语义判定与日志记录。

原有 RTL 不因 UVM 接入修改。

## 激励与独立检查

每个 Master 提交 24 笔，总共 96 笔。请求覆盖同 ID 两笔、同 ID 换目标、多个 ID、不同目标、AW/W 独立延迟、有效字节范围内的窄传输/非对齐、单拍及 256 拍、全零/稀疏 strobe，以及 Slave 拒绝写入与未映射地址。

Master 使用独立的 B 背压配置；Slave 的 AW/W 随机背压、B 延迟和跨 ID 随机选择使用可复现种子。同 ID 响应仍保序。正常配置的期望响应数量为 DECERR 16 笔、SLVERR 4 笔，其他为 OKAY。

fabric_scoreboard 是独立 UVM component，采样两侧真实接口握手，不读取 RTL 或 Driver 的内部事务队列。它保存来源/目标/原 ID/AW 属性、W 拍快照及 B 关联关系，检查下游 AW 路由与次序、W 数据/字节使能/最后一拍、响应来源和同 ID 顺序、早响应及容量。

预期字节存储由独立的字节地址枚举计算，不调用 Master 的 allowed_mask/fill_pattern 或 Slave 的地址算法。实际输出 W 与输入快照先逐位比较，再使用输入快照建立预期值。对 SLVERR 不更新预期存储；错误目标不允许转发到物理 Slave。

测试排空后，通过 Slave 公开 peek_byte 接口检查每个窗口全部 64KB，共 262144 字节，包含没有被写到的字节，避免只检查“写过的地方”漏掉越界或额外写入。

## 目前边界

本轮系统流量只有启动复位，运行中复位仍主要由前面的 RTL/模型定向测试覆盖；不以此替代 UVM 的在途取消系统场景。系统测试固定 4×4，其他参数配置已有轻量 RTL 回归；这不是 UVM 全参数矩阵。

随机种子当前主要影响背压/响应时序，不代表完整受约束随机事务空间。覆盖率收敛、独立 Slave Monitor/agent、系统级故障注入扩展、性能测量与 AR/R 仍未完成。

## 实际验收结果

本轮最终 68 次运行均达到各自预期：32 位数据 3 个种子、64 位数据 3 个种子，共 6 次系统正常运行；1 次系统存储错误检测；原 Master 默认32位/ID2 的 25 次兼容运行；原 Slave 默认32位/ID4 的 36 次兼容运行。旧模型其他位宽组合没有在本轮全部重跑。

系统每次正常运行接受并完成 96 笔事务，物理 Slave AW/B 各 80 笔，内部 DECERR 16 笔，SLVERR 4 笔。默认 seed7 的一次运行观察到输入 W 1248 拍、物理输出 W 1208 拍、7 次跨 ID 完成超越，四个入口都达到两笔在途；每次完整核对 262144 字节。所有正常系统运行 UVM_ERROR=0、UVM_FATAL=0。

额外负向运行在流量排空后，通过 Slave 公开存储 API 故意翻转 Slave0 地址 0x7000 的一个字节，独立字节比对准确产生且仅产生一次 SYS_MEMORY：expected=00、actual=01。该运行的 UVM_ERROR=1 是明确预期，不被混写为零错误正常通过；它证明存储比对确实执行，不代表完成全部 RTL mutation testing。

机器可读汇总见 [crossbar-uvm-results.json](crossbar-uvm-results.json)。系统日志分别在 logs/uvm_crossbar_d32 和 logs/uvm_crossbar_d64，兼容性日志在 logs/d32_i2 和 logs/slave_d32_i4。新编译只保留上游 UVM 的 TIMESCALEMOD 提示，无本轮新增位宽警告。

Master 原运行脚本以整个 dv 目录计算摘要，所以系统测试文件改变时会把其构建标为过期；本轮按原脚本重新构建再运行，没有绕过摘要检查。系统脚本单独记录相关源文件与运行脚本摘要。

## 复现入口

```sh
make system-build
make system-regress
make system-build64
make system-regress64
make system-memory-fault
```

也可单次运行 `python3 scripts/run_crossbar_uvm.py test --seed 41`。负向检查只在显式指定 `--inject-memory-fault` 时注入，其日志/结果与正常运行分开保存。脚本检查原始错误行、UVM ERROR/FATAL 汇总、完成标志及仿真结束，操作系统退出 0 不单独构成通过。

下一小步建议完善独立 Slave Monitor/agent 和系统测试的复位/覆盖计划，把当前可运行接入逐步变成完整可复用验证环境；不把这些未完项或 AR/R 静默删除。
