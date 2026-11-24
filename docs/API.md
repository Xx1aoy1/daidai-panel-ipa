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
| GET | `/envs` | — | 按 `page_size=100` 翻页拉全，客户端本地筛选（**`page_size>100` 会被面板降级成 20**） |
| POST | `/envs` | `{name, value, remarks, group, enabled}` | |
| PUT | `/envs/:id` | 同上 | |
| DELETE | `/envs/:id` | — | |
| PUT | `/envs/:id/enable` \| `/disable` | — | 同名变量可并存 |

### 订阅

| 方法 | 路径 | 备注 |
| --- | --- | --- |
| GET | `/subscriptions` | 分页，客户端按 `page_size=100` 翻页 |
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

### 管理员接口（全部 `RequireAdmin`，operator / viewer 回 403）

#### 通知渠道

| 方法 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- |
| GET | `/notifications` | — | `{data: [{id, name, type, config, enabled, push_scope, today_send_count, last_test_at, last_test_status, created_at, updated_at}]}`，**非分页** |
| GET | `/notifications/types` | — | `{data: [{type, name, icon, fields: [{key, label, widget, placeholder, required, options}]}]}`，实测 **19 种**渠道 |
| POST | `/notifications` | `{name, type, config, push_scope}` | **201** + `{message, data: {...}}`（注意 `data` 与 `message` 平级，不是包一层） |
| PUT | `/notifications/:id` | 同上，**按键更新** | 只改请求里出现的键，没传的保持原值 |
| PUT | `/notifications/:id/enable` \| `/disable` | — | 启停 |
| POST | `/notifications/:id/test` | — | 真实发一条「呆呆面板测试通知」，失败回 400 + `发送失败: ...` |
| DELETE | `/notifications/:id` | — | 删除 |

关键约束：

- `config` 是 **JSON 字符串**，不是嵌套对象；值必须**全是字符串**（写进数字/布尔会让该渠道所有推送静默失败）。
- `push_scope` 只能是 `default` / `bound`；传 `null` 视为「没提供」，跳过不改。
- `widget` 取值实测有 `input` / `password` / `select` / `textarea`；`select` 的 `options` 是 `[{value, label}]`。
- 同一类型里 **`key` 可能重复**（`wecom` 的 `content_template` 出现两次，分别叫「文本模板」和「内容模板」），渲染表单时 id 要用 key+label 组合。

#### 系统

| 方法 | 路径 | 返回 |
| --- | --- | --- |
| GET | `/system/info` | `{data: {hostname, machine_code, cpu_usage, num_cpu, memory_total/used/free/usage, disk_total/used/free/usage, net_rx_bytes, net_tx_bytes, net_rx_speed, net_tx_speed, uptime, goroutines, go_version, os, arch, deployment_type, data_dir, version}}` |
| GET | `/system/health-check` | **无 data 外壳**：`{items: [{name, status, message}], last_checked_at}` |
| POST | `/system/health-check` | 主动体检，结构同上 |

- `uptime` 是中文人话字符串（「16时33分」），不是秒数。
- 面板对 `page_size > 100` 静默降级成 20 的毛病在这些接口上不适用（都不是分页）。

#### 日志管理（`RequireRole("operator")`）

| 方法 | 路径 | 参数 |
| --- | --- | --- |
| DELETE | `/logs/:id` | — |
| POST | `/logs/batch-delete` | `{ids: [int]}`（另有等价的 `DELETE /logs/batch`） |
| DELETE | `/logs/clean` | `?days=N`，缺省读配置 `log_retention_days` |
| GET | `/logs/:id/raw-ticket` | — |

清理会**同时删记录和磁盘文件**。原始日志下载是「换票」模式：

```
GET /logs/1574/raw-ticket  →  {expires_at, expires_in: 120, filename, size,
                               url: "/api/v1/logs/1574/raw?ticket=v1.xxx"}
GET <root><url>            →  原始日志字节流（这条路由不挂 JWTAuth，靠 ticket 验签）
```

票据 120 秒一次性，`url` 是**相对路径**，要自己拼根地址；下载时不要再带 `Authorization`。

#### 脚本格式化

| 方法 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- |
| POST | `/scripts/format` | `{content, language, formatter?}` | `{data: {content, language, formatter}}` |

- 只认 **python / shell / go / json**，其他语言回 400「不支持的语言」。
- python 走 `black`（退回 `autopep8`），shell 走 `shfmt`，go 走 `gofmt`，都是面板侧的可执行文件。
- 没装对应工具时不报错，原样返回且 `formatter == "none"` —— 客户端据此提示「面板没装格式化器」。

#### 系统设置（`/configs`）

| 方法 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- |
| GET | `/configs` | — | `{data: {键: {...}}}` —— **map，不是数组** |
| GET | `/configs/:key` | — | `{data: {key, value, config}}` |
| POST | `/configs` | `{key, value, description?}` | `{message}` |
| PUT | `/configs/batch` | `{configs: {键: 值}}` | `{message}`，整组提交 |
| DELETE | `/configs/:key` | — | `{message}`，重置为「未设置」 |

单项字段：

```
value_type   bool | int | enum | string      → 决定控件
value        永远是字符串："true" / "5" / "daily"
default_value / label / description / group / group_label / order
secret       仅渲染提示（见下）
min / max    仅 int 项，用于范围校验
options      [{value, label}]，仅 enum 项
registered   false 表示面板内部键，设置页不该展示
```

实测 **61 项，其中 57 项 `registered`**，分 7 组：任务运行 / 网络代理 / 告警通知 / 订阅拉取 / 安全 / 面板与运行时 / 定时备份。
另外 4 项是内部键：`machine_code`、`system_health_last_checked_at`、`system_health_last_result_json`、`trusted_proxy_cidrs_migrated`。

关键约束：

- **所有值都是字符串**，布尔写 `"true"` / `"false"`，数字写十进制字符串。
- `secret` 只是让前端用密码框渲染，**服务端仍然明文回传** `value`。面板源码注释说明了原因：网页端靠回填明文才能在「整组保存」时不把真实值覆盖成空。
- 整组保存是逐键 `SetConfig`，中途有一项失败时**前面的键已经写入**（接口只回 400 + 首个错误）。
- 改这几类键会立刻重载运行时，不用重启面板：`timezone`、`trusted_proxy_cidrs`、`max_concurrent_tasks`、`backup_schedule_*`。
- `*_at` 是面板自己写的时间戳（如 `auto_update_last_checked_at`），客户端渲染成只读。

#### 依赖管理（`/deps`）

| 方法 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- |
| GET | `/deps` | — | `{data: [{id, name, type, status, python_version, created_at, updated_at}]}`，**不带 log** |
| POST | `/deps` | `{type, names: [string], python_version?}` | **201** + `{message, data: [...]}`（平级） |
| GET | `/deps/:id/status` | — | `{data: {...同上, log}}` |
| DELETE | `/deps/:id` | `?force=true` | 普通删除 = 先卸载再删记录；`force` = 直接删记录 + 强删文件 |
| POST | `/deps/batch-delete` | `{ids: [int]}` | 批量强删（跳过处理中的） |
| PUT | `/deps/:id/reinstall` | — | 用同一条记录重跑安装 |
| PUT | `/deps/:id/cancel` | — | 只能取消 installing / removing |
| GET | `/deps/:id/log-stream` | — | SSE 日志流（`event: done` 结束） |
| GET | `/deps/export` | `?type=nodejs\|python\|linux&python_version=` | **text/plain**，一行一个包名 |
| GET | `/deps/pip` | `?python_version=` | 裸数组 `[{name, version}]`（pip list --format=json） |
| GET | `/deps/npm` | — | 裸对象 `{name, dependencies: {包名: {version, overridden}}}` |
| GET | `/deps/mirrors` | — | 裸对象 `{pip_mirror, npm_mirror, linux_mirror, linux_distribution, linux_package_manager, linux_mirror_supported, linux_mirror_message}` |
| PUT | `/deps/mirrors` | `{pip_mirror?, npm_mirror?, linux_mirror?}` | **指针判空**：不传的字段不动 |
| GET | `/deps/python-runtimes` | — | `{data: [{version, label, default, venv_path, venv_healthy, python_path, pip_path, available, message}], default_version}` |
| PUT | `/deps/python-runtime-default` | `{version}` | 即改配置 `python_default_version` |
| GET | `/deps/playwright` | — | 裸对象 `{supported, reason, packages, browsers_path, python_installed, browsers_installed, linux_installed, linux_total}` |
| POST | `/deps/playwright/install` | — | 把系统依赖 + Chromium 排进顺序队列 |

关键约束：

- 状态机：`queued → installing → installed / failed`，卸载走 `removing`，取消后为 `cancelled`。
  处于 `queued` / `installing` / `removing` 时，删除和重装都回 400「依赖正在处理中」，只能取消。
- 包名过滤：含 `; | & \` $ ( ) { }` 或**以 `-` 开头**的名字会被面板**静默丢弃**（不建记录、不报错）。
  客户端在提交前把这类名字标红提示。
- `type` 只能是 `nodejs` / `python` / `linux`；Python 会按 `python_version` 装进对应 venv，
  不传则用默认版本；同一个包在 3.10 / 3.11 / 3.12 下是三条独立记录。
- **返回口径不统一**：`/deps` 与 `/deps/python-runtimes` 包了 `data`，`/deps/mirrors`、`/deps/pip`、
  `/deps/npm`、`/deps/playwright`、`/deps/export` 都是裸的。
- `log` 只在 `/deps/:id/status` 返回，列表接口不带。
- 客户端没用 SSE：移动网络下断线重连比 1.5s 轮询更麻烦，而且 status 接口一次就能拿到全量日志。

#### 备份与恢复（`/system/backup*`、`/system/restore*`）

| 方法 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- |
| GET | `/system/backups` | — | `{data: [{name, size, created_at}]}`，**空目录回 `{data:null}`** |
| POST | `/system/backup` | `{name?, password?, selection:{configs,tasks,subscriptions,env_vars,logs,scripts,dependencies,task_views}}` | `{message, data:{path}}`，path 是**服务端绝对路径** |
| DELETE | `/system/backup` | `?filename=` | `{message}` |
| GET | `/system/backup/download` | `?filename=` 或 `/download/:filename` | 二进制 + `Content-Disposition: attachment`，**需要 Authorization** |
| POST | `/system/backup/upload` | multipart，字段名 `file` | `{message, data:{filename}}`（同名会自动 `-1` 后缀） |
| POST | `/system/restore` | `{filename, password?}` | `{message}`，**同步阻塞到整库替换完成** |
| GET | `/system/restore/progress` | — | `{data: {active, status, stage, message, percent, error, source, selection, started_at, updated_at}}` |
| POST | `/system/restart` | — | 重启面板（连接会断开） |

关键约束：

- 列表记录只来自目录文件本身：`name` / `size` / `created_at`（文件 mtime），没有「备份了哪些项」的元数据。
  空目录时 `data` 是 **null 而不是 []**，解析要按空数组兜。
- 不传 `password` 写 `.tgz`（gzip tar），传了就写 `.enc`。
  加密格式（v3.4.2 起）：`DDPENC02` 魔数 + 16 字节随机盐 + GCM nonce + 密文，
  密钥由 **PBKDF2-HMAC-SHA256 / 600000 轮**派生；老备份是 `SHA-256(password)` 单次派生，只解不写。
  **密码丢了无法恢复**，面板没有找回入口。
- `selection` 八个开关全 `false` 时服务端会 `NormalizeDefaults()` 退回「全选」，
  所以客户端必须在提交前挡住空选择，否则用户以为什么都没备。
- `name` 留空由服务端生成 `backup_yyyyMMdd_HHmmss`；带后缀会被剥掉再按加密与否补 `.tgz` / `.enc`。
- 上传限制 **512MB**，只认 `.json` / `.enc` / `.tgz` / `.tar.gz`，且会**校验内容**（gzip 头或 JSON），
  不是光看扩展名。校验通过才从临时文件改名，列表接口会隐藏 `.upload-*` 临时文件。
- 恢复是**同步阻塞**的整库替换：普通会话 90 秒超时不够用，客户端改走 2 小时超时的会话，
  并且**不做 401 自动续期重试**（重放同一个请求等于再恢复一遍）。
- 恢复期间用 `GET /system/restore/progress` 轮询（1 秒一次）：`status` 取 `idle / running / completed / failed`，
  空闲时 `updated_at` 是 `0001-01-01T00:00:00Z`。进度是面板进程内的内存状态，重启即清空。
- 恢复**会替换用户表**（备份勾了 configs 时），当前登录态大概率失效，客户端恢复完引导重新登录。
- 恢复**不会自动重启**，接口返回的 message 里写「正在准备重启面板」只是文案，
  要让运行时按新配置生效得显式调 `POST /system/restart`。

#### 用户管理（`/users`）

| 方法 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- |
| GET | `/users` | — | `{data: [{id, username, role, enabled, avatar_url, last_login_at, created_at, updated_at, two_factor_enabled}]}` |
| POST | `/users` | `{username, password, role}` | **201** + `{message, data:{...}}`（平级） |
| PUT | `/users/:id` | `{role?, enabled?}` | `{message, data:{...}}` |
| DELETE | `/users/:id` | — | `{message}` |
| PUT | `/users/:id/reset-password` | `{password}` | `{message}` |

关键约束：

- `role` 只有 `admin` / `operator` / `viewer`；创建时缺省是 `operator`。
- `two_factor_enabled` 不在 user 表里，是列表接口额外查一次 2FA 表合并出来的。
- **改角色、改启用状态、重置密码、删除，四条路径都会 `RevokeAllUserSessions`**：
  对方手上的 access token 立刻失效，不只是下次登录被拒。界面上必须提前说清楚。
- `DELETE /users/:id` 删自己回 **400「不能删除自己」**；删除会连带清掉该用户的 passkey
  （SQLite 可能复用 id，留着孤儿 passkey 会让新用户继承旧通行密钥）。
- 重置密码会**清该用户的全部 passkey**，返回值里会注明清掉了几个。
- 用户名规则：1-32 位，中文 / 字母 / 数字 / 下划线。
  密码规则（只用于「设置新密码」，登录不校验）：至少 8 个字符、UTF-8 不超过 **72 字节**（bcrypt 硬限制），
  字母 / 数字 / 符号三类里至少含两类。

#### 安全中心（`/security/*`）

权限分两档：`login-logs` / `sessions*` / `ip-whitelist` / `audit-logs` / `login-stats` 全部 `RequireAdmin()`
（operator、viewer 回 `403 需要管理员权限`）；`2fa*` 与 `passkeys*` 只作用于**当前登录用户**，任何角色都能调。

| 方法 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- |
| GET | `/security/login-logs` | `page`、`page_size`（≤100，越界回落 20）、`username`（**精确匹配**） | 分页 `{data, total, page, page_size}` |
| DELETE | `/security/login-logs` | — | `{message:"已清除 N 条登录日志"}` |
| GET | `/security/login-stats` | `days`（1-90，越界回落 7） | `{data:{total_logins, success_logins, failed_logins, active_sessions, locked_accounts, period_days}}` |
| GET | `/security/sessions` | — | `{data:[{id, user_id, username, client_type, client_type_label, client_name, ip, user_agent, created_at, expires_at, current}]}` |
| DELETE | `/security/sessions/:id` | — | `{message:"会话已撤销"}`；不存在回 **404「会话不存在」** |
| DELETE | `/security/sessions/others` | — | `{message:"已撤销 N 个其他会话"}` |
| DELETE | `/security/sessions/user/:user_id` | — | `{message:"已撤销 N 个会话"}` |
| GET | `/security/ip-whitelist` | — | `{data:[{id, ip, remarks, created_at}]}` |
| POST | `/security/ip-whitelist` | `{ip, remarks?}` | **201** + `{message:"添加成功", data:{...}}` |
| DELETE | `/security/ip-whitelist/:id` | — | `{message:"删除成功"}`（删不存在的 id 也回 200） |
| GET | `/security/2fa/status` | — | `{data:{enabled: bool}}` |
| POST | `/security/2fa/setup` | — | `{data:{secret, uri}}`，**不改变启用状态** |
| POST | `/security/2fa/verify` | `{code}` | `{message:"2FA 已启用"}` |
| DELETE | `/security/2fa` | `{code}`（**必填**） | `{message:"2FA 已禁用"}` |

关键约束（全部实测）：

- **登录日志只有「用户名精确」一种筛选**，没有时间范围、状态、IP 过滤；`status` 只有 `0` 成功 / `1` 失败。
  记录里带 `client_type`（`web` / `app`，按 UserAgent 现推）和 `client_name`（登录时客户端报的名字）。
- **会话列表是全局的**：admin 看到所有人的会话，`current` 按会话号（JWT 的 `sid`）判定，
  所以行里的 `username` 可能是别人。`expires_at` 是 access 过期时间，refresh 还能续的会话也会列出来。
- `DELETE /security/sessions/others` 只影响**当前用户自己**（按 token 里的用户名找 user_id），
  不影响列表里别人的会话；撤销自己当前会话时下一次请求就回 `401 code=session_revoked`。
- **IP 白名单没有开关**：列表非空即开启，空列表才是不限制（`IsIPWhitelisted` 里 `len==0 → true`）。
  添加/删除**立即生效**，但只作用于**登录**：不在名单里的 IP 登录回 **403「当前 IP 不在登录白名单中」**，
  已登录的会话不会被立刻踢掉。撞上这条限制时连 `POST /auth/login` 都过不去，只能去网页端（或用已在线的会话）处理。
- 白名单格式由服务端 `NormalizeIPWhitelistEntry` 规范化，支持单 IP、CIDR 和 IPv4 通配 `203.0.113.*`；
  重复添加回 `400「该 IP 或网段已在白名单中」`，非法格式回 `400「IP 地址格式无效」` / `400「IP 段格式无效，请使用 CIDR，例如 203.0.113.0/24」`。
- **2FA 三步走**：`setup` 只发 `secret` + `otpauth://` 链接（二维码要客户端自己画），
  然后 `verify` 验码才真正启用；已启用时再调 `setup` 回 `400「两步验证已启用，如需重新绑定请先关闭」`
  （防止拿一个登录态就把 2FA 悄悄重置掉）。
- 关闭 2FA **必须带当前动态码**：缺码 `400「请输入当前的动态验证码」`，码错 `400「动态验证码错误」`；
  未启用时调关闭直接回 `200 {message:"2FA 未启用"}`。
- TOTP **有防重放**：同一个 6 位码在同一个 30 秒窗口内只能用一次，重复用回 `400「验证码无效」`，
  登录时则回 `401 code=invalid_totp`。客户端做自动化测试时每个码只能换一次请求。
- 启用 2FA 后登录：不带码回 `401 code=two_factor_required`（体里同时带 `captcha_*` 与 `two_factor_required`），
  带码正确才 200。
- 面板**不提供备用恢复码**；丢了认证器要靠另一个 admin 账号处理（重置密码不会关 2FA）。
- `POST /auth/login` 有频率限制：短时间连续失败会回 **429「请求过于频繁，请稍后再试」**（不锁账号，等几分钟自动恢复），
  与 `code=account_locked` 的 429（带 `remaining_seconds`）不是一回事。

### 仍未接入（面板有、客户端暂时没做）

`/scripts/upload|download|rename|move|copy`、`/scripts/versions/:id/rollback`、`/system/panel-log`、`/system/processes`、`/system/config-script`、`/security/passkeys*`（通行密钥）、`/security/audit-logs`（安全审计）、`/tasks/batch/*`、`/tasks/views`、`/tasks/:id/pin`、`/envs/import|export`、`/deps/:id/log-stream`（SSE，改用轮询）、`/open/*`（App Key 开放接口）、`/mcp/*`。

## 实测补充（面板 v3.4.5）

- `POST /tasks` 返回 **201**，体是 `{data: {...}}`（不是 200，也不是裸对象）。
- 任务命令只接受托管命令（`task xxx.js` 等）；裸 shell（`echo`）会写入失败日志：
  `[执行错误: 找不到托管依赖命令 echo，请先在依赖页面安装对应 Python/Node 依赖，或改用脚本文件命令]`。
- 订阅的 `type` 是 `git-repo`，上次同步时间是 `last_pull_at`。
- viewer 访问 `/envs`、`/subscriptions`、`/scripts/tree` 及所有写操作 → `403 权限不足`；
  `/notifications`、`/configs` 对 operator 也是 `403 需要管理员权限`，**admin 可正常读写**（已用 admin 实测）。
- `POST /auth/refresh` 只回 `access_token`，**不轮换** refresh token。
- **分页陷阱**：`page_size` 超过 100 时面板不报错，而是**静默降级成 20**（实测 `/envs?page_size=500` 只回 20 条、89 个变量只看到 20 个）。客户端因此统一用 100 一页翻到底。
- `response.Success()` 的内部实现是 `c.JSON(200, payload)`，不会额外包一层 `data`。
  所以「`{data: X}`」还是「裸 X」完全取决于 handler 自己怎么写 —— 同一个面板里两种风格并存，
  客户端解码必须先试包装、失败再试裸对象。
