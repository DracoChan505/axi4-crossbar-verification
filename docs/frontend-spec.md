# Crossbar AW 缓冲与 W 路由记录连接增量

> 此文保留 AW 控制增量的验收边界。W 两拍缓冲与实际转发已在后续增量实现，见 [W 路径规格与验收](wpath-spec.md)。

日期：2026-11-15。用户要求继续。首配置仍为 4 个外部 Master、4 个物理 Slave；本轮将已实现的译码、Tracker、仲裁接成 AW 控制路径，另增加内部错误目标的逻辑出口。没有实现 WDATA 转发或 B 通道。

## 1. 文件与实例组成

- rtl/axi_record_fifo.sv：参数化同步记录 FIFO，无直通；满时即便本拍弹出，也到下一拍才恢复入队能力。
- rtl/axi_write_frontend.sv：AW 控制连接模块，包含每入口 Tracker、AW FIFO、W 目标 FIFO；每出口仲裁器、AW 输出寄存器、W 来源 FIFO、出口预留计数。
- dv/tests/frontend/frontend_tb.sv：独立事务账本和多入口控制路径自检。
- scripts/run_frontend.py：编译、运行、记录参数/种子/源摘要和明确通过标志。

默认入口 4、物理出口 4、原 ID 2 位、地址 32 位；入口上限 2，出口上限 4。额外逻辑出口编号 4 对应未来 DECERR 处理端，不能连接成第五个物理 Slave 对外宣称 4×5。

每入口有一个深度 INPUT_LIMIT 的 AW FIFO 和一个同深度 W 目标 FIFO；每逻辑出口有一个 AW 寄存器与深度 OUTPUT_LIMIT 的 W 来源 FIFO。队列只存元数据，不存整个 burst。

## 2. 接口方向与编码

相对于 axi_write_frontend：

- 输入 clk/reset_n，以及静态 map_base/map_limit。
- 输入 s_awvalid/id/addr/len/attr，输出 s_awready；数组按外部 Master 入口编号索引。
- 输出 m_awvalid/id/addr/len/attr，输入 m_awready；数组按逻辑目标编号索引，包含最后的错误目标。
- attr 是内部 17 位拼接 `{AWSIZE[2:0], AWBURST[1:0], AWLOCK, AWCACHE[3:0], AWPROT[2:0], AWQOS[3:0]}`。各字段逐位保持，不改含义；后续 AXI 顶层拆回各物理信号。
- 输入 complete_valid[入口]、complete_id[入口]：上游 Master 的 B 握手通知，原始 ID，释放该入口 Tracker。
- 输入 release_valid[出口]：下游 B 已被本 Crossbar 接收并安全保存到响应缓冲的通知，释放出口预留名额；不释放入口 Tracker。
- 输出 w_target_valid/target/len，输入 w_target_ready：每入口最早尚未完成 W 的目标与 AWLEN。
- 输出 w_source_valid/source/len，输入 w_source_ready：每出口最早尚未完成 W 的来源与 AWLEN。

W 两边的 ready 在实际集成中必须仅在该 burst 最后一拍 W 于下游握手时同时置位，分别弹出匹配的入口/出口记录；没有 W 记录时不接受提前 W，已有记录也不表示对应出口 AW 已握手。W 数据路径还需等两端记录相互匹配。

下游 ID=`{source_index, original_id}`，默认 2+2=4 位。1 入口配置保留一个为 0 的来源位，避免零位宽接口；这是本模块的参数接口约定。

complete/release 是受信任的内部通知接口，本轮没有 BID 路由/响应缓冲来产生它们。完成通知必须对应实际合法 B，不可由超时或 WLAST伪造。

## 3. 入口准入及原子更新

s_awready 为寄存准入许可，无当拍地址/ID 到 READY 的组合路径。第 N 沿看到 s_awvalid 且 Tracker、AW FIFO、W 目标 FIFO 均可用后，沿后拉高 READY；最早第 N+1 沿完成接收。源必须按 AXI 保持 VALID 和 payload 到握手。

接收沿同时发生三件事：Tracker 分配、完整 AW 加目标入队、W 目标加 AWLEN 入队。任何资源不足都不能先接收再补记。

许可发出后，资源只能由这个入口唯一生产者在该 AW 握手时占用，其他事件只会释放空间，所以许可不会被另一个请求抢走。断言再次核对实际接收沿资源仍可用。映射在运行中保持不变。

许可在接收后撤销；下一请求重新检查，因此首实现不承诺每拍接受一笔 AW，采用保守的寄存时序。入口总 outstanding 仍从上游 AW 握手计到上游 B 握手，满容量时不提前复用完成当沿的名额。

## 4. 出口预留与 AW/W 顺序

只有入口 AW FIFO 的队首可参与一个目标的仲裁。被选中并捕获到出口 AW 寄存器后，给该入口置 issued 标记；直到该笔 m_awvalid && m_awready 才弹出入口 AW 队首并清标记。入口的后一笔 AW 因而不会绕过前一笔去另一个 Slave。

仲裁的“接收完成”事件是捕获到出口 AW 寄存器。此时预留出口容量，并确保 W 来源 FIFO 有空间；该出口同一时刻只有一个未握手 AW 寄存器，不会有第二个生产者抢走这个来源槽位。下游 AW 握手时才写入来源记录，顺序与 Slave 实际接收 AW 一致。

出口容量计数包含“已捕获、尚未下游 AW 握手”和“下游已接收、尚未回收 B”两类事务。release_valid 释放名额，含义与 Slave 自己从 AW 到 B 的容量计数不同。容量满时保留已有 AW/W 推进能力；不因 full 屏蔽已锁定仲裁请求。

出口 AWVALID 和 payload 来自寄存器，不依赖 AWREADY；背压时保持。当前采用单个输出寄存器，弹出当沿不重新填入，存在保守气泡；性能优化后续以测量和回归为依据。

每个入口按实际下游 AW 握手顺序发出，每个出口也按实际握手顺序记录 W 来源。这些顺序边都符合 AW 接收事件的先后关系，避免仅因本模块重排 AW 造成循环依赖。测试能检查此顺序和有限场景进展，不是整个 AXI 系统无死锁的形式证明；外部端点永久停止响应仍可阻塞系统。

## 5. 复位

公共 reset_n 异步清除 READY 许可、Tracker、所有 FIFO 的指针/计数、issued、出口 AWVALID 和预留计数。旧 FIFO 数据位无需清零：有效计数清零后不可输出为有效事务。复位后新请求重新开始；本模块不保存内存数据。

## 6. 自检范围

独立 TB 只从公开接口握手建立每入口预期 AW/目标队列、每出口来源队列、完成账本和按 ID 目标绑定记录。逐字段检查下游 AW 及来源 ID，检查同入口发出顺序、队列配对、容量和最终排空。未读取 RTL 私有队列。

测试用逐拍计数模拟 W burst 完成，用两级队列模拟下游 B 被接收与上游 B 被接收之间的延迟；这是内部完成事件模型，不是 WDATA/B 通道或 UVM 系统验证。

场景包括多入口争同一出口、出口容量满、不同出口并行 AW、随机 AWREADY、1～4 拍及 256 拍的路由记录存续、真实错误目标路由、同 ID 跨目标等待、延迟归还入口/出口名额、在途/背压复位、复位后新事务及最终排空。输入 VALID 在未接受前持续保持。

参数矩阵：4×4/32位/入口2出口4；3×2/32位/入口3出口3；1×1/32位/入口1出口1；4×4/64位/入口2出口4。每组种子 7、41、2026。这里 64 位指地址宽度，本模块没有数据总线。

运行 `python3 scripts/run_frontend.py` 或 `make frontend-regress`。使用已有 Verilator 5.052，启用断言、编译警告作为失败；结果写入 frontend-results.json，日志在 logs/frontend。

## 7. 剩余工作

下一增量实现 WDATA/WSTRB/WLAST 的两拍缓冲与实际路由，遵守以上配对/弹出规则。随后完成 B 路由与缓冲、DECERR 事务处理，形成真正的 4×4 AW/W/B 闭环。Slave Monitor/agent 和系统 Scoreboard 仍需补齐；当前控制 TB 不能替代它们。读通路仍属于后续必需目标。

## 8. 实际验收结果

最终源码的 12/12 次参数/种子运行全部通过，四组编译无警告失败。4×4、32 位地址、seed7 的一次实际运行：上游接受 659 笔，完成 651 笔，公共复位取消 8 笔；出口最大在途达到 4，多出口 AW 同拍握手发生 104 次，119 笔发往内部错误目标。有空位但同 ID 目标不符而被阻挡的采样周期为 7，同 ID 重复在途接收见证为 8。取消数包含已接受但尚未发出的事务，因此转发数与接收数不必相等。

上述完成/取消来自控制 TB 的模拟 W/B 事件；119 笔错误目标路由不表示真实 DECERR BRESP 已实现。机器可读证据见 [frontend-results.json](frontend-results.json)，日志保留在 logs/frontend。现有 Tracker 与译码/仲裁源摘要与此前验收记录一致。

结构检查阶段把入口 READY 从地址/ID 组合准入改为寄存准入许可，并重新跑过最终回归；当前采用保守吞吐实现，不把仿真通过称为综合、时序收敛或形式证明通过。
