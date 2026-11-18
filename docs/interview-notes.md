# AXI4 Crossbar 项目：问题与解决方案记录

> 面试素材文档 — 2026-11-16 整理
> 涵盖读通路实现过程中遇到的设计 bug、TB 时序问题、协议理解点。

---

## 1. RTL Bug：R burst 多拍死锁

**现象**
读通路 scoreboard 报 `SCBD_RLAST: beat=2 beats=2 rlast=0`。对一个 2-beat burst，第 2 拍到来时 DUT 的 `s_rlast` 仍为 0，意味着 DUT 多发了拍数，或根本发不完第 2 拍。

**根因**
`axi_read_data_path` 有一个 per-master output register（`full` bit）。原始逻辑是：
```
else if (complete_valid[i]) begin  // complete_valid = rvalid && rready && rlast
    full[i] <= 0;
end
```
只有在 RLAST 被接受时才清零。对单拍 burst 没问题；对多拍 burst，第 1 拍进入 output register 后 `full=1`，`s_rlast=0`，`complete_valid=0`，`full` 永远不能清零 → 第 2 拍永远无法 capture → 系统死锁。

**修复**
```sv
// 任意拍被 master 接受都要清空 output register
else if (s_rvalid[i] && s_rready[i]) begin
    full[i] <= 0;
end
```
`complete_valid`（RLAST 专用）仍然单独通知 tracker 释放 outstanding 名额，不影响 output register 的流水线控制。

**面试要点**
- 设计两个相关但语义不同的信号时，要明确哪个控制流水线（output reg 清空），哪个控制资源（outstanding 释放）。
- 写通路没有这个问题，因为 B 本身是单 beat，完全等价于 RLAST。
- 这类 bug 在仿真里的表现是系统卡死（`completed=0`），而不是数据错误，定位需要追踪 full/capture 状态。

---

## 2. RTL 断言误报：FRONTEND_READ_UNKNOWN_RELEASE

**现象**
`release_valid |-> output_count != 0` 断言失败。

**根因**
DECERR 路径极快（AR → 内部直接生成 R，无存储访问），导致 `capture_output`（+1）和 `release_valid`（-1）在同一拍触发，此时 `output_count` 为 0。写通路不出现，因为 B 要经过 AW→W→B 整个流程，时间差足够。

**修复**
断言放宽，允许同拍同时发生：
```sv
assert property (... release_valid[o] |-> (output_count[o] != 0 || capture_output[o]))
```

**面试要点**
- 断言设计要考虑合法的"极端快"路径，不能只用正常路径的时序假设写断言。
- `output_count=0 且 release_valid=1` 单独看是错的，但配合 `capture_output=1` 是完全合法的：`+1-1=0` 状态不变。

---

## 3. TB 时序问题：negedge vs posedge 驱动

**现象**
运行 `FRONTEND_READ_AR_UNSTABLE`：`m_arvalid && !m_arready |=> m_arvalid && $stable(...)` 断言失败，但 RTL 的 FF 逻辑理论上不可能变化。

**根因**
TB 的 slave AR receiver 用 `@posedge clk` 推进并立刻赋值 `m_arready=1`，这个赋值和 RTL 断言在同一 delta cycle 竞争：

```sv
// 有问题的 TB 写法
@(posedge clk);
m_arready[o] = 1;   // 在同一 delta 更新，断言看到的是旧值还是新值取决于执行顺序
```

写通路 TB 用的是 `@negedge clk` 推进所有输出驱动，断言在 posedge 采样，在 negedge 时信号已稳定，不存在竞争。

**修复**
所有 TB 侧驱动信号改为 `@negedge clk` 触发，和写通路 TB 保持一致：
```sv
// 正确写法
always @(negedge clk) begin
    m_arready[o] = ...;  // negedge 更新，posedge 时已稳定
end
```

**面试要点**
- SV TB 中驱动输入信号要在 `negedge`（或 clocking block），RTL 断言在 `posedge` 采样，两者时序天然错开。
- 违反这个约定不一定立刻报错，但会产生难以复现的 delta-cycle 竞争，表现为"理论上不会失败"的断言却失败了。
- 这是 AXI TB 中 `input valid/ready` 驱动的标准做法。

---

## 4. TB 协议违规：stale ARREADY 被复用

**现象**
`FRONTEND_READ_ADMISSION_LOST`：accept_ar=1 但 tracker_ready=0，说明 DUT 接受了一笔 AR 但 tracker 认为条件不满足。

**根因**
`ready_registered`（DUT 内部 FF）在 T0 置 1，T1 posedge 时 `s_arready=1`。TB 的 negedge driver 在 T0.5 检测到 arready=1 后，立刻清 `s_arvalid=0`，然后**同一个 negedge** 加载下一笔新事务（`s_arvalid=1`，新 id/addr）。T1 posedge 时，`ready_registered` 仍为 1（下一拍才自清），新事务的 `s_arvalid=1` + 旧 `arready=1` → `accept_ar=1`，但新事务的 id/target 未经 tracker 检查。

**修复**
接受后强制等一个 negedge（cooldown bit）再发下一笔：
```sv
if (accepted_mask[i]) ar_cooldown[i] = 1;  // 本 negedge 不发新事务
// 下一个 negedge：ar_cooldown=0 → 可以发
```

**面试要点**
- AXI Master 驱动：握手完成后，`VALID` 应在 `READY` 拉高的**那一拍结束后**才能撤销并更换 payload。对于寄存式 ready（需要一拍延迟才自清的 DUT），Master 必须额外等一个周期。
- 这类问题在单拍 burst 或低背压场景下很难触发（因为 stall 自然引入了间隔），需要多 outstanding + 低随机延迟才能复现。

---

## 5. 设计取舍：R 数据路径 vs W 数据路径的结构差异

**写通路 W**
- W 数据流向：Master → Slave（同向）
- 路由信息来自**显式 W 目标队列**（per-ingress）和 **W 来源队列**（per-egress），双向队首匹配
- 需要缓冲（2-beat FIFO），保证背压时不堵塞

**读通路 R**
- R 数据流向：Slave → Master（反向）
- 路由信息来自 **RID 高位的 source 字段**（AR 路由时把 master 编号嵌入 ID），不需要显式路由队列
- 多拍 burst 需要 **lock-until-RLAST** 机制：一旦开始服务某 slave 的 R burst，锁定该 source 直到 RLAST，防止同一 master 的不同事务 R beats 交错

**为什么写通路需要队列而读通路不需要？**
写通路的 W 数据本身不带路由信息（W 没有地址），必须靠 AW 建立的路由记录来关联。读通路的 R 数据在 RID 里已经携带了完整的路由信息（source bits = 哪个 master），可以直接解码。这是 AXI 协议对读写通道的本质差异。

---

## 6. 同拍 capture+release 的 output_count 状态机设计

**背景**
`output_count` 用于限制每个下游 slave 端口的 outstanding AR 数量：
- `capture_output` → `+1`（AR 进入 output 寄存器，占用一个 slot）
- `release_valid` → `-1`（下游 RLAST 收到，释放 slot）

**问题**
如果 `capture_output` 和 `release_valid` 在同一拍触发（count=0 时），case 语句走 `default` 不变，这是正确行为。但原来的断言 `release_valid |-> count != 0` 会误报。

**正确的断言**
```sv
assert property (release_valid[o] |-> (output_count[o] != 0 || capture_output[o]))
```
允许"同拍净效果为0"的合法状态。

**面试要点**
- 资源计数器的 case/priority 语句设计：同时 +1 和 -1 时走 default 保持不变，是正确的 "atomic" 操作语义。
- 断言要覆盖所有合法的角点案例，包括边界组合。

---

## 7. 参数化设计的 ID 扩展方案

**设计**
Master 侧 ID 为 `ID_WIDTH`（默认 2 位），Slave 侧 ID 为 `OUTPUT_ID_WIDTH = ID_WIDTH + SOURCE_WIDTH`（默认 4 位）：
```
Slave 侧 ID = {master_index[SOURCE_WIDTH-1:0], original_id[ID_WIDTH-1:0]}
```

**好处**
- Slave 收到 AR 后，R 响应只需按 RID 路由，不需要额外查表
- Crossbar 从 R 响应的 ID 高位直接还原目标 Master，低位还原原始 ID

**代价**
- 下游 ID 位宽增大（`$clog2(INPUTS)` 位额外开销）
- UVM 系统测试需要两套 ID 宽度的 interface（入口 ID2，出口 ID4），需要参数化接口设计

**面试要点**
- 这是 AXI 互联标准做法（参考 PULP axi_xbar 和 verilog-axi 的 arb_id expansion）
- 不用这个方案的替代是维护显式路由表（per-outstanding-AR 记录 source），代价是存储面积和查找延迟

---

## 8. 同一 ID 顺序保护的两层机制

读通路中，同一 Master 的同一 ID 有两层顺序保护：

**第一层：Frontend（AR 路由层）**
`axi_write_tracker`（读通路复用）：同 ID 只有在目标 Slave 相同时才允许新 AR，否则等到旧事务排空。确保同 ID 的 AR 不会发送到不同 Slave。

**第二层：Data Path（R 数据层）**
`locked` bit + `locked_source`：一旦开始从某 Slave 接收 R beats，锁定该 source 直到 RLAST。确保同一事务的 R beats 不会被其他事务的 R beats 打断。

**关键区别**
第一层保证"同 ID 不会出现在不同 Slave 上"，第二层保证"已经在传输的 burst 不会中途切换 source"。两层分别处理 AR 路由和 R 数据流控制。

---

## 9. 验证方法论：独立 Scoreboard 的设计原则

**写通路 Scoreboard 设计**
`fabric_scoreboard` 只观察两侧真实引脚握手，不读取 RTL 或 Driver 的内部队列：
- 从 Master 侧 AW 握手建立期望记录
- 从 Slave 侧 AW/W 握手确认路由正确
- 对比 B 响应来源和内容
- 全量 262144 字节存储比对（不只看写过的地址）

**读通路 Scoreboard 设计**
用 `in_flight_ref` 队列（有序，按 AR 接受顺序）+ 按 RID 匹配最老的 pending entry：
- 保证同 ID 的事务按顺序关联 R beats
- 对 DECERR 事务检查 `rresp=2'b11`，对物理 Slave 检查 `rresp=2'b00`
- beat 计数与 RLAST 时序严格校验

**面试要点**
- Scoreboard 不依赖 Driver 私有状态（DUT/driver 的内部 outstanding 记录）是 DV 方法论的关键点，这样即使 DUT 有 bug 也能被检出，而不是两边状态一起错。
- 全量字节比对 vs 只比对写过的字节：后者会漏掉越界写或额外写入。

---

## 10. Mutation Testing 的覆盖局限

**已做的 mutation testing**
- `wrong_bid`：篡改 BID，scoreboard 检出
- `wrong_byte`：篡改写入字节，存储比对检出
- `BAD_SOURCE`：注入非法 source 位的 BID/RID，RTL 断言检出

**局限**
- 没有做完整的 RTL mutation（如翻转仲裁逻辑、破坏 WLAST 计数等）
- Mutation testing 检出证明 checker 在执行，但不代表 checker 覆盖了所有潜在错误路径

**面试要点**
- Mutation testing 是验证"验证是否有效"的元测试，不是功能覆盖的替代
- 在面试中可以坦承这三个 mutation 是针对性的，完整覆盖需要自动 mutation 工具（如 Cadence JasperGold Mutation）

---

## 11. 在途复位的四类边界问题

P1 实现在途复位测试（crossbar_uvm7）时，发现了验证基础设施层面的四类设计挑战：

**11.1 同步复位的 Scoreboard 时序窗口问题**

DUT 是同步复位（`reset_n` 在下一个 posedge 生效），Scoreboard 在同一 posedge 看到 `ARESETn=0` 并立即 flush 队列。结果：
- DUT 在 flush 那个周期的 pipeline 输出（WVALID/BVALID）已经是复位前的值
- Flush 后下一周期 DUT 才真正停止
- 若 DUT pipeline 输出未清空，Scoreboard 会遇到"队列已空但信号有效"的假 FATAL

**修复**：在每个 Scoreboard 加 `in_reset` guard，ARESETn 变高后跳过至少 1 个 guard 周期，给 DUT pipeline 完全清零时间。将复位边界的孤立 handshake 由 FATAL 改为 count-but-ignore。

**11.2 `fork...join_none...join_any` 结构的调度陷阱**

原先写法：
```sv
fork
    begin fork w_seqs.start() join_none end   // 立即完成
    begin fork r_seqs.start() join_none end   // 立即完成
    begin wait_for_scenario_and_reset(); end   // 应该是长任务
join_any
disable fork;
```
`join_any` 在前两个分支（join_none blocks）立即完成时马上触发，`disable fork` 把 reset controller 也 kill 了。导致 `reset_cycle=0`，场景永不确认。

**修复**：用 `fork...join_none` 把 sequences 放到后台，然后直接阻塞调用 `wait_for_scenario_and_reset()`，不用 join_any。

**11.3 结构体值语义 vs 类引用语义**

Scoreboard 把记录从 `awaiting_fwd` push 到 `outgoing_w` 和 `outgoing_b` 时，如果记录是 `struct`（值语义），这两个队列持有的是两个独立拷贝。后续 `outgoing_w[0].forwarded++` 不会更新 `outgoing_b` 里的副本，B 检查时 `forwarded != beats` 永远成立。

**修复**：将 `wr_t` 从 `typedef struct` 改为 `class`，保证引用语义。

**11.4 Test 中 `driver.cancelled` 读取时机**

`driver.cancelled` 在 `clear_state()` 里累加，`clear_state()` 在 Driver 的 `run_phase` 里响应 `ARESETn=0` 时调用。Test 在复位释放后立即读取 `cancelled`，此时 Driver 的 `run_phase` 可能还没执行完当前 `@(vif.mon)` 周期的 `clear_state()`，导致 `cancelled` 计数偏低1。

**修复**：在读取 `cancelled` 之前多等几个周期让 Driver 完成状态更新。

**面试要点**
- 在途复位是 AXI 互联实现中最难测的场景之一，因为 DUT、TB、Scoreboard 三方都有状态需要同步取消
- 同步复位的 Scoreboard 保护不是"reset 看到就 flush"，需要考虑 DUT pipeline 的输出延迟
- 取消与正常完成必须分别计数，才能证明复位后没有多余的"僵尸事务"完成

---

## 12. 存储保留语义与 AXI 复位协议

**AXI 规范**
AXI 规范没有规定 Slave 存储必须随 `ARESETn` 清零。正常复位只取消在途事务，已经写入 Slave 的数据保留。

**本项目实现**
- 写 Slave driver 的 `reset_control()` 清空事务队列（`active_q`、`write_q`），但不调用 `memory.clear_memory()`
- 读 Slave 同理：`reset_state()` 清空 `active_q`，读内存不变
- TB 层面通过独立 `clear_memory()` 显式清零（需先停流量）

**测试验证**
复位后对 write_slave 存储的前4KB 抽样（每64字节1个点）：
- 比对 Scoreboard 追踪的 `expected_bytes` 与 `driver.memory.peek_byte()`
- bytes_mismatched=0 证明：(1) 完整 W burst 已写入的字节保留，(2) 没有未预期的额外写入

**面试要点**
- 部分写入（burst 没完成就复位）的字节不在 `expected_bytes` 里，不做检查（这是正确的：协议允许部分写入结果不确定）
- "存储保留"是独立于"事务取消"的属性，需要分开证明

