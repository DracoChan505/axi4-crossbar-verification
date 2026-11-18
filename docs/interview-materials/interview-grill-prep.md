# 面试拷问预备手册

**目标**：从零基础到能应对面试官追问。你目前对 AXI 通道有书面认知，这里补全"为什么"和"怎么验证"。

**使用方式**：每个问题先自己试着回答，再对照参考答案。标注 ⭐ 的是高频必会题。

---

## 第一层：AXI4 协议基础（你必须答得不卡壳）

### ⭐ Q1: AXI4 有哪几个通道？各自传什么？

**5个独立通道**：

| 通道 | 全称 | 方向 | 传什么 | 关键信号 |
|------|------|------|--------|---------|
| AW | Address Write | M→S | 写地址 | AWADDR, AWLEN, AWSIZE, AWBURST, AWID, AWVALID, AWREADY |
| W | Write Data | M→S | 写数据 | WDATA, WSTRB, WLAST, WVALID, WREADY |
| B | Write Response | S→M | 写响应 | BRESP, BID, BVALID, BREADY |
| AR | Address Read | M→S | 读地址 | ARADDR, ARLEN, ARSIZE, ARBURST, ARID, ARVALID, ARREADY |
| R | Read Data | S→M | 读数据+响应 | RDATA, RRESP, RLAST, RID, RVALID, RREADY |

**记忆口诀**：写有3通道（AW→W→B），读有2通道（AR→R），地址都是M→S，响应/数据都是S→M。

**面试官追问"为什么分5个通道"**：独立通道允许并行操作。比如 Master 发了 AW 后，可以紧接着发下一个 AW（outstanding），不需要等当前写完成。如果只有一个通道，每次必须等整个事务结束才能发下一个。

---

### ⭐ Q2: VALID/READY 握手是怎么回事？

**核心规则**：
- VALID 由源端（发送方）置起，表示数据/地址有效
- READY 由目的端（接收方）置起，表示可以接收
- **只有 VALID 和 READY 同时为高的那个时钟上升沿，传输才发生**
- **VALID 一旦置起，在传输完成前不能撤销**（这是 AXI 最严格的规则）
- READY 可以等待 VALID 后再置起，也可以提前置起

**面试官追问"VALID 能不能等 READY 再置起"**：不能。VALID 必须独立于 READY 置起。如果 VALID 等 READY，而 READY 也等 VALID，就会死锁。AXI 规范要求 VALID 不能依赖 READY，但 READY 可以依赖 VALID。

**面试官追问"READY 能不能提前置起"**：可以。READY 可以一直为高（表示始终准备好），也可以在看到 VALID 后才置起。两种都是合法的。设计中选择哪种取决于时序需求——提前置起可以减少延迟，但可能丢失数据如果接收方还没真正准备好。

**你在项目里的实践**：你的 Slave agent 可以注入 backpressure（READY 延迟置起），场景 3 和 4 就是测试 B/R 通道的 backpressure。

---

### ⭐ Q3: AWLEN 和 AWSIZE 是什么意思？burst 怎么工作？

**AWLEN**：burst 中的 beat 数量减 1。AWLEN=0 表示1拍，AWLEN=15 表示16拍。
**AWSIZE**：每拍的 byte 数量。AWSIZE=2 表示 2^2=4 bytes = 32-bit。
**AWBURST**：burst 类型。
- INCR（最常用）：地址递增，不回绕
- WRAP：地址回绕（用于 cache line fill）
- FIXED：地址固定不变（用于 FIFO 类操作）

**面试官追问"为什么 AWLEN 是数量减1"**：AWLEN 是3-bit（AXI4），范围0-7表示1-8拍。用"数量减1"可以用更少的 bit 表示更大的范围，这是总线协议的常见设计。

**面试官追问"你的项目支持哪些 burst 类型"**：只支持 INCR。FIXED 和 WRAP 留作扩展。INCR 覆盖了绝大多数实际应用场景。

**你在项目里的实践**：你的 covergroup 里有 `cp_length` coverpoint，bins 包括 single(1)、short_burst(2-16)、long_burst(17-255)、maximum(256)。

---

### ⭐ Q4: AWID/BID/ARID/RID 是什么？为什么要用 ID？

**ID 的作用**：标识不同的 transaction，允许同一 Master 发出多个 outstanding transaction，并且响应可以**乱序返回**。

**规则**：
- 同一 ID 的 transaction **必须按顺序返回响应**
- 不同 ID 的 response 可以**乱序**返回
- B 通道的 BID 必须匹配对应的 AW 的 AWID
- R 通道的 RID 必须匹配对应的 AR 的 ARID

**面试官追问"为什么需要 ID 乱序"**：假设 Master 向 Slave 0 发了读请求（ID=0），又向 Slave 1 发了读请求（ID=1）。Slave 0 响应慢，Slave 1 响应快。如果没有 ID，Slave 1 的数据必须等 Slave 0 的数据先返回（严格顺序），浪费带宽。有 ID 后，Slave 1 的数据可以先返回（不同 ID 可以乱序），Master 通过 ID 匹配到正确的请求。

**你在项目里的实践**：
- Master 侧 ID 2-bit（0-3）
- Crossbar 内部用 tracker 绑定 ID → target Slave，确保同 ID 的写事务发到同一 Slave
- 4个 Master × 2-bit ID = 需要区分 4×4=16 个可能的 ID 空间
- 所以内部用 4-bit（source 2-bit + master_id 2-bit）表示

---

### ⭐ Q5: BRESP 和 RRESP 有哪些值？

**4种响应值**（2-bit）：

| 值 | 名称 | 含义 |
|----|------|------|
| 00 | OKAY | 正常完成 |
| 01 | EXOKAY | Exclusive access 成功（你的项目不支持） |
| 10 | SLVERR | Slave 错误（如地址越界、协议违规） |
| 11 | DECERR | Decode 错误（没有 Slave 响应这个地址） |

**面试官追问"DECERR 怎么处理"**：在 Crossbar 里，如果地址没有匹配到任何 Slave 窗口，Crossbar 内部有一个虚拟 DECERR Slave 自动响应，返回 BRESP/RRESP=11。这样 Master 不会卡住等待永远不来的响应。

**你在项目里的实践**：`axi_write_decerr.sv` 和 `axi_read_decerr.sv` 就是内部 DECERR 端点，接收未匹配地址的事务并返回 DECERR 响应。写通路 DECERR 独立验证 4/4 通过。

---

### ⭐ Q6: WSTRB 是什么？怎么用？

**WSTRB（Write Strobes）**：每 bit 对应 WDATA 中的一个 byte。WSTRB[i]=1 表示该 byte 要写入，=0 表示该 byte 保持不变。

**例子**：32-bit 数据（4 bytes），WSTRB=0b0011 表示只写低2字节，高2字节不变。

**面试官追问"WSTRB 和 AWSIZE 的关系"**：AWSIZE 告诉你每拍有多少 byte，WSTRB 告诉你哪些 byte 实际有效。两者独立——AWSIZE=2（4 bytes/拍）但 WSTRB 可以是 0b0010（只写第2个 byte）。

**你在项目里的实践**：scoreboard 检查 `bytes_bad=0`，就是验证 WSTRB 标记的有效 byte 是否正确写入和读回。

---

## 第二层：Crossbar 架构和设计决策

### ⭐ Q7: Crossbar 是什么？为什么需要它？

**Crossbar（交叉开关）**：连接多个 Master 和多个 Slave 的互连结构，允许任意 Master 访问任意 Slave，支持多路并发。

**对比总线（Bus）**：总线同一时刻只允许一个 Master 访问一个 Slave。Crossbar 允许多个 Master 同时访问不同 Slave。

**面试官追问"你的 Crossbar 是几乘几"**：4×4，4个 Master 端口和4个 Slave 端口。

**面试官追问"为什么不用总线"**：总线带宽受限（同一时刻只有一个事务在飞）。Crossbar 支持并发，4×4 理论上可以同时有4个事务在飞（每个 Master 访问不同 Slave）。

---

### ⭐ Q8: 你的 Crossbar 怎么决定把请求路由到哪个 Slave？

**静态地址译码**：每个 Slave 对应一个固定的地址窗口（4KB 对齐）。Master 发出的地址通过译码器判断属于哪个 Slave 窗口，然后路由到对应的 Slave。

**面试官追问"4KB 对齐是什么意思"**：每个 Slave 的地址窗口大小是 4KB（0x1000），起始地址是 4KB 的整数倍。比如 Slave 0 在 0x0000-0x0FFF，Slave 1 在 0x1000-0x1FFF。

**面试官追问"如果地址不在任何窗口内呢"**：路由到内部 DECERR Slave，返回 DECERR 响应。

**你在项目里的实践**：`axi_address_decode.sv` 做地址译码，根据 AWADDR/ARADDR 输出 4-bit one-hot 的 Slave 选择信号。

---

### ⭐ Q9: 如果两个 Master 同时要访问同一个 Slave 怎么办？

**仲裁（Arbitration）**：当多个 Master 的请求竞争同一个 Slave 时，仲裁器决定谁先访问。

**你的设计**：轮询仲裁（round-robin）。每个 Slave 端口有一个仲裁器，按轮询顺序选择 Master。如果 Master i 上次被选中了，下次优先选下一个 Master。

**面试官追问"为什么选 round-robin 而不是固定优先级"**：round-robin 保证公平性，每个 Master 都有机会访问。固定优先级会导致低优先级 Master 可能"饥饿"（永远等不到访问）。

**面试官追问"仲裁在哪个通道做"**：AW 通道和 AR 通道各自有仲裁器。因为写和读是独立通路，所以分别仲裁。

**你在项目里的实践**：`axi_rr_arbiter.sv` 是轮询仲裁器。`axi_write_frontend.sv` 和 `axi_read_frontend.sv` 各包含仲裁逻辑。

---

### ⭐ Q10: 什么是 outstanding transaction？你的设计支持多少？

**Outstanding**：Master 发出地址请求后，不需要等响应返回就可以发下一个请求。在途（未完成）的请求数量就是 outstanding。

**你的设计**：每入口最多 2 笔 outstanding。4个 Master × 2 = 最多 8 笔同时在途。

**面试官追问"为什么限制 outstanding 数量"**：
1. **资源**：每笔 outstanding 需要 tracker 记录目标 Slave 和 ID，存储有限
2. **时序**：过多 outstanding 增加仲裁和路由复杂度
3. **验证**：有限的 outstanding 数量更容易验证覆盖

**面试官追问"怎么跟踪 outstanding"**：`axi_write_tracker.sv` 为每个 Master 入口维护计数器。AW 接收时 +1，B 返回时 -1。同时绑定 AW 的 ID → 目标 Slave，确保同 ID 的响应能正确路由回源 Master。

---

### ⭐ Q11: 读写通路为什么要分开设计？

**独立路径**：读（AR/R）和写（AW/W/B）是完全独立的通道，可以并行操作。分开设计简化了状态机和验证。

**面试官追问"分开会不会影响性能"**：不会。AXI4 协议本身就是读写通道独立的。分开设计反而提高了吞吐量——读和写可以真正并发。

**面试官追问"有没有读写共享的逻辑"**：有。地址译码器（`axi_address_decode.sv`）读写共用，因为地址窗口映射是统一的。仲裁器也是读写各有一套但逻辑相同。

---

## 第三层：UVM 验证方法学

### Q12: UVM 验证环境有哪些核心组件？

**UVM 验证环境核心组件**：

| 组件 | 作用 | 你的项目对应 |
|------|------|------------|
| Agent | 封装 driver + monitor + sequencer | axi_master_agent, axi_slave_agent |
| Driver | 驱动接口信号 | axi_master_driver, axi_slave_driver |
| Monitor | 观察接口信号，发到 analysis port | axi_master_monitor, axi_slave_monitor |
| Sequencer | 管理 sequence 向 driver 发 item | uvm_sequencer |
| Sequence | 定义激励模式 | w7_sequence, r7_sequence 等 |
| Scoreboard | 比对期望和实际结果 | w_scbd, r_scbd |
| Test | 编排 phase 和 sequence | crossbar_uvm7_test |

**面试官追问"Agent 为什么封装这三个"**：因为它们操作同一个接口，逻辑上属于一组。Agent 可以通过配置切换 active/passive 模式——active 包含 driver（驱动信号），passive 只有 monitor（只观察）。

---

### ⭐ Q13: UVM 的 phase 机制是怎样的？

**UVM phase 分三大类**：

1. **Build phases**（自顶向下执行）：
   - `build_phase`：创建组件、配置参数
   - `connect_phase`：连接 TLM port
   - `end_of_elaboration_phase`：最终检查

2. **Run-time phases**（自底向上执行，并行运行）：
   - `run_phase`：主要测试逻辑（你用的是这个）
   - 内部细分：`reset_phase`、`main_phase`、`shutdown_phase`

3. **Cleanup phases**：
   - `extract_phase`：收集结果
   - `check_phase`：检查正确性
   - `report_phase`：生成报告
   - `final_phase`：最终清理

**面试官追问"你用的是 run_phase 还是 main_phase"**：用的是 `run_phase`，在里面用 `raise_objection`/`drop_objection` 控制测试结束时机。

**面试官追问"objection 是什么"**：objection 是 UVM 的机制，告诉框架"还有测试没做完"。当所有 objection 都 drop 后，`run_phase` 结束。如果忘记 raise，测试会立即结束（因为没有任何东西阻止它结束）。

**你在项目里的实践**：`crossbar_uvm7_test` 在 `run_phase` 开头 `phase.raise_objection(this)`，在所有 sequence 完成后 `phase.drop_objection(this)`。

---

### ⭐ Q14: Scoreboard 怎么工作？你怎么知道数据是对的？

**Scoreboard 工作流程**：
1. Monitor 观察接口，把每个 transaction 通过 analysis port 发出
2. Scoreboard 收集两个来源：
   - Master 侧 monitor：期望的数据（Master 发出的请求）
   - Slave 侧 monitor：实际返回的数据
3. Scoreboard 比对期望和实际，不一致就报 UVM_ERROR

**你在项目里的具体实现**：
- `w_scbd`（写 scoreboard）：跟踪每个写事务的地址、数据、WRSTRB
- 比对逻辑：Master 发的写数据 vs Slave 收到的写数据，字节级匹配（`bytes_bad`）
- Reset 后：post-reset 的数据不能被 pre-reset 的残留数据污染

**面试官追问"如果 scoreboard 报错了，怎么定位"**：
1. 看 UVM_ERROR 的消息，知道是地址还是数据不匹配
2. 看波形，确认 Master 发了什么、Slave 收了什么
3. 检查 Crossbar 内部路由和仲裁逻辑

---

### Q15: Sequence 和 Sequence Item 是什么？

**Sequence Item**：一个事务的封装。比如一个写事务包含 AWADDR、AWLEN、WDATA、WSTRB 等字段。

**Sequence**：一组 sequence item 的编排。定义"发什么、怎么发、什么时候发"。

**你在项目里的实践**：
- `axi_write_item`：写事务的 sequence item
- `w7_sequence`：在途复位场景的写 sequence，发送20个随机写事务
- `w7_post_sequence`：复位后的写 sequence，发送32个写事务验证恢复

---

## 第四层：项目细节深度拷问

### ⭐ Q16: 你的在途复位验证具体怎么做的？

**场景设计**：
1. 启动4个 Master 的写 sequence + 4个 Master 的读 sequence（pre-reset，各20个事务）
2. 在特定周期触发复位（不同场景不同周期：9/10/20/46-58/12-17/7）
3. 复位4个周期（reset_n=0）
4. 复位后启动新的写 + 读 sequence（post-reset，各32个事务）
5. 验证 post-reset 数据完整性（`bytes_bad=0`）

**面试官追问"为什么选这些复位周期"**：
- 场景 0（cycle 9）：AW/AR 地址刚发出，还没到 Slave
- 场景 1（cycle 10）：W 数据正在传，burst 中间
- 场景 2（cycle 20）：R 数据正在返回，burst 中间
- 场景 3（cycle 46-58）：B 响应正在被 backpressure 憋着
- 场景 4（cycle 12-17）：R 响应正在被 backpressure 憋着
- 场景 5（cycle 7）：混合 outstanding 最早可能复位

**面试官追问"怎么判断复位后 DUT 是正确的"**：
1. 所有 pre-reset 的 outstanding transaction 被正确取消（`w_cancelled`、`r_cancelled`）
2. Post-reset 事务全部完成（`w_post=32`、`r_post=32`）
3. Post-reset 数据完整性验证（`bytes_bad=0`）
4. `RESET_PASS` 标记出现在日志中

---

### ⭐ Q17: Xcelium 上出现的 TRY_NEXT_BLOCKED 是什么？怎么修的？

**问题**：场景 0 和 5 在 Xcelium 上报 `TRY_NEXT_BLOCKED` UVM_ERROR，12/18 失败。

**根因**：
- 场景 0/5 复位非常早（cycle 7-9）
- 此时 pre-reset sequence 还在 20-item 循环中
- UVM 的 `stop_sequences` 被调用停止 sequence
- 但 driver 的 `try_next_item` 在同一 NBA（Non-Blocking Assignment）周期还在轮询 sequencer
- 这个时序竞争是 UVM 框架的已知行为，不是 DUT bug

**修复**：
1. 创建 `try_next_catcher` 类继承 `uvm_report_catcher`
2. 过滤 ID 为 `TRY_NEXT_BLOCKED` 且 severity 为 `UVM_ERROR` 的报告
3. 将其降级为 `UVM_INFO`（不影响功能，只是日志级别）
4. 在 `run_phase` 的 `raise_objection` 后注册 catcher

**关键点**：这不是"掩盖错误"，而是精确过滤一个已知的、非功能性的 UVM 框架竞争。其他所有 UVM_ERROR 不受影响。

**面试官追问"为什么不直接关掉所有 UVM_ERROR"**：那会掩盖真正的 DUT bug。用 `uvm_report_catcher` 只过滤特定 ID（`TRY_NEXT_BLOCKED`），其他错误照常报告。这展示了对 UVM 机制的精确控制。

**面试官追问"为什么 Verilator 没触发这个问题"**：Verilator 的开源 UVM 实现和 Xcelium 的 CDNS-1.1d 在 `try_next_item` 和 `stop_sequences` 的调度顺序略有不同。这是工具实现差异，不是 RTL 差异。

---

### ⭐ Q18: 你怎么保证 Verilator 和 Xcelium 验证的是同一个设计？

**保证措施**：
1. **同一份 RTL**：`rtl/*.sv` 文件完全相同，没有工具相关的 ifdef
2. **同一份 UVM 代码**：`dv/` 目录下的所有文件相同
3. **相同的参数化**：`AXI_DATA_W`、`AXI_ID_W` 等参数一致
4. **相同的测试逻辑**：`crossbar_uvm7_pkg.sv` 中的场景定义和检查逻辑相同

**面试官追问"有没有工具相关的差异"**：有。Xcelium 对 SV 作用域更严格——`w_seqs` 数组在 Verilator 隐式接受，Xcelium 要求显式声明。修复后两工具用同一份代码。

---

### Q19: 你的 Master agent 怎么驱动 AXI 信号？

**Driver 工作流程**（以写事务为例）：
1. 从 sequencer 获取 sequence item（`get_next_item`）
2. 驱动 AW 通道：置 AWVALID=1，等 AWREADY=1，传输完成
3. 驱动 W 通道：按 AWLEN 逐拍发 WDATA，置 WVALID=1，等 WREADY=1
4. 等 B 通道响应：BVALID=1 时置 BREADY=1，检查 BRESP
5. 通知 sequencer 完成（`item_done`）

**面试官追问"VALID 是组合逻辑还是时序逻辑"**：VALID 是时序逻辑（寄存器输出），在时钟上升沿更新。READY 可以是组合逻辑（取决于 READY 信号来源的设计）。

---

### Q20: Slave agent 怎么模拟 Slave 的行为？

**Slave agent 的职责**：
1. 接收 Master 发来的 AW/W/AR 请求
2. 存储写数据（内部有一个 memory model）
3. 返回 B 响应（BRESP=OKAY）
4. 返回 R 数据（从 memory model 读取）
5. 可以注入 backpressure（延迟 READY）

**面试官追问"Slave 的 memory model 怎么实现"**：关联数组（associative array），用地址作为索引。写事务存数据，读事务取数据。这样 scoreboard 可以验证数据完整性——Master 写什么，读回来就应该是什么。

---

## 第五层：常见"愚蠢问题"解答

> 这些是你可能会觉得不好意思问的问题。面试官不会觉得愚蠢，但你不问可能永远不知道。

### Q21: "beat" 和 "transaction" 是什么关系？

一个 **transaction**（事务）= 一次完整的读或写操作。  
一个 **beat**（拍）= 一个时钟周期内的一次数据传输。

一次 burst 事务包含多个 beat。比如 AWLEN=15 的写事务，W 通道有 16 beat（16 个 WDATA 传输），但只有 1 个 transaction（1 个 AWADDR）。

---

### Q22: NBA（Non-Blocking Assignment）是什么？

**<=** 是非阻塞赋值，在时钟沿统一更新。  
**=** 是阻塞赋值，立即更新。

在 RTL 设计中，时序逻辑（always_ff）用 `<=`，组合逻辑（always_comb）用 `=`。

**为什么在 UVM 竞争中提到 NBA**：UVM 的 TLM 通信和 sequence 停止机制在仿真器的时间步中按特定顺序执行。如果 `try_next_item` 和 `stop_sequences` 在同一个时间步（同一 NBA cycle）执行，就会产生竞争。

---

### Q23: "信号置起"是什么意思？

就是把信号拉高（设为1）。比如"AWVALID 置起"就是 AWVALID=1。对应的"撤销"就是拉低（设为0）。

这是硬件人口语，正式说法是"assert"（置起）和"deassert"（撤销）。

---

### Q24: Outstanding 和 pipeline 有什么区别？

**Outstanding**：多个事务同时在途，响应可以乱序返回。  
**Pipeline**：单事务内的多拍数据按顺序流水传输。

一个 AWLEN=7 的 burst 是 8-beat pipeline，但只是一个 outstanding=1 的事务。两个 AW（AWLEN=0）连续发出不等响应是 outstanding=2。

---

### Q25: Master 和 Slave 在 Crossbar 里是什么角色？

- **Master**：发起事务的一方（如 CPU、DMA）  
- **Slave**：响应事务的一方（如内存控制器、外设）  
- **Crossbar**：中间的互连，把 Master 的请求路由到正确的 Slave

在验证环境里，用 **agent 模拟 Master 和 Slave 的行为**——Master agent 驱动信号模拟真实 Master，Slave agent 响应模拟真实 Slave。

---

### Q26: "回压（backpressure）"是什么？

就是接收方用 READY=0 告诉发送方"我现在收不了"。发送方必须等 READY=1 才能完成传输。

在 AXI 里，每个通道都有 VALID/READY 握手。如果 Slave 处理不过来，可以把 BREADY 或 RREADY 拉低，Master 就必须等。这就是 backpressure。

你的场景 3（B_backpressure）和场景 4（R_backpressure）就是测试复位发生时 backpressure 正在生效的情况。

---

## 第六层：简历和项目呈现

### ⭐ Q27: 简历上这个项目怎么写？

**一行版**（适合简历空间有限）：
> AXI4 Crossbar 验证 — 独立设计参数化 5通道 AXI4 互连（4×4, 32/64-bit），使用 UVM 完成 134 次回归验证，包括 6种在途复位场景在 Verilator 和 Cadence Xcelium 双平台 72 次全通过

**两行版**：
> - 设计参数化 5通道 AXI4 Memory-Mapped Crossbar（15个 SV 模块，4×4 配置，32/64-bit）
> - UVM 验证环境搭建 + 6种在途复位场景验证，Verilator/Xcelium 双平台 72/72 通过（UVM_ERROR=0）

**面试官追问"你的贡献是什么"**：全部独立完成。从 RTL 设计到 UVM 环境到工具链搭建。

---

### ⭐ Q28: 面试官说"给我讲讲你的项目"，你怎么用2分钟回答？

"我独立完成了一个 AXI4 Crossbar 的设计和验证。设计是参数化的 SystemVerilog，5通道完整（AW/W/B/AR/R），4×4 配置，支持 32/64 位数据宽度，共15个模块。

验证方面，我搭建了完整的 UVM 环境，包括 Master 和 Slave agent、scoreboard，覆盖了从轻量 TB 到联合并发到在途复位的多层验证，总共134次回归全通过。

最有深度的是在途复位验证。我设计了6种场景，覆盖地址通道在途、数据突发中断、响应回压、混合 outstanding 等不同复位时机。每种场景3个 seed，32和64位各跑一轮，在 Verilator 和 Xcelium 两个平台总共72次全通过，零 UVM 错误，数据完整性零错误。

在 Xcelium 移植时遇到了一个 UVM 框架的时序竞争问题——`TRY_NEXT_BLOCKED`。我通过日志分析定位到是早期复位时 sequence 还在循环导致的 NBA 竞争，用 `uvm_report_catcher` 精确过滤了这个已知工具行为，修复后36/36 全通过。

这个项目展示了我的协议理解、RTL 设计、UVM 方法学和跨工具调试能力。"

---

## 第七层：你可能会被问但还没准备的

### Q29: 你的项目有什么不足？

**诚实回答**：
"目前有几个已知限制：第一，只支持 INCR burst，FIXED 和 WRAP 没实现。第二，代码覆盖率报告还没生成，功能覆盖有但代码覆盖（line/toggle）待补充。第三，没有综合和时序分析结果。第四，exclusive access 等 AXI 扩展功能未支持。

如果时间允许，下一步我会先补覆盖率报告，然后加综合脚本。"

**不要说**："没有不足"——显得没自知之明。

---

### Q30: 如果让你重做，你会做什么不同？

"验证策略上，我会更早引入覆盖率驱动。目前是先写完场景再跑，比较被动。如果重做，我会先定义覆盖率目标，然后针对性写 sequence。

工具链上，我会更早搭建 Xcelium 流程。目前是先在 Verilator 全部完成再移植 Xcelium，遇到了一些兼容问题。如果同时开发，可以更早发现跨工具差异。"

---

### Q31: 这个项目和工业实践有什么差距？

**诚实回答**：
"主要差距在三个层面：第一，规模——工业 Crossbar 可能是 8×8 甚至更大，outstanding 数量更高。第二，验证方法——工业项目通常有 formal 验证、coverage-driven 验证、assertion-based 验证等更完整的流程。第三，物理实现——工业项目需要综合、时序收敛、功耗分析，我只做了 RTL 和功能验证。

但这个项目覆盖了功能验证的核心流程，协议理解和 UVM 方法学的掌握是直接可迁移的。"

---

## 使用指南

### 面试前3天
1. 通读全文，重点标 ⭐ 的必须能脱口而出
2. 对着镜子练习 Q28 的2分钟项目介绍
3. 准备3个你自己的 STAR 故事（TRY_NEXT_BLOCKED 修复、在途复位设计、跨工具兼容）

### 面试前1天
1. 复习第一层（AXI 基础）和第二层（架构）的所有问题
2. 确认能画 AXI 5通道图和 Crossbar 架构图
3. 检查代码仓库可访问

### 面试中
1. 被问住时不要硬撑，说"这个我还没深入研究过，但我的理解是..."
2. 被追问细节时，回到你做过的具体场景举例
3. 被问不足时，诚实说限制但强调学到的经验
