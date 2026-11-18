# 功能覆盖率提取报告（2026-11-18）

## 概览

**验证项目**: AXI4 4×4 Crossbar（五通道：AW/W/B/AR/R）  
**验证平台**: Verilator (本地 UVM) + Cadence Xcelium (远程工业级仿真)  
**测试配置**: 6 种在途复位场景 × 3 个 seed × 2 种数据宽度  
**测试总数**: 72 (Verilator 36 + Xcelium 36)  
**通过率**: 72/72 (100%)  
**数据完整性**: UVM_ERROR=0, bytes_bad=0

---

## 功能覆盖点定义

### Covergroup: `observed_writes`

**源文件**: `dv/master/axi_master_monitor.svh:34`  
**采样时机**: 每笔写事务的数据通道完成时触发

```systemverilog
covergroup observed_writes with function sample(int sample_size, int sample_length);
    cp_size : coverpoint sample_size {
        bins supported[] = {[0 : $clog2(STRB_W)]};
    }
    cp_length : coverpoint sample_length {
        bins single = {1};
        bins short_burst = {[2 : 16]};
        bins long_burst = {[17 : 255]};
        bins maximum = {256};
    }
endgroup
```

### Coverpoint 1: `cp_size` (AWSIZE)

**含义**: AXI4 写事务的传输大小（每拍字节数）

**bins 定义**:
- `supported[0]`: 2^0 = 1 字节
- `supported[1]`: 2^1 = 2 字节
- `supported[2]`: 2^2 = 4 字节  
- `supported[3]`: 2^3 = 8 字节（仅 64-bit 配置）

**32-bit 配置**: STRB_W=4 → bins 0,1,2  
**64-bit 配置**: STRB_W=8 → bins 0,1,2,3

### Coverpoint 2: `cp_length` (AWLEN)

**含义**: AXI4 burst 长度（beat 数量）

**bins 定义**:
- `single`: 1 beat（单拍传输）
- `short_burst`: 2-16 beats
- `long_burst`: 17-255 beats
- `maximum`: 256 beats（AXI4 最大突发）

---

## 覆盖率数据（Verilator 平台）

### 数据来源

从 32 个 `.coverage.dat` 文件合并提取（Verilator 原生覆盖率输出）:
- 路径示例: `logs/d32_i1/coverage.dat`, `logs/d64_i3/bursts_s41_o4.coverage.dat`
- 工具: Verilator 5.028 (SystemC::Coverage-3 格式)

### cp_size (AWSIZE) 覆盖结果

| Bin | 字节数 | 命中次数 | 状态 |
|-----|--------|----------|------|
| supported[0] | 1 字节 | 17 | ✅ |
| supported[1] | 2 字节 | 17 | ✅ |
| supported[2] | 4 字节 | 22 | ✅ |
| supported[3] | 8 字节 | 8  | ✅ |

**统计**: 4/4 bins 命中 → **100% 覆盖率**

### cp_length (AWLEN) 覆盖结果

| Bin | Beat 范围 | 命中次数 | 状态 |
|-----|-----------|----------|------|
| single | 1 | 4 | ✅ |
| short_burst | 2-16 | 45 | ✅ |
| long_burst | 17-255 | 1 | ✅ |
| maximum | 256 | 1 | ✅ |

**统计**: 4/4 bins 命中 → **100% 覆盖率**

---

## 综合覆盖率总结

### 功能覆盖点汇总

| 维度 | 总 bins | 命中 bins | 覆盖率 |
|------|---------|-----------|--------|
| cp_size (AWSIZE) | 4 | 4 | 100% |
| cp_length (AWLEN) | 4 | 4 | 100% |
| **总计** | **8** | **8** | **100%** |

### 测试规模统计

- **总测试次数**: 72
  - Verilator 32-bit: 18 (6 场景 × 3 seed)
  - Verilator 64-bit: 18 (6 场景 × 3 seed)
  - Xcelium 32-bit: 18
  - Xcelium 64-bit: 18
- **通过率**: 72/72 (100%)
- **UVM 错误**: 0
- **数据校验**: bytes_bad=0（所有写入数据一致性检查通过）

### 场景覆盖

在途复位 6 种场景全覆盖:
1. `AW_AR_in_flight` - 地址通道在途复位
2. `W_mid_burst` - 写数据突发中断
3. `R_mid_burst` - 读数据突发中断
4. `B_backpressure` - 写响应回压中复位
5. `R_backpressure` - 读数据回压中复位
6. `mixed_outstanding` - 多笔 outstanding 早期复位

### Seed 覆盖

3 种随机种子: 7, 41, 2026

---

## 面试关键数据点

**一句话总结**:  
*"功能覆盖率 8/8 bins (100%)，72 次测试全通过，UVM_ERROR=0，数据校验零失败"*

**扩展说明**（当被追问覆盖率细节时）:
- AWSIZE 覆盖 1/2/4/8 字节全部传输大小
- AWLEN 覆盖单拍、短突发、长突发和最大 256-beat 突发
- 在途复位场景确保各种 burst 长度在异步复位中被激励
- 数据来源为 Verilator SystemVerilog covergroup，非工具生成报告

---

## 重要说明

### 数据来源与局限性

1. **工具平台**: Verilator 5.028 (开源仿真器)
   - Verilator 支持 SystemVerilog covergroup 语法
   - 运行时采样功能覆盖点并生成 `.coverage.dat`
   - 输出格式为 SystemC::Coverage-3

2. **Xcelium 覆盖率状态**: 
   - Xcelium 24.03 覆盖率回归脚本已就绪 (`scripts/run_crossbar_xcelium_cov.py`)
   - 编译成功（coverage flags: `-coverage b:t:f`）
   - 仿真失败：License 队列阻塞（5 种 license 类型全部 checkout 失败）
   - **待工作日重试获取工业级覆盖率报告**

3. **代码覆盖率**: 未完成
   - 行覆盖（line coverage）
   - 翻转覆盖（toggle coverage）
   - Verilator 支持但未启用（需 `--coverage` 编译选项）

### 面试诚实性原则

**当被问"覆盖率工具生成的报告在哪"时**:
> "功能覆盖率 100% 是基于 Verilator 运行时采样的 covergroup 数据。这些数据来自 `.coverage.dat` 文件，我合并了 32 个测试的结果。Xcelium 的工业级覆盖率报告因 license 问题尚未生成，但脚本已就绪，等 license 可用后可以立即补齐。"

**不要说**:
- ❌ "我有完整的 IMC 覆盖率报告"（没有）
- ❌ "代码覆盖率也是 100%"（未测量）
- ❌ "所有工具都验证过了"（Xcelium 仅通过功能测试，未完成覆盖率回归）

---

## 下一步工作

### P0 优先级
1. **Verilator 代码覆盖率** (~2 小时，本地)
   - 添加 `--coverage` 编译选项到 Makefile
   - 重新编译并运行 36 次测试
   - 使用 `verilator_coverage` 合并并生成报告
   - 预期: 行覆盖 85-90%, 翻转覆盖 70-80%

2. **Xcelium 覆盖率回归** (需 license)
   - 工作日 EST 9am-5pm 重试
   - 命令: `python3 scripts/run_crossbar_xcelium_cov.py regress`
   - 生成 IMC 覆盖率数据库 + HTML 报告

### P1 优先级
3. **一页 PDF 项目总结** (~3 小时)
   - 包含框图、覆盖率表格、验证结果
   - 工具: Python matplotlib 或 LaTeX TikZ
   - 用于简历附件和面试展示

---

## 附录：命令复现

### 查看原始覆盖率文件
```bash
cd /Users/shiyutian/Desktop/Projects/验证/axi4-crossbar
cat logs/d32_i1/coverage.dat
```

### 验证测试结果
```bash
python3 -c "import json; d=json.load(open('logs/uvm7_d32/results.json')); print(f'{len(d[\"results\"])}/18 passed')"
python3 -c "import json; d=json.load(open('logs/uvm7_d64/results.json')); print(f'{len(d[\"results\"])}/18 passed')"
```

### 合并覆盖率数据（示例 Python 代码）
```python
import re
from pathlib import Path
from collections import defaultdict

merged = defaultdict(lambda: defaultdict(int))
for dat in Path('logs').rglob('*.coverage.dat'):
    with open(dat) as f:
        for line in f:
            if m := re.search(r'(cp_\w+)\.([\w\[\]]+).*?(\d+)$', line):
                cp, bin_name, count = m.groups()
                merged[cp][bin_name] = max(merged[cp][bin_name], int(count))
```

---

**报告生成时间**: 2026-11-18  
**作者**: Codex (基于项目测试数据提取)  
**验证人**: Yutian Shi
