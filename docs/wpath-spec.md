# Crossbar W 两拍缓冲与数据转发

> 本文保留 W 增量的验收边界。真实 B 路由已在后续增量接入，见 [B 路径与联合验收](bpath-spec.md)。

2026-11-15。用户要求继续上一增量。本轮在已有 AW 控制路径上接入实际 WDATA/WSTRB/WLAST；尚未接入真实 B 路由和 DECERR 响应端。

## 1. 文件与组成

- rtl/axi_write_data_path.sv：每入口两拍数据 FIFO、输入拍数计数、按两端路由记录选择出口、输出拍数检查。
- dv/tests/wpath/wpath_tb.sv：同时实例化已有 axi_write_frontend 与新数据路径，独立握手账本逐拍检查。
- scripts/run_wpath.py：本机编译及参数/种子回归，包含两项错误 WLAST 测试。

复用 axi_record_fifo，不修改之前通过的 AW 控制源码。默认 4 个入口、5 个逻辑出口，其中 0～3 为物理 Slave，4 为未来 DECERR 处理端。DATA_WIDTH 默认 32，WSTRB 宽度为 DATA_WIDTH/8。

每入口只保存两拍 `{WDATA, WSTRB, WLAST}`，不缓存完整 burst。W 没有独立仲裁器：来源由已接受的 AW 顺序记录决定。

## 2. 信号方向

相对于 axi_write_data_path：

- 输入 clk、reset_n。
- 输入 s_wvalid/s_wdata/s_wstrb/s_wlast；输出 s_wready，按入口编号索引。
- 输出 m_wvalid/m_wdata/m_wstrb/m_wlast；输入 m_wready，按逻辑出口编号索引。
- 输入 w_target_valid/target/len，输出 w_target_ready，连接 AW 前端的每入口 W 目标队列。
- 输入 w_source_valid/source/len，输出 w_source_ready，连接 AW 前端的每出口 W 来源队列。

两类路由队列的 ready 都是“该 burst 在下游完成”的弹出脉冲，不是收到一拍数据就弹出。

## 3. 接收、保持与转发规则

只有入口已经有 AW 路由记录，数据 FIFO 有空位，且当前 burst 尚未接收满 AWLEN+1 拍，s_wready 才为 1。提前提出的 WVALID 会被背压，源必须保持它及 payload；不要求源等 AWREADY 才提出 WVALID。

对应出口尚未接收 AW 时，允许入口缓存最多两拍 W；但必须等出口来源记录建立，并与入口目标记录相互匹配后，才可向下游提出 WVALID。因此本实现的下游 W 不会早于对应 AW 握手。

当前 burst 的最后一拍已被入口 FIFO 接收后，暂停接收下一笔 burst 的 W，直到当前最后一拍实际在下游握手。这样 FIFO 不混装两个 burst，避免仅凭当前队首把下一笔 W 送往旧目标。首实现允许 burst 边界有气泡，不把它描述为连续满吞吐。

输出只取匹配来源的 FIFO 队首。WDATA、WSTRB、WLAST 原样转发，不做地址运算或字节重新排列。被背压期间，数据和两端路由记录均不弹出，因此输出保持稳定。

仅当 m_wvalid && m_wready && m_wlast 时，同时弹出该出口来源记录及对应入口目标记录，并清零本 burst 的拍计数。其他 W 拍只弹出数据 FIFO，不弹路由记录。WLAST 不释放入口 Tracker 或出口 B 在途计数；它们仍按前端定义的 B 完成通知释放。

例：入口 M0 的 W 目标队首为 S2，S2 的来源队首也为 M0，才允许 M0 的 FIFO 驱动 S2。若 S2 当前来源是 M1，M0 保持缓存并等待，不能抢占或交错发送两笔 burst。

## 4. 时序与检查

FIFO 无直通，输入握手后的数据最早下一采样沿在出口握手。满 FIFO 不使用当拍下游消费产生的空位提前接收，下一周期恢复 ready。s_wready 不组合依赖 m_wready；m_wvalid/data 来自已寄存的数据与路由状态，不组合依赖 s_wvalid/data。

按 AWLEN 检查每一拍输入 WLAST：提前为 1 或最后一拍仍为 0 都触发 WDATA_INPUT_LAST。输出也核对 AWLEN 与 WLAST，背压时以断言检查稳定性。非法输入用于仿真诊断，硬件运行时的故障恢复不属于本阶段承诺。

本模块不解释 AWSIZE/WSTRB 合法字节范围，只保证 WSTRB 位精确保留；窄传输、非对齐字节合法性由已有协议检查/端点及后续系统验证检查，不能因本轮通过就声称该覆盖已经收敛。

公共 reset_n 清空数据 FIFO 有效状态和拍计数；AW 前端同步清空路由记录。已经送到外部 Slave 的数据不由 Crossbar 回滚，本模块没有外部存储清零功能。

## 5. 自检方法与边界

TB 在上游 W 实际握手时保存完整拍数据，在下游 WVALID 时逐位比较，握手后弹出预期拍。另从 AW 握手记录检查来源、目标、burst 长度与顺序，监测每入口最多缓存两拍及路由弹出时机。参考模型不读取 RTL 内部 FIFO。

输入驱动在尚未 AW 握手时就可以提出 W；输出有随机 WREADY。初期固定阻挡下游，用来见证缓冲达到两拍并产生背压；在 AW/W 缓冲有在途状态时公共复位，再运行新流量。输入 VALID 被阻挡时保持，WSTRB 包含全开、全零、稀疏组合。

真实 W 转发包括 1～4 拍与 256 拍 burst；不同入口/出口可以同时握手。每个 burst 完成后，TB 才允许进入模拟的 B 回收队列，并分别延迟出口名额释放与入口完成通知。这仍是 B 通知模型，未生成/验证真实 BID/BRESP/BVALID/BREADY。

参数：4×4/地址32数据32/入口2出口4；3×2/地址32数据32/入口3出口3；1×1/地址32数据32/入口1出口1；4×4/地址64数据64/入口2出口4。每组 seed=7、41、2026。另在默认配置故意提前 WLAST、缺失最终 WLAST，要求精确触发 WDATA_INPUT_LAST，而不是因其他错误或超时退出。

运行 `python3 scripts/run_wpath.py` 或 `make wpath-regress`。本机 Verilator 5.052，断言启用、编译警告作为失败。

## 6. 实际结果

最终 12/12 次正常运行和 2/2 次负向断言运行达到预期。结果与源摘要见 [wpath-results.json](wpath-results.json)，原始日志位于 logs/wpath。

默认 4×4、32 位数据、seed7 的一次运行记录：

- 输入接收 2182 拍，输出转发 2175 拍，复位取消缓存中的 7 拍，数量闭合。
- 实际缓冲峰值 2 拍；W 提前等待见证 595 次、缓冲满背压见证 4262 次、输出背压见证 725 次。
- 多出口 W 同拍握手 359 次；全零 WSTRB 输入 606 拍、稀疏 WSTRB 输入 855 拍。
- 接受 AW 473 笔，其中完成 465 笔、复位取消 8 笔。83 笔路由到内部错误目标，但真实 DECERR 响应仍未实现。

这些是具体测试见证，不是系统吞吐指标或覆盖收敛率。旧 AW 前端与其 TB 源摘要保持不变；本轮在新联合 TB 中验证 AW/W 连接，不重复宣称旧控制回归已重跑。

## 7. 下一步

实现 B 来源识别、恢复原 ID、响应仲裁/缓冲及真实握手释放两类名额，然后加入内部 DECERR 处理端，形成完整 4×4 写通路闭环。独立 Slave Monitor/agent、系统 Scoreboard 和 AR/R 仍在计划内。本轮没有综合、STA、形式证明或完整系统验证完成结论。
