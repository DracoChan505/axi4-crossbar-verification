# Slave 第二增量：响应调度与背压

日期：2026-11-15。用户授权“先做下一部分，优先把基本的成型”。本增量落实已确认的 Slave 功能，不改变最终 4×4 Crossbar 目标。

## 已实现

- 不同 ID 的 B 响应可乱序；同一个完整 ID 的响应保持 AW 接收顺序。
- 三种响应策略：B_IN_ORDER 默认全局按序；B_OLDEST_READY 选择满足条件的最早事务；B_RANDOM_READY 从满足条件的事务中随机选择。
- AWREADY、WREADY 分别支持周期背压或有界随机背压。
- B 支持固定延迟、按内部 AW 序号增加延迟和随机增加延迟，便于制造明确的乱序场景。
- 已选出的 B 在 BREADY=0 时锁定，直到握手。后续事务变为可响应，也不替换当前 BID/BRESP。
- 原有容量、W 顺序、字节写入、SLVERR 与复位行为保留。

## 文件与接口

主要阅读顺序：

1. `dv/slave/axi_slave_cfg.svh`：配置项及非法配置检查。
2. `dv/slave/axi_slave_driver.svh`：`ready_gate()`、`select_response()`、B 握手后的队列删除。
3. `dv/tests/slave/slave_acceptance_test.svh`：独立引脚观察、乱序/背压测试和 Master 直连测试。

没有新增 AXI 物理信号。配置在 build 阶段固定，不支持运行中随意改动。

`response_order` 默认 B_IN_ORDER。`aw_stall_period/aw_stall_cycles` 和对应 W 字段描述周期内关闭的前若干个周期；周期为 0 表示不启用。`aw_random_stall_max`、`w_random_stall_max` 默认 0，每个通道可单独选择随机策略。一个通道不同时叠加周期与随机策略；周期全关闭等不能推进的配置会报 SLAVE_CONFIG。

`b_delay_cycles` 为基本延迟；`b_extra_delay_by_seq[aw_seq]` 指定某笔额外延迟；`b_random_delay_max` 为额外随机延迟上界。三者之和在 AW 握手时保存。内部 aw_seq 仅用于模型配置/日志，既不是 AXI ID，也不用于 W 接口匹配；普通复位后不重用其编号。

## 周期约定

在采样沿观察握手，沿后更新下一周期输出。最终 W 在第 N 沿握手，B 最早在 N 沿之后拉高，最早第 N+1 沿握手。配置延迟 D 时，最早第 N+D 沿之后提出 B；其他事务占用 B 通道、同 ID 前序未完成或 BREADY 背压均可能进一步延后。

满容量时不使用同沿 B 释放的名额接受 AW；下一采样沿才可能接受新 AW。W 仍按已接收 AW 的顺序处理，B 调度改变不影响 W 队列。

背压策略每个非复位周期推进。周期策略从复位后的策略周期 0 开始；随机策略在每次开放一个周期后选择 0..max 个关闭周期。策略开放还须满足 AW 有空位或 W 有已接收 AW，才能使 READY 为 1。因此随机关闭上界不是整个系统的最大等待时间承诺。

AW、W、B 使用独立的确定性随机状态，seed 可复现。普通复位清空在途记录、重新初始化策略状态；已提交的存储字节保留。

## 实际结果

86/86 次运行达到预期：32 位 / ID4 全套 36 次，64 位 / ID4 全套 36 次；32 位额外种子 41、2026 共 6 次；容量 1/2 和同 ID 容量 2 共 3 次；32 位 / ID2 精选 5 次。包含 10 次预期 FATAL 的负向测试，以及 2 次精确捕获 CLEAR_BUSY 的清零拒绝测试。无非预期 UVM_ERROR/FATAL。

源文件摘要及逐次结果见 [机器可读记录](slave-stage2-results.json)。编译保留上游 UVM 的 TIMESCALEMOD 提示，无项目新增警告。

## 验证内容

自检 TB 从实际 AW/W/B 握手建立独立事务账本，按 BID 找该 ID 最早记录，检查响应前 W 已完成、状态与数据正确、没有丢失/重复，并用稳定性 checker 检查背压期间信号保持。测试不读取 Driver 私有队列。

新增场景包括：不同 ID 超越、两个 ID 各有两笔事务的保序、混合 OKAY/SLVERR、B 锁定期间另一 ID 变为可响应、默认模式不超越、周期/随机背压、随机策略下复位、现有 Master 直连压力、非法背压配置。

32 位 / ID4 / seed7 的实际见证：

- 同 ID 保序测试达到 4 笔在途，观察到 2 次跨 ID 超越。
- B 锁定测试观察到乱序，随后阻挡响应 20 个采样周期。
- 随机背压测试实际观察到 AW、W 各 19 个被阻挡周期。
- Master 直连压力测试完成 12 笔双拍写入，峰值在途 2；AW 阻挡 26 周期、W 阻挡 54 周期、跨 ID 超越 3 次。

这些为运行见证，不是覆盖收敛率或吞吐量指标。随机测试目前随机化时序，并非完整的随机事务空间。

## 运行方法

在项目目录执行：

```sh
python3 scripts/run_slave.py build
python3 scripts/run_slave.py regress
python3 scripts/run_slave.py test --case integration_stress --seed 41
python3 scripts/run_slave.py build --data-width 64
python3 scripts/run_slave.py regress --data-width 64
python3 scripts/run_slave.py build --id-width 2
python3 scripts/run_slave.py test --case reorder_same_id --id-width 2
```

使用本机 Verilator 5.052 / UVM 2020.3.2。脚本核对源文件摘要，拒绝旧二进制；判断完成标志和 UVM 错误/致命错误，不仅依赖退出码。日志按参数、seed、容量保存。编译器曾对嵌套队列索引表达式报内部错误，已拆分候选数量、随机下标、队列访问后通过编译，未关闭检查或删除功能。

## 后续边界

这仍是外部 Slave 验证模型及其自检，不是 Crossbar RTL 的验证完成。独立 Slave Monitor、active/passive agent 封装及接口事件输出仍待下一增量；之后才具备开展 Crossbar 集成所需的完整观察组件。当前直连测试用独立 TB 观察逻辑，不能冒充已经完成可复用 Monitor。

同 ID 跨 Slave 的顺序保护需要 Crossbar Tracker/路由实现后另验。完整功能覆盖收敛、仲裁、4×4 路由以及 AR/R 仍在总计划内。此前故障注入报告保留为历史证据，本增量未声称重新运行该轮故障注入。
