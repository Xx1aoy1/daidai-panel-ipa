# 呆呆面板 iOS 客户端（DaidaiPanel-iOS）

一个第三方开源的 **iOS 原生客户端**，用来在 iPhone / iPad 上管理 [呆呆面板（Daidai Panel）](https://github.com/linzixuanzz/daidai-panel)：
看概览、跑任务、跟日志、改环境变量、拉订阅、翻脚本。

- 纯 **Swift + SwiftUI**，零第三方依赖，二进制很小
- 最低 **iOS 15.0**，arm64
- 仓库内置 **GitHub Actions 自动出包**，产出**未签名 IPA**，配合 **TrollStore** 直接安装（也可自签）
- 后端只通过面板公开的 `/api/v1` 接口通信，不改服务端任何代码

---

## 零、直接下载（已构建好的 IPA）

到 **[Releases](https://github.com/Xx1aoy1/daidai-panel-ipa/releases/latest)** 下载最新的
`DaidaiPanel-iOS-<版本>-unsigned.ipa`，在「文件」里点它 → 「用 TrollStore 打开」→ Install 即可。

- 不需要 Apple 开发者账号，不会 7 天掉签
- 装好第一次启动：填面板地址（如 `http://192.168.0.100:5700`）→ 账号密码 →（开了 2FA 会多一个验证码框）
- 连不上先看 **更多 → 面板信息 → 连接诊断**：`服务可达` 查地址与网络，`登录态有效` 查令牌

---

## 一、它能做什么

| 模块 | 能力 |
| --- | --- |
| 登录 / 多面板 | 地址 + 账号密码登录、2FA（TOTP）二次验证、刷新令牌自动续期、多台面板保存与一键切换、令牌存 Keychain |
| 概览 | 任务总数 / 启用 / 运行中、今日执行与成功率、近 7 日成功/失败/中断趋势、最近 10 条执行、环境变量与订阅计数、面板版本 |
| 任务 | 列表（关键字搜索 + 全部/运行中/已启用/已禁用筛选 + 分页）、置顶标记、状态徽标、立即运行 / 停止 / 启用 / 禁用 / 删除、左右滑快捷操作 |
| 任务编辑 | 新建与编辑：名称、命令、Cron（**面板自带模板库**按分类选择）、**表达式实时解释 + 下次执行时间**、任务类型（Cron / 手动）、超时、失败重试、成功退出码、多实例、成功/失败通知开关；多条定时规则按行原样读写 |
| 日志 | 执行日志列表（状态筛选 + 任务名搜索 + 分页）、日志详情全文（等宽、可选中复制）、运行中的任务可进入**实时跟随**（1.5s 轮询，跑完自动停并补全 final 日志，显示成功/失败/终止）、**左滑删除单条**、**按 7/30/90 天清理历史日志（记录 + 磁盘文件一起删）**、**原始日志文件下载分享** |
| 环境变量 | 列表（名称/备注/分组筛选）、敏感变量默认打码可点开、新建 / 编辑 / 删除、左滑启用禁用 |
| 订阅 | 列表、立即拉取、启用/禁用、上次同步时间 |
| 脚本 | 目录树浏览（含子目录）、文件内容查看与**在线编辑保存**、**在线试跑（运行当前内容 / 已保存版本，输出实时跟随、可终止/复制）**、**历史版本只读预览**、**一键格式化（python/shell/go/json，走面板的 black/shfmt/gofmt）**、二进制文件保护 |
| 通知渠道（admin） | 渠道列表（启用状态、今日发送量、上次测试结果）、**19 种渠道类型**、**按字段定义动态生成的配置表单**（input / password / select / textarea）、新建 / 编辑 / 启停 / 删除、**发送测试消息**、默认推送 vs 绑定推送 |
| 系统监控（admin） | CPU / 内存 / 磁盘实时占用条、上下行速率与累计流量、健康检查逐项状态（含主动体检）、主机名 / 面板版本 / 部署方式 / 运行时长 / 协程数 / 数据目录，支持每 5 秒自动刷新 |
| 系统设置（admin） | 面板 `/configs` 的 **57 个注册项、7 个分组**（任务运行 / 网络代理 / 告警通知 / 订阅拉取 / 安全 / 面板与运行时 / 定时备份）：bool 开关、int 数字（带 min/max 校验与范围提示）、enum 下拉、密码框可回显、多行清单；只提交改过的键，保存后立即生效；`*_at` 时间戳渲染成只读 |
| 依赖管理（admin） | 三类依赖（Node.js / Python / 系统包）列表与筛选、**批量提交安装**（换行/逗号/空格分隔，提交前提示非法包名）、**实时安装日志**（1.5s 轮询 + 自动滚底）、重装 / 取消 / 卸载 / 强制卸载、**镜像源切换**（pip / npm / apt，带常用源预设）、**多版本 Python 默认版本切换**、**Playwright 一键安装**、已装包清单（托管导出 / pip list / npm list -g）与复制分享 |
| 其他 | 面板信息（版本 / API / 框架）、连接诊断、服务器管理、关于页 |

**暂未实现**（见路线图）：依赖管理、系统设置（`/configs` 61 项）、备份恢复、用户管理、2FA 与安全设置管理、SSE 订阅拉取进度。
这些都在面板网页端仍可操作，客户端不阻塞。

---

## 二、兼容性

| 项 | 说明 |
| --- | --- |
| 面板版本 | 适配呆呆面板 **v3.x**（接口为 `/api/v1`，同时兼容 `/api` 旧前缀，客户端统一走 v1） |
| 系统版本 | iOS **15.0** 及以上（覆盖 TrollStore 常见机型） |
| 架构 | arm64（真机），Mac 上可用模拟器跑但不作目标 |
| 签名 | 仓库产出的 IPA **完全未签名**，仅用于 TrollStore / 自签工具（TrollStore、AltStore、Sideloadly 等） |
| 账号角色 | `admin` 全功能（任务、环境变量、订阅、脚本、在线运行、**通知渠道、系统监控、系统设置、依赖管理、日志清理**）；`operator` 可读写任务/环境变量/订阅/脚本与日志清理，但通知渠道与系统监控回 403；`viewer` 收敛为只读（隐藏新建/运行/启停/编辑/删除，环境变量·订阅·脚本不开放） |
| 多定时规则 | 面板把多条 cron 以**换行**存在 `cron_expression`，客户端按行原样读写，编辑不会压成一条 |
| 命令格式 | 面板只接受托管命令（如 `task xxx.js`）；直接写 `echo`、`ls` 会报「找不到托管依赖命令」，编辑页已作提示 |
| 通知 / 配置 / 依赖 | `/notifications`、`/configs`、`/deps` 全部需要 **admin**，operator 与 viewer 均回 403；这三块都已接入 |

> 面板默认是 HTTP（`http://IP:5700`）。`Info.plist` 已放开 ATS（`NSAllowsArbitraryLoads`），
> 否则 iOS 会直接拦掉明文请求。这也是本客户端不能上架 App Store 的原因之一。

---

## 三、快速开始（出包 → 装机）

### 1. 用 GitHub Actions 出包（推荐，不需要 Mac）

1. 把本仓库推到 GitHub（或 fork）。
2. 打开 **Actions → Build unsigned IPA → Run workflow**（runner 用 `macos-latest`；`macos-14` 已被 GitHub 下线，会秒取消）。
3. 跑完在 **Artifacts** 里下载 `DaidaiPanel-iOS-ipa`，解压得到 `DaidaiPanel-iOS-<版本>-unsigned.ipa`。
4. 把 IPA 传到手机（AirDrop / 文件 App / 局域网），用 **TrollStore** 打开 → Install。
5. 打 tag（`v1.1.0`）推送时，工作流会自动建 Release 并把 IPA 挂上去；工作流已声明 `contents: write` 权限。

### 2. 本地构建（需要 macOS + Xcode）

```bash
brew install xcodegen
./Scripts/build-ipa.sh 1.0.0
# 产物：DaidaiPanel-iOS-1.0.0-unsigned.ipa
```

或者用 Xcode 打开：`xcodegen generate && open DaidaiPanel.xcodeproj`，选真机 + 自己的开发者证书直接跑。

### 3. 装机后

第一次打开 → 填面板地址（`192.168.0.100:5700` 这种即可，自动补 `http://`）→ 用户名密码 →（若开了 2FA 会多出一个验证码输入框）→ 连接。

---

## 四、项目结构

```
DaidaiPanel-iOS/
├── project.yml                     # XcodeGen 工程描述（不提交 .xcodeproj）
├── .github/workflows/build-ipa.yml # macOS CI：生成工程 → 编译 → 打未签名 IPA → 上传产物/Release
├── Scripts/
│   ├── build-ipa.sh                # 本地一键出包
│   └── make_icon.py                # 生成 1024 图标（PIL）
├── docs/
│   ├── API.md                      # 客户端用到的接口清单与字段
│   └── ARCHITECTURE.md             # 分层、数据流、令牌续期、日志策略
└── Sources/
    ├── App/
    │   ├── DaidaiPanelApp.swift    # @main
    │   ├── RootView.swift          # 启动页 / 登录 / 主界面切换
    │   └── MainTabView.swift       # 概览 / 任务 / 日志 / 更多
    ├── Core/
    │   ├── APIClient.swift         # 传输层：地址拼接、鉴权头、401 续期、解码兜底
    │   ├── PanelAPI.swift          # 接口层：路径 + 参数 + 模型映射
    │   ├── PanelAPI+Admin.swift    # 管理员接口：通知渠道 / 系统 / 日志管理 / 格式化
│   ├── PanelAPI+ConfigDeps.swift # 管理员接口：系统设置 / 依赖管理 / 镜像源 / 运行时
    │   ├── ScriptRunner.swift      # 脚本在线运行：启动 → 轮询输出 → 终止/清理
    │   ├── SessionStore.swift      # 会话层：多面板、令牌、Keychain、登录态
    │   ├── KeychainStore.swift     # 令牌存储
    │   ├── LiveLogPoller.swift     # 实时日志轮询
    │   ├── PanelError.swift        # 统一错误（含面板 code）
    │   ├── Formatters.swift        # 时间解析与相对时间
    │   └── AppInfo.swift           # 版本号 / 设备信息
    ├── Models/                     # PanelTask / TaskLog / EnvVar / Script / Dashboard / Notifier / SystemInfo / Config / Dependency / Auth
    ├── Components/                 # Theme、状态徽标、统计卡、空态、错误条、分享面板
    └── Features/
        ├── Login/                  # 登录（含 2FA、已保存面板）
        ├── Dashboard/              # 概览
        ├── Tasks/                  # 列表 / 详情 / 编辑
        ├── Logs/                   # 列表 / 详情 / 实时
        ├── Envs/                   # 列表 / 编辑
        ├── Subs/                   # 订阅
        ├── Scripts/                # 目录树 / 编辑器 / 试跑输出 / 历史版本
        ├── Notifications/          # 通知渠道列表 / 动态表单编辑（admin）
        ├── System/                 # 系统监控：资源 / 网络 / 健康检查（admin）
        ├── Configs/                # 系统设置：按 /configs 的 value_type 渲染表单（admin）
        ├── Deps/                   # 依赖管理：列表 / 安装 / 详情日志 / 镜像源 / 运行时 / 清单（admin）
        └── Settings/               # 更多 / 服务器 / 面板信息 / 关于
```

分层原则：**视图只碰 SessionStore 和 ViewModel，ViewModel 只碰 PanelAPI，PanelAPI 只碰 APIClient**。
换接口版本、加接口只改 `PanelAPI*.swift` 两个文件。

---

## 五、构建方案说明

为什么要 XcodeGen + 未签名产物：

1. `.xcodeproj` 是二进制式工程文件，手写/patch 极易冲突；用 `project.yml` 描述工程，CI 每次现生成，仓库里只有可读的 YAML。
2. TrollStore 安装不需要签名，`xcodebuild` 加 `CODE_SIGNING_ALLOWED=NO` 就能产出可用的 `Payload/DaidaiPanel.app`，
   再 `zip` 成 `.ipa`；TrollStore 安装时会自己 `ldid` 伪签名。
3. 因此**不需要付费开发者账号、不需要企业证书、不需要 7 天重签**。

产物结构：

```
DaidaiPanel-iOS-1.0.0-unsigned.ipa
└── Payload/
    └── DaidaiPanel.app/
        ├── DaidaiPanel           # 主二进制（arm64）
        ├── Info.plist
        └── Assets.car / AppIcon60x60@2x.png …
```

---

## 六、已知限制

- **人机验证无法在 App 内完成**：面板若开了第三方验证码，需要先在网页端登录一次，解锁后再回 App（登录页会给出提示）。
- **实时日志是轮询**：面板 `/tasks/:id/live-logs` 返回的是「最后 200 行 + done」快照，不是 SSE，所以按 1.5s 轮询，比网页端略滞后。任务一结束面板会清空该缓冲（`logs: []`），客户端会自动改读 `latest-log` 补全，不会变空白。
- **脚本编辑器没有语法高亮**：`TextEditor` 只做等宽显示；语法高亮需要接 CodeMirror/Highlightr，留到后续版本。
- **接口字段以「宽松解码」为准**：模型字段基本都按可选处理，面板升级加字段不会崩，但也意味着拿不到的值显示为空。
- iOS 15 的 `NavigationView` 样式比 iOS 16 的 `NavigationStack` 朴素一些，这是为兼容 TrollStore 老系统刻意做的取舍。

---

## 七、路线图

- [x] 脚本在线运行 + 输出回显（支持运行未保存内容、终止、复制）
- [x] 脚本历史版本只读预览
- [x] 代码格式化（面板 `/scripts/format`，python/shell/go/json）
- [x] 通知渠道列表、动态表单、新建/编辑/启停/测试推送（admin）
- [x] 系统监控（CPU / 内存 / 磁盘 / 网络 / 健康检查，5 秒自动刷新）
- [x] 日志管理（单条删除、按天数清理、原始日志下载分享）
- [x] 依赖管理（安装 / 重装 / 取消 / 卸载 / 实时日志 / 镜像源 / 多版本 Python / Playwright）
- [x] 系统设置（`/configs` 57 个注册项，按 value_type 动态渲染表单）
- [ ] 备份创建 / 下载 / 恢复
- [ ] 用户管理（增删改、重置密码）
- [ ] 2FA 绑定、会话管理、IP 白名单查看
- [ ] 后台进程列表与终止
- [ ] 小组件（Widget）展示今日执行概况
- [ ] 脚本编辑器语法高亮
- [ ] 中文/英文双语

---

## 八、许可

MIT。见 [LICENSE](LICENSE)。

本项目与呆呆面板作者无隶属关系，仅使用面板公开接口；面板本身遵循其自身仓库的 MIT 协议。
