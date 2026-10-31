# PR #1 审查反馈核验与修复

## TL;DR

核验对象为 [PR #1](https://github.com/oneinstack-next/oneinstack-next/pull/1)
在 `97cf0e704ad050e4b634f129004919120efe3303` 上收到的 9 条 CodeRabbit
行内评论。审查提交和汇总评论重复引用这些条目，没有额外独立反馈。
9 条均有当前代码证据，全部接受并修复；没有机械执行评论中的代理提示。
严重性分布：Critical 0 / High 7 / Medium 1 / Low 1。
本地 24 项契约测试为 23 项通过、1 项 Windows POSIX 测试跳过。
合并仍应以修复后提交的 Linux CI 为门槛，不能用本地测试代替。

## Core Conclusion Card

| 项目 | 结论 |
| --- | --- |
| 已核验反馈 | 9 / 9，全部成立 |
| 已落实代码修复 | 9 / 9 |
| 附加 CI 问题 | reload 就绪竞态、PID 交接读取、Python 3.9 与 xz 依赖，一并修复 |
| 本地回归 | 24 项：23 通过、1 平台跳过；最终完整回归耗时 56.871 秒 |
| 静态检查 | 52 个改动或新增 Shell 文件语法通过，针对性 ShellCheck 和 diff 空白检查通过 |
| 合并门槛 | 修复后提交的 Ubuntu、Rocky、Nginx/Tengine/OpenResty 与 ARM 检查通过 |

## Findings

| 评论 | 严重性 | 核验依据与修复 | 验证 |
| --- | --- | --- | --- |
| [4431664589](https://github.com/oneinstack-next/oneinstack-next/pull/1#discussion_r4431664589) | High | Rocky 任务日志明确显示 `curl-minimal` 与 `curl` 冲突；DNF 安装增加 `--allowerasing`。 | 原失败日志确认冲突；修复后 Rocky CI 为最终门槛。 |
| [4431664592](https://github.com/oneinstack-next/oneinstack-next/pull/1#discussion_r4431664592) | High | Apache 预检查必需 nghttp2 1.59.0，但目录缺项。增加发布者 release 的精确身份、大小、归档布局和 SHA-256，登记为明确官方例外。 | 发布者 checksum 匹配、`configure` 文件核验、实际统一下载器通过。 |
| [4431664595](https://github.com/oneinstack-next/oneinstack-next/pull/1#discussion_r4431664595) | High | PHP 7.4/8.0 的预检查选择 2.1.4，而安装选择 1.20.1。两者改用 `MongoDB_Artifact_For_PHP`，覆盖主 PHP 与 mphp，并登记 1.20.1。 | 实际预检查与安装函数在 PHP 7.4/8.0、mphp74/80 下选择一致。 |
| [4431664599](https://github.com/oneinstack-next/oneinstack-next/pull/1#discussion_r4431664599) | High | MySQL 8.4 下载 xz，却尝试 gzip 解压，失败后仍可停止服务和移动目录。按选定制品后缀解压，验证可执行布局，全部成功后才进入备份和变更。 | gzip/xz 真实小归档通过；坏 xz 调用真实升级函数时 dump、service、mv 均未执行。 |
| [4431664604](https://github.com/oneinstack-next/oneinstack-next/pull/1#discussion_r4431664604) | High | 所有 PHP 升级均请求缺少目录项的旧 FPM 补丁。现在仅 PHP 5.3–5.5 请求和应用该补丁，解压/补丁失败立即返回。 | 实际升级函数的 PHP 8.5、5.6 不请求补丁，5.5 请求补丁；在构建前停止夹具。 |
| [4431664609](https://github.com/oneinstack-next/oneinstack-next/pull/1#discussion_r4431664609) | High | 实际定义位于 `include/check_sw.sh`。末尾条件使非 Ubuntu24 正常路径返回 1；改为正常返回 0，同时传播 Ubuntu24 的 `ln` 失败。 | 实际函数：20/22 不调用链接命令且成功；24 链接成功/失败分别返回 0/非零。 |
| [4431664615](https://github.com/oneinstack-next/oneinstack-next/pull/1#discussion_r4431664615) | Low | README 的 cron 把脚本当作 `cd` 目录，不能运行备份。改为进入项目目录后执行 `./backup.sh`，保留 01:00 与输出重定向。 | 命令结构与实际脚本入口核对；未执行真实备份。 |
| [4431664623](https://github.com/oneinstack-next/oneinstack-next/pull/1#discussion_r4431664623) | Medium | `set -e` 对 `! grep` 不终止脚本；HTTP HSTS 禁用断言无效。改为命中头部时显式退出。 | 提取实际断言，注入带/不带 HSTS 的 HTTP 响应头；泄漏必须中止，正常必须通过。 |
| [4431664627](https://github.com/oneinstack-next/oneinstack-next/pull/1#discussion_r4431664627) | High | Apache 精确 IP vhost 优先于原有 wildcard vhost，可能把旧站点流量导向新站点。后端恢复 `*:88`，监听仍限制在 `127.0.0.1:88`。 | 实际 Apache writer 生成结果回归；原监听限制保持不变。 |

## Architecture Impact

Archi 确认 Apache 修复重新区分了“监听暴露范围”和“名称虚拟主机匹配”。
恢复 wildcard vhost 不会扩大监听范围；精确 IP 的优先级由
[Apache 官方规则](https://httpd.apache.org/docs/2.4/vhosts/details.html)说明。
Ubuntu helper 恢复明确的退出状态契约，没有新增服务或部署架构。

Cody 确认数据库的归档和可执行布局检查现在位于备份、停止服务及移动数据之前；
MongoDB 的两个消费入口共享选择函数，避免分别维护版本分支再次产生漂移。
历史 PHP 补丁若缺少受审核制品身份仍明确阻止对应旧组合，未增加绕过校验。

## Additional CI Repairs

Tessa 检查初始失败日志，确认各产品已进入真实编译/配置解析阶段，随后在请求
断言处失败，且 ARM 的早期任务曾通过，存在时序敏感性。reload 过程中只要出现
一个新 worker，旧就绪条件便可能成立，而旧 worker 此时仍可接受连接。
`Nginx_Health` 现在等待所有捕获的旧 worker 都停止接受新连接；精确匹配 active
worker 的进程标题，允许旧连接继续 graceful shutdown。回归夹具断言在旧/新
worker 并存时不得发请求，在旧 worker 转入 shutdown 后才继续。

Rocky 9 的 Python 3.9 不支持 `Path.write_text(newline=...)`。测试夹具改用
`Path.open(..., newline='\n')`，保留 Windows 的 LF 输出并兼容 3.9。
真实二进制 harness 增加失败位置、HTTP 状态与日志尾部诊断，没有放宽请求断言。

后续 [67fdfe8 的 Linux 运行](https://github.com/oneinstack-next/oneinstack-next/actions/runs/41227894587)
确认 Rocky 已通过 DNF 替换与 Python 3.9/POSIX 检查，仅有效 xz 归档测试因缺少系统
`xz` 程序失败；workflow 现显式安装对应平台的 xz 包。四个产品任务均通过前述
请求与证书检查，随后在首次真实 USR2 切换中失败：正常 PID 文件重命名窗口内，
未保护的 `cat` 失败被继承的 `set -e` 提前终止。该读取现在显式视作暂时空状态，
继续有限轮询。健康检查的瞬时 curl 失败也显式进入下一次尝试。

前后对照故障测试直接调用真实 helper，保留 `set -e`：提交版本的健康检查与 PID
交接测试分别以 7、1 退出，修复后两者都通过；PID 测试同时核对新二进制、旧备份
和旧 master 的退出顺序。此证据证明有限重试合同，真实 Linux 切换仍须由最新 CI
完成验证。

## Artifact Evidence

- nghttp2 1.59.0：发布者 [checksums.txt](https://github.com/nghttp2/nghttp2/releases/download/v1.59.0/checksums.txt) 与下载字节匹配；SHA-256 为 `90fd27685120404544e96a60ed40398a3457102840c38e7215dc6dec8684470f`。
- MongoDB 1.20.1：从 [PECL](https://pecl.php.net/package/mongodb/1.20.1) 发布者地址独立下载；项目固定 SHA-256 为 `614e57594918feb621f525e6516d59ce09b78f5172355ba8afb6c2207c1ce900`。这是直接观察的项目 pin，不宣称发布者签名验证。
- PECL 的根目录 `package.xml` 通过显式 `allowed_root_files` 登记；其他根目录条目和路径穿越仍拒绝。预期 `config.m4` 仍必须存在。
- 两个制品都通过实际 `Download_Artifact` 的网络、摘要与归档验证；目录现为 78 项、75 项强摘要、15 项随项目补丁。

## Test Coverage Assessment

| 场景 | 类型 | 优先级 | 证据 |
| --- | --- | --- | --- |
| xz/gzip 正常布局与坏 MySQL 升级包 | 契约/隔离真实函数 | P0 | 不触发 dump、停止服务或数据移动 |
| PHP 旧补丁范围与 MongoDB 双入口一致性 | 契约 | P0 | PHP 主/附加版本分支覆盖 |
| Ubuntu helper 成功与链接失败传播 | 契约 | P1 | 使用私有 scratch 路径，无系统包修改 |
| HTTP HSTS 泄漏与 reload active-worker 重叠 | 故障注入 | P0 | 必须拒绝错误结果，不能仅验证成功路径 |
| Apache writer wildcard 与 PECL 根文件允许列表 | 契约 | P1 | 实际 writer/下载器代码执行 |
| PID 文件暂时缺失与瞬时探测失败 | 故障注入/前后对照 | P0 | 直接 set -e 调用可重试，旧代码确实失败 |
| 产品、OS、架构和实际热切换 | Linux 集成 | P0 | 修复后 PR workflow 必须通过 |

契约覆盖足以回归本次局部修复；生产兼容结论仍不足。完整数据库升级、Apache/Tomcat
真实生命周期、公开 IPv6、完整 PHP/Magento 应用以及 ACME staging 仍属于原计划的
独立运行验收。查看 [PR 最新检查](https://github.com/oneinstack-next/oneinstack-next/pull/1/checks)
判定修复后 Linux 集成门槛，不使用旧提交的成功结果代替。

## Action List

| 顺序 | 行动 | 负责人 | 紧急度 | 目标日期/状态 |
| --- | --- | --- | --- | --- |
| 1 | 核验全部评论并修复 9 项有效反馈 | Cody / Archi / 根代理 | 合并前 | 2026-10-31，代码与本地回归完成 |
| 2 | 补齐制品依据及故障路径测试 | Tessa / 根代理 | 合并前 | 2026-10-31，网络和本地检查完成 |
| 3 | 推送修复并跟进最新 Linux CI，修复真实失败 | 根代理 | 合并前 | 以 PR 最新提交检查为准 |
| 4 | 完成原计划的完整栈与 ACME staging 实机验收 | 维护者提供环境后继续 | 发布前 | 仍未以本次局部回归宣称完成 |

## Disclaimer

本报告由工程保障团队 AI 协作生成，关键决策请由人类工程负责人复核。
