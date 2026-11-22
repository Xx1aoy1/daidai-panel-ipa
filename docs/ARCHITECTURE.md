# 架构说明

## 分层

```
SwiftUI View  ──▶  SessionStore（会话/令牌/多面板）  ──▶  PanelAPI（路径映射）  ──▶  APIClient（传输）
      │                     │
      └──▶ ViewModel ──────┘        （单个页面的加载状态、分页、错误文案）
```

- **APIClient**：只负责「地址拼接 + 请求头 + 发请求 + 401 续期 + 解码兜底」。不知道业务。
- **PanelAPI**：一个 `extension APIClient`，把每个业务动作映射成「方法 + 路径 + 参数 + 返回类型」。加接口只动这里。
- **SessionStore**：全局单例（`@StateObject` 挂在 App 上），持有当前 `APIClient`、用户信息、已保存的多台面板、Keychain 读写；`handle(error:)` 统一把「令牌彻底失效」翻译成「退回登录页」。
- **ViewModel**：仅在页面需要分页/筛选/局部刷新时使用（任务、日志、环境变量、订阅、概览）。简单的只读页面直接用 `@State` + `task{}`。
- **View**：不拼 URL、不解析 JSON、不直接读 Keychain。

## 数据流示例：运行一个任务

```
TaskRow 左滑「运行」
  └─ TaskListView.perform { client in try await client.runTask(id:) }
       └─ APIClient.send(PUT /tasks/:id/run)
            ├─ 200 → 回到列表，重新拉第一页
            └─ 401 且可续期 → refreshAccessToken() → 重放原请求一次
```

## 令牌与安全

| 数据 | 存放位置 | 说明 |
| --- | --- | --- |
| access / refresh token | **Keychain**（`kSecClassGenericPassword`，service 固定，account 为 `access.<UUID>` / `refresh.<UUID>`） | 每台面板一套，切换面板互不影响 |
| 面板地址、名称、用户名 | UserDefaults（`daidai.servers` JSON） | 不含密码 |
| 密码 | **不存储** | 只在登录请求里用一次 |
| TOTP 动态码 | 不存储 | 每次登录现输 |

`access` 过期策略：任意请求收到 401 且 `code` 不属于登录类错误时，用 refresh 换新 access 并重放一次；
换不到就清 Keychain、`isLoggedIn = false`，界面自动回登录页（`SessionStore.handle(_:)`）。

## 解码策略（为什么字段几乎都是可选的）

面板不同版本会增减字段，例如 `labels` 在某些版本是字符串、某些是数组，`task` 可能内嵌也可能只有 `task_name`。
直接强类型解码会因为一个字段类型变化导致整页失败，所以：

1. 只把 `id` 当必填，其余全用可选；
2. 响应先用 `DataEnvelope<T>` 试，再退化到裸 `T`（`APIClient.decodeObject`）；
3. 列表先试 `PagedEnvelope<T>`，再试 `DataEnvelope<[T]>`，最后试 `[T]`（`APIClient.list`）。

代价是「字段缺失时显示为空」，收益是面板升级不会让 App 白屏。

## 日志的两种形态

| 场景 | 接口 | 客户端实现 |
| --- | --- | --- |
| 历史日志 | `GET /logs/:id` | 一次性拉全文，`Text` 等宽显示，可复制 |
| 任务最新一次 | `GET /tasks/:id/latest-log` | 详情页顶部显示尾部 14 行 |
| 运行中跟随 | `GET /tasks/:id/live-logs` | **轮询**（1.5s）拿「最后 200 行 + done」，`done=true` 自动停 |

面板也有 `GET /logs/:id/stream`（SSE），网页端在用。客户端保留 `APIClient.streamRequest/streamBytes` 以便后续切过去；
当前选择轮询的原因是 `live-logs` 只给快照、且轮询在弱网/后台切换时更稳。

## 线程模型

- `APIClient`、`SessionStore`、所有 ViewModel 都是 `@MainActor`；
- 网络用 `async/await`（`URLSession.data(for:)`），挂起不阻塞主线程；
- 所有 `@Published` 更新都发生在主线程，不需要手动 `DispatchQueue.main`。

## 构建

`project.yml` → XcodeGen → `DaidaiPanel.xcodeproj` → `xcodebuild`（`CODE_SIGNING_ALLOWED=NO`）→ `Payload/*.ipa`。
不提交 `.xcodeproj`，避免工程文件冲突；`Info.plist`（含 ATS 放开）在 `Sources/Resources/` 里，随源码走。
