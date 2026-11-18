# Master 写通路实现审查指南

状态：首轮实现，等待用户代码审查。仅实现外部 Master UVM agent 及模块自检，不含 Crossbar 或正式 Slave agent。

## 建议阅读顺序

1. `dv/interfaces/axi_write_if.sv`：AW/W/B 信号、clocking block 方向与采样时序。
2. `dv/master/axi_write_item.svh`：事务字段、非对齐 lane 构造、输入合法性检查和深拷贝。
3. `dv/master/axi_master_cfg.svh`：默认两笔活跃名额、两条待发送记录和 BREADY 背压设置。
4. `dv/master/axi_master_driver.svh`：先处理本沿 B，再处理 AW/W 握手，再调度并驱动下一周期。
5. `dv/master/axi_master_monitor.svh`：独立 AW/W 队列、逐拍事件、完整写事件及 B 完成事件。
6. `dv/master/axi_master_agent.svh`：组件连接、active/passive 模式、共同复位取消 sequence。
7. `dv/checkers/axi_write_checker.sv`：AW、W、B 等待稳定性断言。
8. `dv/tests/master/master_test_pkg.sv`：test-only 响应支架、独立字节参考检查、定向和随机用例；不是下一模块的正式 Slave agent。

`axi_master_pkg.sv` 组织类型与包含文件。使用标准 `uvm_sequencer#(axi_write_item)`，没有另建一个不增加行为的 sequencer 子类文件。

## 实现中的重要约定

- AW、W、B 在逻辑上独立推进，但状态更新集中到 Driver 的单个周期过程，避免多个线程修改同一计数。AW 等待不阻塞 W 或 B；三者均能在同一周期产生事件。
- `pending` 是已接管但未调度任务；`reserved` 是已调度但 AW 未握手任务；`outstanding` 是 AW 已握手但 B 未握手任务。后两者合计不超过配置容量。
- 接管时深拷贝并调用 item_done；完成时复制结果、恢复 sequence 路由信息，通过 put_response 返回。内部 uid 单调增加，epoch 区分复位轮次。
- 两个通道按同一任务顺序前进，W burst 不交错。W 可以先于 AW 被接收。B 以 ID 匹配最早尚未完成的 AW，检查其 W 在本沿之前已完成。
- Monitor 不读 Driver 内部计数，发布独立的 aw_ap、beat_ap、write_ap、complete_ap。序号来自被动观察；不能把 Monitor 的 uid 当成 Driver 私有 uid。
- 普通 reset 丢弃任务与关联状态，不自动重发；sequence 被统一停止。模拟存储保持，独立 clear_memory 操作清零。Master 自检只验证支架中的保留/清零；完整系统参考存储提交规则仍要在 Slave/Scoreboard 集成时验证。
- 地址与数据位宽通过编译宏配置（默认 32/32/2）；每个仿真构建使用统一接口类型。运行时配置名额和 B 背压。最终 Crossbar 的 RTL 参数化不由此代替。
- 默认 normal/non-cacheable/non-bufferable 属性、INCR、非 exclusive；保留 QoS 等字段。首阶段未启用 USER/REGION、AR/R，与已确认范围一致。

## 本机运行

在项目目录执行：

```sh
make master-build
make master-test
make master-regress
python3 scripts/run_master.py test --case reorder --trace
```

需要现有相邻 `local-uvm` 安装目录；可用环境变量 `AXI_LOCAL_UVM` 指定其他路径。脚本自动使用英文临时别名解决中文路径构建问题，不移动项目。

参数化例子：

```sh
python3 scripts/run_master.py build --data-width 64 --id-width 3
python3 scripts/run_master.py test --data-width 64 --id-width 3 --max-out 4 --case random --seed 41
```

每次运行保存原始日志、覆盖数据和结构化判定；结果要求完成标记、正确 UVM 错误计数和退出码一致，不能只看进程退出 0。源文件变化后必须重新构建。

## 如何理解故障注入的通过

被动模式下由测试直接驱动错误信号，要求唯一指定 checker 报告恰好一次。catcher 只将该预期报告降为 INFO，其他错误仍失败。报告中的 ERROR=0 不意味着没有发生故障检测：必须同时看到 EXPECTED_DETECTION 和对应错误代码。

## 当前边界

- 随机用例使用固定 seed 的合法参数随机选择与显式构造；不是约束求解器随机化覆盖的证明。
- 基础 coverpoint 和显式场景计数已接入；不宣称原生交叉覆盖、加权汇总或完整覆盖收敛已解决。保留现有工具限制报告。
- Verilator 主要为二态仿真；本轮不证明 X/Z 传播检查能力。
- Monitor 看不到同 ID B 响应内部身份；某些重复/调换必须靠目标端独立记录才能验证。
- 配置有诊断边界（地址 12～63 位、数据字节数为 2 的幂且 8～1024 位、ID 1～16 位），但只实际验证报告列出的配置，不声称这些数值的全组合已验收。
- 正式 Slave 模型、Crossbar 路由、读通路和系统故障隔离尚未开始。本轮结束后等待用户审查，不自动进入下一模块。
