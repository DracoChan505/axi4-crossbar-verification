# Master 模块首轮自检报告

日期：2026-11-12。状态：本机实现与自检完成，等待用户审查；不是 Crossbar 或完整 AXI4 系统验收。

## 结果

32/32 次运行通过：默认 32-bit data / 2-bit ID / 2 outstanding 配置 25 次；64-bit data / 3-bit ID / 4 outstanding 配置 4 次；32-bit data / 1-bit ID / 1 outstanding 配置 3 次。

其中 8 次为显式负向测试，均要求且实际捕获唯一指定错误一次，无额外错误。不是把有错误的正常用例当通过。其余 24 次是正常或复位/错误响应场景。默认随机测试 seed=7、41、2026，各发送 48 笔合法随机写事务；参数配置的随机测试使用 seed=41。

机器可读结果见 [master-results.json](master-results.json)，含源文件摘要、每次配置、日志路径和实测计数。

## 需求与证据

- M01：smoke，单拍 AW/W 同沿接收，完整 B 返回，队列最终为空。
- M02–M03：w_first、aw_first、backpressure，实际命中不同先后与等待；独立 SVA 检查 AW/W/B 稳定性。neg_awstable、neg_wstable、neg_bstable 分别检验检查器能发现一次预期故障。
- M04：bursts，覆盖固定非对齐例子、1/2/4-byte 尺寸、跨 word、触及 4KB 边界、256 拍、稀疏/全零 WSTRB。参考模型不调用 Driver 的 mask helper。invalid_item 验证跨 4KB、非法 WSTRB 被合法构造路径拒绝；neg_strb 验证接口检查器也能发现非法 strobe。
- M05：same_id，实测 peak outstanding=2、pending_peak=2，6 笔全部完成，无队列覆盖；参数配置测试单笔与四笔容量。
- M06–M07：reorder 实测默认配置有 2 次非队头 ID 完成；same_id 顺序完成。Scoreboard 对照独立测试意图检查数据，response_handler 检查内部任务标签与响应状态。
- M08：backpressure 的 BVALID 等待计数为 33 个采样沿；error_resp 返回 SLVERR 仍释放并报告完成。
- M09：Driver 每周期检查 O/R/active 不变量；共享周期更新经定向及随机流量运行。neg_early 明确在最后一拍 W 握手的同沿提出 BVALID，要求 EARLY_B。并非所有可能的同周期组合都已穷举。
- M10：reset_aw、reset_w、reset_b、reset_bvalid、reset_queued，分别覆盖地址接收后、数据中途、等待响应、响应有效但未接收、存在排队任务时复位。旧 sequence 终止，新任务成功完成；已提交字节保留。
- M11：8 个注入分别命中 B_NO_PENDING（无请求/完成后重复两种场景）、EARLY_B、WLAST、B_STABILITY、AW_STABILITY、W_STABILITY、WSTRB。只接收指定错误一次，其余错误仍导致失败。
- M12：三个构建配置通过；非默认配置是选定用例验收，不是所有参数组合穷举。
- M13：正常用例排空后独立清零模拟和参考存储；普通 reset 保留已经实际写入的数据。这里只验证必要支架，系统级参考存储的提交/复位一致性仍需后续 Slave/Scoreboard 集成验收。

## 覆盖证据与限制

Monitor 含基础原生 covergroup（尺寸、burst 长度），并输出独立场景计数。默认 bursts 用例的原生 bin 数据逐项核对：尺寸 1/2/4 字节分别为 1/3/5 次；单拍/2～16拍/17～255拍/256拍分别为 1/6/1/1 次，与独立计数一致。

已知 cross 查询和加权汇总兼容性限制没有消失。本轮不报告完整覆盖率百分比，不宣称交叉覆盖、代码覆盖、全协议断言、X/Z 传播或形式验证收敛。原生 `.coverage.dat` 按每个运行单独保存，可回查具体 bin。

## 工具与重现

Verilator 5.052、Accellera UVM 2020.3.2，SystemVerilog 1800-2017；本机执行，无 Cadence 依赖。编译启用 timing/assert/coverage-user/vpi 及官方 UVM DPI。

- `make master-build`：构建默认配置。
- `make master-regress`：执行默认 25 次运行。
- 参数运行和代码阅读顺序见 [审查指南](master-review.md)。

编译剩余警告为第三方 uvm_pkg 缺省 timescale；项目自身的位宽警告已修正。运行出现主机栈大小提示，本轮没有因此失败，不将其解释为任意规模环境都安全。

## 本轮修正记录

1. 两个初始注入用例在 BREADY=0 时撤回 BVALID，意外再触发 B_STABILITY。修正支架的接收时序，保留原检查器，不扩大允许错误集合；原始失败日志在 logs/initial-run。
2. 初次接入嵌入式覆盖组时构造位置不合适，且直接捕获父类字段的采样出现空引用。改为类构造时初始化、显式 sample 参数，最小用例和完整回归通过；原始失败在 logs/coverage-debug。未修改工具或 UVM 库来掩盖错误。

## 交付边界

Master agent、接口、Monitor、基础检查器和 test-only 支架已实现。正式 Slave agent、Crossbar、AR/R、系统路由验证、故障隔离增强均未实现。等待用户检查当前模块后，再推进下一模块。
