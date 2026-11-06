# 文明 VI / Civ6：2K 一直离线修复（Steam Windows）

网络和 Steam 商店正常，但《文明 VI》主菜单的 2K 始终离线、互联网联机不可用？如果属于本项目识别的**本地初始化同步故障**，工具会在游戏启动时安装临时保护，让游戏自身继续完成登录。

**这是 [yeeesy/Civ6-2K-Online-Fix](https://github.com/yeeesy/Civ6-2K-Online-Fix) 的社区分支，基于上游 `v1.1.0`。核心修复、图形界面和安全校验来自原作者及上游贡献者。** 本分支补充游戏 `1.0.12.72` 的 DX12 适配与 Steam 自动启动器，保留 MIT 许可证。与 2K、Firaxis、Take-Two、Valve 均无隶属或背书关系。

**[下载社区版](https://github.com/jiang-haibin/Civ6-2K-Online-Fix/releases/latest)** · [适配原理](docs/TECHNICAL.md) · [验证记录](docs/VALIDATION.md) · [反馈问题](https://github.com/jiang-haibin/Civ6-2K-Online-Fix/issues)

## 先确认适用范围

本分支版本为 `1.1.0-community.72.1`；它是工具版本，与游戏版本不同。工具按**文件名、SHA-256、大小及 PE 身份**识别游戏，不会只凭版本号写入。

| Windows Steam 游戏构建 | 渲染器 | 状态 | 证据与行为 |
| --- | --- | --- | --- |
| `1.0.12.72 (1327737)` | DX12 | 本机实测，允许修复 | 恢复 2K 登录；可加载互联网房间列表；已验证 Steam 自动启动 |
| `1.0.12.72 (1327737)` | DX11 | 只读候选 | 已建立静态配置，尚未实测修复；**不会写入** |
| `1.0.12.68` | DX11 / DX12 | 继承上游支持 | 沿用上游精确配置，本分支未重新进行旧版实机验证 |
| 其他哈希、平台或游戏更新 | 任意 | 不支持 | 拒绝修复；不要自行套用旧地址 |

新版建议在 Steam 选择 **DX12**。DX11 候选不表示 DX11 已修好。已验证的是单台机器的登录和房间列表，尚未验证完整多人对局、多台机器或长时间运行。网络、账号、2K/Steam 服务器和 Mod 问题需要分别排查；单凭“离线”无法确认属于此故障。

## 下载和校验

1. 从本分支 [Releases](https://github.com/jiang-haibin/Civ6-2K-Online-Fix/releases) 下载版本对应的 `Civ6_2K_Online_Fix_*.zip` 和同名 `.zip.sha256`。GitHub 自动提供的 **Source code** 是源码，不含可执行程序。
2. 核对压缩包 SHA-256：

   ```powershell
   Get-FileHash '.\Civ6_2K_Online_Fix_1.1.0-community.72.1.zip' -Algorithm SHA256
   Get-Content '.\Civ6_2K_Online_Fix_1.1.0-community.72.1.zip.sha256'
   ```

   两处的 64 位哈希应相同。校验用于发现下载损坏或文件差异；下载来源仍应是本仓库的 Release。
3. 完整解压到固定、可写的目录，例如 `D:\Tools\Civ6Fix`。两个 EXE 必须放在同一目录，不能直接在 ZIP 内运行。
4. 可选：在首次运行前用 **PowerShell 7** 执行包内的 `verify_hashes.ps1`，核对全部文件。运行产生新日志后会出现“额外文件”，此时应对新解压的副本执行完整集合校验。

程序未做 Authenticode 签名，可能显示未知发布者。请核验源码与校验值，不要为运行本工具而关闭安全软件。普通使用无需管理员权限。

## 方法一：先开修复器，再开游戏

1. 完全退出《文明 VI》。已经卡在离线的游戏需重新启动。
2. 打开 `Civ6_2K_Online_Fix.exe`，等它进入监听。
3. 在 Steam 点击开始游戏，新版选择 **DX12**。
4. 等工具给出最终结果，再查看游戏主菜单的 2K 状态和“多人游戏 → 互联网”是否可用。

修复成功后可关闭工具窗口，本次保护随游戏进程退出而结束。工具的成功结果不等于完整多人对局测试通过。若仍离线，请用本页后面的反馈方法收集证据。

## 方法二：Steam 启动游戏时自动运行

完成一次手动验证后，可设置自动启动，之后仍从 Steam 点击开始游戏。

1. 完全退出游戏，保留解压后的文件夹。
2. Steam → 库 → 右键《文明 VI》→ 属性 → 通用 → **启动选项**，填写：

   ```text
   "D:\Tools\Civ6Fix\Civ6-Start.exe" %command%
   ```

   把双引号内路径换成自己的实际位置；保留 `%command%`，不要把它改成游戏文件路径。如果已有其他启动参数，先记录原值并确认兼容，不要把两条 `%command%` 命令拼接起来。
3. Steam 有渲染器选项时，新版选择 **DX12**，然后正常开始游戏。

启动器先运行同目录修复器，收到 `listener_ready` 后才运行 Steam 传入的游戏命令，并一直等待游戏结束，让 Steam 正常跟踪运行状态。它不负责更改渲染器。

如果修复器缺失、启动失败、提前退出或准备超过 60 秒，启动器会记录原因并继续启动原游戏。**回退只保证尝试启动游戏，不保证能联网。** 运行时不联网下载更新，也不安装系统自启动、服务或计划任务。

**撤销：** 完全退出游戏，清空或还原 Steam 启动选项，再删除解压目录即可。移走目录前先撤销启动选项，否则 Steam 会找不到启动器。修复不修改游戏 EXE、存档或系统 DLL，无需恢复这些文件。

## 排查与反馈

| 现象 | 下一步 |
| --- | --- |
| 更新后提示未知构建 | 停止套用旧配置，提交新版本信息和只读诊断 |
| 新版选择 DX11 后未修复 | 当前 DX11 只读，改用 Steam 的 DX12 启动项 |
| 自动模式游戏打开但仍离线 | 完全退出，使用方法一查看修复器的最终结果；检查实际识别的渲染器 |
| 提示目标已存在其他改动 | 停止重复开多个修复器；退出游戏后单独启动本工具重试 |
| 两项状态都就绪但仍不能联机 | 继续检查游戏 UI、账号、网络及服务器；不要把状态值当作对局成功证明 |
| 工具超时 | 复制终态脱敏诊断；超时不是删除 SQLite/账号缓存的依据 |

请向**本分支** [提交 Issue](https://github.com/jiang-haibin/Civ6-2K-Online-Fix/issues)，提供：工具版本、Windows 版本、游戏版本与渠道、实际 DX11/DX12、手动/自动启动、游戏 UI 表现，以及工具 GUI 的“复制脱敏诊断”。不要上传账号、游戏 EXE、存档、数据库、原始日志或未经检查的截图。

`logs/` 中的 JSONL 和 `Civ6-Start.log` 可能含本机路径、PID、内存地址等；它们只保存在本机，不会自动发送。`--diagnose` 是只读发现/预检，**输出仍需自行脱敏**，不能代替完整运行后的诊断摘要。更多说明见 [DIAGNOSTICS.md](docs/DIAGNOSTICS.md)。

```text
Civ6_2K_Online_Fix.exe                     图形界面，默认只监听
Civ6_2K_Online_Fix.exe --no-gui --watch-only 无窗口监听，供启动器使用
Civ6_2K_Online_Fix.exe --diagnose           只读发现与预检
Civ6_2K_Online_Fix.exe --self-test          离线自检
```

## 原理和边界

受影响的启动中观察到 OpenSSL 相关互斥锁计数变为 `-1`，Discovery/SSO 停在 `3/3`，登录日志报 `514 (ERROR_NOT_INITIALIZED)`。这是本次诊断的证据，**不是所有离线现象的通用根因**。

沿用上游方法：工具在游戏进程中分配临时保护代码，将游戏 `_Mtx_unlock` 的 IAT 指针临时指向保护入口。只有调用来自指定的 OpenSSL 解锁位置、且目标锁计数不大于零时，才跳过该次无效解锁；其他调用转发给系统原函数。它不伪造账号登录、不绕过所有权或服务器认证。

新配置额外校验 59 字节回调指令结构及四处 RIP 相对操作数目标；同时保留精确文件身份、运行时映像、System32 运行库、目标所有权、写后回读和保护恢复等检查。未知或不一致时停止，DX11 候选不会获得写入权限。进程内修改仍有并发风险，保护不会在游戏仍可能执行它时热释放。细节见 [TECHNICAL.md](docs/TECHNICAL.md)。

## 源码与构建

正式发布使用 Windows x64、PowerShell 7、Visual Studio 2022（C++ x64 工具、MSBuild/Roslyn）和 Windows 10/11 SDK，无需额外包管理依赖：

```powershell
./build.ps1 -Analyze
./build/Civ6_2K_Online_Fix.exe --self-test
./package.ps1
```

`build.ps1` 同时构建修复器和启动器，执行核心、校验器、发布策略和启动器回退/参数测试。GitHub CI 再从包内源码异路径重建两个 EXE，逐字节比对，全部通过后生成可下载工件。Release 附件取自对应提交的成功 CI，保留完整源码和 SHA-256 清单。

本机仅有 MinGW 时可用 `./build.ps1 -Mingw` 做开发构建，需 x64 `g++`/`windres` 在 PATH 和 .NET Framework C# 编译器。此路径不等同 MSVC `/analyze`、CFG/CET 或可复现发布验证；`package.ps1` 会拒绝将它当正式包。

| 文件/目录 | 作用 |
| --- | --- |
| `src/` | 原生修复器、界面、严格校验及会话生命周期 |
| `launcher/Civ6-Start.cs` | 单文件 Steam 自动启动器 |
| `tests/` | 核心、安全、诊断、校验和启动器回归测试 |
| `build.ps1` | 生成版本信息、编译两个 EXE、测试并输出构建清单 |
| `package.ps1` | 校验发布条件，按允许清单打包源码与程序并生成哈希 |
| `verify_hashes.ps1` | 核对解压包的精确文件集合与 SHA-256 |
| `version.json` | 工具版本唯一来源 |
| `docs/` | 适配原理、脱敏验证记录、诊断及维护说明 |

详见 [维护说明](docs/MAINTAINER.md)、[贡献指南](CONTRIBUTING.md)、[安全策略](SECURITY.md)。历史上游 Release/Review 文档保留于 `docs/`，仅描述其对应版本。本项目使用 [MIT License](LICENSE)，感谢上游作者提供可审阅的实现。

## English quick start

This is a community fork of [yeeesy/Civ6-2K-Online-Fix](https://github.com/yeeesy/Civ6-2K-Online-Fix), based on upstream v1.1.0. It adds an exact profile for **Windows Steam Civ VI 1.0.12.72 DX12** and a Steam launch wrapper. DX12 login and internet lobby listings were verified on one local machine; a full multiplayer match was not tested. New DX11 is **read-only**, while the legacy 1.0.12.68 profiles retain upstream support.

Download the ZIP and checksum from [this fork's Releases](https://github.com/jiang-haibin/Civ6-2K-Online-Fix/releases). Exit the game, extract everything, start the helper, then launch **DX12** from Steam. To automate this, set Steam launch options to `"D:\Tools\Civ6Fix\Civ6-Start.exe" %command%` using your actual extraction path. Clear the option before removing the folder. Helper failure falls back to launching the base game, without promising online access.

The helper temporarily guards one verified invalid unlock in game memory. It does not modify game files or bypass authentication. Unknown hashes fail closed. Raw logs can contain private data; share the GUI's sanitized diagnostic summary instead. Source, strict MSVC build/analysis, tests, packaging and reproducible rebuild checks are included. Original MIT attribution is preserved.
