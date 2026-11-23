# 接口对照（客户端 ↔ 呆呆面板）

面板基础路径：`http://HOST:PORT/api/v1`（`/api` 为旧前缀，客户端统一走 v1）。
所有请求都带以下头，面板据此把会话标记为「APP 端」，走 APP 端会话数上限，不会挤掉网页登录：

```
X-Client-Type: app
X-Client-App: DaidaiPanel-iOS
X-Client-Platform: ios
X-Device-Model: iPhone
X-OS-Version: 17.x
User-Agent: DaidaiPanel-iOS/1.0.0 (1)
```

## 响应约定（重要）

面板没有统一的 `{code, msg, data}` 外壳，实际有三种形态，客户端都要兼容：

| 形态 | 例子 | 客户端处理 |
| --- | --- | --- |
| 裸对象 | `GET /auth/user` → `{"user": {...}}` | 直接解 |
| `data` 包装 | `GET /system/dashboard` → `{"data": {...}}` | 先试 `DataEnvelope<T>`，失败再按裸对象解 |
| 分页 | `GET /tasks` → `{"data": [...], "total": 42, "page": 1, "page_size": 30}` | `PagedEnvelope<T>`，再退化为 `[T]` |

错误：HTTP 非 2xx 时可能是 `{"error": "中文文案", "code": "机器码"}`（`code` 只在 auth 相关接口出现）。
`code` 取值：`invalid_credentials` / `two_factor_required` / `invalid_totp` / `captcha_required` / `account_locked` / `session_revoked`。

## 鉴权

- 登录返回 `access_token` + `refresh_token`，之后所有请求带 `Authorization: Bearer <access_token>`。
- access 过期（默认 480 小时）后 401，客户端用 `POST /auth/refresh`（Bearer 放 **refresh_token**）换新 access，再重试原请求一次。
- refresh 也失败 → 清 Keychain、退回登录页。

## 状态码含义

| 字段 | 取值 |
| --- | --- |
| 任务 `status`（float） | `0` 禁用 / `0.5` 排队中 / `1` 空闲（已启用） / `2` 运行中 |
| `/tasks/:id/live-logs` 的 `status` | **任务状态**（同上），不是日志状态 |
| 任务 `enabled`（bool） | 开关位，与运行态无关（禁用任务手动运行也会变成 0.5/2） |
| 日志 `status`（int） | `0` 成功 / `1` 失败 / `2` 运行中 / `3` 手动终止 |

---

## 客户端实际调用的接口

### 认证

| 方法 | 路径 | 参数 / 请求体 | 返回 | 备注 |
| --- | --- | --- | --- | --- |
| GET | `/auth/check-init` | — | `{need_init: bool}` | 免登录；面板未初始化时提示 |
| POST | `/auth/login` | `{username, password, totp_code?}` | `{access_token, refresh_token, user}` | 401 + `code=two_factor_required` 表示要动态码 |
| POST | `/auth/refresh` | 头 `Authorization: Bearer <refresh>` | `{access_token}` | 限流 30 次/分 |
| POST | `/auth/logout` | — | `{message}` | 按会话号撤销 |
| GET | `/auth/user` | — | `{user: {...}}` | 用于恢复会话 |
| GET | `/version` | — | `{version, api_version, framework}` | 免登录 |

### 概览

| 方法 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- |
| GET | `/system/dashboard` | `range=7`（1–90） | `{data: {task_count, enabled_tasks, running_tasks, today_logs, success_logs, failed_logs, aborted_logs, env_count, sub_count, yesterday_*, recent_logs[], daily_stats[{date,success,failed,aborted}], range_days}}` |

### 任务

| 方法 | 路径 | 参数 / 请求体 | 备注 |
| --- | --- | --- | --- |
| GET | `/tasks` | `keyword`, `status`(0/1/2), `page`, `page_size`(≤100) | 分页；`page_size` 会被面板夹到 1–100 |
| POST | `/tasks` | `{name, command, cron_expression, task_type, timeout, max_retries, retry_interval, notify_on_failure, notify_on_success, success_exit_codes, allow_multiple_instances}` | `name`/`command` 必填 |
| PUT | `/tasks/:id` | 同上 | 编辑 |
| PUT | `/tasks/:id/run` | — | 立即运行 |
| PUT | `/tasks/:id/stop` | — | 终止 |
| PUT | `/tasks/:id/enable` \| `/disable` | — | 开关 |
| DELETE | `/tasks/:id` | — | 删除任务（脚本文件保留） |
| GET | `/tasks/:id/latest-log` | — | 返回日志对象本体（含 `content`），可能是 404「还没有日志记录」 |
| GET | `/tasks/:id/live-logs` | — | **快照**：`{logs: [string], done: bool, status: float}`，不是 SSE。`done=true` 时面板已清空内存缓冲、`logs` 恒为 `[]`，必须改读 `latest-log` |
| GET | `/tasks/cron/templates` | — | **裸数组** `[{name, expression, category, description}]`，表达式可能是 6 位（带秒） |
| POST | `/tasks/cron/parse` | `{expression}` | `{is_valid, description, format, next_run_times[]}` |

### 日志

| 方法 | 路径 | 参数 | 备注 |
| --- | --- | --- | --- |
| GET | `/logs` | `task_id`, `status`(0/1/2/3), `keyword`(任务名), `page`, `page_size`, `start_time`, `end_time` | 分页 |
| GET | `/logs/:id` | — | 单条日志（含 `content`） |
| GET | `/logs/:id/stream` | — | SSE，网页端用；本客户端暂未使用 |

### 环境变量

| 方法 | 路径 | 请求体 | 备注 |
| --- | --- | --- | --- |
| GET | `/envs` | — | `page_size=500` 一次拉全，客户端本地筛选 |
| POST | `/envs` | `{name, value, remarks, group, enabled}` | |
| PUT | `/envs/:id` | 同上 | |
| DELETE | `/envs/:id` | — | |
| PUT | `/envs/:id/enable` \| `/disable` | — | 同名变量可并存 |

### 订阅

| 方法 | 路径 | 备注 |
| --- | --- | --- |
| GET | `/subscriptions` | 分页，客户端 `page_size=200` |
| PUT | `/subscriptions/:id/pull` | 触发一次同步 |
| PUT | `/subscriptions/:id/enable` \| `/disable` | |
| GET | `/subscriptions/:id/logs` | 拉取日志（客户端暂未使用） |

### 脚本

| 方法 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- |
| GET | `/scripts/tree` | — | `{data: [...]}`，节点真实字段是 **`key`（完整相对路径）、`title`、`type`、`isLeaf`、`extension`、`size`、`mtime`、`children[]`** —— 注意没有 `name` / `path` |
| GET | `/scripts/content` | `path=相对路径` | `{data: {path, content, binary, size}}`；二进制返回 base64 且 `binary=true` |
| PUT | `/scripts/content` | `{path, content, message?}` | 保存，返回 `{message, version}` |
| POST | `/scripts/run` | `{path}` 或 `{path, content, language}` | **201** + `{message, run_id}`；带 `content` 表示跑这段内容不落盘 |
| POST | `/scripts/run-code` | `{code, language}` | **201** + `{message, run_id}`；`language` ∈ python/javascript/node/typescript/shell/bash/go |
| GET | `/scripts/run/:run_id/logs` | — | `{data: {logs: [string], done: bool, exit_code: int\|null, status: "running"\|"success"\|"failed"\|"stopped"}}`，结束后**不清空** |
| PUT | `/scripts/run/:run_id/stop` | — | 终止 |
| DELETE | `/scripts/run/:run_id` | — | 清除临时运行记录 |
| GET | `/scripts/versions` | `path=相对路径` | `{data: [{id, script_path, version, message, content_length, created_at}]}`（最多 50 条） |
| GET | `/scripts/versions/:id` | — | 含 `content` 的完整版本 |

### 未接入（面板有、客户端暂时没做）

`/scripts/format`、`/scripts/upload|download|rename|move|copy`、`/scripts/versions/:id/rollback`、`/deps/*`、`/notifications/*`（需 admin）、`/configs`（需 admin）、`/system/backup*`、`/system/health-check`、`/system/panel-log`、`/system/processes`、`/tasks/batch/*`、`/tasks/views`、`/tasks/:id/pin`、`/envs/import|export`、`/open/*`（App Key 开放接口）、`/mcp/*`。

## 实测补充（面板 v3.4.5 / operator 账号）

- `POST /tasks` 返回 **201**，体是 `{data: {...}}`（不是 200，也不是裸对象）。
- 任务命令只接受托管命令（`task xxx.js` 等）；裸 shell（`echo`）会写入失败日志：
  `[执行错误: 找不到托管依赖命令 echo，请先在依赖页面安装对应 Python/Node 依赖，或改用脚本文件命令]`。
- 订阅的 `type` 是 `git-repo`，上次同步时间是 `last_pull_at`。
- viewer 访问 `/envs`、`/subscriptions`、`/scripts/tree` 及所有写操作 → `403 权限不足`；
  `/notifications`、`/configs` 对 operator 也是 `403 需要管理员权限`。
- `POST /auth/refresh` 只回 `access_token`，**不轮换** refresh token。
