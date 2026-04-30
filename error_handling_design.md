# ColouredFlow Runner — Error Handling 设计方案

> 状态：**v3.1（codex round-3 APPROVED WITH CONDITIONS；4 项条件已应用 →
> 终稿）**。待用户 review。 范围：`ColouredFlow.Runner.*`。下游模块（expression
> / enabled_binding_elements / multi_set / definition）仅在 runner
> 暴露错误的接口处涉及。

## 0. 修订历程摘要

**v1 → v2**（针对 codex v1 review）：

- 收窄 v1 范围至 tiering + Tier 2 funnel + caller-safe wrapper + telemetry 收敛
- CrashLedger / ErrorHandler / Recovery / Sharding / Backoff 全部移
  future（独立设计先过审）
- 撤回预设 `max_restarts`/`max_seconds` 数值
- 区分 lifecycle exception 与 span exception
- 公开承认 leak modes
- 加 P0 caller-safety 测试切片

**v3 → v3.1**（应用 codex round-3 APPROVED WITH CONDITIONS 4 项）：

- §6.1 snapshot 写策略按调用点分：bootstrap（`enactment.ex:121`）vs
  async（`enactment.ex:353`）；二者均非致命，但代价不同。
- §6.1 + §5.2.2 补 caller 入口：首次
  `handle_continue(:calibrate_workitems, _)`（`enactment.ex:141`）+
  `Runner.terminate_enactment/2` → `Enactment.Supervisor.terminate_enactment/2`
  路径走 caller-safe wrapper。
- §6.1 `occurrences_stream/2` 失败按错因拆：infra 错（DB 断、`Repo.all`
  异常）Tier 3 让崩；decode/replay 错（codec 损坏、`CatchingUp.apply/2`
  内崩）Tier 2 转 funnel `:replay_failed`。
- §4.6 `:reoffer_s` 名称统一（v3 误写 `:reoffer`，已修；`workitem_logs.action`
  enum 已含 `:reoffer_s`，无须迁移）；§5.2.3 新增 `terminate/2` 识别
  `{:shutdown, {:fatal, reason}}` 与 `{:fatal_persistence_failed, _}`，emit
  结构化 stop 事件，去除 `"unknown"` 占位。

**v2 → v3**（针对 codex v2 review 5 项 verdict + 抽查发现）：

- **统一 Tier 2 漏斗**：把现有 `check_termination` 的
  `termination_criteria_evaluation` 致命路径折入新
  funnel（`enactment.ex:243-256` 与新路径**共用同一 helper**），而非两套。
- **Storage 契约改的 caller surface 全枚举**：P0-3 / P0-4 不止是 storage
  层改返；同步改 `Runner.terminate_enactment/2`、span-wrapped
  写（`produce_workitems` `start_workitems` `withdraw_workitems`
  `complete_workitems`）以及 `Runner.insert_enactment/1` 等所有
  caller，每处显式分类 tier。
- **Caller-safe wrapper 全 exit surface**：除 `:noproc` `:timeout` 外，覆盖
  `:nodedown` `:shutdown` `:normal` `:killed` `:calling_self` 及任何其他
  reason；统一归一为 typed exception。
- **Rescue 跨所有 callback 入口**：`populate_state` 仅一处；同改
  `handle_continue({:calibrate_workitems, _, _}, _)`、`handle_call({:complete_workitems, _}, _, _)`、`handle_call({:start_workitems, _}, _, _)`、`handle_cast(:take_snapshot, _)`
  等所有读 storage 的入口。
- **Recovery preconditions 补全**：含 zero-occurrence case；`:reoffer_started`
  后置条件（被 reoffer 的 workitem 释放其预占 token，markings 从 in-memory
  状态回滚）。
- **新增 `:resumed` event**：区分 first boot 与 crash-restart。
- **Telemetry exception 持久化加 stacktrace**（仅当真有时；EnactmentLog
  `embeds_one :exception` 加 `stacktrace_text` 字段）。

## 1. v1 范围（明确边界，与 v2 同）

**v1 in scope（P0+P1，必须落地）**：

- 错误层级（Tier 1-4）静态分类；提供 `Errors` facade
- **统一**致命错误漏斗 `to_exception/3`（覆盖现有 + 新增 Tier 2 路径）
- **跨所有 callback 入口** rescue 转 funnel
- Storage 行为契约扩展 + **所有 caller** 同步更新
- Caller-safe wrapper：**全 GenServer.call exit surface** 转 typed exception
- 公共 exception 加 stable `error_code: atom()`
- Telemetry 元数据加 `tier` `lifecycle` `severity` `source_phase`；区分
  lifecycle vs span；删除无依据 `:stacktrace` 默认
- 新增 `:resumed` lifecycle event（first boot vs crash-restart 区分）
- Supervisor `max_restarts` / `max_seconds` 暴露 knob（默认不变）
- 测试切片：caller-safety + fatal-reason 持久化扩展
- Leak modes 文档化

**v1 out of scope（推迟 future，独立设计先过审）**：

- `ErrorHandler` behaviour（telemetry-only 替代）
- CrashLedger 自熔断
- `Runner.recover_enactment/2`（须前置完整 storage 切片 + audit 不变量）
- `Runner.reoffer_workitem/2`（同上）
- Bulkhead sharding、backoff supervisor
- `Utils.fetch_*!` 改 typed exception
- Tier 1 → Tier 2 自动升级

## 2. OTP 原则与本系统映射（与 v2 同）

| OTP 原则                               | 本系统映射                                                                                                                                              |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 错误内核 vs 容忍区                     | **错误内核 = 持久化事件流（snapshot + occurrence + workitem_logs + enactment_logs）**，非 GenServer 进程态。GenServer 是事件流的 in-memory projection。 |
| Let it crash                           | 仅当**重启真能恢复**时让进程崩。                                                                                                                        |
| `:transient`                           | `:normal                                                                                                                                                |
| `:ignore` from `init/1`                | DynamicSupervisor 视为正常结果。v1 不引入；future CrashLedger 引入时须在 `Runner.start_enactment/1` 边界归一为 typed `EnactmentQuarantined`。           |
| `init/1` 早返 + `handle_continue` 重活 | 现行结构正确，保留并依赖。                                                                                                                              |
| 显式 return tuple                      | 公共 API 守 `{:ok, _}                                                                                                                                   |
| Telemetry 解耦                         | 监控 / 日志 / 告警 / trace 走 telemetry handler；hot path 不接外部代码。                                                                                |

## 3. 错误层级（Tier 1-4）

| Tier | 触发分类                             | 行为                                                                                                           |
| ---- | ------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| 1    | 调用方错 / user-supplied 数据错      | `{:error, exception}` 同步返回；DB `:running` 不变；走 span exception                                          |
| 2    | Enactment 致命（不可重启自愈）       | 经统一 funnel 写 DB `:exception` + lifecycle exception event + `{:stop, {:shutdown, {:fatal, reason}}, state}` |
| 3    | 基础设施瞬时错（重启可能恢复）       | 不 rescue，let it crash；受 supervisor `max_restarts` 约束                                                     |
| 4    | 编程错（validator 通过后理论不触及） | 保留现状 raise；触及即 audit                                                                                   |

### Tier 1 — 操作错误（用户感知；同步返回；进程不变）

| 触发                                                               | Exception 模块                                  | error_code                     |
| ------------------------------------------------------------------ | ----------------------------------------------- | ------------------------------ |
| workitem 不存在 / 已 completed / 已 withdrawn                      | `Runner.Exceptions.NonLiveWorkitem`             | `:non_live_workitem`           |
| workitem 状态机违例                                                | `Runner.Exceptions.InvalidWorkitemTransition`   | `:invalid_workitem_transition` |
| token 不足以消费                                                   | `Runner.Exceptions.UnsufficientTokensToConsume` | `:unsufficient_tokens`         |
| transition action 输出变量缺                                       | `Runner.Exceptions.UnboundActionOutput`         | `:unbound_action_output`       |
| 输出值类型不匹配                                                   | `Definition.ColourSet.ColourSetMismatch`        | `:colour_set_mismatch`         |
| Action / arc 表达式求值出错                                        | `Expression.InvalidResult` 或原始 ex            | `:expression_eval_failed`      |
| **新** enactment 已停 / 隔离 / 未启                                | `Runner.Exceptions.EnactmentNotRunning`         | `:enactment_not_running`       |
| **新** GenServer.call 超时                                         | `Runner.Exceptions.EnactmentTimeout`            | `:enactment_timeout`           |
| **新** GenServer.call 异常 exit（非 noproc/timeout）               | `Runner.Exceptions.EnactmentCallFailed`         | `:enactment_call_failed`       |
| **新** 持久化失败（caller-facing，如 `Runner.insert_enactment/1`） | `Runner.Exceptions.StoragePersistenceFailed`    | `:storage_persistence_failed`  |

### Tier 2 — Enactment 致命错误（用户感知；优雅停机）

| 触发                                | reason atom                                     |
| ----------------------------------- | ----------------------------------------------- |
| 终止条件求值失败（已实现）          | `:termination_criteria_evaluation`              |
| Storage 状态漂移                    | `:state_drift`                                  |
| Snapshot 反序列化损坏               | `:snapshot_corrupt`                             |
| Occurrence 重放失败                 | `:replay_failed`                                |
| 启动时 flow / enactment 行缺失      | `:enactment_data_missing`                       |
| 启动时 cpnet 损坏（codec 错）       | `:cpnet_corrupt`                                |
| 致命错持久化自身失败（leak mode 1） | `:fatal_persistence_failed`（仅出现在降级路径） |

行为：经统一 funnel `to_exception/3`（§5.1）。**含现有 `check_termination`
路径折入**。

### Tier 3 — 基础设施瞬时（系统处理）

DB 连接断、网络抖、Repo 偶发 deadlock。让异常冒泡 → supervisor 重启 →
`populate_state` 重读重放。v1 不调默认 `max_restarts`，仅暴露 knob。

### Tier 4 — 编程错（开发期）

DSL 编译期 raise、validator 静态检查、`Utils.fetch_*!`。runtime 触及即记
supervisor crash + audit。v1 不改造。

## 4. 用户集成 API

「Telemetry first」。无 in-process 钩子。

### 4.1 `Runner.Errors` facade

```elixir
defmodule ColouredFlow.Runner.Errors do
  @spec tier(Exception.t()) :: 1 | 2 | 3 | 4
  @spec error_code(Exception.t()) :: atom()
  @spec lifecycle?(Exception.t()) :: boolean()
  @spec to_persisted_reason(Exception.t()) :: ColouredFlow.Runner.Exception.reason() | nil
end
```

中央化分类，`case` 模式匹配 module name + 字段。新增 exception
必须在此注册。**不**依赖 exception module 自报 metadata（系统也分类外部
exception 如 `ArithmeticError` `Expression.InvalidResult`
`ColourSet.ColourSetMismatch`）。

`ColouredFlow.Runner.Exception.reason/0` enum
仍是「持久化致命原因」专用，不重载为全局分类法。

### 4.2 公共 exception 加 `error_code`

每个 `Runner.Exceptions.*` exception 加 `error_code: atom()`
字段（编译期常量）。

**兼容性注意**：现有 caller 多以 `match` exception module 模式使用；加字段对
`is_struct(ex, Module)` `match? %Module{}` 模式无影响。仅 positional `struct/2`
调用受影响 — 全代码库 grep 确认无此用法（`Module.exception/1` 全部用 keyword
args）。

### 4.3 Telemetry 不变量

| 不变量 | 内容                                                                                                                                                           |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1      | 每次持久化 `:exception` 状态转换**恰好**触发一条 lifecycle exception event：`[:coloured_flow, :runner, :enactment, :exception]`。                              |
| 2      | 每次操作内部失败（含返回 `{:error, _}` 与 rescued raise）触发 span exception event：`[:coloured_flow, :runner, :enactment, :{op}, :exception]`。               |
| 3      | 不变量 1 与 2 互不重复。                                                                                                                                       |
| 4      | 致命降级路径（leak mode 1：致命错持久化自身失败）emit 一条特殊 lifecycle event 元数据 `degraded: true`，确保即便 DB 全挂 ops 也能从 telemetry 看到致命发生过。 |

新增 metadata 字段：

| 字段           | 类型                    | 含义                                         |
| -------------- | ----------------------- | -------------------------------------------- |
| `tier`         | `1                      | 2                                            |
| `lifecycle`    | `boolean()`             | `true` 仅 lifecycle event                    |
| `severity`     | `:operational           | :fatal`                                      |
| `error_code`   | `atom()`                | 来自 exception                               |
| `source_phase` | `atom()                 | nil`                                         |
| `stacktrace`   | `Exception.stacktrace() | nil`                                         |
| `degraded`     | `boolean()`             | `true` 仅 leak mode 1 降级路径（持久化失败） |

### 4.4 lifecycle 事件清单（v1 终态）

```text
[..., :enactment, :start]                  # 已有 — first boot
[..., :enactment, :resumed]                # 新 — crash-restart（区分 first boot）
[..., :enactment, :stop]                   # 已有
[..., :enactment, :terminate]              # 已有
[..., :enactment, :exception]              # 已有，加 metadata 字段；含 degraded 路径
```

`:resumed` 触发：`populate_state` 完成后若 snapshot.version > 0 或有 occurrence
重放过，emit `:resumed` 而非 `:start`。`:start` 仅 first boot（version == 0 且
occurrence 流空）。

### 4.5 Caller-safe wrapper（v1 P0；全 exit surface）

```elixir
@call_timeout 5_000

@spec start_workitem(enactment_id, workitem_id) ::
        {:ok, Workitem.t(:started)} | {:error, Exception.t()}
def start_workitem(enactment_id, workitem_id) do
  call_enactment(enactment_id, {:start_workitems, [workitem_id]}, fn
    [workitem] -> {:ok, workitem}
  end)
end

defp call_enactment(enactment_id, message, on_ok) do
  case Registry.whereis_name({:enactment, enactment_id}) do
    :undefined ->
      {:error, EnactmentNotRunning.exception(enactment_id: enactment_id)}

    pid when is_pid(pid) ->
      try do
        case GenServer.call(pid, message, @call_timeout) do
          {:ok, result} -> on_ok.(result)
          {:error, _} = err -> err
        end
      catch
        :exit, {:noproc, _} ->
          {:error, EnactmentNotRunning.exception(enactment_id: enactment_id)}

        :exit, {:timeout, _} ->
          {:error, EnactmentTimeout.exception(enactment_id: enactment_id, timeout: @call_timeout)}

        :exit, {:shutdown, _} ->
          # called process shutting down (e.g. graceful Tier 2 stop in flight)
          {:error, EnactmentNotRunning.exception(enactment_id: enactment_id, reason: :shutting_down)}

        :exit, {:normal, _} ->
          # called process exited normally during call
          {:error, EnactmentNotRunning.exception(enactment_id: enactment_id, reason: :stopped_during_call)}

        :exit, {:nodedown, node} ->
          {:error, EnactmentCallFailed.exception(enactment_id: enactment_id, reason: {:nodedown, node})}

        :exit, {:killed, _} ->
          {:error, EnactmentCallFailed.exception(enactment_id: enactment_id, reason: :killed)}

        :exit, {:calling_self, _} ->
          # programming error — let it crash to surface
          reraise %ArgumentError{message: "calling self via Runner API"}, __STACKTRACE__

        :exit, reason ->
          # catch-all for any other reason; surfaces process crash mid-call
          {:error, EnactmentCallFailed.exception(enactment_id: enactment_id, reason: reason)}
      end
  end
end
```

要点：

- `:undefined` 立即返 `EnactmentNotRunning`，免做 `GenServer.call` 然后吃
  `:noproc`。
- `whereis` 与 `call` 之间存在 race（whereis 返 pid，call 抵达前 pid 已死）→
  `:exit, {:noproc, _}` 与 `:exit, {:normal, _}` 双覆盖保障。
- `call_in_flight + process dies` → `:exit, {:shutdown, _}` 或
  `:exit, reason`，统一 typed exception。
- `:calling_self` 仅 reraise（编程错、应崩出）。

### 4.6 Recovery（推迟 future，但前提显式）

`Runner.recover_enactment/2` `Runner.reoffer_workitem/2` 不在 v1。落地前置：

#### Recovery invariants

1. `enactments.state` 与 `enactment_logs` 状态序列一致（每次状态变更追加日志）。
2. `workitem_logs` 序列与 `workitems` 当前状态一致（最后一条 `to_state` == 当前
   `state`）。
3. `occurrences.step_number` 单调递增、无空洞、最大值 == `enactments`
   已应用的版本。
4. `snapshots.version` ≤ `max(occurrences.step_number)`；**zero-occurrence
   case**：若该 enactment 从未发生过 occurrence，`snapshots.version` 必须为 0 且
   `markings` 等于 `enactments.initial_markings`。
5. 任何 recovery 操作必须在 `Repo.transaction/1` 内完成上述四个 schema
   同步更新；不存在「只改 enactments.state，不改其余」的部分恢复。

#### `:reoffer_started` 后置条件

把 `:started` workitem 改回 `:enabled` 时必须保证：

a. 该 workitem 的 `binding_element.to_consume` markings **不**实际反向加回
storage（因为 occurrence 流并未应用过 — `:started`
仅是「资源已分配未消费」状态；token 当前在 in-memory state.markings
中是「保留」非「消费」）。 b. 仅 enactment GenServer in-memory state 的
`workitems` map 该项 state 改为 `:enabled`；下次 `calibrate_workitems` 自然重算
enabledness。 c. `workitem_logs` 追加一条
`{from_state: :started, to_state: :enabled, action: :reoffer_s}`。`:reoffer_s`
已在 `workitem_logs.action` Ecto.Enum 内（`workitem_log.ex:24-28` 由
`Workitem.__transitions__/0` 派生），**无须**枚举扩展。 d. 不得触动
`occurrences` `snapshots` `markings`。 e. 跨 enactment 重启边界：reoffer 写
`workitem_logs` 后即生效；下次 enactment 启动 `populate_state` 通过
`Storage.list_live_workitems` 读到该 workitem 为 `:enabled`，自然延续。

#### 必备 storage 行为扩展

```elixir
@callback recover_enactment(enactment_id, strategy :: :resume | :reoffer_started) ::
  {:ok, recovered_state :: map()} | {:error, term}
@callback reoffer_workitem(workitem :: Workitem.t(:started)) ::
  {:ok, Workitem.t(:enabled)} | {:error, term}
```

须改：`Storage.Default`、`Storage.InMemory`。独立 PR 序列。

## 5. Supervisor 雪崩防御（v1 三道）

### 5.1 防线 1：统一 Tier 2 漏斗（覆盖**所有**致命路径）

#### 函数签名

```elixir
@spec to_exception(state(), reason :: atom(), context :: map()) ::
        {:stop, {:shutdown, {:fatal, atom()}}, state()}
        | {:stop, {abnormal_reason :: term()}, state()}
defp to_exception(%__MODULE__{} = state, reason, ctx) do
  exception = Errors.build_exception(reason, ctx)

  case Storage.exception_occurs(state.enactment_id, reason, exception) do
    :ok ->
      emit_event(:exception, state, %{
        tier: 2,
        lifecycle: true,
        severity: :fatal,
        source_phase: ctx.phase,
        exception_reason: reason,
        error_code: exception.error_code,
        exception: exception,
        degraded: false
      })

      {:stop, {:shutdown, {:fatal, reason}}, state}

    {:error, persistence_error} ->
      # leak mode 1：致命错的持久化本身失败
      emit_event(:exception, state, %{
        tier: 2,
        lifecycle: true,
        severity: :fatal,
        source_phase: ctx.phase,
        exception_reason: reason,
        error_code: exception.error_code,
        exception: exception,
        degraded: true,
        persistence_error: persistence_error
      })

      Logger.error("Tier 2 fatal but persistence failed: ...")
      {:stop, {:fatal_persistence_failed, persistence_error}, state}
      # ↑ abnormal exit；计入 supervisor 额度；公开承认（§7 leak mode 1）
  end
end
```

#### 现有 Tier 2 路径折入

`enactment.ex:243-256` 当前 `check_termination/2` 内联致命路径：

```elixir
# 当前
{:error, exception} ->
  :ok = Storage.exception_occurs(state.enactment_id, :termination_criteria_evaluation, exception)
  emit_event(:exception, state, %{...})
  {:stop, "Terminated due to ...", state}
```

改为：

```elixir
{:error, exception} ->
  to_exception(state, :termination_criteria_evaluation, %{
    phase: :check_termination,
    underlying_exception: exception
  })
```

#### 新增 Tier 2 路径

| 触发位                                                                          | 调 funnel 处              |
| ------------------------------------------------------------------------------- | ------------------------- |
| `populate_state` snapshot 反序列化错                                            | `:snapshot_corrupt`       |
| `populate_state` occurrence 重放错                                              | `:replay_failed`          |
| `populate_state` `Repo.one!`/`Repo.get!` 失败（行缺失）                         | `:enactment_data_missing` |
| `populate_state` cpnet codec 错                                                 | `:cpnet_corrupt`          |
| `handle_call({:start_workitems, _}, _, _)` storage 漂移                         | `:state_drift`            |
| `handle_call({:complete_workitems, _}, _, _)` storage 漂移                      | `:state_drift`            |
| `handle_continue({:calibrate_workitems, _, _}, _)` storage 漂移                 | `:state_drift`            |
| `handle_continue({:calibrate_workitems, _, _}, _)` `get_flow_by_enactment` 失败 | `:enactment_data_missing` |
| `handle_cast(:take_snapshot, _)` 失败                                           | `:state_drift`            |

每处 callback 入口包裹 `try/rescue`（§5.2）；rescue 块归一调 funnel。

### 5.2 防线 2：Caller-safe wrapper + 跨入口 rescue

#### 5.2.1 公共 API caller-safe wrapper（§4.5）

#### 5.2.2 Callback 入口 rescue

每个会读 storage 或调用 expression 求值的 callback 入口均须 rescue：

```elixir
def handle_continue(:populate_state, %__MODULE__{} = state) do
  try do
    # 现有逻辑
  rescue
    e in [Schemas.Snapshot.DecodeError] ->
      to_exception(state, :snapshot_corrupt, %{phase: :populate_state, underlying: e})

    e in [Ecto.NoResultsError] ->
      to_exception(state, :enactment_data_missing, %{phase: :populate_state, underlying: e})

    e ->
      # 未识别异常：保持 Tier 3 行为（让 supervisor 重启）
      reraise e, __STACKTRACE__
  end
end
```

`reraise` 关键：未识别异常**不**误转 Tier 2；原 Tier 3
语义保留，仅识别的致命模式才转。

类似 rescue 应用于以下 callback 入口：

- `handle_continue(:calibrate_workitems, _)` — **首次**
  calibrate（`enactment.ex:141-150`）；调 `Storage.get_flow_by_enactment` +
  `WorkitemCalibration.initial_calibrate` + `apply_calibration` +
  `check_termination`；任一 storage 失败转 funnel
- `handle_continue({:calibrate_workitems, _, _}, _)` — transition 后
  calibrate（`enactment.ex:153-171`）；同上
- `handle_call({:start_workitems, _}, _, _)`（`enactment.ex:281-298`）
- `handle_call({:complete_workitems, _}, _, _)`（`enactment.ex:300-347`）
- `handle_cast(:take_snapshot, _)`（`enactment.ex:350-357`）— snapshot 写失败
  logs + 不转 Tier 2（§6.1）
- `handle_call({:terminate, _}, _, _)`（`enactment.ex:261-274`）—
  `Storage.terminate_enactment` 失败转 funnel
  `:terminate_persistence_failed`（写库失败意味着 enactment 状态不可信，应进
  `:exception`）

注意：`with_span/4` 内部已有 rescue（`telemetry.ex:177-202`）但是
reraise；不冲突 — span rescue 用于 emit `:exception` event 后 reraise，再被外层
callback rescue 捕获并归类。reraise 保留原始 `kind` / `reason` /
`stacktrace`（`telemetry.ex:189`、`telemetry.ex:202`），无 fidelity 损失。

#### 5.2.3 `terminate/2` 识别结构化 reason

当前 `terminate/2`（`enactment.ex:517-523`）对非 `{:shutdown, _}` reason 一律
emit `reason: "unknown"`，丢失 leak mode 1 信息。改为：

```elixir
def terminate({:shutdown, {:fatal, reason}}, state) when is_atom(reason) do
  emit_event(:stop, state, %{reason: {:shutdown, {:fatal, reason}}, fatal_reason: reason})
end

def terminate({:shutdown, reason}, state) do
  emit_event(:stop, state, %{reason: reason})
end

def terminate({:fatal_persistence_failed, persistence_error}, state) do
  emit_event(:stop, state, %{reason: :fatal_persistence_failed, persistence_error: persistence_error})
end

def terminate(reason, state) do
  emit_event(:stop, state, %{reason: reason})
end
```

`reason` metadata 类型由 string 升为 term；订阅者更新。

### 5.3 防线 3：Supervisor knob（v1 P1）

```elixir
def init(_) do
  opts = Application.get_env(:coloured_flow, __MODULE__, [])
  DynamicSupervisor.init(
    [strategy: :one_for_one]
    |> Keyword.merge(Keyword.take(opts, [:max_restarts, :max_seconds]))
  )
end
```

**默认沿用 OTP `3/5s`，不预设新值**。

### 推迟 future

- CrashLedger / Bulkhead / Backoff（独立设计文档先过审）

## 6. Storage 行为契约改的 caller 全枚举（P0-3 / P0-4）

### 6.1 现有 Storage callback 返回类型

| Callback                                                                                                                                                                             | 当前行为                                                 | v1 改造                                                                                                                                 | caller 改动                                                                                                                                                                                                                                                                                                                                                             |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `exception_occurs/3`                                                                                                                                                                 | Multi 失败 raise                                         | 改返 `:ok                                                                                                                               | {:error, {:reason, ctx}}`                                                                                                                                                                                                                                                                                                                                               |
| `insert_enactment/1`                                                                                                                                                                 | Multi 失败 raise（caller-facing）                        | 改返 `{:ok, schema}                                                                                                                     | {:error, %StoragePersistenceFailed{}}`                                                                                                                                                                                                                                                                                                                                  |
| `terminate_enactment/4`                                                                                                                                                              | Multi 失败 raise                                         | 改返 `:ok                                                                                                                               | {:error, {:terminate_persistence_failed, ctx}}`                                                                                                                                                                                                                                                                                                                         |
| `produce_workitems/2`                                                                                                                                                                | Multi 失败 raise（span 内）                              | 改返 `[Workitem.t(:enabled)]                                                                                                            | {:error, {:produce_persistence_failed, ctx}}`                                                                                                                                                                                                                                                                                                                           |
| `start_workitems/2`                                                                                                                                                                  | `transition_workitems` 漂移 raise（span 内）             | 改返 `:ok                                                                                                                               | {:error, {:state_drift, ctx}}`                                                                                                                                                                                                                                                                                                                                          |
| `withdraw_workitems/2`                                                                                                                                                               | 同上                                                     | 同上                                                                                                                                    | enactment.ex L201、L204 caller 接                                                                                                                                                                                                                                                                                                                                       |
| `complete_workitems/4`                                                                                                                                                               | `unexpected_updated_rows!` raise（span 内）              | 改返 `:ok                                                                                                                               | {:error, {:state_drift, ctx}}`                                                                                                                                                                                                                                                                                                                                          |
| `take_enactment_snapshot/2`（**bootstrap**，`enactment.ex:121`，catchup 后、live-workitem 载入前）                                                                                   | `Repo.insert!` 异常                                      | 改返 `:ok                                                                                                                               | {:error, {:snapshot_persistence_failed, ctx}}`                                                                                                                                                                                                                                                                                                                          |
| `take_enactment_snapshot/2`（**async**，`enactment.ex:353`，complete_workitems 后）                                                                                                  | 同上                                                     | 同上                                                                                                                                    | `handle_cast(:take_snapshot, _)` 接：记 telemetry + 继续运行；**不**转 Tier 2（下次 complete 自然重试）                                                                                                                                                                                                                                                                 |
| `read_enactment_snapshot/1`                                                                                                                                                          | `Repo.get_by` 安全（返 nil）；codec 反序列化错可能 raise | rescue codec 错 → `{:error, :snapshot_corrupt}`                                                                                         | `populate_state` 接                                                                                                                                                                                                                                                                                                                                                     |
| `get_flow_by_enactment/1`                                                                                                                                                            | `Repo.one!` raise（行缺失）                              | 行缺失改返 `{:error, :enactment_data_missing}`；连接错仍冒泡（Tier 3）                                                                  | 多处 caller：`populate_state` 隐式经 `read_enactment_snapshot`、`handle_continue(:calibrate_workitems, _)`（**首次 calibrate**，`enactment.ex:142`）、`handle_continue({:calibrate_workitems, _, _}, _)`（**transition 后 calibrate**，`enactment.ex:162`）、`handle_call({:complete_workitems, _}, _, _)`（`enactment.ex:492`）。每处接 `{:error, _}` 转 Tier 2 funnel |
| `get_initial_markings/1`                                                                                                                                                             | `Repo.get!` raise                                        | 同上                                                                                                                                    | `populate_state` 接                                                                                                                                                                                                                                                                                                                                                     |
| `Runner.terminate_enactment/2` → `Enactment.Supervisor.terminate_enactment/2` → 内部 `GenServer.call(via, {:terminate, options})`（`runner.ex:11`、`enactment/supervisor.ex:39-43`） | 当前对停掉/隔离的 enactment 抛 `:noproc` exit 至 caller  | 同 `WorkitemTransition`，包 caller-safe wrapper（§4.5）— 改 `Enactment.Supervisor.terminate_enactment/2` 用同一 `call_enactment` helper | 公共 API 返回类型从 `:ok` → `:ok                                                                                                                                                                                                                                                                                                                                        |
| `occurrences_stream/2`（**infra 错**：DB 连接断、`Repo.all` 异常）                                                                                                                   | 异常冒泡                                                 | 保留 — Tier 3，let it crash → supervisor 重启                                                                                           | `populate_state` 不 rescue 此类                                                                                                                                                                                                                                                                                                                                         |
| `occurrences_stream/2`（**decode/replay 错**：codec 失败、occurrence 损坏、`CatchingUp.apply/2` 内 `MultiSet` 操作错）                                                               | 异常冒泡                                                 | rescue 后转 Tier 2 `:replay_failed`                                                                                                     | `populate_state` 内 try/rescue 显式捕获，调 funnel；流在 `CatchingUp.apply/2` 同步全消耗（`enactment.ex:173-179`），故可在 callback 边界捕                                                                                                                                                                                                                              |
| `list_live_workitems/1`                                                                                                                                                              | `Repo.all` 异常冒泡                                      | 保留（Tier 3）                                                                                                                          | 无                                                                                                                                                                                                                                                                                                                                                                      |

### 6.2 `Storage.InMemory` 同步改造

每个改契约的 callback 须在 `in_memory.ex`
同步更新返回类型；`not_found!/1`（`in_memory.ex:318`）裸 raise 需评估是否同改 —
测试用，可能保留 raise 但加 typed exception。

### 6.3 测试覆盖

- 每个 storage 错误路径测试用例（注入 Multi 失败 / 行缺失 / 反序列化错 → 验证
  caller 行为）
- Caller-safety 测试：停掉 / 未启 / 致命停机 / 隔离的 enactment 调公共 API →
  期望 typed exception
- Fatal reason 持久化测试：扩展后的 `:reason` enum 在 EnactmentLog 写读全
  round-trip
- Lifecycle vs span exception telemetry 不变量测试

## 7. Leak modes（公开承认）

| # | leak mode                             | 描述                                                                                                 | 缓解                                                                                               |
| - | ------------------------------------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| 1 | 致命错的持久化本身失败                | `Storage.exception_occurs/3` 自身需 Repo；Repo 全挂时降级为 abnormal exit、计入 supervisor 额度      | funnel 中 emit `degraded: true` lifecycle event；ops 仍可见致命；Repo 恢复后 supervisor 重启即正常 |
| 2 | `:kill` 信号                          | `terminate/2` 不调                                                                                   | v1 不依赖 `terminate/2` 做任何状态保存                                                             |
| 3 | Registry 单点                         | `Registry` 进程崩 → 所有 `via` 名失效                                                                | OTP supervisor 自动重启 Registry；不在 enactment 路径上做防御                                      |
| 4 | 节点级 Repo 全挂                      | 所有 enactment `populate_state` 同步失败 → DS 额度可能耗尽                                           | future：boot gate；v1 仅文档                                                                       |
| 5 | `populate_state` 完成前 caller 调 API | call 入队等 handle_continue；GenServer 串行处理消息无 leak                                           | 文档化此契约                                                                                       |
| 6 | Tier 2 funnel emit_event 失败         | telemetry handler 错冒泡到 emit_event                                                                | telemetry 库 handler 错误隔离；仍记录                                                              |
| 7 | Storage 契约改后 caller 漏处理        | dialyzer 不报、测试不覆盖                                                                            | P0-3 dialyzer + 全 caller 测试覆盖；CI gate                                                        |
| 8 | zero-occurrence enactment recovery    | 若 enactment 从未 occurrence 而进 `:exception` 后 recover，`:reoffer_started` 无 workitem 可 reoffer | future：`recover_enactment` 检测 zero-occurrence 自动降级为 `:resume`                              |
| 9 | `whereis` 与 `call` 之间 race         | pid 返回后死掉前抵达 call                                                                            | caller-safe wrapper 全 exit surface 覆盖（§4.5）                                                   |

## 8. 实施清单

### P0 — Foundation

| #    | 项                                                           | 文件                                                                                                                                                                                                        | 依赖       |
| ---- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| P0-1 | `Runner.Errors` facade（内部用）                             | 新模块 `runner/errors.ex` + 测试                                                                                                                                                                            | 无         |
| P0-2 | 公共 exception 加 `error_code` 字段                          | `runner/exceptions/*.ex` + `definition/colour_set/colour_set_mismatch.ex` + `expression/invalid_result.ex` + 新增 `EnactmentNotRunning` `EnactmentTimeout` `EnactmentCallFailed` `StoragePersistenceFailed` | P0-1       |
| P0-3 | `Storage` 行为契约改（§6.1 全表）                            | `runner/storage/storage.ex` 契约 + `runner/storage/default.ex` impl + `runner/storage/in_memory.ex` impl + 错误路径测试                                                                                     | P0-1       |
| P0-4 | 统一 `to_exception/3` funnel + 现有 `check_termination` 折入 | `runner/enactment/enactment.ex`                                                                                                                                                                             | P0-3       |
| P0-5 | 跨所有 callback 入口 rescue（§5.2.2 全列）                   | `runner/enactment/enactment.ex`                                                                                                                                                                             | P0-4       |
| P0-6 | Caller-safe wrapper（§4.5 全 exit surface）                  | `runner/enactment/workitem_transition.ex` + 4 新 exception module                                                                                                                                           | P0-2       |
| P0-7 | Caller-safety 测试切片                                       | 新测试                                                                                                                                                                                                      | P0-6       |
| P0-8 | Fatal reason 持久化测试                                      | `enactment_logs.exception.reason` enum 扩展验证                                                                                                                                                             | P0-3, P0-4 |

### P1 — Tuning & Surfacing

| #    | 项                                                                                                  | 文件                                                         |
| ---- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| P1-1 | `Runner.Errors` facade publish + 文档化                                                             | `runner/errors.ex` `@moduledoc`                              |
| P1-2 | Telemetry metadata 加 `tier` `lifecycle` `severity` `error_code` `source_phase` `degraded`          | `runner/enactment/enactment.ex` `emit_event/3` `with_span/4` |
| P1-3 | Telemetry 不变量文档化                                                                              | `runner/telemetry.ex` `@moduledoc`                           |
| P1-4 | Supervisor `max_restarts` / `max_seconds` 暴露为 `Application.get_env`                              | `runner/enactment/supervisor.ex`、`runner/supervisor.ex`     |
| P1-5 | `WorkitemStream.decode_cursor/1` 行为决议（保静默回零，文档化）                                     | `runner/worklist/workitem_stream.ex` `@moduledoc`            |
| P1-6 | Leak modes 入 `Runner` 模块 `@moduledoc`                                                            | `runner/runner.ex`                                           |
| P1-7 | 新增 `:resumed` lifecycle event（first boot vs crash-restart 区分）                                 | `runner/enactment/enactment.ex:populate_state` 末尾          |
| P1-8 | EnactmentLog `embeds_one :exception` 加可选 `stacktrace_text` 字段 + 持久化（仅 rescue context 时） | `runner/storage/schemas/enactment_log.ex` + 迁移             |

### Future（独立设计文档先过审）

- F-1 CrashLedger（ETS + dedicated owner + `:ignore` quarantine + supervisor
  `:DOWN` monitor + `Runner.start_enactment/1` 边界归一）
- F-2 Recovery API（`Runner.recover_enactment/2` + storage 切片 + audit 不变量 +
  zero-occurrence 处理）
- F-3 Reoffer API（`Runner.reoffer_workitem/2` + storage 切片 +
  `workitem_logs.action` 扩展 + 后置条件§4.6）
- F-4 Sharding（仅 DS 选择分片，不动 Registry key）
- F-5 Backoff supervisor wrapper（不可注册半成品 enactment 进程）
- F-6 `Utils.fetch_*!` 改 typed exception
- F-7 `ErrorHandler` behaviour（仅 telemetry
  被证不够时才考虑；fail-closed、out-of-process）
- F-8 Tier 1 → Tier 2 自动升级（仅经 telemetry handler / 外部 circuit breaker）
- F-9 Boot gate（节点级 Repo 健康预检）

## 9. 兼容性影响

| 项                                              | 影响                                                                                                                                  | 缓解                                                                            |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 公共 API 返回                                   | `{:ok, _}                                                                                                                             | {:error, Exception.t()}` 形态保留；新增 4 种 exception type                     |
| Telemetry 字段                                  | 加 `tier` `lifecycle` `severity` `error_code` `source_phase` `degraded`                                                               | additive                                                                        |
| 新增 `:resumed` event                           | `[..., :enactment, :resumed]`                                                                                                         | 现订阅 `[:start]` 的需更新 — 文档明示                                           |
| `Storage` 行为契约                              | 多 callback 返回类型扩展                                                                                                              | 实现方需更新；`InMemory` 同步；契约前向兼容                                     |
| `enactment_logs.exception.reason` enum 取值     | 加 6 项（`:state_drift` `:snapshot_corrupt` `:replay_failed` `:enactment_data_missing` `:cpnet_corrupt` `:fatal_persistence_failed`） | `Ecto.Enum` 字符串映射，无须迁移                                                |
| `enactment_logs.exception.stacktrace_text` 字段 | 新增 nullable column                                                                                                                  | 须迁移：`runner/storage/migrations/v3.ex`                                       |
| `Runner.start_workitem/2` 等返回                | 4 种新 exception                                                                                                                      | union 扩展，pattern-match 保险                                                  |
| 测试 helper `runner_helpers.ex:213`             | `:noproc` exit 路径变 `{:error, %EnactmentNotRunning{}}`                                                                              | P0-7 同步更新                                                                   |
| `terminate_enactment` 持久化失败                | 现 raise → 改 funnel + Tier 2                                                                                                         | caller-facing：`Runner.terminate_enactment/2` 公共 API 返回类型从 `:ok` 改 `:ok |

## 10. §7 答案锁定（与 v2 同；按 codex v1 建议）

| #  | 问                          | 答                                                                                       |
| -- | --------------------------- | ---------------------------------------------------------------------------------------- |
| 1  | Behaviour vs telemetry-only | telemetry-only                                                                           |
| 2  | CrashLedger 存哪            | ETS + dedicated owner under `Runner.Supervisor`                                          |
| 3  | recover 策略集              | 仅 `:resume` + `:reoffer_started`；`:reset_to_snapshot` `:replay_from(version)` 永不引入 |
| 4  | reoffer 触发                | 仅手动                                                                                   |
| 5  | Tier 1 → Tier 2 自动升级    | 不做                                                                                     |
| 6  | CrashLedger 阈值            | 5 / 60s 默认，可配                                                                       |
| 7  | `:exception` 查询 API       | 仅 `Runner.get_exception_details/1`                                                      |
| 8  | stable `error_code`         | 加                                                                                       |
| 9  | `Utils.fetch_*!` 归属       | Tier 4                                                                                   |
| 10 | `gen_statem` 化 Enactment   | 不做                                                                                     |

## 附录 A — 当前错误位点速览（v3 修订）

```
runner/storage/default.ex:95,121,153,219      # P0-3 改返 tuple
runner/storage/default.ex:342                  # P0-3 改返 tuple
runner/storage/default.ex:21,30                # Repo.one!/get!；P0-3 行缺失改返 tuple；P0-5 caller rescue
runner/storage/default.ex:420-432              # take_enactment_snapshot；P0-3 加 :ok | {:error, _}
runner/storage/default.ex:436-443              # read_enactment_snapshot；P0-3 codec 错改 typed
runner/storage/in_memory.ex:318                # P0-3 同步改 typed
runner/worklist/workitem_stream.ex:98          # P1-5 文档化保留
runner/telemetry.ex:177-202                    # span rescue + reraise，保留（外层 callback rescue 接力）
runner/enactment/enactment.ex:243-256          # P0-4 折入 funnel
runner/enactment/enactment.ex:107-139,141-171  # P0-5 rescue
runner/enactment/enactment.ex:281-298,300-347  # P0-5 rescue
runner/enactment/enactment.ex:350-357          # P0-5 rescue（take_snapshot）
runner/enactment/enactment.ex:261-274          # P0-5 rescue（terminate）
runner/enactment/workitem_transition.ex        # P0-6 caller-safe wrapper
expression/expression.ex:233                   # eval rescue → {:error, [ex]}，保留
expression/arc.ex:60,102                       # 同上
enabled_binding_elements/binding.ex:200        # match_bind_expr rescue → :error，保留
enabled_binding_elements/utils.ex:21,35,48,65,84  # Tier 4，未来 typed
multi_set.ex:549,563                           # 保留
notation/*.ex                                  # Tier 4 编译期，保留
validators/exceptions/*.ex                     # Tier 4 静态，保留
runner/storage/schemas/json_instance/codec/colour_set.ex:221  # P0-5 :cpnet_corrupt
```

## 附录 B — Supervisor 行为参考

| exit reason                                                                             | restart 策略 | 计入 `max_restarts`？ | 触发重启？      |
| --------------------------------------------------------------------------------------- | ------------ | --------------------- | --------------- |
| `:normal`                                                                               | any          | 否                    | 仅 `:permanent` |
| `:shutdown`                                                                             | any          | 否                    | 仅 `:permanent` |
| `{:shutdown, _}`                                                                        | any          | 否                    | 仅 `:permanent` |
| 其它（含 `raise`、未捕获 throw、显式 `exit(reason)`、`{:fatal_persistence_failed, _}`） | `:transient` | **是**                | 是              |

| `init/1` 返回                  | DynamicSupervisor 反应                                             |
| ------------------------------ | ------------------------------------------------------------------ |
| `{:ok, state}`                 | 启动；正常                                                         |
| `{:ok, state, {:continue, _}}` | 启动；进入 handle_continue                                         |
| `:ignore`                      | **不**计入失败、**不**重启；`start_child/2` 返 `:ignore` — v1 不用 |
| `{:stop, reason}`              | 计入失败；可能重启                                                 |

## 附录 C — `GenServer.call/3` exit reason 全集（caller-safe wrapper 覆盖参考）

| exit pattern         | 含义                             | wrapper 行为                                        |
| -------------------- | -------------------------------- | --------------------------------------------------- |
| `{:noproc, _}`       | 进程已死或 via 名未注册          | `EnactmentNotRunning`                               |
| `{:timeout, _}`      | call 超时                        | `EnactmentTimeout`                                  |
| `{:shutdown, _}`     | called process 正在 shutdown     | `EnactmentNotRunning(reason: :shutting_down)`       |
| `{:normal, _}`       | called process 正常退出 mid-call | `EnactmentNotRunning(reason: :stopped_during_call)` |
| `{:nodedown, node}`  | 远程节点失联                     | `EnactmentCallFailed(reason: {:nodedown, node})`    |
| `{:killed, _}`       | called process 收到 `:kill`      | `EnactmentCallFailed(reason: :killed)`              |
| `{:calling_self, _}` | 编程错（自调）                   | reraise — 让程序员看到                              |
| 其它 reason          | 未识别异常退出                   | `EnactmentCallFailed(reason: reason)`               |
