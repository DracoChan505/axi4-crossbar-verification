# 外部 Slave 写通路 agent 规格 v0.1

日期：2026-11-14。状态：用户已确认关键行为及软件接口，并授权逐步实现；第一增量已完成并自检，后续增量待继续。本稿不是测试报告。

用户已确认按本稿逐步实施，工作重心是实现与验证，软件接口知识及面试材料后续补充。本文保留规格讨论来源，最新实施边界见末尾。Master 代码审查不因进入本阶段而自动视为通过。

## 1. 模块定位与本轮交付

这是 SystemVerilog/UVM 测试环境中的外部存储 Slave，不是可综合 RAM，也不是 Crossbar 内部端口模块。

先独立实现一个可复用 agent，单独接收一组 AW/W/B 接口；系统集成时实例化四份，分别接 Crossbar 的四个 M_AXI 端口。Crossbar 的 S_AXI 接外部 Master，M_AXI 接外部 Slave，名称方向以 Crossbar 为参照。

本轮交付配置、事务记录、Driver、字节存储模型、被动 Monitor、agent、独立自检与运行报告。首轮可用已有 Master 驱动，但验收不得只依赖 Master/Slave 相互认可；另有独立预期字节模型及定向激励。不在此阶段实现 Crossbar、arbiter、读通路或故障恢复；这些仍在最终计划中。

## 2. 参数与功能范围

沿用项目已确认内容：

- ADDR_WIDTH=32、DATA_WIDTH=32、STRB_WIDTH=4；支持参数变化。
- INCR，1～256 拍，AWSIZE=0/1/2，合法非对齐、稀疏/全零 WSTRB。
- 四个地址窗口各 64KB：S0 从 0x0000_0000、S1 从 0x0001_0000、S2 从 0x0002_0000、S3 从 0x0003_0000 起。每个实例仅负责自己的窗口，使用绝对地址检查，内部存储索引可减去 base_addr。
- 上游原始 ID 为 2 位；Crossbar 下游 ID 为 4 位。Slave 原样保存完整 AWID 并返回 BID，不解析来源位，不将 ID 当成 Slave 编号。
- AWLOCK/AWCACHE/AWPROT/AWQOS 均接收并记录。首轮合法 profile 与 Master 一致；不以属性传递测试冒充 exclusive、权限或缓存语义验证。
- 不新增 USER/REGION。FIXED/WRAP、exclusive 与其他属性语义属于后续规格，不从最终目标中删掉。

已确认：Slave 的 MAX_OUTSTANDING 默认 4，可配置，容量涵盖 AW 已接收至 B 握手的所有事务，包括等待 W、等待响应延迟、等待 BREADY。它是 Slave 模型自身的容量，与 Crossbar 出口容量分别记账，即使默认都为 4，也不能共用计数。

直接连接 Master 自检时可用 ID_WIDTH=2；Slave 独立测试另跑 ID_WIDTH=4。已有接口目前用全局宽度宏，尚不能同时实例化 2 位与 4 位 ID 接口；Crossbar 集成前必须将接口及相关 virtual interface/类型参数化，并单独回归 Master。不得用截断 ID 或悄悄把所有 ID 改为 4 位代替这项工作。本阶段不借此提前大改 Master。

## 3. 物理接口（相对于外部 Slave）

一份 agent 只连接一组以下信号，三个通道共用时钟和复位。

- 输入：ACLK 1 位、ARESETn 1 位，低有效共同复位。
- AW 输入：AWVALID 1、AWADDR 32、AWID ID_WIDTH、AWLEN 8、AWSIZE 3、AWBURST 2、AWLOCK 1、AWCACHE 4、AWPROT 3、AWQOS 4。
- AW 输出：AWREADY 1。
- W 输入：WVALID 1、WDATA DATA_WIDTH、WSTRB STRB_WIDTH、WLAST 1。
- W 输出：WREADY 1。
- B 输出：BVALID 1、BID ID_WIDTH、BRESP 2。
- B 输入：BREADY 1。

Monitor 全部只读。Driver 是 AWREADY/WREADY/BVALID/BID/BRESP 的唯一正常驱动者。测试配置和内存检查 API 不增加 AXI 引脚。

## 4. 已确认的接收策略与逐周期规则

### 4.1 AW/W 接收

已确认默认不缓存尚无 AW 的 W：只有已接受的 AW 队列中存在尚未收齐数据的事务，才允许 WREADY=1。AWREADY 的生成只依据自身容量和配置背压，不等待 WVALID，避免循环等待。

Master 可以先提出 WVALID 并保持。Slave 等 AW 握手后接收 W，这是允许的接收策略，并非 AXI 要求 WVALID 必须晚于 AW。提前 W 握手能力不作为本阶段默认功能；已有 Master Monitor 的 W-first 关联能力保留，早到 W 的场景仍需验证。

AW 按握手次序入队；每个 W burst 对应最早尚未完成数据接收的 AW。不能因为后来的 AWID 不同就把 W 分给另一笔事务。后一笔 AW 可在前一笔 W 未结束时接收。

当一笔最后 W 完成，下一笔已在 AW 队列中且不配置背压时，可保持 WREADY，下一沿接收下一笔首拍；不必等待前一笔 B。

### 4.2 统一采样与驱动

沿用 Master：上升沿 input #1step 采样，output #0 在该沿后驱动。下面 n 表示采样沿。

- AW 于 n 握手，若此前没有待接收 W，则在 n 后提出 WREADY，最早 n+1 接收对应 W。
- 对应最终 W 于 n 握手，且 AW 已接受，默认 B 延迟为 0：n 后可提出 BVALID，最早 n+1 握手。不能在 n 采样到提前的对应 BVALID。
- 额外响应延迟为 d 时，在最终 W 的 n+d 沿后最早可提出 BVALID；d=0 如上。若 B 输出被其他响应占用或受同 ID 前序阻挡，则继续等待。
- 一旦 BVALID=1 而 BREADY=0，必须保持 BVALID/BID/BRESP，不能重新仲裁替换它。
- 满容量时 AWREADY=0；n 沿 B 握手释放名额后，n 后才可恢复 AWREADY，新 AW 最早 n+1 握手。W/B 继续独立推进。
- 同沿 AW/W/B 先取同一采样快照，再统一更新状态。O_next=O+aw_fire-b_fire；WLAST 不减少 O。

默认无额外 AW/W 背压，B 额外延迟 0。可配置确定性周期背压与带种子的有限随机背压，AW/W 策略独立。周期配置须保证存在放行周期；随机正常测试使用有界等待。测试超时不当作 AXI 协议超时。

### 4.3 两笔例子

A(ID=0) 的 AW 于沿 10 接收，A 的两个 W 于沿 11、12 接收；B(ID=1) 的 AW 可于沿 11 接收。B 的单拍 W 最早沿 13 接收。A 默认响应最早沿 13 握手。

若对 A 注入额外响应延迟，B 可先完成 B 响应；W 仍先 A 后 B。若两笔 ID 相同，B 必须等待 A 的 B 握手。这些时间都以对端 READY 允许且没有其他排队阻挡为前提。

## 5. 响应调度与 ID 顺序

每笔内部记录包含 epoch、接收序号 aw_seq、完整 AWID、地址属性、已收拍数、W 完成周期、响应可用周期及错误策略。内部序号不占引脚。

已确认提供两种测试策略：

- 默认按 AW 次序返回，便于基础波形阅读。
- 可配置跨 ID 调度：从已完成 W、延迟到期、且为该 ID 最早未响应事务的候选中选取。可用按序或带种子的随机候选选择；定向乱序用不同事务延迟确保可复现。

同 ID 顺序检查使用完整下游 ID。不同 Master 的原始 ID 相同，但来源前缀不同，Slave 将其视为不同 ID。B 输出锁定后，直到握手或共同复位才释放。

BID 必须等于该记录完整 AWID。默认 BRESP=OKAY；受控失败返回 SLVERR。EXOKAY 不在非 exclusive 首轮激励中。系统未映射地址的 DECERR 由以后 Crossbar 默认错误目标负责，不由正常 Slave 假装完成全系统译码测试。

## 6. 字节存储与错误语义

### 6.1 正常提交

建议稀疏字节存储，首次未写地址读回 0，仅供测试后门核对。每个合法 W 握手沿即提交该拍有效字节，不等待整个 burst 或 B 完成。

与 Master 规格一致的地址定义：s=2**AWSIZE，q=floor(AWADDR/s)*s。第 0 拍有效范围从 AWADDR 到 q+s-1；第 i>0 拍从 q+i*s 到 q+(i+1)*s-1。DATA 所在总线 word 的起点为该拍起始地址向下按 STRB_WIDTH 对齐；WSTRB[j]=1 时提交 WDATA[8*j +: 8] 到 word_base+j，且 j 必须在本拍允许范围中。

固定验收例：32 位总线、AWADDR=0x1001、AWSIZE=2、两拍，首拍允许 WSTRB=1110，写 0x1001～0x1003；第二拍允许 1111，写 0x1004～0x1007。AWSIZE=1、地址 0x1001 时首拍允许 0010，第二拍对应 0x1002～0x1003，允许 1100。WSTRB 可以是允许掩码的子集，包括全零。

自检预期数据使用独立的字节地址枚举，禁止直接调用 Master allowed_mask 或 Slave 内部写入函数作为判据。测试中还必须覆盖最后字节恰在 0xFFF 的合法 burst 与跨 4KB 的拒绝检查。

### 6.2 失败与非法输入分开

已确认采用拒绝写入模式；具体错误规则建议在 AW 接收时按预设地址范围/接收序号决定并锁定：该笔仍消耗完整合法 W burst，全部字节不提交，最终返回 SLVERR。此为本项目可重复的“拒绝写入”故障模型，不声称所有真实 AXI Slave 的 SLVERR 都保证无部分写入。

合法协议但越出本实例窗口：按同一拒绝写入策略消耗 W 并返回 SLVERR；自检必须显式预期该结果。以后系统测试若错误地路由到这里，即使 Slave 合法返回 SLVERR，系统路由检查仍须失败。

错误 WLAST、越界 WSTRB、协议非法 SIZE/BURST/4KB 请求属于负向协议测试，不悄悄裁剪、缩短或按成功写入。正常运行立即诊断并停止该用例；负向用例仅认可预定错误码，不能因任意崩溃或超时而判通过。当前不承诺对任意非法输入自动恢复。

## 7. 复位、清零与软件 API

普通 reset：取消所有已接收未响应事务，清空 AW/W/B 状态，AWREADY/WREADY/BVALID 置 0，BID/BRESP 输出确定值；不发送取消 B，不自动重放。异步断言清输出，计账仍以统一采样边界为准。

沿上采样 ARESETn=0 时不算握手、不提交内存；此前有效沿已经写入的字节保留，包括中断 burst 的部分写入。释放后从新 epoch 接受新请求，旧响应不能复活。配置、日志及累计覆盖保留。

已确认的软件接口约定：

- cfg：active、base_addr、size_bytes、max_outstanding=4、AW/W 背压参数、B 延迟范围、响应调度模式、seed、错误规则；build 前设置，运行时改变必须在静止边界。
- memory.peek_byte(address)：只读测试后门，不参与 Driver 决策或独立预期计算。
- memory.clear_memory()：仅全环境停发且排空，或共同复位已清控制状态后调用；coordinator 同步清参考存储，完成后才恢复流量。
- agent.idle()：无已接收事务、无待输出 B；不将测试用例尚未提出的任务算进 Slave 状态。

被动模式仅 Monitor 工作，Driver 不驱动，内存模型不冒充真实目标存储内容。外部 Slave 是响应型模型，首版无需为了形式增加 sequencer；响应控制通过配置和预设策略实现。

## 8. Monitor、Scoreboard 与覆盖

Slave Monitor 独立观察引脚，记录 AW、逐拍 W、数据完整、B 首次有效及 B 握手事件，不读取 Driver 私有队列来决定观察事实。事件包含 port、epoch、cycle、aw_seq、完整 ID、地址、拍号、DATA/STRB、响应状态；发布后不修改。

按默认接收策略，W 握手时已有 AW，Monitor 可独立推导逐字节写入意图。Driver 另可发布实际提交诊断事件，但 Scoreboard 不能拿它当唯一预期来源。错误注入计划由测试统一提供独立预期；收到 W 不等于错误注入场景实际写入。

本阶段 Scoreboard 核对独立期望与引脚事件、最终内存、响应数量/时序。系统阶段再把 Master 请求、目标 Slave 观察及参考存储联合起来，证明路由正确。Monitor 单独无法从同一个 BID 看出内部同 ID 响应偷换，定向测试需要独立记录及不同延迟/状态证据。

覆盖目标包含尺寸、长度、非对齐偏移、WSTRB 类型、容量占用、背压、同/不同 ID、响应先后及复位阶段的组合。本机原生 cross 查询/汇总限制仍存在；可用可审计事件计数记录组合命中，但不声称这些等同原生覆盖收敛。保留后续原生覆盖补验任务。

## 9. 文件与实施顺序

预计新增：

- dv/slave/axi_slave_cfg.svh：配置与响应策略。
- dv/slave/axi_slave_record.svh：事务记录与观察事件。
- dv/slave/axi_slave_memory.svh：字节存储及清零/后门。
- dv/slave/axi_slave_driver.svh：接收、提交、响应调度。
- dv/slave/axi_slave_monitor.svh：被动观察与关联。
- dv/slave/axi_slave_agent.svh、axi_slave_pkg.sv：组件与编译组织。
- dv/tests/slave/：独立期望模型、定向/随机/负向用例及 top。
- scripts/run_slave.py、Makefile 入口、测试报告和可复现结果。

复用现有 axi_write_if 的 sink/mon clocking 与稳定性 checker，避免另造重复物理接口。共享类型的提取如必要，只做明确且受回归保护的改动。所有新代码每条语句独立一行、四空格缩进、函数与 begin/end 清楚展开。

规格确认后分三步交付：先配置/记录/存储及单笔 AW/W/B；再补容量、背压和 ID 响应调度；最后完成 Monitor、独立验收、复位和负向回归。每步自检并给用户可读入口，不越过 Slave 范围写 Crossbar。

## 10. 验收清单

每项须记录 seed、参数、工具版本、事件周期、ID、内部观察序号及明确错误码。通过要求零非预期 UVM_ERROR/FATAL、明确完成标志、正确内存/响应/计数和最终排空；复位取消按预期例外记录。

- S01 单拍：字段、一个 B、正确字节；丢失/重复/写错位置失败。
- S02 AW/W 先后：提前 W 被背压，AW 不等 W；无额外背压时有限时间完成；死锁或无 AW 接收 W 失败。
- S03 burst/字节：1/2/4 字节、1/2/16/256 拍、非对齐、稀疏/全零掩码、word/4KB 边界；任一多写/少写/地址偏移失败。
- S04 容量：到 4 后阻止第五笔 AW，W/B 继续；B 握手后下一沿可恢复，任何超限/提前释放失败。此项需独立允许至少 5 笔提交的激励，不能用默认 Master 两笔上限虚称测到 4。
- S05 B 时序：最终 W 前无 B，延迟 0/1/多周期边界准确，BREADY=0 时保持；早返回、改变负载或等 BREADY 才首次产生 B 失败。
- S06 ID：同 ID 多笔保序、不同 ID 实际产生乱序，4 位 ID 全值回传；截断来源位或绕过同 ID 前序失败。
- S07 同周期：旧 B、新 AW、另一笔 W 同沿，各队列/计数一致；覆盖更新丢失、复用过早或错误关联失败。
- S08 错误响应：拒绝写入返回 SLVERR、完整消耗 W、内存不变；错误吞没、部分偷写或不释放容量失败。
- S09 普通复位：空闲、AW 后、W 中、B 延迟中、BVALID 被阻挡时复位；已提交字节保留，旧任务不复活；复位沿提交或清空历史内存失败。
- S10 独立清零：静止/复位隔离期同步清零，活跃状态调用须拒绝；不同步或并发写入竞争失败。
- S11 Monitor 独立性：被动模式不驱动；握手记录与独立激励一致；故障注入验证早 B、稳定性、WLAST、WSTRB、ID 错误的检查能力，标明检测职责与可观测限制。
- S12 参数/随机：精选 DATA_WIDTH=32/64、ID_WIDTH=2/4、容量=1/2/4，固定种子混合流量；非法配置须有诊断。参数通过不外推全组合。

## 11. 审查焦点与依据

已逐项确认第 4.1 节 AW 后接收 W、第 5 节按序/跨 ID 乱序两种模式（默认按序）、第 6.2 节拒绝写入时完整接收 W、不修改内存、返回 SLVERR。Slave 自身默认容量 4、可配置也已确认。软件接口约定随后也已确认，用户授权先实现基础增量，再逐步补全；正常模式无额外延迟作为常规默认配置。

依据：Arm IHI 0022H 的 AXI4 条款（A2 信号、A3 通道依赖及字节、A5 ID），沿用 Master 已审规格；本稿容量、调度、内存提交和错误策略为项目选择。

- [Arm IHI 0022H 官方 PDF](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)
- [verilog-axi axi_ram.v](https://github.com/alexforencich/verilog-axi/blob/master/rtl/axi_ram.v)：仅参考握手、字节写使能和保持响应的组织。本次未复制代码、未锁定提交；该 RAM 不替代本项目多事务/乱序 UVM 模型的验证要求。

## 12. 2026-11-14 实施授权与第一增量

用户确认软件接口先按规格落实，优先实现，具体知识后续补充。先交付配置、事务记录、字节存储和单笔写入闭环，再由用户查看；不是一次完成全部 Slave 功能。

已新增 dv/slave 的配置、记录、存储、按序 Driver 和编译包，及 dv/tests/slave 的直接引脚自检。Driver 从初版保留容量队列，但完整并发验证、跨 ID 调度、AW/W 可配置背压、Monitor 和 agent 封装仍待后续增量。最新阅读入口见 [第一增量指南](slave-stage1-review.md)，实际测试结论以第一增量报告为准。

### 2026-11-15 已实现功能补验

容量边界、同 ID 多笔、AW/W/B 同拍事件、额外复位阶段、活跃/复位隔离清零、单拍字节组合及 Master 直连已有补充证据。60 次运行达到预期，另两项隔离故障被冻结 TB 检出。完整状态以 [验收报告](slave-acceptance-report.md) 为准；第 12 节的“待验证”描述保留为第一增量历史状态，未实现功能仍待后续增量。

### 2026-11-15 第二增量实现

已实现跨 ID 响应调度（同 ID 保序、B 背压锁定）、AW/W 独立周期或随机背压，以及每笔/随机 B 延迟。默认仍按序且无额外背压。具体配置字段、周期边界和复位语义见 [第二增量说明](slave-stage2-report.md)。独立 Monitor/agent 封装尚未实现；当前引脚观察代码在自检 TB 中。
