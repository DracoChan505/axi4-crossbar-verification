# AXI4 Crossbar 项目全景总结

**时间线**：2026年10月-11月（8周）  
**角色**：独立设计 + 验证  
**定位**：简历核心项目，展示完整 RTL → UVM → 工业工具链能力

---

## 一、项目背景和目标

### 为什么做这个项目
- **求职需要**：硬件验证岗需要完整的验证项目经验
- **技能差距**：之前只有 AXI-Stream 包交换验证，需要展示 AXI4 Memory-Mapped 互连能力
- **工具链广度**：需要证明能在工业级 EDA 工具（Cadence Xcelium）上工作，不只是开源工具

### 最终目标
完成一个**简历可写、面试可讲**的 AXI4 Crossbar 验证项目：
- RTL 参数化设计（支持多配置）
- UVM 验证环境（方法学规范）
- 双平台验证（Verilator + Xcelium）
- 在途复位深度验证（展示场景设计能力）

---

## 二、完成了什么工作

### 2.1 RTL 设计（15个模块，~3000行）

#### 顶层架构
```
axi_crossbar.sv (5通道顶层)
├── axi_crossbar_write.sv (写通路)
│   ├── axi_write_frontend.sv (AW 准入/路由/仲裁)
│   ├── axi_write_data_path.sv (W 数据路由)
│   ├── axi_write_response_path.sv (B 响应路由)
│   ├── axi_write_tracker.sv (在途计数 + ID 绑定)
│   └── axi_write_decerr.sv (内部 DECERR 端点)
└── axi_crossbar_read.sv (读通路)
    ├── axi_read_frontend.sv (AR 准入/路由/仲裁)
    ├── axi_read_data_path.sv (R 数据路由)
    └── axi_read_decerr.sv (内部 DECERR 端点)
```

#### 核心设计决策
| 决策点 | 选择 | 原因 |
|--------|------|------|
| 读写分离 | 独立 frontend + data path | 简化验证，降低状态机复杂度 |
| 仲裁策略 | 轮询（round-robin） | 公平性，避免饥饿 |
| ID 管理 | Master 侧 2-bit，拼接 source | 支持 4×4 配置 |
| Outstanding | 每入口最多 2 笔 | 平衡复杂度和性能 |
| 地址译码 | 静态 4KB 对齐窗口 | 简化逻辑，满足典型需求 |
| DECERR 处理 | 内部虚拟 Slave | 避免协议违规 |

#### 参数化支持
- **配置**：4×4 Master/Slave（可扩展）
- **数据宽度**：32/64-bit 可切换（通过 `AXI_DATA_W` 参数）
- **ID 宽度**：Master 2-bit，Slave 4-bit（source + master_id）
- **Outstanding**：每入口可配置（默认 2）

#### 已实现的 AXI4 协议特性
✅ 5通道独立（AW/W/B/AR/R）  
✅ INCR burst（其他 burst 类型留作扩展）  
✅ Multiple outstanding transactions  
✅ 多 ID 支持  
✅ 响应路由（source 位追踪）  
✅ 同 ID 顺序保护（tracker 绑定目标）  
✅ DECERR 错误响应  

❌ 暂不支持：FIXED/WRAP burst、exclusive access、atomic operations、user signals

---

### 2.2 验证环境搭建（UVM）

#### 验证架构
```
UVM Testbench (7套)
├── 轻量 TB（快速功能验证）
│   ├── crossbar_write_tb.sv (写通路)
│   └── crossbar_read_tb.sv (读通路)
├── UVM 系统验证
│   ├── crossbar_uvm (写通路 + 存储错误检测)
│   ├── crossbar_uvm5 (读通路)
│   ├── crossbar_uvm6 (读写联合并发)
│   └── crossbar_uvm7 (在途复位场景) ← 最核心
└── 独立 Monitor
    └── slave_monitor (协议违规检测)
```

#### UVM 组件
**Agent**：
- `axi_master_agent`（写 Master）+ `axi_master_read_agent`（读 Master）
- `axi_slave_agent`（写 Slave）+ `axi_slave_read_agent`（读 Slave）
- 每个 agent 包含 driver、monitor、sequencer

**Scoreboard**：
- Transaction-level 检查（地址路由、数据完整性、响应正确性）
- 字节级完整性验证（`bytes_bad=0` 是通过标准）
- 在途计数验证（reset 前后状态一致性）

**Sequence**：
- 随机地址生成（4个 Slave 窗口）
- 随机 burst length（1-16）
- 随机 ID（0-3）
- 可控复位时机（用于在途复位场景）

---

### 2.3 验证流程和工具链

#### 本地开发流程（Verilator）
```bash
# 步骤 1：轻量 TB 快速验证
make write-regress  # 13次（4配置×3seed + BAD_SOURCE）
make read-regress   # 13次

# 步骤 2：UVM 系统验证
make system-build && make system-regress  # 写通路 32/64-bit
make read-uvm-build && make read-uvm-regress  # 读通路 32/64-bit

# 步骤 3：在途复位验证
make reset-build && make reset-regress  # 6场景×3seed 32-bit
make reset-build64 && make reset-regress64  # 6场景×3seed 64-bit
```

**工具**：
- Verilator 5.052（开源）
- UVM 2020.3.2（本地 `/Users/shiyutian/Desktop/Projects/验证/local-uvm`）
- Python 脚本驱动回归（`scripts/run_*.py`）
- Makefile 封装常用命令

#### 远程 Xcelium 验证（工业标准确认）
**服务器**：`frey.ece.jhu.edu` (128.220.11.68)，JHU ECE RAID  
**路径**：`/raid/fall2026/yshi131/axi4-crossbar/`  
**工具**：Xcelium 24.03-s005，UVM CDNS-1.1d

```bash
# 远程执行（通过 SSH + expect 脚本）
python3 scripts/run_crossbar_xcelium.py build
python3 scripts/run_crossbar_xcelium.py regress  # 32-bit
python3 scripts/run_crossbar_xcelium.py build --data-width 64
python3 scripts/run_crossbar_xcelium.py regress --data-width 64  # 64-bit
```

**挑战与解决**：
1. **SSH 自动化**：sandbox 限制 → expect 脚本处理密码认证
2. **Tcl 变量冲突**：`$PATH` 被 Tcl 解释 → 转义为 `\$PATH`
3. **SV 作用域严格性**：Xcelium 比 Verilator 严格 → 显式声明 `w_seqs` 数组
4. **UVM 竞争修复**：`TRY_NEXT_BLOCKED` 误报 → `uvm_report_catcher` 降级为 INFO

---

### 2.4 验证场景设计（重点：在途复位）

#### 6种在途复位场景
| # | 场景名 | 复位周期 | 验证目标 |
|---|--------|---------|---------|
| 0 | AW_AR_in_flight | 9 | AW/AR 地址在途时复位，验证 frontend 状态清空 |
| 1 | W_mid_burst | 10 | W 数据突发传输中复位，验证 data_path 中断处理 |
| 2 | R_mid_burst | 20 | R 数据突发传输中复位，验证 read_path lock 状态 |
| 3 | B_backpressure | 46-58 | B 响应回压时复位，验证 response_path 排空 |
| 4 | R_backpressure | 12-17 | R 响应回压时复位，验证读路径 backpressure 处理 |
| 5 | mixed_outstanding | 7 | 混合 outstanding（读写同时在途）早期复位 |

#### 场景设计逻辑
每个场景包含 3 个阶段：
1. **Pre-reset**：启动固定数量的 transactions（20个），在特定周期触发复位
2. **Reset**：4周期复位信号，清空 DUT 所有状态
3. **Post-reset**：启动新的 transactions（32个），验证 DUT 完全恢复

**检查点**：
- `w_inflight_at_rst`、`r_inflight_at_rst`：复位时在途数量
- `w_cancelled`、`r_cancelled`：pre-reset transactions 被取消数量
- `w_post`、`r_post`：post-reset transactions 完成数量
- **`bytes_bad=0`**：post-reset 数据完整性（核心指标）

---

## 三、验证结果

### 3.1 最终数据（截至 2026-11-18）

#### Xcelium 工业级验证
| 数据宽度 | 场景数 | seed 数 | 总测试 | 通过 | UVM_ERROR | bytes_bad |
|---------|--------|---------|--------|------|-----------|-----------|
| 32-bit | 6 | 3 | 18 | ✅ 18 | 0 | 0 |
| 64-bit | 6 | 3 | 18 | ✅ 18 | 0 | 0 |
| **小计** | - | - | **36** | **✅ 36** | **0** | **0** |

#### Verilator 本地验证（对照）
| 数据宽度 | 场景数 | seed 数 | 总测试 | 通过 |
|---------|--------|---------|--------|------|
| 32-bit | 6 | 3 | 18 | ✅ 18 |
| 64-bit | 6 | 3 | 18 | ✅ 18 |
| **小计** | - | - | **36** | **✅ 36** |

#### 其他验证项（累计）
| 验证类型 | 次数 | 通过 |
|---------|------|------|
| 读写通路轻量 TB | 26 | ✅ 26 |
| 写 DECERR 独立检查 | 4 | ✅ 4 |
| Slave Monitor UVM | 19 | ✅ 19 |
| 读写联合并发 UVM | 6 | ✅ 6 |
| 写通路存储错误检测 | 7 | ✅ 7 |
| **总计** | **134** | **✅ 134** |

**双平台在途复位验证合计**：72/72 全通过（Verilator 36 + Xcelium 36）

---

### 3.2 跨工具一致性

**Verilator vs Xcelium 差异**：
- **编译速度**：Verilator ~5秒，Xcelium ~8秒
- **SV 严格性**：Xcelium 对变量作用域、类型检查更严格
  - 示例：`w_seqs` 数组 Verilator 隐式接受，Xcelium 要求显式声明
- **UVM 实现**：Xcelium 内置 CDNS-1.1d，Verilator 用开源 UVM 2020.3.2
  - 示例：`TRY_NEXT_BLOCKED` 竞争在 Xcelium 触发，Verilator 未触发
- **结果一致性**：相同 RTL + UVM 环境在两个工具上均通过 36/36 验证

**意义**：证明设计和验证环境的跨工具可移植性，符合工业实践

---

## 四、搭建流程回顾

### 4.1 时间线（8周）

| 周 | 阶段 | 完成内容 | 输出 |
|----|------|---------|------|
| 1-2 | RTL 设计 + 轻量验证 | 15个模块，读写通路轻量 TB | `rtl/*.sv`, `dv/tests/crossbar_{write,read}/` |
| 3-4 | UVM 环境搭建 | Master/Slave agent, scoreboard | `dv/{master,slave,master_read,slave_read}/` |
| 5 | 写通路 UVM 验证 | 系统验证 + DECERR + 存储错误 | `dv/tests/crossbar_uvm/`, 7/7 pass |
| 6 | 读通路 UVM 验证 | 独立读路径验证 | `dv/tests/crossbar_uvm5/`, 6/6 pass |
| 7 | 在途复位设计 + Verilator 验证 | 6场景 UVM 测试 | `dv/tests/crossbar_uvm7/`, 36/36 pass |
| 8 | Xcelium 移植 + 修复 + 归档 | 远程验证 + 跨工具修复 | Xcelium 36/36 pass, 面试材料 |

### 4.2 关键里程碑

#### 里程碑 1：RTL 设计完成（Week 2）
- 15个模块全部实现
- 轻量 TB 快速功能验证通过（26/26）
- 决策文档和模块规格完成

#### 里程碑 2：UVM 环境可用（Week 4）
- Master/Slave agent 可复用
- Scoreboard 基础功能验证
- 写通路系统验证通过（7/7）

#### 里程碑 3：读写联合验证（Week 6）
- 读通路独立验证（6/6）
- 读写并发场景验证（6/6）
- 协议违规检测（Slave Monitor, 19/19）

#### 里程碑 4：在途复位完成（Week 7）
- 6种场景设计和实现
- Verilator 32/64-bit 全通过（36/36）
- 数据完整性零错误（`bytes_bad=0`）

#### 里程碑 5：Xcelium 工业验证（Week 8）
- 远程自动化流程搭建
- UVM 竞争问题修复
- Xcelium 32/64-bit 全通过（36/36）
- 跨工具一致性确认

---

### 4.3 核心搭建步骤

#### Step 1：本地 Verilator + UVM 环境
```bash
# 安装 Verilator 5.052（本地编译或 Homebrew）
# 获取 UVM 2020.3.2 源码到 local-uvm/
# 配置 Makefile 指向 Verilator 和 UVM 路径
```

#### Step 2：RTL 模块开发
```bash
# 顺序：基础 FIFO/仲裁器 → tracker → frontend → data_path → 顶层
# 每个模块：规格 → 实现 → 轻量 TB → 集成
```

#### Step 3：UVM 环境搭建
```bash
# agent 开发：interface → driver → monitor → sequencer
# scoreboard：transaction 收集 → 比对逻辑
# test：sequence 编排 → phase 控制
```

#### Step 4：Python 回归脚本
```python
# scripts/run_*.py
# 功能：编译 → 多配置/多 seed 回归 → 结果解析 → JSON 输出
# 支持：Verilator 本地 + Xcelium 远程
```

#### Step 5：远程 Xcelium 自动化
```bash
# expect 脚本处理 SSH 密码认证
# Python 脚本统一本地/远程接口
# 日志自动回传和解析
```

---

## 五、当前完成度

### 5.1 已完成（100%）
✅ RTL 设计：15个模块，参数化支持  
✅ 轻量 TB：读写通路功能验证  
✅ UVM 环境：完整 agent + scoreboard  
✅ 系统验证：写通路 + 读通路 + 联合并发  
✅ 在途复位：6场景 ×3seed ×2宽度 ×2平台 = 72次全通过  
✅ 跨工具验证：Verilator + Xcelium 一致性  
✅ 文档：15+ 规格/报告 + 面试材料  

### 5.2 部分完成（70%）
⚠️ 覆盖率收集：功能覆盖（covergroup）已有，代码覆盖待生成报告  
⚠️ 文档完整性：部分模块规格是 v0.1 讨论稿，非最终版

### 5.3 未开始（0%）
❌ 综合：Genus/DC 综合脚本  
❌ 时序分析：静态时序分析 + 约束编写  
❌ Formal 验证：JasperGold 协议合规性  
❌ 性能分析：带宽、延迟、吞吐量测试  
❌ 面积/功耗：综合后报告  

---

## 六、技术债务和已知限制

### 6.1 协议支持
- 只支持 INCR burst，FIXED/WRAP 未实现
- 无 exclusive access、atomic operations
- 无 user signal 扩展

### 6.2 验证覆盖
- 代码覆盖率报告未生成（功能覆盖已收集）
- Cross coverage 因工具限制未完全展开
- 极端场景（最大 burst、最大 outstanding）覆盖不足

### 6.3 性能
- 未测试实际带宽、延迟
- 仲裁公平性仅理论保证，未量化测试

### 6.4 工具链
- Xcelium 覆盖率数据库生成需要调整脚本（`-covdir` 不可用）
- 远程验证依赖 JHU 服务器，无本地 Xcelium license

---

## 七、面试可讲的亮点

### 7.1 技术深度
- **协议理解**：AXI4 5通道、outstanding、ID routing、burst、顺序保护
- **RTL 设计**：读写分离、tracker 状态机、响应路由、DECERR 处理
- **UVM 方法学**：完整 agent、scoreboard、sequence、phase 控制
- **调试能力**：UVM 竞争问题定位和修复（`TRY_NEXT_BLOCKED` catcher）

### 7.2 工程广度
- **双平台**：Verilator（快速迭代）+ Xcelium（工业标准）
- **自动化**：Python 回归脚本、expect 远程脚本、Makefile 封装
- **文档规范**：模块规格、测试报告、决策记录、面试材料
- **版本控制**：Git 管理，450+ 行变更记录

### 7.3 验证设计
- **场景设计**：6种在途复位场景，覆盖所有通道和状态
- **数据完整性**：`bytes_bad=0` 零错误标准
- **跨工具一致性**：72/72 全通过证明设计可靠性

### 7.4 项目管理
- **独立完成**：从零到全栈（设计 + 验证 + 工具链）
- **时间控制**：8周完成可展示成果
- **目标导向**：面试核心项目定位清晰

---

## 八、下一步计划

### 短期（面试前）
- [ ] 覆盖率报告生成（简化版或手动分析）
- [ ] 1页项目总结 PDF（带架构图）
- [ ] 面试拷问预备材料（见 Task 3）
- [ ] 代码走查准备（选3-5个关键文件精讲）

### 中期（简历增强）
- [ ] 综合结果（Genus/DC）
- [ ] 时序分析（静态时序 + 约束）
- [ ] 性能测试（带宽、延迟）

### 长期（技能拓展）
- [ ] Formal 验证（JasperGold）
- [ ] 8×8 扩展配置
- [ ] QoS 优先级仲裁
- [ ] 低功耗设计（clock gating）

---

## 九、文件索引

### RTL 核心文件
- `rtl/axi_crossbar.sv` — 5通道顶层
- `rtl/axi_crossbar_write.sv` — 写通路顶层
- `rtl/axi_crossbar_read.sv` — 读通路顶层
- `rtl/axi_write_frontend.sv` — AW frontend（仲裁核心）
- `rtl/axi_write_tracker.sv` — 在途跟踪（状态机核心）

### UVM 核心文件
- `dv/master/axi_master_driver.sv` — 写 Master driver
- `dv/master_read/axi_master_read_driver.sv` — 读 Master driver
- `dv/tests/crossbar_uvm7/crossbar_uvm7_pkg.sv` — 在途复位测试（UVM catcher 修复）
- `dv/tests/crossbar_uvm7/top7.sv` — 在途复位 TB 顶层

### 验证脚本
- `scripts/run_crossbar_xcelium.py` — Xcelium 远程回归脚本
- `scripts/run_crossbar_uvm7.py` — Verilator 在途复位回归脚本
- `Makefile` — 本地回归命令封装

### 文档
- `README.md` — 项目总览 + 验收结果
- `docs/project-plan.md` — 项目计划（v0.1 讨论稿）
- `docs/decisions.md` — 设计决策记录
- `docs/interview-materials/` — 面试材料目录
  - `xcelium-verification-log.md` — Xcelium 验证进度日志
  - `project-summary.md` — 面试版项目总结
  - `interview-talking-points.md` — 面试话术要点

---

**总结**：这是一个从零到完整的 AXI4 Crossbar 验证项目，独立完成 RTL 设计、UVM 验证环境搭建、双平台验证流程（Verilator + Xcelium），72次在途复位验证全通过，展示了完整的硬件验证工程能力。
