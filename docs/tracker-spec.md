# Write Transaction Tracker：第一模块规格与实现边界

2026-11-15。用户授权进入具体 Crossbar；本模块落实总计划中已经确认的 ID 绑定与在途计数，不提前决定其余模块的流水结构。

## 功能与位置

每个外部 Master 入口各放置一个 Tracker，4×4 配置共 4 个实例。它记录“这个 Master 的哪些 ID 还有事务没有收到 B”，并限定同 ID 在未排空前只能去同一目标。它不是整条事务的数据存储器，也不是 W 路由队列。

默认 ID_WIDTH=2，MAX_OUTSTANDING=2。TARGETS=5，目标 0～3 表示四个物理 Slave，目标 4 预留给内部 DECERR 处理端。DECERR 也参与 ID 绑定，避免错误响应绕过同 ID 的旧事务。错误端本轮尚未实现，Tracker 的第五目标只是一个可跟踪的编号。

RTL 使用最多 MAX_OUTSTANDING 个活动 ID 槽，每槽保存原始 ID、目标、未完成数量。相同 ID 的两笔请求使用同一槽并加计数；容量按事务总数算，不按不同 ID 个数算。结构不随 2^ID_WIDTH 成比例扩展。

## 信号方向（相对于 Tracker）

- 输入 clk、reset_n：公共时钟，低有效复位。
- 输入 request_valid、request_id、request_target；输出 request_ready：上层请求分配记录。valid 与 ready 同沿为 1 才计入。
- 输入 complete_valid、complete_id：上游 Master 侧 B 实际握手对应的单周期通知，ID 已去除来源前缀。
- 输出 complete_known、complete_target：查询该 complete_id 是否有在途记录、原先绑定哪个目标。known 与 complete_valid 独立，target 仅在 known 为 1 时有意义。
- 输出 outstanding：当前入口未完成事务总数。

所有目标编号宽度至少为 1；接口采用普通 SystemVerilog 信号，后续顶层连接参数化 AXI 接口。本模块不依赖现有 UVM 接口的全局宽度宏。

## 分配与释放时序

request_ready 取决于沿前状态：入口未满，目标合法，且 ID 无旧记录或仍指向原目标。request_valid 不是 ready 的前提。非法目标不被接收。

complete_valid 必须对应已存在记录；否则断言报 TRACKER_UNKNOWN_COMPLETION，不能借无效完成释放容量。W 最后一拍不释放任何 Tracker 记录。

满容量时，即使该沿有 B 完成也不提前接受新事务；释放后下一沿才可能接受。相同 ID 最后一笔完成的当沿仍不接受切换目标；下一沿可以。未满时允许一个请求和一个完成同沿发生：相同 ID 的数量净变化为 0，不同 ID 各自加减。

reset_n 拉低即清除全部槽与计数，阻止请求接收；复位期间忽略事件。整个系统共同复位后，外部旧响应也必须消失。

例：ID0→S0 接受两笔，则 count=2；ID0→S1 被阻止。第一个 B 后 count=1，仍阻止切换；第二个 B 后 count=0，下一沿可接受 ID0→S1。ID1→S1 则只受总容量限制，不受 ID0 的目标约束。

## 与后续 Crossbar 的连接约束

上层必须把 Tracker 分配与上游 AW 接收、AW 元数据保存、W 路由记录分配做成同一个原子事件，不能只占 Tracker 而丢失其他记录。Tracker request_valid 必须包含其他资源已可用的条件，S_AXI_AWREADY 必须与该原子接收一致；不能将内部 ready 直接接到 AXI 引脚而跳过缓冲/组合路径审查。

上游 ID 扩展采用已确认的 `{来源Master编号, 原始ID}`；4 个入口时 2+2=4 位。响应取高位选择 Master，低位恢复 ID。同 ID 跨 Slave 的阻止机制在本 Tracker，真正的 ID 拼接/拆分在后续路由模块。

上游 Tracker 保留到 Master 的 B 握手，不因下游 B 已进入内部缓冲而提前释放。出口容量的释放位置属于出口队列规格，尚未在这里隐含定案。

后续必须确保下游收到的 AW 顺序与 W 来源队列一致，避免多个入口相互等待导致 W 路径死锁。一个 Tracker 的通过不能证明这一点。

## 自检与验收

独立轻量 SystemVerilog TB 使用按 ID 索引的参考计数，与 RTL 的活动槽结构不同。逐周期检查 ready、完成查询目标、总计数，并覆盖同 ID 重复、跨目标阻塞、排空切换、同沿加减、满容量禁止提前复用、在途复位、DECERR 目标及合法随机请求/完成。

参数矩阵：容量/ID位数/目标数分别为 1/2/5、2/2/5、4/3/5、2/1/1；每组 seed=7、41、2026，每次至少 2000 个随机周期。另用无记录完成验证断言。结果由脚本实际运行生成，见 tracker-results.json。

运行：`python3 scripts/run_tracker.py`。无 UVM 依赖，符合总计划允许模块轻量自检；系统集成仍采用 UVM。

本增量尚未包含译码、AW 仲裁、W 缓冲/路由、B 仲裁、DECERR 完整事务处理及 4×4 顶层。因此不能称作完整 Crossbar 闭环已完成。

## 本轮实际结果

本机 Verilator 5.052：12/12 次正常测试通过，1/1 次无记录完成的负向断言测试达到预期；四组参数各执行三个种子，共 24000 个随机激励周期，另有定向边界与复位检查。编译警告按错误处理，最终四组均通过。结果见 [机器可读记录](tracker-results.json)，原始日志位于 logs/tracker。

首轮在容量 1 配置发现“计数不超过 1”的断言被工具判断为位宽决定的恒真表达式；现改为检查“允许分配时必须有容量”，未豁免编译警告。

本轮是行为仿真与断言自检；没有做综合、时序收敛、形式证明或完整 Crossbar 验证。

## 参考依据

功能约束来自已确认的 project-plan.md 第 2 节与 decisions.md。本轮查阅 verilog-axi 的地址准入组织和 PULP 的 ID 扩展说明；未复制其源码。相关链接仅作架构参考，当前未锁定上游提交，不将它们作为测试期望模型：

- https://github.com/alexforencich/verilog-axi/blob/master/rtl/axi_crossbar_addr.v
- https://github.com/pulp-platform/axi/blob/master/doc/axi_xbar.md
- Arm IHI 0022H：https://developer.arm.com/documentation/ihi0022/h/（本轮网页正文无法读取，不声称重新逐条核查全文；沿用项目已有规范版本。）
