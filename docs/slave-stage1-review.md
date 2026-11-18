# Slave 第一增量：代码阅读与运行

日期：2026-11-14。范围：配置、事务记录、字节存储、按序写入/响应闭环和独立自检。此增量不是完整 Slave agent 验收，更不是 Crossbar 验收。

本次 32/64 位配置共 28 次运行达到预期，具体证据和限制见 [测试报告](slave-stage1-test-report.md)。

最新的容量、复位及联合运行补验见 [验收报告](slave-acceptance-report.md)；下文保留第一增量交付边界。

## 本次可阅读的内容

1. `dv/slave/axi_slave_cfg.svh`：地址窗口、容量（默认 4）、响应额外延迟和拒绝写入地址范围。
2. `dv/slave/axi_slave_record.svh`：每个接受的 AW 保存哪些字段。
3. `dv/slave/axi_slave_memory.svh`：字节写入、查看与独立清零。
4. `dv/slave/axi_slave_driver.svh`：AW 入队、W 写入、按序 B 返回及复位清理。
5. `dv/tests/slave/slave_test_pkg.sv`：直接驱动引脚的独立测试；没有调用 Master 数据生成器或 Slave 地址函数来计算预期。

代码采用每条语句一行和四空格缩进。先看配置与记录即可，不要求此时学习 UVM 软件接口或准备面试回答。

## 已实现的行为边界

- 接受 AW 后才接收对应 W，提前 W 等待；保存完整 ID。
- W 每拍合法握手后更新有效字节，支持非对齐 INCR 与逐字节使能。
- 默认收齐 W 后提出 B；允许配置额外 B 延迟，B 被阻挡时保持响应。
- 按 AW 顺序返回。容量队列从初版保留，W 不等待前一笔 B 才能推进；本增量验收以单笔在途及串行事务为主，不将队列存在视为并发验收通过。
- 拒绝写入仍消耗全部 W，再返回 SLVERR；不写入内存。窗口外请求也拒绝写入。
- 普通复位清事务但保留已写字节；独立清零必须在静止或复位清理后进行。

仍待后续增量：跨 ID 响应调度、可配置 AW/W 背压、完整多事务容量压力测试、独立 Slave Monitor、active/passive agent 封装及系统 Scoreboard。完整覆盖和同 ID 内部顺序检查仍未完成，不能把本次定向测试称为覆盖收敛。

## 运行

在项目目录执行：

```sh
make slave-build
make slave-test
make slave-regress
```

默认 32 位数据、4 位 ID；独立测试用全部 ID 位为 1 检查完整回传。64 位数据配置：

```sh
python3 scripts/run_slave.py build --data-width 64
python3 scripts/run_slave.py regress --data-width 64
```

使用本机已有 Verilator 5.052、UVM 2020.3.2，不依赖 Cadence。未新增第三方库。原有 Master 源码、共享接口和 checker 不修改。

运行器记录源码摘要并拒绝陈旧构建。普通用例必须零 UVM_ERROR/FATAL、有正确完成标志、无超时。负向用例应以唯一指定 UVM_FATAL 结束：错误 WLAST 对应 SLAVE_WLAST、非法字节使能对应 SLAVE_WSTRB、跨 4KB 对应 SLAVE_BOUNDARY；其他 fatal、崩溃或超时不能算检测成功。

日志在 `logs/slave_d32_i4/` 或 `logs/slave_d64_i4/`，`results.json` 记录每项结果。CASE 的 seed 用于复现；当前这些是定向用例，不因记录 seed 就宣称随机覆盖。
