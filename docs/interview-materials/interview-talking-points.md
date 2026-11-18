# 面试话术要点

**场景**：面试官问"介绍一下你的验证项目"

---

## 30秒电梯演讲

"我独立完成了一个 5通道 AXI4 Crossbar 的设计和验证。RTL 是参数化的 SystemVerilog，支持 4×4 配置和 32/64 位数据宽度。验证方面，我搭建了完整的 UVM 环境，包括 master/slave agent 和 scoreboard，完成了超过100次回归验证。

特别值得一提的是在途复位场景——我设计了6种不同时机的复位场景，覆盖地址通道在途、数据突发中断、响应回压等情况。这些场景在 Verilator 和 Cadence Xcelium 两个平台上都全部通过，总共72次验证，零错误。

在 Xcelium 移植过程中，我还解决了一个 UVM 时序竞争问题，使用 report catcher 精准修复，没有改变 DUT 或测试逻辑。"

---

## 核心数据（随时可报）

- **RTL 规模**：15个模块，约3000行 SystemVerilog
- **验证总量**：100+ 次回归，其中在途复位 72 次（双平台 ×2 宽度 ×3 seed ×6 场景）
- **工具链**：Verilator 5.052（本地）+ Cadence Xcelium 24.03（远程）
- **方法学**：UVM 2020.3.2 / CDNS-1.1d
- **通过率**：72/72 (100%)，UVM_ERROR=0，bytes_bad=0
- **周期**：8周从零到完整验证

---

## 高频问题准备

### Q1: 为什么选择 AXI4 Crossbar？

"我想要一个能展示完整验证能力的项目。Crossbar 涉及多 master/slave 并发、仲裁、路由、顺序保护等复杂逻辑，验证场景丰富。同时 AXI4 是工业标准协议，相关经验直接适用于实际工作。"

### Q2: 最大的技术挑战是什么？

"**Xcelium 上的 UVM 竞争修复**。初次回归有6次测试失败，报 `TRY_NEXT_BLOCKED` 错误。我通过日志分析发现是早期复位场景（cycle 7-9）触发的——复位时 pre-reset sequence 还在循环，`try_next_item` 和 `stop_sequences` 在同一 NBA 周期产生竞争。

关键是我通过时序推理和 UVM 文档确认这是已知工具行为，不是 DUT bug。然后用 `uvm_report_catcher` 将这个特定 ID 降级为 INFO，而不是简单粗暴地关闭所有错误检查。修复后36/36全通过。"

### Q3: 如何保证验证完整性？

"**分层验证 + 双工具交叉验证**：
1. 自底向上：每个模块先独立验证（tracker、routing、frontend 等）
2. 通路级：读写通路分别用轻量 TB 快速回归
3. 系统级：UVM 环境做联合并发和在途复位场景
4. 跨工具：Verilator 快速迭代，Xcelium 工业标准确认

另外用 scoreboard 做 transaction-level 检查，每次测试都验证 `bytes_bad=0`，确保数据完整性。"

### Q4: Verilator 和 Xcelium 的差异？

"**Verilator 快但宽松，Xcelium 严格但完整**：
- 编译速度：Verilator 几秒，Xcelium 需要十几秒
- SV 支持：Xcelium 对变量作用域、类型检查更严格，暴露了 Verilator 宽松接受的问题（比如 `w_seqs` 数组隐式声明）
- 调试：Verilator 本地快速，Xcelium 需要远程但有完整波形和覆盖率工具

我的策略是开发阶段用 Verilator 快速迭代，回归确认用 Xcelium 保证工业标准。"

### Q5: 如何处理在途复位验证？

"**场景设计 + UVM sequence 控制**：
1. 6种场景覆盖不同复位时机：地址在途（cycle 9）、数据突发中（cycle 10/20）、响应回压（cycle 12-58）、混合 outstanding（cycle 7）
2. 每个场景启动固定数量的 pre-reset transactions，在特定周期触发复位
3. 复位后立即启动 post-reset transactions，验证 DUT 能正确从任意状态恢复
4. Scoreboard 检查：pre-reset 的 cancelled transactions 不能污染 post-reset 结果

重点是覆盖**所有通道的所有状态**，不只是 idle 状态复位。"

### Q6: 项目中学到了什么？

"**三个层面**：
1. **技术深度**：理解了 AXI4 协议细节（outstanding、ID routing、burst）、UVM 时序模型（NBA、TLM）、跨工具兼容性
2. **工程能力**：自动化脚本、远程流程、问题定位、文档规范
3. **项目管理**：如何在8周内完成从设计到验证的完整流程，如何平衡快速迭代和质量保证"

---

## 避坑指南

### ❌ 不要说
- "我用了 ChatGPT 生成代码"（即使用了也强调是辅助，核心设计和调试是自己完成）
- "Verilator 够用了，Xcelium 没必要"（体现不出工业工具链经验）
- "UVM 太复杂了"（显得方法学功底不足）
- "复位验证很简单"（显得对问题理解不深）

### ✅ 应该强调
- "独立完成"（设计 + 验证 + 调试）
- "双工具验证"（展示工具链广度）
- "问题定位能力"（UVM 竞争修复的完整思路）
- "工程实践"（自动化、文档、版本控制）
- "可量化成果"（72/72，UVM_ERROR=0，bytes_bad=0）

---

## 代码走查准备

面试官可能会要求看代码。准备这些文件：

1. **RTL 核心模块**（选1个讲透）
   - `rtl/axi_crossbar.sv`（顶层，展示接口设计）
   - `rtl/axi_write_tracker.sv`（状态机，展示逻辑复杂度）
   
2. **UVM 环境**（选1-2个讲透）
   - `dv/agents/axi_master_agent/axi_master_driver.sv`（driver，展示协议实现）
   - `dv/scoreboard/axi_crossbar_scoreboard.sv`（检查逻辑）
   
3. **测试用例**
   - `dv/tests/crossbar_uvm7/crossbar_uvm7_pkg.sv`（在途复位场景 + UVM catcher 修复）

**讲解思路**：
- 先说接口（输入输出）
- 再说功能（状态机/流程）
- 最后说验证点（如何测试、覆盖什么场景）

---

## 反问环节准备

1. "团队的验证流程是怎样的？使用什么工具链和方法学？"
2. "这个岗位的项目复杂度如何？会涉及哪些协议和场景？"
3. "团队如何平衡验证深度和项目进度？"
4. "有机会参与 formal 验证或覆盖率驱动的验证吗？"

---

## 最后检查清单

面试前24小时：
- [ ] 重新跑一遍 Verilator 回归，确保还能通过
- [ ] 检查 Xcelium 服务器连通性（万一面试时需要演示）
- [ ] 准备好代码仓库链接（GitHub private repo + 临时访问）
- [ ] 打印一份项目总结（带图表）
- [ ] 回顾 STAR 法则示例（至少准备3个完整故事）
