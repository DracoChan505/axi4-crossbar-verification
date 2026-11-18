# Slave 第一增量自检报告

日期：2026-11-14。结论：32/64 位数据、4 位 ID 两组配置，共 28 次运行达到预期；其中 22 次正常通过、6 次准确触发预定 fatal。仅证明本增量所列行为，不代表完整 Slave/Crossbar 验收。

后续补验结果见 [已实现功能验收报告](slave-acceptance-report.md)。本报告的 28 次运行保留为第一增量历史基线。

## 实现与证据

交付配置、AW 事务记录、稀疏字节存储、按序响应 Driver、编译包、独立引脚激励和运行器。源文件位于 dv/slave 与 dv/tests/slave；入口见 [阅读与运行指南](slave-stage1-review.md)。

机器可读汇总：[slave-stage1-results.json](slave-stage1-results.json)。原始结果：[32 位](../logs/stage1_baseline_slave_d32_i4/results.json)、[64 位](../logs/stage1_baseline_slave_d64_i4/results.json)。每个结果包含源码摘要、工具版本、seed、退出码、UVM 计数、预期错误及日志绝对路径。两组使用相同源代码，seed=7；测试为定向用例，不宣称随机覆盖。

编译/运行：make slave-build、make slave-regress；64 位使用 python3 scripts/run_slave.py build --data-width 64 与对应 regress。

工具：本机 Verilator 5.052 / UVM 2020.3.2、SystemVerilog 1800-2017、启用断言。本项目新增源文件没有编译警告；保留上游 uvm_pkg 缺少 timescale 的警告。仿真器另报告栈大小警告，本次用例均正常结束，未据此宣称更大规模兼容性。

## 14 个用例，各运行两种数据宽度

- smoke：单拍完整写入、完整 4 位 BID 回传、响应前字节已提交、周边字节未修改。
- w_first：W 提前持续有效 5 拍，没有 AW 时不能握手；AW 接受后正常完成。
- unaligned：地址 0x1001、两拍 4 字节传输；独立硬编码预期检查 0x1001～0x1007，32/64 位总线选择不同 lane。
- sparse：第二拍只写部分字节，其余保持原值。
- max_burst：256 拍、每拍 1 字节、末字节恰好 0xFFF，检查全部 256 个字节与相邻地址。
- delay：额外延迟 3 拍，独立记录最终 W 与首次 BVALID 的采样沿，检查精确周期。
- b_stall：BREADY 拉低期间保持响应，等待 7 个测试循环后释放，只完成一次。
- reject：先后门放入已知非零内容，AW 接收时决定失败，接收两拍 W 后返回 SLVERR，原值保留。
- outside：窗口外合法请求完整消耗两拍 W 并返回 SLVERR，不绕回写入窗口起始位置。
- reset_partial：两拍 burst 收完首拍后共同复位，已写字节保留、未写部分未变、无陈旧 B；复位后新事务正常完成。
- clear：排空后清零内存并逐字节检查。
- neg_wlast：提前 WLAST，唯一预期 fatal 为 SLAVE_WLAST。
- neg_strb：单字节非对齐地址使用错误 lane，唯一预期 fatal 为 SLAVE_WSTRB。
- neg_boundary：跨 4KB 请求，唯一预期 fatal 为 SLAVE_BOUNDARY。

负向测试以预期 fatal 结束是通过检测标准，不是“正常请求零 fatal”。运行器要求唯一指定错误、无其他 UVM_ERROR、正常结束标志且无超时；退出码 0 本身不构成通过。

## 本轮发现并修复

1. 初版直接引脚测试在 READY 有效时过早认为握手完成，且时钟事件后的延迟影响 clocking 输出驱动。现按 VALID && READY 判断，在采样事件处安排驱动；内存检查所需的稳定等待只放在已安排驱动之后。没有降低稳定性检查。
2. 负向边界测试在 DUT 同沿报告 fatal 后又立即报告“漏报”。现先让出一个采样等待，预期 fatal 可正常结束仿真，避免测试自身重复报错。
3. Slave 的异步复位原先通过 clocking output 驱动，沿间赋值等到下一时钟事件才生效。现仅异步复位断言分支直接 NBA 清输出，正常收发仍用 clocking block；首个复位采样沿输出检查通过。

初版失败日志保存在 logs/slave_stage1_initial_failure；复位修复前日志保存在 logs/slave_stage1_reset_failure。最新结论只引用最终两组结果。

## 需求映射及尚未验收部分

S01、S02 的单笔闭环与 AW 后接收 W 已有证据；S03 已测部分尺寸、非对齐和最大长度，尚缺完整尺寸/偏移/掩码组合。S05 已测默认与 3 拍 B 延迟及 B 背压；S08 已测拒绝写入和窗口外请求；S09 已测 W 中途复位及恢复；S10 已测静止清零；S11 仅包含当前协议负向检测；S12 只包含本次两组宽度。

尚未验收：满 4 笔与第五笔阻挡、不同 ID 乱序/同 ID 多笔顺序、AW/W 可配置背压、同沿多事务更新、其他复位阶段、活跃时清零拒绝、独立 Monitor、被动模式、完整 agent 封装、Master-Slave 联合运行及系统路由 Scoreboard。

当前 Driver 保留队列和默认容量 4，但不能因代码中有队列就声称 S04/S06/S07 已通过。原始 Master 源码、接口和 checker 本轮未修改；本报告不增加 Master 的验收结论。

本增量没有原生功能/代码覆盖收敛报告。后续须补齐覆盖与完整验收，不以 28 次运行替代这些任务。
