# Master 验证模型模块规格 v0.4

更新：2026-11-12。状态：用户已授权按本机优先方案实现，首轮 Master agent 已完成并通过报告列出的自检，等待用户代码审查。前文保留需求与讨论来源；最新实现与验收状态见第 17 节。

## 1. 定位与边界

这里的 Master 是测试环境中的外部 AXI Master，不是芯片用的可综合 Master RTL，也不是 Crossbar 内部的 S_AXI 处理模块。

最终配置实例化 4 个 Master agent，各连接 Crossbar 的一个 S_AXI。首阶段只处理 AW/W/B；AR/R 后续添加。每个 agent 组织事务产生、Driver、Monitor、配置；协议检查器观察接口，Scoreboard 独立判断正确性。

本模块交付：事务类型、接口定义、Driver、Monitor、agent、配置和模块自检。整体 Crossbar、正式 Slave agent、系统级 Scoreboard 不在本模块实现范围内，但自检要有独立可控的响应支架和结果检查。

## 2. 配置与事务能力

已确认：

- ADDR_WIDTH=32，DATA_WIDTH=32，STRB_WIDTH=DATA_WIDTH/8=4。
- ID_WIDTH=2；原始 ID=0/1/2/3。默认根据目标 Slave 编号选择，测试可显式覆盖。
- MAX_OUTSTANDING=2，参数化。ID 数量与 outstanding 上限独立。
- 单拍和 1～256 拍 INCR 写；AWSIZE=0/1/2，分别表示每拍 1/2/4 字节。
- 合法非对齐地址及合法 WSTRB；不能把非对齐每拍机械视为相同有效字节位置。
- 两笔可同 ID、也可不同 ID；同 ID 完成有序，不同 ID 可乱序。
- 可控 AW/W 初始延迟、W 拍间隔和 BREADY 背压。延迟配置是测试行为，不是新的 AXI 信号。
- 能产生 W 早于 AW、AW 早于 W、同周期出现的场景。

默认合法激励必须符合 4KB 边界、传输尺寸与字节位置规则。非法协议激励若将来加入，必须是显式负向测试，不混入默认随机流量。未映射地址可属于合法 AXI 请求，应与协议非法请求区分。

## 3. 物理接口清单

方向均相对于外部 Master；连接对象为 Crossbar S_AXI。采样/驱动约定及工具兼容性门槛见第 13 节，禁止测试台与 DUT 在同一采样沿竞争。

### 时钟复位

- `ACLK`：输入，1 位，共同时钟。
- `ARESETn`：输入，1 位，低有效共同复位。复位释放与时钟关系按协议落实。

### AW 输出（Master → Crossbar）

- `AWVALID`：1 位，地址及属性有效。
- `AWADDR`：ADDR_WIDTH，起始地址。
- `AWID`：ID_WIDTH，事务 ID。
- `AWLEN`：8 位，拍数减一。
- `AWSIZE`：3 位，每拍字节数的编码。
- `AWBURST`：2 位，当前 INCR 为 01。
- `AWLOCK`：1 位，exclusive 属性；首阶段默认建议及后续功能边界见第 12 节。
- `AWCACHE`：4 位，内存属性；首阶段默认建议及激励范围见第 12 节。
- `AWPROT`：3 位，访问保护属性；首阶段默认建议及激励范围见第 12 节。
- `AWQOS`：4 位，服务质量属性；可配置，首阶段不据此改变轮询仲裁。

### AW 输入（Crossbar → Master）

- `AWREADY`：1 位，地址接收许可。

### W 输出（Master → Crossbar）

- `WVALID`：1 位，当前数据拍有效。
- `WDATA`：DATA_WIDTH，写数据。
- `WSTRB`：STRB_WIDTH，逐字节写使能。
- `WLAST`：1 位，最后一拍。

### W 输入（Crossbar → Master）

- `WREADY`：1 位，当前数据拍接收许可。

AXI4 不提供 WID。W 关联依靠写事务顺序。

### B 输入（Crossbar → Master）

- `BVALID`：1 位，响应有效。
- `BID`：ID_WIDTH，对应事务的原始 AWID。
- `BRESP`：2 位，响应状态。

### B 输出（Master → Crossbar）

- `BREADY`：1 位，响应接收许可。

同一接口上的对应 AWID/BID 必须相等。Master 不处理 Crossbar 下游新增的来源位。

已确认：首阶段不启用 AWUSER/WUSER/BUSER 和 AWREGION，不在当前 Master 写接口中声明或激励这些可选信号。最终是否加入按具体用途另行决定；其他已列出的信号全部保留。

## 4. 测试用例的软件接口

UVM sequence item 拟包含：起始地址、ID、LEN/SIZE/BURST、AW 属性、逐拍 DATA/STRB、AW/W 起始延迟、W 拍间隔。最终字段名待实现规格完成后统一。

BREADY 策略由独立响应控制提供，不与当前 AW/W worker 的阻塞状态绑定。正常默认 BREADY=1，背压测试可暂时置 0，复位期间置 0。事务对象进入 Driver 的待发送队列不代表 AW 已被接收。

提交与完成通知分离：Driver 保存事务独立副本后报告已接管，允许测试继续提交；对应 B 握手后报告实际完成及 BRESP。每笔任务有内部唯一编号（不占 AXI 引脚，不替代 AWID），以区分重复 ID 的事务。

Monitor 通过 analysis port 发布观察事件。具体事件类型采用独立 AW/W/B 记录和重建事务视图，最终类型与 Scoreboard 接口协同确认。事件对象不能被后续采样覆盖或复用修改。

## 5. 时序与事务生命周期

### 5.1 握手与稳定性

在有效时钟采样沿，VALID 与 READY 同时为 1 才算传输。AW/W VALID 一旦置位，在握手前保持 VALID 和该通道全部负载。允许在尚未提出下一拍前插入间隔，不允许撤回正在等待的有效拍。

### 5.2 待发送、内部预留、outstanding

三个概念分开：

1. 待发送：测试用例提交，但尚未获得发送名额。
2. 内部预留：事务被调度给 AW/W worker，可能先出现 W，但 AW 尚未握手。
3. Outstanding：AW 已握手，B 尚未握手。

AW 握手只将预留转为 outstanding，不重复占名额。预留与 outstanding 的合计限制为 MAX_OUTSTANDING，防止已满两笔时又提前发送第三笔 W。Monitor 的 outstanding 统计仍只以实际 AW/B 握手为准。

待发送队列不计入 outstanding。待发送队列建议深度为 2，独立于两个活跃名额，接口语义见第 11 节；接管任务与 B 完成的通知已明确分离。

### 5.3 AW 与 W 的独立发送

两个 worker 共用一致的事务顺序。AW 顺序为 A→B 时，W 按 A 的所有拍→B 的所有拍，不能 interleave。B 的 AW 可在 A 的 W 完成前握手，但 B 的第一拍 W 只能在 A 的最后一拍 W 握手后提出；不能把尚未握手的 A.WLAST 当成完成。不要求等 A 的 B 响应后才能发送 B 的 AW/W。

AW 不等待 WREADY 才提出；W 也不能因等待 AWREADY 而无法产生 W-first 测试。Crossbar 若需要先获得 AW，可以对提前的 W 背压。

W 可以先于 AW 握手或先出现于接口；是否实际握手由接收端决定。针对正式 Crossbar 的 W-first 用例不能误要求它必须在 AW 前接收 W。

### 5.4 响应匹配与完成

响应接收独立运行。BID 匹配该 ID 的最早未完成事务。不同 ID 可乱序，重复 ID 不能乱序匹配。

- WVALID && WREADY && WLAST：数据发送完成，不释放 outstanding。
- BVALID && BREADY：事务完成，释放 outstanding。
- BRESP 为错误仍完成事务并释放名额；错误状态保留供测试检查。
- 不存在对应事务的 B、重复响应、早于必要请求/数据完成的响应应由检查器报告，不能靠自动丢弃掩盖。

例：先发 A(ID=0)、再发 B(ID=1)，W 仍先 A 后 B；B(ID=1) 可先于 B(ID=0) 完成。若两笔 ID 都为 0，则按请求顺序完成。

### 5.5 同周期事件

一个采样沿可能同时发生 AW/W/B 握手，计数按事件共同更新，避免覆盖式加减。

已确认采用保守调度：名额满时，在采样沿 N 观察到 B 握手并释放名额后，才允许调度下一事务、提出新 AW；最早在采样沿 N+1 完成新 AW 握手。不通过当前 B 信号提前复用名额。后续吞吐分析必须区分 Driver 引入的等待与 Crossbar 自身限制。

### 5.6 复位

普通 reset 是事务与控制状态复位，不擦除存储内容。基础阶段为全系统共同复位：

- Driver 清空待发送任务、内部预留、outstanding、AW/W 当前状态和响应匹配记录；AWVALID/WVALID 无效，BREADY=0。
- Monitor 清空未完成的 AW/W/B 关联记录。
- Scoreboard 清空待检查事务、预期响应等运行状态，但保留参考存储内容。
- 测试控制统一终止本轮 sequence 和等待，复位后从新任务重新开始；不逐笔发取消响应，不自动重发旧任务。
- 复位前后任务须隔离，内部编号采用不重复编号或带运行轮次信息，避免旧通知匹配新任务。
- 地址映射等配置、既有错误日志与累计覆盖率保留，不能用复位清掉历史失败。

Slave 模拟存储器保留复位前已经实际提交的字节，包括中途中断 burst 中已写入的部分；未写入的数据不能凭旧预期补写。参考存储器需依据 Slave 侧实际写入事件同步更新，而非仅凭 Master AW 或整笔 B 完成更新。这一跨模块约定在 Slave/Scoreboard 规格中细化；复位采样边界统一采用第 13 节规则。参考模型不能直接复制 Slave 的存储结果作为预期：需先独立比对上游预期与下游实际路由/字节内容，再按下游实际接收时刻提交正确预期字节，避免把路由或数据错误同步进参考模型而掩盖错误。

另设独立的测试环境“存储清零”操作，不接入普通 ARESETn，也不是 Crossbar 擦除外部存储器的硬件功能。仅在停发并排空事务后，或共同复位期间控制状态已清理后执行；同时清零 Slave 模拟存储器与 Scoreboard 参考存储器，防止与写入并发竞争。首次测试的初始化可调用此操作。API 名称待实现时确定。

## 6. Monitor 与检查职责

每个 Master 接口一个被动 Monitor，不驱动信号，不读取 Driver 私有计数作为事实。

- AW 握手：采样完整地址和属性，建立事务顺序记录。
- W 握手：采样 DATA/STRB/LAST，累积 burst 并按顺序关联 AW。
- B 握手：采样 ID/RESP，标记对应事务完成。
- 即使接收端允许 W 先握手，也能分别保存 AW/W 记录后再关联；不能写死必须 AW 先被观察。
- 监测数据完成与响应完成两个不同事件。

协议检查器还要观察未握手周期：稳定性不能仅通过握手日志检查。检查包含 AW/W 负载保持、WLAST/拍数、合法字节使能、响应时机和 ID 关联等。具体 SVA 与过程式检查划分依工具支持确定。

Master Monitor 证明入口收到了什么和返回了什么；不能单独证明 Crossbar 送到了正确 Slave。系统级路由检查需要后续 Slave Monitor 与独立 Scoreboard。

## 7. 文件职责（原规划与实际对应）

实际代码位于 `dv/` 下。sequencer 使用 UVM 标准泛型类，没有单独增加无行为子类；其余文件按以下职责组织。

```text
dv/interfaces/axi_write_if.sv          AW/W/B 信号及采样驱动接口
dv/master/axi_master_cfg.svh           agent 与激励配置
dv/master/axi_write_item.svh           写事务对象
（在 agent 内）uvm_sequencer          sequence 与 Driver 连接
dv/master/axi_master_driver.svh        调度、AW/W worker、B 接收
dv/master/axi_master_monitor.svh       被动采样与事务关联
dv/master/axi_master_agent.svh         agent 组件连接
dv/master/axi_master_pkg.sv            类定义编译组织
dv/checkers/axi_write_checker.sv       独立接口协议检查
dv/tests/master/                       自检测试及必要响应支架
```

文件拆分可按可读性调整，不能因此改变职责或扩大本轮实现范围。共享接口与包需防止编译循环依赖。

## 8. 验收清单

以下为原定验收清单；已执行的具体用例和边界见 master-test-report.md，不把系统级未完成部分视为通过。每个测试需有明确失败条件、可复现配置和日志，不以“仿真结束”代替通过。

- M01：单笔单拍写，核对 AW/W/B 字段、握手次数和最终计数。
- M02：AW-first、W-first、同周期提出；分别改变 AWREADY/WREADY，检查无错误依赖或死锁。
- M03：AW/W 等待时保持全部负载；W 拍间隔可控。
- M04：1、2、4 字节尺寸，典型/最大 burst 长度，合法非对齐及字节使能；由独立算法核对预期字节更新。
- M05：两笔 outstanding 达上限后，不再超额启动；W/B 继续推进；B 完成后恢复。
- M06：不同 ID 的 B 按序与乱序返回，匹配正确事务。
- M07：同 ID 连续两笔，按序匹配；WLAST 不提前释放名额。
- M08：BVALID 等待 BREADY 时不释放，握手时释放；错误 BRESP 同样释放并保留状态。
- M09：同周期 AW/W/B 事件、容量边界以及连续事务，计数和队列不溢出/下溢。
- M10：空闲、仅 AW 已接收、W 传输中、B 等待期间共同复位；任务取消、等待终止、无陈旧记录污染；已实际写入内容保留，未写入部分不凭空修改。
- M11：Monitor 与独立支架的事件记录一致，不依赖 Driver 内部状态；用显式错误注入验证检查器能报告错误，不能把预期报告算成 DUT 缺陷。
- M12：非默认合法参数配置的编译与基础运行；具体参数矩阵在接口参数约束确定后列出。

- M13：独立存储清零操作与普通 reset 分开验证；模型与参考存储器同步清零，正常 reset 不清零。Master 自检先用必要支架检查控制行为，完整存储一致性在 Slave/系统集成阶段验收。

### 自检执行顺序

1. 基础单笔：M01，先确认接管与完成通知、信号及计数。
2. 数据与时序：M02、M03、M04，覆盖 AW/W 先后、稳定性、尺寸、长度与非对齐。
3. 并发与响应：M05、M06、M07、M09，检查两笔名额、同/不同 ID、下一周期再启动。
4. 背压与响应状态：M08，并组合 AW/W 等待场景。
5. 复位与独立清零：M10、M13，核对取消、保留和清零三种不同效果。
6. 检查器有效性与参数配置：M11、M12，再运行固定种子的组合回归。

各组单独记录预期结果、实际结果和失败信息；本清单不是已执行报告。

所有随机用例记录 seed；有界测试超时用来判定测试没有结束，不冒充 AXI4 的协议超时规定。正式 Slave fault timeout 属于后续功能。

## 9. 审查状态与实现前门槛

本稿明确以下协议实现规则：AW/W 顺序配对、逐字节参考算法、BVALID 的前置条件、复位采样优先级、负向测试与日志要求。之前已确认的功能不重新投票。

新增常规实现建议（待整稿审查，不代表用户逐项批准）：PENDING_DEPTH=2、属性默认配置、事件类型/通知接口、clocking block 时序约定。具体数值与边界见后文。USER/REGION 已确认首阶段不启用，最终范围按具体用途另行决定。

编码前需要：整稿审查、工具对本稿所需 SV/UVM 特性的兼容性验证；首阶段可选端口范围已定案。只建立必要兼容性用例，不借此实施 Master 或 Crossbar。之后实现范围仍仅限 Master 与必要自检支架，交付代码、命令、结果及限制后由用户审查。

## 10. AW/W 关联与非对齐字节规则

### 10.1 Driver 与 Monitor 的顺序契约

Driver 为任务分配稳定的发送顺序号；AW worker、W worker 均遍历这一顺序，不能各自仲裁。提前提出或握手的 W 只能属于该顺序中下一笔尚未完成 W 的事务。不同 ID 也不能 W 交错。

Monitor 完全根据接口采样建立两条独立队列：

- AW 队列：每个实际 AW 握手分配 `aw_seq`，保存全部字段和采样周期。
- W 队列：每个实际 W 握手保存 beat；WLAST 握手封闭当前 burst，分配 `w_seq`。
- 第 k 个 AW 关联第 k 个 W burst。任一方可以提前，均缓存等待；AW 已到时可边接收 W 边检查，无需等整个 burst。
- 关联记录必须保留到 B 完成；数据接收队列与按 ID 的响应待完成队列不是同一个释放时刻。
- 未到 AW 时最多先缓存合法 burst 的 256 拍；超过上限/配置观察容量、超时缺 AW/WLAST 时明确报错，不能静默丢弃或无限增长。故障后结束该负向用例或共同复位，不通过跳队列“修复”记录。
- 有 AW 时逐拍核对期望最后一拍。提前 WLAST、期望末拍缺 WLAST、额外 beat 都报错。不能依据错误 WLAST 重新划分而宣告通过。

Monitor 无法仅凭相同内容的无 ID W 信号证明发送者内部把两笔数据交换过；须把实际数据与 sequence 的独立预期记录比较。Monitor 自身不读 Driver 私有状态。

### 10.2 Driver 的 lane 算法（INCR，零起始拍号 i）

定义：`D=DATA_WIDTH/8`，`S=2**AWSIZE`，`L=AWLEN+1`，`A=AWADDR`，`Q=floor(A/S) x S`。

配置约束：D 为 2 的幂；1 <= S <= D；1 <= L <= 256。地址运算使用额外进位位，拒绝地址宽度溢出，不能先截断再检查。

- i=0：`addr=A`；其余拍：`addr=Q+i x S`。
- `word_base=floor(addr/D) x D`。
- 首拍允许地址区间为 `[A,Q+S-1]`；后续拍为 `[addr,addr+S-1]`。
- byte lane j 对应地址 `word_base+j`，数据位为 `WDATA[8*j +: 8]`。
- 允许掩码 M 的第 j 位当且仅当上述地址在允许区间内置 1。
- 合法条件：`WSTRB & ~M == 0`（只在 D 位内求补）。允许 M 的任意子集，包括全 0；默认完整写取 WSTRB=M，稀疏写用例显式选择子集。
- 未使能 lane 的数据不参与存储比较；Driver 可固定为 0 便于读波形，但在 WVALID 等待期间仍须保持整个 WDATA 稳定。
- 尾字节 `E=Q+L x S-1`。检查 `floor(A/4096)==floor(E/4096)`，不跨 4KB；不能靠清除末拍 WSTRB 使本来跨界的 burst 合法。

以上计算不是对非对齐起始地址每拍直接累加 S；只有第一拍非对齐，后续拍从对齐基址推进。

### 10.3 独立参考模型：按绝对字节地址枚举

参考模型不调用 Driver 的 lane/mask helper。对每拍枚举其传输尺寸块内的绝对字节地址：起点为 Q+i x S、终点不含 Q+(i+1) x S；首拍跳过小于 A 的地址。将保留地址分别映射到总线字节位置，检查实际 WSTRB 未选择集合外的 lane。

在实际 W 握手时，只对实际 WSTRB=1 的字节形成 `(绝对地址, byte值)` 更新事件；WSTRB=0 的位置保持原值。用独立 sequence 预期字节核对 Driver 输出，自检不能直接把 Driver 已排好的 WDATA 当唯一正确答案。两套算法共享协议定义但不共享实现函数，并使用下面的手工固定期望作为第三层检查。

### 10.4 固定例子（最大允许掩码，不要求所有合法测试都写满）

32-bit 总线，lane0 为 WDATA[7:0]，掩码按 bit3..bit0 书写。

- A=0x1001，SIZE=0，L=4：每拍地址为 1001、1002、1003、1004；掩码依次 0010、0100、1000、0001。每拍一个字节，跨 word 后回到 lane0。
- A=0x1001，SIZE=1，L=3：首拍仅 1001/lane1，M=0010；第二拍 1002..1003/lane2..3，M=1100；第三拍 1004..1005/lane0..1，M=0011。
- A=0x1001，SIZE=2，L=2：首拍 1001..1003/lane1..3，M=1110；第二拍 1004..1007/lane0..3，M=1111。最多写 7 字节。
- A=0x1003，SIZE=1，L=2：1003/lane3，M=1000；然后 1004..1005/lane0..1，M=0011。
- 4KB 边界合法：A=0x0FFD，SIZE=2，L=1，E=0x0FFF，M=1110。
- 4KB 边界合法：A=0x0FFA，SIZE=1，L=3，E=0x0FFF；三个掩码 1100、0011、1100。
- 4KB 边界非法：A=0x0FFD，SIZE=2，L=2，E=0x1003。合法生成器拒绝；显式负向测试应报告越界，不能进入正常通过用例。

## 11. Driver 接口、计数与响应检查

### 11.1 接管与容量（新增实现建议）

`PENDING_DEPTH=2`，独立于 `MAX_OUTSTANDING=2`。前者仅限制尚未调度的 Driver 队列；当前最多 2 笔排队、2 笔预留或在途。测试场景总长度不受此值限制。

队列有空位时，Driver 才获取下一个 sequence item；深拷贝并成功入队后调用 `item_done()`，表示已接管，不表示 AXI 完成。不发 item_done 直到能保存任务；满时提交方等待，不丢任务、不覆盖。只允许一个获取过程，不对一个请求重复 item_done。

每笔保存 UVM sequence/transaction 路由信息和内部 `(epoch, task_uid)`。B 握手后，经 response 通知独立消费者一次完成结果。测试方在继续发送的同时持续处理 responses，不能因默认 UVM response queue 未及时消费而溢出；具体采用 response handler/独立收集线程，不能靠无限队列掩盖问题。

共享复位由 coordinator 统一终止 sequence、worker 和旧等待；清理 response 队列并切换 epoch 后再重启。仅清空 Driver 数组不足以取消 sequencer 中阻塞的请求。

### 11.2 原子状态更新

以时钟沿 n 前的状态和同一份采样快照计算事件，然后统一提交：

- `aw_fire`、`w_fire`、`b_fire` 分别表示本沿实际握手；`b_retire` 仅在响应匹配和时机合法时为 1。
- `O_next = O + aw_fire - b_retire`；非法 B 直接报告失败，不允许计数下溢后继续算通过。
- `R_next = R - aw_fire + new_reservation`；AW 握手将同一任务由 R 移到 O。
- 调度只使用周期开始时的空闲名额，不能使用本沿 B 新释放的名额来构成本沿 AW；本沿后才可预留并驱动，最早 n+1 握手。实现须区分“本沿事件”与“本沿后调度”，避免公式中的 new_reservation 被误当成同沿传输。
- `0<=R+O<=MAX_OUTSTANDING`，`0<=pending<=PENDING_DEPTH`。队列顺序/ID 表/名额由一个协调更新过程拥有，worker 用事件请求更新，避免多个线程分别加减覆盖。

W 完成只更新数据完成状态，不改变 R+O。AW/W 可以在同沿完成不同或同一任务的对应阶段，但 B 前置条件必须使用前态，不能用本沿刚采到的 AW/W 使过早 B 合法。

### 11.3 周期级 B 判定

对每个采样沿 n，凡 BVALID=1（即使 BREADY=0），在该沿之前的已记录状态中必须存在 BID 对应的最早未完成 AW，且对应 W 已按 AWLEN 完整握手并正确结束。

若该事务 AW 或最终 W 恰在沿 n 握手，本沿采样到的 BVALID 不能依靠这次握手获得合法性：报 EARLY_B。合法最早情况是在最后必要握手沿 n 之后提出 BVALID，于沿 n+1 被采样/握手。B 与另一笔事务的最终 W 同沿发生不受此限制，按各自记录判断。

- `B_NO_PENDING`：BVALID 时没有对应 ID 的已接收未完成 AW；不能等到 BREADY 再检查。
- `EARLY_B`：有 AW，但其数据在前态未完整握手，或当前 B 先于对应 AW 接收。
- `B_STABILITY`：BVALID && !BREADY 后的有效响应被撤回或 BID/BRESP 改变（复位例外）。
- `DUPLICATE_B`：已完成且没有新的匹配任务又返回响应，可归类无待完成响应；记录历史帮助诊断。
- `W_LENGTH/WLAST`：数据拍数不符或结束位置不合法；不能把错误 WLAST 当成有效数据完成。

可观测性限制：同 ID 有多笔在途时，B 不带地址或唯一序号。仅靠 Master 接口无法证明某个“合法位置的 B”其实是重复或内部调换；Monitor 只能按 ID 队头解释。自检响应支架和系统 Slave Scoreboard 必须另存独立事务记录才能识别此类错误。不能宣称 Master checker 单独检测所有同 ID 调换或重复。

## 12. 默认属性与后续功能边界（实现建议）

首阶段默认 profile：AWBURST=01(INCR)、AWLOCK=0、AWCACHE=0010、AWPROT=010、AWQOS=0000。CACHE 选择 Normal Non-cacheable Non-bufferable；PROT 为普通、非安全、数据访问。默认合法场景不产生 FIXED/WRAP、exclusive 或缓存语义压力测试，这些是后续功能规格，不从最终目标中删除。

首阶段保留这些字段，Driver 检查等待期间稳定，系统检查端到端传递；非缓冲默认 profile 的写响应来自最终目标，不在 Crossbar 中凭 AW 接收提前构造成功响应。QOS 首阶段不改变已确定的轮询策略。不能把“传递正确”声称为缓存、权限隔离、exclusive 或 QoS 功能已验证。

已确认首阶段不启用 AWUSER/WUSER/BUSER 和 AWREGION。当前每个 Slave 一段映射，无 REGION 使用需求，也无自定义 USER 负载需求。最终是否加入按具体用途决定，不将其永久排除。

## 13. 仿真、采样与复位边界

### 13.1 本地核查结果（2026-11-12，只读检查）

- 实际执行 `/Users/shiyutian/Desktop/Projects/验证/local-uvm/tools/verilator-5.052/bin/verilator --version`：Verilator 5.052，构建标记 built20261026。它不在默认 PATH，不能再称本机没有 Verilator。
- 本地库 `/Users/shiyutian/Desktop/Projects/验证/local-uvm/third_party/1800.2-2020.3.2`：README 标明 Accellera UVM 2020.3.2 / IEEE 1800.2-2020。
- 建议源语言约束为 SystemVerilog IEEE 1800-2017，时间单位 1ns、精度 1ps。编译入口应显式记录语言和工具版本，不能仅凭扩展名声称兼容。
- 既有 local-uvm README 记录了简单示例测试；本轮没有重跑，更没有证明 AXI agent、clocking block、SVA 或功能覆盖已通过。
- 编码前兼容性门槛：clocking input #1step/output #0、virtual interface、并发 worker/复位终止、response handler、所用 SVA 和 covergroup 分别有最小检查结果。若不支持，报告替代方案或使用兼容仿真器，不静默删除检查与覆盖。

### 13.2 统一时序约定（实现建议）

所有功能事件以 ACLK 上升沿编号。Driver/Monitor 使用 input #1step 的 clocking 采样快照；Driver output #0 在该沿采样后驱动，供后续上升沿接收，不与 DUT Active-region 采样竞争。checker 使用相同的沿前语义，不能在 NBA 后读原始信号再解释为本沿事件。自检 Slave 支架遵循相同规则。

复位控制器在下降沿改变 ARESETn，保证下个上升沿之前稳定；释放在上升沿之后同步驱动，下一上升沿开始正常采样。合法测试禁止在上升沿 Active 区直接改变复位。

复位优先于本沿握手：采样到 ARESETn=0 时，本沿不计 AW/W/B 事件、不提交存储字节，只执行清理；采样为 1 且复位尚未发生时正常记账。已在前一个有效沿提交的字节保留。异步复位断言取消 worker/有效输出，采样计账仍遵守统一边界；故意在采样边界制造 delta-cycle 竞争不属于合法功能测试。

独立 `clear_memory()`（建议 API 名）由 coordinator 仅在静止状态或复位隔离期调用；同时处理模拟存储和参考存储，操作完成后才恢复流量。不为这个测试操作添加 AXI 引脚。

## 14. 验收失败条件与日志契约

通用日志字段：test、seed、工具版本、配置、epoch、agent/port、cycle、event、AWID/BID、aw_seq、w_seq、beat_index、AW 握手周期、最终 W 握手周期、B 首次有效/握手周期、O/R/pending 前后值、checker_code。Driver 日志含 task_uid；被动 Monitor 的未知 task_uid 为空，用独立观察序号关联，不伪造内部可见性。

每项预期通过均要求零非预期 ERROR/FATAL、完成标记、预期事件数量及空队列检查（复位取消除外）。进程退出 0 不足以通过。负向测试需要指定预期 checker_code 和触发点；崩溃、超时、其他错误或未命中指定错误均不算通过。

- M01 失败：字段/数据不符，握手缺失或重复，接管与完成混淆，最终 O/R 非零。重点日志 task_uid、三类握手周期。
- M02 失败：顺序错、W burst 交错、错误等待依赖、在允许进展的支架场景不结束。记录 aw_seq/w_seq 与 VALID/READY 时间线。
- M03 失败：等待期间任一负载变化、有效信号撤回；记录前后负载与通道。
- M04 失败：允许掩码/实际字节更新不符、WSTRB 越界、4KB 越界被合法生成器接受；记录绝对地址、lane、mask、旧/新字节。固定例子逐个有断言期望。
- M05 失败：R+O 超限、任务覆盖/丢失、满后 W/B 被一起停住，释放后在规定有限支架延迟下不恢复；记录队列与名额变化。
- M06 失败：不同 BID 匹配错任务、乱序响应导致误报/丢完成；记录响应的独立支架来源与 Driver 任务映射。
- M07 失败：同 ID 队列次序错误，WLAST 提前释放；内部调换需独立支架证据，不能仅靠相同 BID 推断。
- M08 失败：BVALID 等待时提前释放、B 负载改变、错误 BRESP 未完成或未记录；记录首次有效到握手期间的响应快照。
- M09 失败：计数覆盖/下溢，满容量提前在本沿接收新 AW，EARLY_B 漏报，合法“旧 B 与新 W 同沿”误报；保留完整前态/事件/后态。
- M10 失败：旧等待未终止、旧通知进入新 epoch、复位沿计入握手、已提交字节丢失或未提交字节被补写；记录 reset 时间、epoch 和提交地址。
- M11 失败：漏报指定注入错误、合法流量误报、依赖 Driver 私有状态；包括无待处理 B、过早 B、B 稳定性、错误 WLAST 的定向负向测试。
- M12 失败：合法参数编译/运行失败或非法配置无诊断。建议矩阵为 DATA_WIDTH=32/64、ID_WIDTH=1/2/3、MAX_OUTSTANDING=1/2/4 的精选组合；不宣称全组合覆盖。
- M13 失败：普通 reset 擦除内存、独立 clear 未同步、清零与活跃写入竞态；Master 支架验收与后续系统验收分别报告。

## 15. 规范依据与本稿边界

Arm IHI 0022H：A3.3 的写响应依赖、A3.4 的地址/字节位置、A4 的内存属性、A5 的事务标识。采用 AXI4 适用条款，不把 AXI3 WID 或 AXI5 扩展带入本阶段。

- [Arm 官方规范 PDF](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)
- [Arm 对非对齐 INCR 后续地址的解释](https://community.arm.com/forums/f/soc-design-and-simulation-forum/10300/axi-burst-size-meaning)

上文算法和检查方案是本项目的规格化设计；队列容量、调度、采样和 API 是实现选择，不是协议强制数值。工具核查仅为版本与文件存在性检查。所有验收项仍待实现后执行。

## 16. 工具兼容性检查结果（2026-11-12）

已完成独立特性探针，详见 [工具检查报告](tool-compatibility-2026-11-12.md)。原始证据在 `checks/tool-compat/2026-11-12/`。第 13 节的“只读核查”是本轮运行前的历史状态，现在以本节结果补充。

通过的具体探针：clocking input #1step/output #0、并发 worker 停止/重启、UVM 提交/乱序完成通知、等待 sequence 取消/重启、基础 SVA 正常/故障/复位禁用、简单 coverpoint 采样。

未通过：直接 cross 覆盖查询编译失败；带 option.weight=0 的覆盖组汇总未按预期权重计算（预期 25%，实际 37.5%）。不能宣布覆盖工具完全兼容。正式功能覆盖验收工具路线需解决，不能降低原定覆盖目标来迎合工具。

这些文件仅是工具兼容性探针，不是 Master/Crossbar 实现。本轮没有批准或开始功能模块编码。

## 17. 本机优先实施结果

用户确认优先 Mac 上的 SystemVerilog/UVM，并明确授权开始 Master；Cadence 连通性不作为开工条件。当前已实现 Master 写通路 agent 及必要支架，详见 [代码审查指南](master-review.md) 和 [首轮测试报告](master-test-report.md)。32 次自检运行通过，不含 Crossbar 系统验收。

实现采用单个周期协调过程管理队列和计数，同时独立推进 AW/W/B；不要求为了结构形式强行用三个线程修改同一状态。Monitor 发布 AW、单拍 W、完整写数据和 B 完成四类独立观察事件。嵌入式基础覆盖组在构造函数初始化并显式传入采样参数，保留原生覆盖限制。

当前编译宽度由 AXI_ADDR_W/AXI_DATA_W/AXI_ID_W 宏统一定义（默认 32/32/2），运行时 cfg 调整活跃与待发送容量。实现配置细节见指南；不将本轮参数测试外推为全组合保证。下一步等待用户审查，未启动正式 Slave/Crossbar 实现。
