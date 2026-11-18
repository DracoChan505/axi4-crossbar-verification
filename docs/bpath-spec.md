# Crossbar B 响应路由、缓冲与 AW/W/B 联合验收

> 本文保留 B 增量验收边界。内部 DECERR 与写顶层已在后续增量完成，见 [写顶层规格与验收](crossbar-write-spec.md)。

2026-11-15。用户要求继续，实现真实 B 信号路径，替换上一增量 TB 直接生成的完成通知。AW/W 既有 RTL 保持不变。本轮内部错误目标仍由 TB 端点驱动，尚未成为 Crossbar 内部 DECERR 模块。

## 1. 文件与接口

rtl/axi_write_response_path.sv 是新模块；dv/tests/bpath/bpath_tb.sv 将 AW 前端、W 数据路径和 B 响应路径连接，scripts/run_bpath.py 运行参数回归。

默认 INPUTS=4、OUTPUTS=5、原始 ID_WIDTH=2、下游 OUTPUT_ID_WIDTH=4、每出口 RESPONSE_DEPTH=2。OUTPUTS 中最后一个为未来内部错误目标，物理 Slave 仍是 4 个。

相对于新模块：

- 输入 clk/reset_n。
- 输入 m_bvalid/m_bid/m_bresp；输出 m_bready，按下游逻辑出口索引。
- 输出 s_bvalid/s_bid/s_bresp；输入 s_bready，按上游 Master 入口索引。
- 输出 release_valid[出口]，连接 AW 前端出口预留计数的释放通知。
- 输出 complete_valid[入口]/complete_id[入口]，连接入口 Tracker。

来源编号来自下游 BID 高位，原 ID 来自低位；返回原 BID 时去掉来源位。BRESP 两位原样转发，模块不自行将 Slave 错误改写为 OKAY。

## 2. 数据组织与仲裁

每个下游出口有一个深度 2 的 B FIFO，保存完整扩展 BID 与 BRESP。m_bready 仅由寄存的 FIFO 占用状态和复位决定，不组合依赖 BID/BVALID 或上游 BREADY。FIFO 无直通，满时不提前使用当拍弹出的槽位。

每个 Master 各有一个独立轮询仲裁器，在各出口 FIFO 队首中选择属于该 Master 的响应。捕获到该 Master 的单条返回寄存器时，才弹出被选 FIFO；轮询指针在这次内部捕获时推进。

s_bvalid/s_bid/s_bresp 均来自返回寄存器，BREADY 为 0 时保持；即使上游一直不 ready，也不妨碍首次提出 BVALID。寄存器满时不覆盖，原响应握手后的下一周期才可捕获下一条，基础实现保留气泡。

多个 Master 的返回寄存器及仲裁相互独立，可以同拍完成响应。每个出口的 FIFO 只暴露队首，若队首所属 Master 长期不接收，会阻挡该 FIFO 后面的其他 Master 响应；当前实现存在这种队首阻塞，没有承诺端口级完全隔离。后续优化可以考虑分队列，需以实测与验证为依据。

## 3. 释放时刻与顺序

release_valid[o] 精确等于下游 m_bvalid[o] && m_bready[o]。这代表响应已经安全进入本 Crossbar 的 B FIFO，可以归还该出口从 AW 捕获时预留的名额，不必继续占用到 Master 接收。

complete_valid[i] 精确等于上游 s_bvalid[i] && s_bready[i]，complete_id 是已恢复的原始 BID。入口 Tracker 到这个事件才释放，不能因下游 B 已缓存而允许同 ID 提前切换 Slave。

同一 Master 同一 ID 仍由 Tracker 绑定单目标直到排空；同目标端点必须按该 ID 的顺序返回，B FIFO 保留该端点的响应流顺序。来自不同 ID/不同目标的响应可经仲裁乱序返回，不设置全局 AW 顺序阻塞。

模块假设下游 B 对应合法、已收齐 W 的事务；它本身没有重复保存 AW/W 全部账本，不能独立证明无早 B/重复 B。输入来源编号不在 INPUTS 范围内时，仿真断言触发 BRESP_INVALID_SOURCE。其他非法协议行为仍需系统 Monitor/checker 验证；运行时故障隔离不属于当前基础实现。

## 4. 周期与复位

若下游 B 在第 N 沿进入空 FIFO，最早第 N+1 沿捕获到上游返回寄存器，最早第 N+2 沿由 Master 握手。竞争、满缓冲和 BREADY 背压会增加延迟。

公共 reset_n 异步清空 B FIFO 有效状态、返回寄存器有效位及仲裁锁/指针；复位期间两类握手通知均为 0。AW/W 控制也同步清空，旧响应不能在复位后复活。外部 Master/Slave 按项目共同复位约定同时取消在途事务。

## 5. 联合自检

本轮 TB 仍使用轻量 SystemVerilog 端点，但已经驱动实际 m_bvalid/m_bid/m_bresp、s_bready，完成与释放通知由 RTL 真实握手产生，TB 不再直接驱动这些通知。

端点只有对应最后 W 拍握手后才允许产生 B，可从不同扩展 ID 的可响应事务中随机选取，但不能跳过同扩展 ID 的前序。提出 B 后保持到握手。TB 独立保存下游 B 接收账本，检查上游 B 的原 ID、状态、来源、同 ID 顺序以及丢失/重复；不读取 B RTL 私有队列。

同时保留 AW/W 数据、字节使能、目标队列、容量及复位检查。新场景包含上游 BREADY 固定长背压后随机背压、下游 B FIFO 产生背压、多个出口竞争同一 Master、不同 Master 同拍完成、实际跨 ID 完成乱序，以及响应已缓存但尚未上游握手时复位。

参数与上一轮相同：4×4/32位；3×2/32位及容量3；1×1/容量1；4×4/64位地址和数据。每组种子 7、41、2026。额外在 3 入口配置注入来源码 3，要求精确触发 BRESP_INVALID_SOURCE，不能靠超时或其他错误冒充检测。

本轮状态激励含 OKAY、SLVERR、DECERR；其中 DECERR 由 TB 错误端点产生。检查的是响应通路正确传递，不能证明尚未实现的内部 DECERR 端点逻辑正确，也不是 Slave 内存模型或完整 UVM 系统验证。

## 6. 实际运行证据

最终 12/12 次正常运行、1/1 次非法来源负向测试达到预期。工具为现有 Verilator 5.052，断言开启，编译警告作为失败。逐项记录及源摘要见 [bpath-results.json](bpath-results.json)，日志位于 logs/bpath。

默认 4×4、32 位、seed7 的实际结果：

- 下游 B 接收 403 笔；上游完成 397 笔，另 6 笔在缓存期间被公共复位取消，数量闭合。
- 上游 B 背压 447 个采样周期，下游 B 背压 158 个采样周期。
- 观察到 4 次跨 ID 完成超越、58 次多个 Master 同拍 B 完成、6 次多个出口同时向同一 Master 提出 B 的竞争见证。
- 上游收到 OKAY 164 笔、SLVERR 162 笔、DECERR 71 笔。
- AW 接受 413 笔，完成 397 笔、复位取消 16 笔；AW 的取消数还包含尚未产生 B 的事务，因此与缓存 B 取消数不同。

以上为测试场景见证，不是系统性能指标、功能覆盖收敛或形式证明。既有 AW/W RTL 与上一轮 TB 的源摘要未变；本轮运行的是新增 AW/W/B 联合 TB。

运行 `python3 scripts/run_bpath.py` 或 `make bpath-regress`。

## 7. 下一增量

加入可综合的内部 DECERR 写处理端：接收错误目标 AW、消耗完整 W burst、返回对应 BID/DECERR，随后把各部分封装为对外 4 个 Master/4 个 Slave 的写通路顶层。独立 Slave Monitor/agent、系统 Scoreboard、覆盖收敛与读通路仍按总计划补齐。本轮没有完成综合、STA、系统 UVM 验收或完整五通道 Crossbar。
