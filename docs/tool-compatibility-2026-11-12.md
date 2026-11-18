# Master 工具兼容性检查（2026-11-12）

本轮仅为工具特性探针，不是 Master agent 或 Crossbar 实现。源文件、编译命令、原始日志和结构化结果随报告归档。

## 结论

Verilator 5.052 + Accellera UVM 2020.3.2 可运行已测试的采样、并发、响应通知、断言及简单 coverpoint；不能标记为完整兼容。交叉覆盖查询和带权覆盖汇总存在失败，功能覆盖验收工具路线仍需确定。

## 已通过

- `features.sv`：input #1step/output #0 的 clocking block；验证 DUT 在当前沿采样旧驱动、下一沿接收新驱动，Monitor 采到 NBA 前值。
- `concurrency.sv`：三个独立定时 worker；join_any/disable fork 后全部停止，等待后计数不变化，再启动计数恢复。它不是完整 UVM 复位协调器。
- `uvm_response.sv`：通过 config_db 传 virtual interface；class Driver 使用 clocking block；两笔请求先 item_done 接管，再以 1、0 顺序独立 put_response；response_handler 核对 transaction ID 和完成顺序。UVM ERROR/FATAL 均为 0。
- `uvm_reset.sv`：旧 sequence 已提交任务并等待完成；stop_sequences 将其停止，状态为 UVM_STOPPED，新 sequence 重新提交并收到唯一匹配响应。UVM ERROR/FATAL 均为 0。这验证取消/重启机制，不是对完整 reset coordinator 的验收。
- `assertions_reset.sv`：非重叠蕴含、$stable、disable iff；正常用例 0 次失败，故障用例恰好 1 次预期断言失败；等待被复位取消不误报。正常与故障运行都明确检查断言次数，不能以退出码替代判定。
- `coverage_basic.sv`：手动 sample、两个 coverpoint、显式 bins；部分采样为 50%，全部采样为 100%，均由自检核对。

## 未通过与诊断

1. `coverage.sv`：直接调用 cross 项的 get_inst_coverage，编译器报告 Member 'pairs' not found，未运行。
2. `coverage_group.sv`：两个 coverpoint 的 option.weight=0，只让 cross 决定覆盖组结果。一次采样应命中 4 个组合中的 1 个，预期 25%；实际不是 25%，自检失败。
3. `coverage_diagnostic.sv` 仅用于定位，不算通过测试：实际输出 PARTIAL=37.5、FULL=100。检查生成代码发现覆盖组汇总累加两个 coverpoint 与 cross 的命中/总 bins，未应用设置的权重。本例为 3/8=37.5%。因此不能用当前汇总百分比证明标准加权覆盖率。

简单 coverpoint 通过不抵消上述失败。本轮未检查复杂 transition/ignore/illegal bins、覆盖数据库导出/合并、完整 AXI SVA 集合或所有 SV/UVM 特性。

## 对项目的影响

- 可以将已通过的语法/机制作为后续局部实现候选，不能宣告 Master 验收通过。
- 不修改 DUT/Driver 来迎合覆盖工具，不删除原定功能覆盖目标。
- 标准功能覆盖最终验收建议使用兼容仿真器；若保留本机迭代，可研究独立显式 bin 计数作为辅助证据，但需单列设计与验证，不能冒称原生 covergroup 完全等价。本轮未实现替代方案。
- 本轮 UVM 仿真有主机栈大小提示；未发生栈故障。UVM 编译有库 timescale 警告。保留原始日志，后续规模扩大后不能据此保证无问题。

## 运行与证据

实际源语言参数为 --language 1800-2017，timeunit/precision=1ns/1ps；启用 --timing --assert，UVM 额外启用 --vpi 与官方 DPI，覆盖探针启用 --coverage。原始命令在结果 JSON 中。

这些脚本使用固定临时工作路径 `/tmp/axi-compat-20261112`，以及现有 `local-uvm` 工具安装。复现时将本归档的 SV/Python 文件复制到该临时目录，先运行 `run.py`（同时建立 local 工具软链接），再依次运行 `run_uvm.py`、`run_uvm_reset.py`、`run_coverage.py`、`run_coverage_diag.py`、`run_followup.py`。失败探针应保留失败，不得将其过滤为全通过。归档不包含工具库或构建产物。

本报告只记录本次具体探针的结果，未重新执行之前的 UVM 加法器示例，也未验证新的约束随机化能力。
