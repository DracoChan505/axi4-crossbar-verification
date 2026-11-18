# 参数化写 Crossbar 顶层与内部 DECERR 端

> 本文保留轻量顶层验收边界。现有 UVM 模型已在后续增量接入，见 [系统接入报告](crossbar-uvm-integration.md)。

2026-11-15。本增量完成 axi_crossbar_write 的 AW/W/B 写通路封装，内部错误端由 RTL 实现，不再由 TB 代替。它是可运行的写通路基础版本，不是五通道 AXI4 项目的最终完成版本。

## 1. 对外交付

主要入口：rtl/axi_crossbar_write.sv。内部组成包括既有译码、Tracker、AW 前端、轮询仲裁、记录 FIFO、W 两拍缓冲和 B 响应路径，以及新建 rtl/axi_write_decerr.sv。

默认 4 个外部 Master 接入 4 组 s_*，4 个物理 Slave 接到 4 组 m_*。s_/m_ 是从 Crossbar 自身端口角色命名：s_* 是 Crossbar 的从接口、连接外部 Master；m_* 是 Crossbar 的主接口、连接外部 Slave。内部第 5 个逻辑目标只用于错误处理，不暴露给外部。

配置参数为 INPUTS、SLAVES、ADDR_WIDTH、DATA_WIDTH、ID_WIDTH、INPUT_LIMIT、OUTPUT_LIMIT，默认分别为 4、4、32、32、2、2、4。STRB_WIDTH、SOURCE_WIDTH、OUTPUT_ID_WIDTH 是派生宽度，保持默认推导，不作为独立功能配置。单入口时保留一个为 0 的来源位。

端口按入口/出口编号排列为 packed array。每组提供完整的当前写 profile 信号：

- AW：VALID/READY、ADDR、ID、LEN、SIZE、BURST、LOCK、CACHE、PROT、QOS。
- W：VALID/READY、DATA、STRB、LAST。
- B：VALID/READY、ID、RESP。

顶层把此前内部 17 位 AW 属性总线拆成显式信号；不存在需要用户手工拼接属性的外部端口。下游 ID 默认 4 位，即 2 位 Master 来源加 2 位原 ID；上游 B 恢复 2 位原 ID。

输入 clk、reset_n 为单时钟和全系统低有效共同复位。map_base/map_limit 为静态配置输入，遵守此前已确定的互不重叠、4KB 对齐、包含端点的范围约定，运行中保持不变。默认测试映射仍为四个连续 64KB 区间，从 0x00000000 到 0x0003ffff；顶层实例需要连接这些配置值。

没有 AR/R、USER 或 REGION 端口，首阶段只实现已经约定的写 profile；最终读通路仍必须补齐。

## 2. 内部错误端

axi_write_decerr 保存扩展 AWID 与 AWLEN，默认容量与出口上限一致，为 4。AW 接收占用容量，B 握手释放；支持多个在途错误事务。容量满阻止新 AW，不取消已有事务。

W 按 AW 顺序消耗，无 AW 记录时 WREADY=0。逐拍计数，只有 AWLEN+1 拍全部握手后才把 BID 加入错误响应 FIFO；首拍到最后一拍都不产生任何存储写入。错误端没有存储端口，也不连接物理 Slave 的 W 通道。

BID 原样返回包含来源位的 AWID，BRESP 固定 DECERR（2'b11）。B 被阻挡时保持，响应顺序全局按错误端接收 AW 的顺序，因此满足同 ID 保序。固定按序只针对这个内部端点，不取消 Crossbar 不同 ID 跨目标乱序完成的能力。

错误端的 AW 记录 FIFO 和 B FIFO 都无直通。若最后 W 在第 N 沿握手，B 最早在 N 沿之后变为有效，第 N+1 沿可被 B 路径接收；不会提前响应。计数器支持 256 拍 burst。输入 WLAST 与 AWLEN 不符时仿真断言报 DECERR_WLAST；运行时协议故障恢复仍属后续增强。

共同复位清空在途记录、计数和 B 有效状态。已写入物理 Slave 的存储不由 Crossbar 回滚，错误访问自身不会产生物理写入。

## 3. 写通路整体时序

保持已验收的各模块约定：入口 AWREADY 寄存准入，实际握手时原子建立 Tracker、AW 记录和 W 目标记录；每入口按实际下游 AW 接收顺序推进，出口 AW 握手时写入 W 来源。

W 双向队首匹配后转发；每入口最多缓存两拍，在下游最后 W 握手时弹出两端路由记录。WLAST 不释放事务容量。

下游 B 接收到内部缓冲时释放出口预留名额，Master 接收 B 时才释放入口 Tracker；同 ID 目标绑定保持到入口排空。错误端与物理端均经过同一套 ID/容量/返回路径。

当前单条 AW/B 输出寄存器保留气泡，共享出口 B FIFO 存在队首阻塞。基础版本不承诺每拍一事务或完全端口隔离，后续性能工作要以测量为依据。

## 4. 仅使用外部接口的顶层自检

dv/tests/crossbar_write/crossbar_write_tb.sv 只连接顶层公开端口，不读取内部路由队列、计数器、完成通知或错误端信号。物理 Slave 激励仍由轻量 SystemVerilog TB 提供，这次尚未迁移到既有 UVM agent。

对映射访问，逐字段核对外部 AW、逐拍核对 WDATA/WSTRB/WLAST，并以实际物理 B 接收账本检查上游返回。对未映射访问，独立按地址归类，确认它不会出现在任意物理 AW/W 端口，只有完整输入 W burst 已握手后才允许对应上游 DECERR。最终检查事务完成/取消和数据拍数量闭合。

顶层覆盖 4×4、3×2、1×1、32/64 位地址与数据，以及入口/出口容量 1/2/3/4 的精选配置。每组运行 seed=7、41、2026。保持多入口竞争、背压、同 ID 两笔、同 ID 目标切换、W 两拍满、256 拍 burst、复位取消和响应状态检查。测试包括真正由内部 RTL 返回的 DECERR。

新增确定的跨 ID 超越场景：暂缓入口 0 的一笔正常访问响应，允许后一笔不同 ID 的错误访问先完成。首轮两个 seed7 配置未出现所需随机乱序见证，报告为失败；随后补定向激励，保留原验收门槛，最终矩阵通过。没有修改 RTL 来迎合此场景，也没有降低检查要求。

另在 3 入口配置注入非法来源 BID，要求触发 BRESP_INVALID_SOURCE。

## 5. 错误端独立自检

dv/tests/crossbar_write/decerr_tb.sv 单独检查容量 1、3、4：W 先于 AW 时背压；容量满后阻止新 AW；256 拍写未完成时不能返回 B；收齐后固定 DECERR；BREADY=0 时保持；多个返回按序；B 阶段复位后无旧响应。另故意缺失最后 WLAST，要求触发 DECERR_WLAST。

这项独立测试直接阻挡错误端 B，可以覆盖顶层 B 缓冲可能隐藏的端点背压行为。

## 6. 实际结果与运行

最终共有 17 次运行达到预期：顶层 12 次正常 + 1 次非法来源；错误端 3 次正常 + 1 次非法 WLAST。全部使用本机 Verilator 5.052，启用断言，编译警告作为失败。

结果见 [顶层机器记录](crossbar-write-results.json) 与 [错误端机器记录](decerr-results.json)，日志分别在 logs/crossbar_write 与 logs/decerr。

默认 4×4/32位/seed7 的一次运行：

- 接受 95 笔 AW，完成 79 笔，公共复位取消 16 笔。
- 16 笔未映射访问，输入共 1057 拍 W，全部收齐后返回 16 笔内部 DECERR。
- 正常端点上游返回 OKAY 32 笔、SLVERR 31 笔，加上 DECERR 16 笔，共 79 笔。
- 观察到 3 次跨 ID 完成超越、13 次多个 Master 同拍完成响应。

物理下游 B 接收为 68 笔，其中 63 笔已送达 Master、5 笔缓存期间被复位取消；内部错误端的 16 笔不出现在物理下游 B 端口，不能把两者混为同一计数。

这里错误 W 拍统计是上游对未映射请求的实际接收拍数；对已经返回 DECERR 的请求，独立检查保证完整 burst 已接收。它不是通过读取内部握手得到的计数。

运行：

```sh
make write-regress
make decerr-regress
```

顶层依赖 RTL 文件清单为 axi_record_fifo.sv、axi_write_tracker.sv、axi_address_decode.sv、axi_rr_arbiter.sv、axi_write_frontend.sv、axi_write_data_path.sv、axi_write_response_path.sv、axi_write_decerr.sv、axi_crossbar_write.sv；实际编译参数由 scripts/run_crossbar_write.py 保存到日志。

## 7. 当前边界与下一步

至此已经有参数化、包含内部错误处理的 AW/W/B 写通路 RTL 顶层及可复现自检。仍未完成 UVM 系统接入、Slave 独立 Monitor/agent、独立系统 Scoreboard、覆盖收敛、综合/STA/性能测量和 AR/R。

下一步把既有 Master/Slave 模型接入该顶层。现有 UVM 接口使用统一编译宽度宏，需要先支持同一仿真中入口 ID2 与出口 ID4 并存；不使用全端口统一 ID 宽度伪装实际接口。随后用独立的两侧观察记录检查路由和存储结果。读通路和最终五通道目标保持不变。
