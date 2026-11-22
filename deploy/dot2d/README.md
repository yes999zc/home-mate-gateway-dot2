# dot2-d 设备侧写入物（G3 实机建链，2026-11-07）

本目录**逐字节**存档写入 dot2-d（serial `G090L91072732EXG`）的每一份文件——设备上发生过什么、Git 里就有什么。

## 写入清单

| 设备路径 | 内容 | 本仓存档 | 设备侧备份 |
|---|---|---|---|
| `/data/local/etc/echomuse/controller.json` | 端点指向 Home Mate 网关（192.168.1.20:9015，mdns off） | `controller.json`（80B） | `controller.json.before-hm-20261107`（82B 原件→.168:9014） |
| `/data/local/etc/echomuse/ca.pem` | Home Mate 自签 CA 证书（公开材料，证书本身不是秘密） | `hm-ca.pem`（1111B） | `ca.pem.before-hm-20261107`（554B 原件＝设备自带 `ca.pem.bak-20261029-221159` 同内容） |

**永不入 Git**（在 `/secrets/`，已 gitignore）：CA 私钥 `hm-ca.key`、服务器私钥 `server.key`、设备 token `emuse-token`。

## 写入/回滚操作（需要 USB adb＋Magisk root）

```bash
S=G090L91072732EXG
# 写入（首次已做过备份；重放前确认 .before-hm-* 存在）
adb -s $S push deploy/dot2d/hm-ca.pem /data/local/tmp/hm-ca.pem
adb -s $S push deploy/dot2d/controller.json /data/local/tmp/hm-controller.json
adb -s $S shell su -c 'cp /data/local/tmp/hm-ca.pem /data/local/etc/echomuse/ca.pem; cp /data/local/tmp/hm-controller.json /data/local/etc/echomuse/controller.json; rm /data/local/tmp/hm-*'
# 生效：等设备 ≤60s 重拨，或立即 kill server 进程（supervisor 秒级拉起）
adb -s $S shell su -c 'kill $(ps | grep /data/local/bin/server | grep -v grep | awk "{print \$2}")'
# 回滚＝把两个 .before-hm-20261107 cp 回原名，同样等重拨
```

回滚演练记录（2026-11-07 一次通过）：恢复两文件→设备回 `wss://192.168.1.10:9014` refused 重试循环（原始状态，RUI 侧仍禁用）→核心侧 dot2-d 如实 offline→重指回来秒级重新注册、mic 流恢复。

## 硬事实备忘（证书/身份）

- 设备 TLS 客户端按固定名 **`echomuse-controller`** 验证服务器证书（与拨号 IP 无关）——服务器证书 SAN 必含 `DNS:echomuse-controller`。
- register 的 `device_id` 是**序列号**（G090L91072732EXG），不是 stable_id；适配器北向呈现 stable_id=dot2-d。
- 设备不回 ICMP；在线判断用应用层流量（audio_chunk seq / pong）。

## G5-1 · 适配器上机（2026-11-08 凌晨，形态 A 共存）

`deploy/dot2d/on-device/`＝本轮写入 dot2-d 的全部新文件（逐字节存档，SHA256 见内）。形态与边界详见 `docs/g5/on-device-form-20261107.md`。

### 上机后设备布局

| 设备路径 | 内容 | 存档 |
|---|---|---|
| `/data/local/etc/echomuse/controller.json` | 端点＝环回 127.0.0.1:9015 | `on-device/controller.loopback.json` |
| `/data/local/etc/echomuse/controller.json.before-hm-loopback` | 切换前备份（＝.27:9015） | `controller.json`（G3 存档同内容） |
| `/data/local/tmp/hm-adapter/gateway` | armv7 musl 静态适配器（3,348,244B） | `on-device/gateway-armv7-musl` |
| `/data/local/tmp/hm-adapter/server.pem/key` | 专用叶证书（hm CA 签，SAN=echomuse-controller+127.0.0.1）＋私钥 | pem 存档；**key 永不入 Git**（设备路径在案，重签：`openssl req … | openssl x509 -req -CA secrets/hm-ca.pem -CAkey secrets/hm-ca.key …`） |
| `/data/local/tmp/hm-adapter/token` | 设备自身 token 的副本（cp 自 `/data/local/etc/echomuse/token`，mode 644） | 不入 Git（同源已在设备） |
| `/data/local/tmp/hm-adapter/run.sh` | 绝对路径启动器 | `on-device/run.sh` |

### 运行形态（截至本轮收尾）

- **北向**：设备适配器 →（WiFi）→ Mac `192.168.1.20:8932`＝**relay**（网关仓 `relay` 子命令，同二进制在防火墙白名单内）→ 核心 loopback 8932。核心保持仅回环绑定；macOS 应用防火墙不放行 hm-core（未列入白名单、无 sudo 的无人值守夜无法加白）——这是 relay 存在的原因。
- **监督**：Magisk 17.3 `/data/adb/service.d` 不可写（SELinux 拒绝 su），开机自启未成立（脚本存档为 `.unusable` 备查）。当前以 **Mac 侧长连 adb 会话保活**（`nohup adb -s $S shell 'sh /data/local/tmp/hm-adapter/run.sh'`，pid 记录 /tmp/hm-tether.pid）。开机持久化三选一待用户定：升级 Magisk／手装 module 进 magisk.img／改用 init 服务（G5-2 替换形态一并解决）。
- EchoMuse 侧未动：server 照常由其 A/B 监督拉起，仅 controller.json 改指环回。

### 上机回归（全部通过，2026-11-08 00:2x）

mic 流（seq 持续上涨经环回北向）／语音探针 device_confirmed（synth 587ms total 2227ms）／唤醒自回环（Mac 喇叭→设备 mic→mic_wake→GLM 轮→8.0s TTS 应答，LED wake→thinking→speaking）／音量往返。**回滚演练通过**：仅恢复 controller.json.before-hm-loopback＋重启 Mac 适配器→设备自行重拨恢复（gen 13，秒级）。

### 硬事实（G5-1 新增，排障前必读）

1. **macOS 应用防火墙按进程拦 LAN 入站**：hm-core 绑 LAN 后从设备 SYN 被静默丢（挂起无 RST、无 warn 日志）；同机 nc/白名单网关二进制放行。诊断特征＝「连接无任何日志挂死」vs「Connection refused 秒回」。
2. **设备 adb shell 后台进程必死**：nohup/&/setsid（无此命令）皆随会话回收；唯一存活法＝长连 adb 会话或 init/Magisk 服务上下文。
3. `/data/local/hm-adapter`（自建目录）su 写入时通时断（SELinux），`/data/local/tmp`（adb 原生 shell 上下文）稳定——上机布局选后者。
4. Magisk 17.3：`/data/adb/service.d` 不存在且 su 无法创建；su 也写不了 `/sys/power/wake_lock`（EchoMuse 自己的锁在其 init 上下文持有，WiFi 不断）。
5. 嵌套 `su -c 'cd x && ./y'` 引号会被吃：一律绝对路径。


## G5-2 · 直占形态（2026-11-08）

`deploy/dot2d/direct/`＝替换 EchoMuse 的直占音频组件全部写入物（A/B 槽二进制＋监督脚本＋回滚备份＋mixer 快照）。
设备布局、切换/回滚配方、ioctl ABI 破解与实测记录见 `direct/README.md` 与 `docs/g5/direct-firmware-design-20261108.md`。
