# 决策记录

日期：2026-11-08。来源：本聊天用户与助手逐项讨论；不是从旧原型反推需求。

## 已确认

1. 路线 B：参考成熟架构、自行组织实现主要 RTL；最终完整五通道及系统验证，不主动缩减范围。
2. 首配置 4×4；先 AW/W/B，再补 AR/R。
3. 地址/数据各 32 位，WSTRB 4 位；参数化。
4. 支持 1/2/4 字节传输、合法非对齐、INCR 1～256 拍。
5. 每 Master 两笔 outstanding；AW 握手计入，B 握手释放。
6. ID 改为 2 位，默认按 Slave 编号 0～3 分配；测试允许覆盖。替代较早的 1 位 ID 建议。
7. 来源编码在高位，当前下游 ID 为 4 位；返回恢复原 ID。
8. 同 ID 绑定目标直到排空；不同 ID 可以跨 Slave 并发并乱序返回 B。同 ID 同 Slave 允许两笔在途。
9. 轮询仲裁；每出口容量 4，参数化。替代较早的出口 8 笔建议。
10. 写路由记录队列、2 拍 W 缓冲、逐拍转发；不缓存整个 burst。
11. 四 Slave 各 64KB，从 0 开始连续分区，可配置；未映射访问用于 DECERR 检查。
12. UVM 为系统主验证环境；模块可先独立自检。
13. 基础全系统共同复位；Slave 故障隔离/恢复与 Master 故障处理分列为后续增强，先 Slave。
14. 逐模块规格→用户确认→实现自检→用户审查；先外部 Master 验证模型。

## 尚未形成实现批准

分项讨论不等于本轮全部细节已冻结。`master-spec.md` 是本次形成的完整审查稿；尚无实现、仿真通过或覆盖收敛结论。待定事项见规格末尾。

## 变更方式

后续每次变更记录日期、原决定、新决定、理由、影响模块和测试。协议既定要求直接落实；功能范围变化必须与用户共同确认。

## 2026-11-12 补充与修订

- 满容量时 B 完成释放名额，下一周期再启动新 AW，不做同周期提前复用。
- BREADY 正常默认 1、背压测试可控、复位期间 0。
- Driver 接管通知与事务完成通知分开；每笔任务带内部唯一编号。
- 普通 reset 取消排队及在途任务，统一终止等待并重新开始，不逐笔取消、不自动重发。
- 最终采用“控制复位保留存储”。讨论中暂提的“reset 连同存储清零”已被用户撤回，不作为当前需求。
- 独立增加测试环境存储清零操作，模型和参考存储器同步执行；普通 reset 保留已经实际提交的部分写入。
- Monitor/Scoreboard 事务状态清空，参考存储、配置、错误历史及累计覆盖率保留。
- Master 自检按基础、数据时序、并发响应、背压、复位/清零、检查器与参数顺序分组，尚未实现或执行。

## 2026-11-12 审查补充 v0.3

- 已将 AW/W 顺序配对、非对齐字节规则、B 周期判定、复位边界与 M01–M13 失败条件写入 Master 规格。
- 新增待整稿审查的实现建议：待发送深度 2、属性默认 profile、明确 UVM 通知与采样约定；不视为用户逐项确认。
- 发现独立路径中的 Verilator 5.052 与 UVM 2020.3.2；版本已核查，AXI 项目兼容性仍需门槛验证。
- 明确 Master 接口无法单独识别所有同 ID 响应内部调换/重复，不能夸大 checker 的检测能力。
- 本轮只修改文档，无 RTL/UVM 编码、仿真或功能覆盖结果。

## 首阶段可选信号范围确认

用户同意首阶段不启用 AWUSER/WUSER/BUSER 和 AWREGION。其他已确定的 AXI 写接口信号保持不变；最终是否增加这些可选信号按具体用途决定。接口规格与项目计划已同步。此项确认不是 Master 实现完成或工具兼容性通过的证据。

## 工具门槛检查结果

已运行独立兼容性探针，基础时序、并发、UVM 响应与取消机制及基础断言通过；功能覆盖发现 cross 查询和加权汇总限制。详见工具检查报告。功能覆盖方案仍待处理，未静默改为删减覆盖，也未进入 Master 实现。

## 本机优先与 Master 实施

用户明确优先 Mac/Cursor 上的 SystemVerilog + UVM，Cadence 不作为前置阻塞，并授权开始 Master。现已实现外部 Master 写 agent 与必要自检，32 次运行通过；保留功能覆盖兼容性边界。用户代码审查前不展开下一模块。证据见 master-test-report.md。

## 2026-11-14 进入 Slave 规格阶段

用户同意先以实现与验证为重心，面试整理后置，并同意下一步形成外部 Slave 写通路规格。已新增 slave-spec.md v0.1，待审查；不等于批准全部新增设计选择或确认 Master 审查通过。本轮没有 Slave 代码。优先审查 AW 后接收 W 的策略，其后逐项确认响应与故障语义。

## 2026-11-14 Slave 分项确认

- 用户确认 Slave 接受 AW 后才允许对应 W 握手；提前 W 用 WREADY 背压。
- 用户确认首版实现按序及跨 ID 乱序 B 模式，默认按序，同 ID 保序。
- 用户确认拒绝写入模式：接收完整 W burst、不修改内存、收齐后返回 SLVERR，B 握手释放容量。共同复位取消事务另按复位规则处理。
- 以上为分项确认，不扩大为 Slave 整稿冻结或开工批准。

- 用户进一步确认 Slave 自身 MAX_OUTSTANDING 默认 4、可配置：AW 握手占用，B 握手释放；满容量仅阻止新 AW，已有 W/B 继续推进。此计数与 Crossbar 出口计数独立。

## 2026-11-14 Slave 第一增量开工

用户确认软件接口先按规格落实，优先实现，具体知识及面试整理后续补充。授权先实现配置、事务记录、字节存储和单笔 AW/W/B 闭环，随后交付审查。已开展本增量；跨 ID 调度、完整容量压力、AW/W 配置背压和 Slave Monitor/agent 在后续增量补齐，不削减最终范围。

第一增量已完成：32/64 位数据、4 位 ID，共 28 次定向运行达到预期（22 正常、6 指定负向报错）。详见 slave-stage1-test-report.md。交付用户查看，尚未展开跨 ID 调度及完整 Slave Monitor/agent；不等于完整 Slave 验收。

## 2026-11-15 Slave 已实现部分补验

用户要求验收此前未验收项，并确认其属于 verification。已补充独立引脚事务账本、容量/同 ID/同拍/复位/清零/字节矩阵及实际 Master 直连测试，60 次常规运行达到预期；冻结 TB 检出两个隔离副本中故意引入的 BID/数据错误。本轮未修改正式 Slave 功能实现。跨 ID 乱序、可配置 AW/W 背压、独立 Slave Monitor/agent、系统路由 Scoreboard 和覆盖收敛仍未满足，详见 slave-acceptance-report.md；不将测试数外推为完整验证完成。

## 2026-11-15 Slave 第二增量

用户授权继续下一部分，优先基础成型。按已确认的 Slave 范围落实跨 ID 调度和 AW/W 背压；默认保持全局按序、无额外背压。增加确定性种子及按 AW 内部序号指定 B 延迟作为测试配置，同一通道周期与随机背压不叠加。配置、关键时序、测试和剩余边界记录于 slave-stage2-report.md。本轮仍不进入 Crossbar RTL。

## 2026-11-15 用户要求进入具体 Crossbar

用户在 Slave 第二增量完成后明确要求接下来做具体 Crossbar。推进顺序调整为先落实已有确认规则的独立 Write Tracker，再细化后续仲裁/缓冲/路由连接；Slave 独立 Monitor/agent 仍保留待办，不以临时 TB 观察逻辑冒充完成，系统集成验证前补齐。

已新增 rtl/axi_write_tracker.sv，实现每入口在途上限、同 ID 目标绑定和 B 完成释放；目标集合包含内部 DECERR 目标。Tracker 仅在本模块 valid/ready 原子接收时分配，后续上层须与 AW 及路由记录接收保持一致。12 次正常测试和 1 次负向断言测试达到预期，见 tracker-spec.md 与 tracker-results.json。本次没有构建完整 Crossbar 顶层，不代表出口容量、仲裁、W 路由和 B 缓冲时序均已冻结。

## 2026-11-15 地址译码与轮询仲裁增量

用户要求继续。落实按地址选择目标、每出口独立轮询：选中后遇背压锁定，仅内部接收握手推进指针，复位从入口 0 开始；同 ID 与在途限制仍由 Tracker 负责。译码使用静态、互不重叠、4KB 对齐的包含端点窗口，未命中输出内部 DECERR 目标；非法映射单独输出 map_valid=0。该配置约束与既定四个 64KB 窗口兼容，运行中重映射不属于基础阶段。

两个模块、独立 TB 和脚本已落盘。12 次正常、1 次预期断言运行达到预期。完整接口、周期和后续原子接收/组合路径约束见 routing-spec.md。W 来源队列、AW 通道封装与完整交叉开关未在本增量实现，后续须一并解决入口 AW 顺序与出口 W 来源顺序的依赖。

## 2026-11-15 AW 缓冲与 W 路由记录连接

用户要求继续。实现 axi_record_fifo 和 axi_write_frontend，原子接收同时分配入口 Tracker/AW 元数据/W 目标记录。入口 AWREADY 使用寄存准入许可；每入口只发队首，待下游 AW 实际握手后才推进下一笔。每出口独立仲裁、单 AW 输出寄存器、在捕获时预留容量，AW 握手时生成 W 来源记录；release_valid 表示下游 B 已安全接收并保存，complete_valid 表示上游 B 握手，两类容量分开释放。具体接口合同与保守吞吐边界见 frontend-spec.md。

4×4、3×2、1×1、64 位地址等四组参数，三个种子共 12 次最终回归通过。测试以内部事件模拟 W 完成与 B 回收，未实现 WDATA/B/DECERR 完整通道，不对系统验证或覆盖收敛作完成声明。下一增量为 W 两拍数据缓冲和实际转发。

## 2026-11-15 W 数据缓冲与转发

用户继续授权下一增量。实现每入口两拍 W FIFO，按入口目标与出口来源双向队首匹配转发；只在下游最后 W 拍握手时弹出两边路由记录。当前 burst 收齐后暂停接收下一 burst，直到旧 burst 下游完成，避免缓冲中的跨事务归属歧义。WLAST 不释放 Tracker/B 在途容量。输入/输出 WLAST 及背压稳定性有断言；当前不做运行时故障恢复。

新 AW/W 联合 TB 检查真实数据/字节使能/最后一拍，原 AW 控制源码不变。四组参数三个种子的 12 次正常运行、两项预期 WLAST 错误均达到预期。具体接口、周期和见证见 wpath-spec.md；B 回收仍是内部通知模型，下一步实现真实 B 路由与缓冲。

## 2026-11-15 B 响应路由与缓冲

用户继续授权。实现每出口两条 B 缓冲、每 Master 独立轮询与返回寄存器，来源高位用于路由，低位恢复原 ID，BRESP 原样传递。出口名额在下游 B 实际握手并保存时归还，Tracker 在上游 B 握手时归还。保留单返回寄存器的气泡及共享出口 B FIFO 的队首阻塞，不虚称完全端口隔离。

新联合 TB 使用真实 B 引脚替代直接完成通知。12 次正常运行与 1 次非法来源负向测试通过，详情见 bpath-spec.md。错误目标的 DECERR 仍由 TB 端点产生；下一增量实现内部错误端并封装 4×4 写通路顶层。

## 2026-11-15 内部错误端与写顶层

用户授权下一步。新增 axi_write_decerr：按出口容量保存多笔 AW，收齐每笔 W 后才返回 DECERR，无存储写入；新增 axi_crossbar_write，默认对外 4×4，内部额外错误目标不暴露。AW 属性在顶层恢复独立物理字段。

仅观察公开接口的顶层自检 12 正常 + 1 非法来源、错误端独立检查 3 正常 + 1 非法 WLAST，共 17 次最终运行达到预期。首轮随机测试的乱序见证不足通过加入确定的正常/错误跨 ID 超越激励补齐，没有降低验收条件。详见 crossbar-write-spec.md。

现已形成写通路基础闭环；下一阶段接入现有 UVM 模型，先解决入口/出口 ID 位宽共存，再补独立监控与系统检查。不能将轻量 TB 通过称为五通道、完整 UVM 验证、覆盖或 PPA 完成。

## 2026-11-15 UVM 系统接入

用户明确要求接入。axi_write_if 参数化，Master/Slave 包分别提供 ID 位宽宏并回退兼容原 AXI_ID_W。系统以入口2位、出口4位实例化四个既有 Master agent、四个 Slave driver、八个稳定性 checker，新增独立 UVM 双侧事务/字节 scoreboard，不读取 RTL/Driver 私有队列。Slave 尚未封装独立 agent/Monitor，未冒充完成。

恢复 Slave 记录类原本包引用对应的文件路径，内容不变。最终6次正常系统运行、1次明确预期的存储错误检测、25次 Master 与36次 Slave 兼容运行均达到预期；正常系统每次96笔完成、262144字节核对一致。证据见 crossbar-uvm-integration.md 与 crossbar-uvm-results.json。

本轮系统运行只包含启动复位，运行中取消/恢复及覆盖收敛仍需后续UVM场景，不以较早轻量RTL测试替代最终系统验收。RTL未因本轮接入而修改。

## 2026-11-15 Slave 独立 Monitor 与 agent

用户继续授权补齐该验证组件。实现独立握手关联的 Monitor、事务事件快照，以及 cfg.active 控制的 active/passive agent；active 复用原 Driver，passive 不创建 Driver。支持提前 W、同 ID 首笔匹配和跨 ID B 超越，检查 burst/WSTRB/背压稳定性；复位清除未完成关联，保留审计计数并发布取消事件。

系统用四个 active agent 和一个 Slave0 passive 观察实例，事件与原独立双侧 scoreboard 对照，继续检查全部字节存储。最终 5 项 Monitor 正常、7 项协议违规检测、6 项 32/64 位系统正常、1 项存储错误检测，共 19 次达到预期。旧模型及 RTL 回归本轮未重跑。详见 slave-monitor-agent.md 和同名 results.json。

本轮未修改功能 RTL，也未实现系统在途复位场景；下一步补 UVM 系统复位取消、存储保留和恢复，之后继续覆盖与后续读通路工作。

## 2026-11-16 读通路 RTL 实现

用户授权补完 AR/R 读通路。复用 axi_address_decode、axi_rr_arbiter、axi_record_fifo、axi_write_tracker 四个已有模块，新增五个 RTL：axi_read_frontend（AR 准入/路由/仲裁/出口容量）、axi_read_data_path（R 路由 S→M，per-output FIFO + per-input lock-until-RLAST）、axi_read_decerr（内部读 DECERR 端点，直接从 AR 记录生成 R burst）、axi_crossbar_read（读通路顶层）、axi_crossbar（五通道完整顶层）。共 688 行，全部 lint 零 error。

设计取舍：R 路由靠 RID 高位 source 字段，不需要写通路的显式 W source/target 队列；R burst 顺序保护用 per-input locked bit，lock 到某 source 直到 RLAST，防止跨 burst 交错；release_valid[o] = RLAST 入 per-output FIFO 时释放出口容量；complete_valid[i] = Master 收 RLAST 时释放入口 tracker。

调试发现一个真实 RTL bug：axi_read_data_path 的 output register 只在 complete_valid（RLAST）时清零 full，导致多拍 burst 第 2 拍永远无法 capture、系统死锁。修复：full 在任意 s_rvalid && s_rready 时清零，complete_valid 仅通知 tracker。详见 docs/interview-notes.md。

读通路轻量回归（crossbar_read_tb，4 配置 × 3 seed + 1 BAD_SOURCE 负向）13/13 通过；写通路回归确认无回退 13/13 通过。

## 2026-11-16 读通路 UVM 系统接入

用户要求优先 Mac 本地测试。新增读接口 axi_read_if、读 Master 包（axi_master_read_pkg：item/cfg/driver/monitor/agent）、读 Slave 包（axi_slave_read_pkg：driver/agent，复用 axi_slave_cfg/memory）、五通道 UVM 测试包 crossbar_uvm5_pkg（fabric_r_sequence、fabric_r_scoreboard、crossbar_uvm5_test）、top5 顶层和 run_crossbar_uvm5.py 脚本。写通路 UVM 完全不动。

scoreboard 设计要点：AR 接受时同时填 incoming 和 upstream_r（不依赖下游 RLAST 时序）；R beats 按 RID 匹配 upstream_r 中最老的同 ID 条目（DUT tracker 保证同 ID 顺序）；下游 R beats 也按 RID 匹配 outgoing_r（允许 slave 乱序响应不同 ID）；DECERR 事务直接从 internal endpoint 返回，不出现在物理 slave 端口。预填 slave 存储已知 pattern，非 DECERR 路径逐 beat 比对 RDATA。

最终 32 位 3 seed + 64 位 3 seed 共 6/6 通过，每次 96 笔完成（80 物理 + 16 DECERR + 4 SLVERR），1248 拍上行 R 全部核对，r_stalls 确认背压被观察。Makefile 新增 read-uvm-build/regress 和 read-uvm-build64/regress64 目标。

## 2026-11-17 在途复位 UVM 场景（crossbar_uvm7）

用户授权 P1：在现有读写联合环境中实现在途复位覆盖。新增 crossbar_uvm7_pkg、top7.sv、axi_reset_if.sv、run_crossbar_uvm7.py。6 个场景由 `+SCENARIO` plusarg 参数化选择，reset controller 监控驱动器内部状态（`outstanding`、`beat_index`、`b_stalls`、`r_stalls`），确认目标状态后触发 4 个周期复位，提供场景命中日志证明。

**6 个场景**：SC0=AW/AR 在途（w_inflight=8, r_inflight=8），SC1=W burst 中途（beat_index>0），SC2=R burst 中途（beat_index>0），SC3=B 背压时复位（b_stalls>0），SC4=R 背压时复位（r_stalls>0），SC5=≥2 写 + ≥2 读同时 outstanding。

验收机制：复位前记录 `w_inflight`/`r_inflight`，取消后记录 Driver `cancelled` 增量；复位后运行复用旧 ID 的小型后复位序列（W_REQS_POST=8，R_REQS_POST=8），检查完成数量。存储保留检查：已被 scoreboard 追踪的写字节复位后必须完整，部分写入字节（scoreboard flush 前被接受）保留但不报错（`UVM7_RETENTION` info）。

scoreboard 复位过渡保护：ARESETn=0 时 flush，deassert 后第二次 flush 以处理同步复位末周期残留，`post_reset_guard` 周期内 W beat（如 W before AW 场景）跳过计数不 fatal。AW 在循环中优先于 W 处理，解决 AW+W1 同周期握手导致的 WLAST 计数偏移问题。

axi_master_read_agent 增加 `run_phase` → `stop_sequences`（原来缺失），复位时 sequencer 被正确停止。

最终 32 位 18/18、64 位 18/18，共 36/36 通过。Makefile 新增 reset-build/regress 和 reset-build64/regress64 目标。


用户授权补完联合场景（P0 缺口：五通道同时读写未测试）。新增 crossbar_uvm6_pkg、top6.sv、run_crossbar_uvm6.py，4 个写 Master/Slave + 4 个读 Master/Slave 在同一 DUT 上并发运行。每通道 24 笔 AW/W/B + 24 笔 AR/R，共 8 路序列 fork...join。写 scoreboard 检查路由、数据、BRESP、乱序响应和背压；读 scoreboard 检查路由、RDATA、RRESP、RLAST 时序和背压。两个 scoreboard 独立观察引脚，不读取 Driver 内部队列。

COMBINED_WITNESS 确认：aw=96 b=96 down_aw=80 w_beats=1208 decerr_w=16 || ar=96 r=96 down_ar=80 r_beats=1248 decerr_r=16 r_stalls=4394，全部在单次仿真时间 60.6ms 内并发完成，证明读写通路共享地址译码、仲裁和 Slave 端口无干扰。32 位 3/3、64 位 3/3，共 6/6 通过。Makefile 新增 combined-build/regress 和 combined-build64/regress64 目标。

