# Slave 独立 Monitor 与 agent 增量

2026-11-15。范围为已确认的写通路验证组件；RTL、Slave Driver 的响应调度及存储实现未修改。完整五通道目标不变。

## 文件与接口

- `dv/slave/axi_slave_observation.svh`：事件类型及事务快照。
- `dv/slave/axi_slave_monitor.svh`：仅从接口采样的独立 AW/W/B 关联和协议检查。
- `dv/slave/axi_slave_agent.svh`：封装既有 Driver 和新 Monitor。
- `dv/tests/slave_monitor/`：直接驱动公开引脚的独立测试，不借用生产 Driver 生成预期结果。
- `dv/tests/crossbar_uvm/crossbar_uvm_pkg.sv`：四个 active agent、一个 Slave0 passive 观察实例，以及独立双侧 scoreboard 的交叉核对。

配置通过 UVM config_db 的 `vif` 和 `cfg` 传入。接口类型保留地址、数据和 ID 宽度参数。`cfg.active=1` 时创建 Driver 和 Monitor；`cfg.active=0` 时只有 Monitor，不驱动任何信号。本实现以 cfg.active 为模式开关，未使用 UVM 基类的 is_active 配置。

`monitor.events` 是 `uvm_analysis_port#(axi_slave_observation)`，发布 SLAVE_AW、SLAVE_WRITE、SLAVE_B、SLAVE_RESET。记录包括 epoch、内部 serial、各阶段采样周期、地址、ID、AW 属性、数据/字节使能队列、响应及取消数量。SLAVE_WRITE 表示已观察并关联完整 AW/W，不表示成功写入存储；SLVERR 等语义由系统检查承担。

每次发布新快照，不暴露 Monitor 活跃记录。独立测试故意修改已收到的 AW 事件，确认之后的 W/B 关联不被破坏。一次广播的多个订阅者仍可能收到同一快照句柄，订阅者应只读或自行复制；没有声称实现每订阅者隔离。

## 关联与时序

Monitor 在接口 mon clocking block 上采样，以实际握手建立记录。AW 按接受次序排队，W 按 WLAST 分段保存，完整 burst 与最早未配对 AW 关联。支持 W 提前于 AW 握手；不会使用不存在的 WID，也不允许跨事务 W beat 交错。提前 W 先缓存，待 AW 到齐后检查长度和字节使能。

BVALID 必须对应此前采样沿已握手的 AW 和最后 W 拍。每个采样沿先检查 B，再接收本沿 AW/W，因此与首次 AW 或最后 W 握手同沿出现的 BVALID 不被接受为合法提前响应。同 ID 匹配最早待完成记录，不同 ID 可以超越；B 握手后移除待完成记录。AW/W/B 在 VALID 且未 READY 后须保持 VALID 和载荷。

字节合法范围按对齐传输块和绝对字节地址独立枚举，包括非对齐首拍、后续对齐地址及窄传输。不调用 Driver 的地址/掩码函数。检查 AWLEN/WLAST、WSTRB、INCR 非 exclusive profile、最大传输尺寸、4KB 边界及地址溢出。当前不是全部 AXI4 可选特性的通用 checker。

`monitor_limit=64` 默认限制待 B 或未配对完整 W burst 的数量，必须至少覆盖配置的 max_outstanding；单 burst 最多 256 拍。此限制用于防止错误激励无限增长，不替代 DUT 的实际容量断言。

## 复位与职责边界

采样到复位时清除待关联事务、部分 W burst 及背压保持状态。运行中复位发布一次 RESET，记录已知待 B 的 AW 取消数量，并递增 epoch。启动复位不发取消事件。累计计数和 serial 保留用于测试审计，不代表复位前事务继续有效；提前 W 而尚无 AW 的内容会丢弃，不计入 cancelled_aw。Monitor 的复位观察是时钟采样语义。

Monitor 不读取 Driver/RTL 私有队列，不单独证明 Crossbar 的来源、路由或存储正确。系统仍保留独立双侧引脚 scoreboard 和完整字节存储比较。对于相同 ID、接口上不可区分的响应，单接口 Monitor 无法推断内部是否交换了两个不可区分的结果。

## 验收与复现

```sh
make monitor-build
make monitor-regress
make system-build
make system-regress
make system-build64
make system-regress64
make system-memory-fault
```

独立 Monitor 的五项正常场景为基本闭环、快照隔离、W 提前、同 ID 保序/跨 ID 超越、部分 burst 复位取消后恢复。七项负向场景分别注入无来源 B、提前 B、错误 WLAST、非法 WSTRB、AW/W/B 背压载荷变化；每项必须恰好出现对应一个 UVM_ERROR，且无 FATAL。不能只看进程退出码。

系统继续使用 32/64 位数据、入口 ID2/出口 ID4 和种子 7、41、2026。每次 96 笔，其中 16 笔由内部 DECERR 端完成，80 笔到达物理 Slave。四个 active Monitor 的完整事件逐字段、逐拍对照独立 scoreboard，Slave0 passive 事件再与 active 事件核对。每次核对全部 262144 字节存储。另注入一次存储错误，须准确产生 SYS_MEMORY。

本轮实测 19 次均达到预期：11 次正常运行无 UVM_ERROR/FATAL，8 次负向运行分别检出精确预期错误（7 项协议违规、1 项存储错误）。六次系统正常运行各完成 96 笔，80 条物理 Slave 完成事件与独立 scoreboard 一致，Slave0 的 20 条完成事件在 active/passive 观察下也一致。

机器可读实测记录见 [slave-monitor-agent-results.json](slave-monitor-agent-results.json)。旧 Master/Slave 单模块及 RTL 回归本轮未重跑，不计入本轮次数。工具为本地 Verilator 5.052、UVM 2020.3.2；构建有上游 UVM timescale 和 macOS C++ 弃用警告。

系统在途复位、覆盖收敛、AR/R 和综合/时序仍待完成。本轮复位测试只证明独立 Monitor 清理和重新关联行为，不能替代整个 UVM 系统的复位恢复验收。
