# 重启保护 · DSH Safe Restart

**中文** · [English](README.en.md)

> 一个给 **DeepSeek Harness 桌面版**（DSH）用的「带护栏的重启器」。
> 重启前逐个检查插件能否加载，重启后做健康检查，起不来自动回滚。

**一句话**：DSH 重启失败时会把插件配置**默默降级成出厂状态**（27 个插件变 2 个、197 行的 `cordis.patch.yml` 变 22 行）。这个脚本让这件事不再发生。

| | |
|---|---|
| **谁需要** | 装了一堆第三方插件、又经常要重启 DSH 的人 |
| **做什么** | 预检 → 快照 → 重启 → 健康检查 → 失败自动回滚 |
| **代价** | 多花 5~10 秒（预检的时间），换「重启坏了能自己爬回来」 |
| **依赖** | Windows + PowerShell 7 + DSH 自带 Node，**不联网、不用装任何东西** |

> 仓库名用英文 `dsh-safe-restart`（URL 友好），中文名「重启保护」。

---

## 它解决什么问题

DSH 把插件配置存在你的 profile 目录里：

```
%USERPROFILE%\.dsh\profiles\<profile>\package.json      # dsh.profile.bundles 列表
%USERPROFILE%\.dsh\profiles\<profile>\cordis.patch.yml  # 插件加载顺序与配置
```

只要其中**任何一个**插件在重启后加载失败，DSH 的 web boot 就会失败，然后它会做一件很坑的事：

**默默把配置降级成出厂状态。**

具体表现：

| 项目 | 正常 | 降级后 |
| --- | --- | --- |
| `dsh.profile.bundles` | 几十项 | **2 项**（只剩 dsh-base / dsh-web-app） |
| `cordis.patch.yml` | 几百行 | **661 字节**（22 行，三条 UI 覆盖） |

没有报错弹窗，没有自动备份，没有「是否恢复」的询问。你打开 DSH，只会发现插件全没了。

这个脚本在重启前后各加一道护栏，把这件事变成不可能。

---

## 三个真实案例

这三个事故都真实发生过，也是这套脚本的诞生原因。

### 案例一：一个插件崩了，三十多个插件陪葬

装了 `@ebony-vinyl/dsh-our-free-model` 2.8.3。它的客户端 bundle 在启动时注册了两次，抛 `duplicate factory registration`。web boot 失败，DSH 把配置降级：`bundles` 从 27 项变成 2 项，`cordis.patch.yml` 从 197 行变成 661 字节。

恢复花了一个多小时——因为要一项一项把插件加回去，每加一项重启一次确认。

**如果有这个脚本**：重启前的 dry-run 会检查每个 bundle 能否被 `import`，坏的会被直接拦下，`exit 3`，配置一个字都不会动。

### 案例二：装插件把另一个插件删空了

`pnpm add` 升级插件时，DSH 正开着，文件被占用：

```
ERR_PNPM_EPERM: rename 'node_modules/ds-harness-remote_tmp_15340_11' -> 'ds-harness-remote'
```

pnpm 失败退出，但**已经把上一个包的内容删掉了**。`ds-harness-remote/dist/` 变成空目录（92 KB，原本 8.1 MB），`dist/index.js` 直接消失。

下一次重启时，dry-run 报：

```
NO-ENTRY ds-harness-remote 0.6.5
ABORT: dry-run found bundles that cannot be imported; nothing was restarted
```

**这个脚本拦住了这一刀**。没有它，DSH 会把配置降级。

### 案例三：版本不兼容在重启后才暴露

插件作者发新版，`engines.dsh` 或子路径导出跟当前 DSH 版本对不上。装是装上了，`pnpm` 也没报错，**只有重启后才炸**。

dry-run 检查的是真实的 `import()` 能否成功，所以这类问题在重启前就会暴露。

---

## 用法

### 安装

**不需要装 PowerShell 7。** Windows 10 / 11 自带的 Windows PowerShell 5.1 就够 —— 本仓库的所有脚本和 `.cmd` 启动器都是在 5.1 上测的。

依赖只有三个，而且都不用你装：

| 依赖 | 谁提供 |
| --- | --- |
| Windows PowerShell 5.1 | 系统自带（Win10 1809+ / Win11） |
| .NET Framework 4.5+ | 系统自带，WPF 界面靠它 |
| Node.js | **DSH 自己带的**，脚本会自动去 `dsh-runtimes\*\dependencies\node\bin\node.exe` 找 |

所以对使用者的要求只有一句：**装了 DSH 就能用**。

> 顺带一提：Windows 7 自带的是 PowerShell **2.0**，跑不了 —— WPF 那部分语法和 `ConvertTo-Json -Depth` 都要 PowerShell **3.0+**。不过 Win7 现在也装不了 DSH，所以实际碰不到。

```bat
:: 1. 把仓库放到任意目录
git clone https://github.com/c00d002/dsh-safe-restart.git

:: 2. 进目录，创建桌面快捷方式
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

桌面会出现「**重启DSH（安全）**」，双击即用。

> **⚠ 双击 `.cmd`，不要双击 `.ps1`**
>
> Windows 默认执行策略是 `Restricted`，直接运行 `.ps1` 会报：
>
> ```
> 无法加载文件 ...\xxx.ps1，因为在此系统上禁止运行脚本。
> SecurityError: UnauthorizedAccess
> ```
>
> 仓库里的 `.cmd` 启动器已经带上 `-ExecutionPolicy Bypass`，**只对这一次调用生效**，不改你的系统设置。要走命令行的话就照上面的写法带上这个参数。

卸载快捷方式：

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Uninstall
```

### 日常使用

双击桌面的「重启DSH（安全）」→ 弹确认框 → 等 40~70 秒 → 弹结果。

会话和对话记录都存在磁盘上，重启不会丢。

### 命令行

下面用 `powershell`（5.1）写，如果你装了 7，换成 `pwsh` 也一样。

```powershell
# 正常重启（预检 + 快照 + 重启 + 健康检查 + 回滚）
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-safe-restart.ps1

# 只检查不重启：看预检结果、生成快照，然后退出
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-safe-restart.ps1 -DryRun

# 指定 profile（默认自动选 desktop）
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-safe-restart.ps1 -ProfileName work

# 延长健康检查等待（默认 60 秒，插件多的机器可以调大）
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-safe-restart.ps1 -WaitSec 120

# 跳过预检（不推荐，只在预检本身有 bug 时用）
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-safe-restart.ps1 -SkipSimulate
```

### 图形界面（推荐给不想看命令行的人）

```bat
:: 打开检查窗口：列出每个插件能不能加载，有问题会标红
2-看现状.cmd
```

窗口里有三个按钮：

| 按钮 | 干什么 |
| --- | --- |
| 关闭 | 什么都不改 |
| 恢复快照 / 恢复备份 | 把配置退回上次好的状态，然后重启 |
| 停用并重启 | 把加载失败的插件从启动清单里摘掉，然后重启 |

「恢复」的三种情况：有快照就用快照；没快照就去翻 `package.json.bak-*` 挑插件最多的那份；两样都没有时按钮不显示。

### 退出码

| 码 | 含义 | 配置动过吗 |
| --- | --- | --- |
| `0` | 重启成功 | 没动 |
| `2` | 第一次没起来，已自动回滚并恢复 | 回滚到快照 |
| `3` | 预检拦截，**没有重启** | 完全没动 |
| `4` | 回滚后仍然起不来，需要人工介入 | 回滚过 |

`3` 是最常见的"好消息"——说明护栏起作用了。

---

## 工作原理

四个阶段：

```
1. 预检 (dry-run)
   └─ 逐个 import profile 里声明的 bundle 入口
      └─ 有任何失败 → exit 3，什么都不做

2. 快照
   └─ 复制 package.json / cordis.patch.yml / cordis.yml
      └─ 存到 %LOCALAPPDATA%\dsh-safe-restart\snapshots\<时间戳>\

3. 重启
   └─ 杀掉所有 DeepSeek Harness 进程 → 重新启动

4. 健康检查
   ├─ 进程数 ≥ 2
   ├─ 没有新的 crash-*.log
   └─ DSH 进程自己监听了端口
      └─ 不健康 → 还原快照 → 再启一次 → exit 2 / 4
```

### 自动探测，不写死路径

脚本不假定你的安装位置，以下全部自动探测：

- **DSH 可执行文件**：运行中的进程 → 卸载注册表 → 常见安装路径
- **profile 目录**：`%USERPROFILE%\.dsh\profiles\desktop`，没有则选最近修改的
- **Node**：DSH 自带的 `dsh-runtimes/*/dependencies/node/bin/node.exe` → PATH 里的 `node`
- **日志目录**：`%APPDATA%\@deepseek-ai\dsh-desktop\logs`

所以换机器、换用户名、换盘符都能直接用。

### 日志

```
%LOCALAPPDATA%\dsh-safe-restart\safe-restart.log   主脚本日志
%LOCALAPPDATA%\dsh-safe-restart\ui.log             UI 入口日志
%LOCALAPPDATA%\dsh-safe-restart\snapshots\         快照
```

---

## 常见问题

**Q: 需要装 PowerShell 7 吗？**

不用。Windows 10 / 11 自带的 Windows PowerShell 5.1 就行，本仓库全部测试都在 5.1 上做的。装了 7 也能跑，把命令里的 `powershell` 换成 `pwsh` 即可。

**Q: 双击 `.ps1` 报「因为在此系统上禁止运行脚本」？**

你的执行策略是 `Restricted`（Windows 默认）。别改系统设置，**双击仓库里的 `.cmd` 就行** —— 它们带 `-ExecutionPolicy Bypass`，只对当次运行生效。命令行同理，加上 `-ExecutionPolicy Bypass` 这个参数。

**Q: 提示 `exit 3` 但我看插件都好好的？**

dry-run 检查的是「现在这一刻能不能 import」，不是「你上次用得好不好」。八成是：
- 某个插件刚升级，`dist/` 没装完整（重新 `pnpm add` 一遍）
- DSH 还开着，文件被锁（关掉 DSH 再跑一次 dry-run）

看日志里 `NO-ENTRY` / `IMPORT-FAIL` 那几行，会指出具体是哪个包。

**Q: 快照会占很多空间吗？**

一份快照三个文件，通常几十 KB。脚本不会自动清理，攒多了自己删 `snapshots` 下的旧目录即可。

**Q: 如果崩了之后才第一次打开这个工具，还有救吗？**

有。窗口里那个按钮会自动换名字：
- 之前跑过工具 → 显示「恢复快照 N 个」
- 之前没跑过 → 自动去 profile 目录翻 `package.json.bak*`，挑插件数最多的那份 → 显示「恢复备份 N 个」
- 连 bak 都没有 → 按钮不出现，只能手动重装插件

**Q: 能用于 Web 版 DSH 吗？**

不能。这个脚本重启的是**桌面版进程**。Web 版（`dsh web`）用 `pm2` / `systemd` 之类管理进程更合适。

**Q: 为什么不用计划任务？**

试过。`schtasks /Create` 在某些机器上返回 `4294967295` 且无输出，`Register-ScheduledTask` 报「拒绝访问」。所以改成「独立进程 + 弹窗确认」，更可靠也更透明——你能看见它在干什么。

---

## 附带工具：清理 DSH 登录缓存

**这是另一个坑，和重启保护无关，但同样会让 DSH「打不开」。**

DSH 每次启动都会往 `%APPDATA%\@deepseek-ai\dsh-desktop\Network\Cookies` 写一条登录 cookie，**从不清理**。攒到请求头 16 KB 之后，DSH 启动时会报 `Web authentication failed`，表现就是「**双击没反应 / 打不开**」。

这不是插件问题，也不是配置坏了——删掉两个文件就好。聊天记录、工作区、插件全在 `.dsh` 目录里，一点不受影响。

`清理DSH登录缓存.bat` 就做这一件事：

- 双击运行，先检测 DSH 是否在跑
- 在跑就等你完全退出（窗口关掉不算，要托盘右键退出或任务管理器结束进程），退出后自动继续
- 删掉 `Cookies` 和 `Cookies-journal`
- 提示完成，然后正常启动 DSH

**为什么需要它**：DSH 自己没有「清缓存」按钮，官方文档也没写这个坑。这个脚本是从真实故障里抠出来的——攒了大概两个月，某天双击 DSH 直接弹 `Web authentication failed`，重装都没用，最后才定位到是 cookie 文件涨到 16 KB 触发了 HTTP 431。

**建议**：一个月跑一次，或者发现 DSH 启动变慢、偶尔打不开时先跑一遍。

---

## 目录结构

```
dsh-safe-restart.ps1       主脚本（预检 / 快照 / 重启 / 健康检查 / 回滚）
dsh-safe-restart-ui.ps1    图形入口（确认框 + 结果弹窗）
dsh-simulate.mjs           dry-run 实现：用 Node 逐个 import bundle 入口
install.ps1                创建 / 删除桌面快捷方式
清理DSH登录缓存.bat        附带工具：清掉让 DSH 打不开的 cookie 缓存
README.md                 中文
README.en.md              英文
LICENSE
```

## 版权与许可

**代码著作权归 TNT460 所有，以 GNU General Public License v3.0 授权。**

完整许可文本见 [`LICENSE`](LICENSE)（GNU 官方原文，674 行，可直接校验）。

### 你可以

- 免费使用，**商用也可以**（GPL 从来不禁止赚钱）
- 修改任意部分
- 分发原版或改过的版本，甚至收费分发

### 你必须

- **分发时提供完整源码**（包括你改过的部分）
- **衍生作品也得用 GPL v3** —— 这就是 copyleft：开了源就得一直开着
- 保留版权声明和许可文本
- 改动过的文件要标明「已修改」

### 你不可以

- 把这份代码并进**闭源**产品或服务里再分发
- 附加额外限制（比如要求别人付费才能使用你的修改版）

### 作者不承担

软件按「现状」提供，无任何担保。用它导致的数据丢失、系统故障或其它损失，作者不负责。

它做的事情（杀进程、改配置文件、回滚）本身有风险，用之前请确认快照机制正常。

### 作者保留

- 著作权（copyright）始终在作者手里
- 作者可以用同一份代码再以其它协议授权（双许可，比如以后出一个商业版）

### 现实中的影响

| 场景 | 允不允许 |
|---|---|
| 个人或公司内部用来自动重启自己的 DSH | ✅ 随便用；不分发就没有开源义务 |
| 改几行自己用 | ✅ 同上 |
| 打包进你自己的开源项目 | ✅ 但你的项目也得是 GPL v3 |
| 打包进你公司的闭源工具去卖 | ❌ 不行 |
| 放到收费插件市场里分发 | ⚠️ 可以收费，但必须同时提供源码，且买家有权再分发 |

> 一句话：**自己用、内部用、开源项目用都没问题；想做成闭源商业产品不行。**

### 为什么选 GPL v3 而不是 MIT

MIT 允许别人拿走改成闭源卖，作者一分钱拿不到。GPL 保证「谁改谁开源」，社区改进会回流到这个仓库。

代价也要说清楚：一些公司内部政策禁止引入 GPL 代码，所以它的收录面会比 MIT 窄一些。

> 以上是通俗解释，不构成法律意见。真要商用或担心纠纷，请咨询律师。
