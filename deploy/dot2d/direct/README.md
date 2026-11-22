# G5-2 直占形态 · dot2-d 写入物存档（2026-11-08）

本目录逐字节存档本轮写入 dot2-d（serial `G090L91072732EXG`）的全部文件与取证快照。
设备布局与操作配方见下；设计文档 `docs/g5/direct-firmware-design-20261108.md`。

## 设备侧布局（终态）

| 设备路径 | 内容 | 本目录存档 |
|---|---|---|
| `/data/local/bin/start_server.sh` | **我方监督脚本**（init 服务 `echomuse` 槽位执行；A/B 槽监督＋快退换槽＋双轮败→EchoMuse 回退） | `start_server.sh`（源）＝`start_server.sh.deployed`（设备实测字节） |
| `/data/local/bin/start_server.echomuse.sh` | **原版 EchoMuse 脚本备份＝回滚通道**（用户要求保留至新形态稳定） | `start_server.echomuse.sh.device-backup`＋`start_server.sh.echomuse-original`（G2 期拉取） |
| `/data/local/tmp/hm-direct/audio_a`、`audio_b` | 固件 A/B 槽（armv7 musl 静态，SHA256 见 SHA256SUMS） | `gateway-armv7-musl` |
| `/data/local/tmp/hm-direct/current` | → audio_a 符号链接 | — |
| `/data/local/tmp/hm-direct/state.json` | 设备音量持久化（软件增益律） | `state.json.sample` |
| `/data/local/tmp/hm-direct/supervisor.log` | 监督决策日志（64KB 帽） | — |
| `/tmp/hm-direct.log` | 固件 chatty 日志（RAM，5MB 帽） | — |

自动失败路径不再进入 EchoMuse。监督脚本在新槽快退耗尽后切回另一固件槽；两槽都失败则停在当前槽、写错误灯并打日志。下面若仍出现把 `start_server.echomuse.sh` 拷回 `start_server.sh` 的旧配方，那是人工回退历史，不是监督器行为；本变更不在设备上删除 EchoMuse 文件。

## 部署/切换/回滚配方

```bash
S=G090L91072732EXG
# 部署二进制（shell 上下文直推，勿用 su 建目录——SELinux 上下文错配）
adb -s $S push gateway-armv7-musl /data/local/tmp/hm-direct/audio_a
adb -s $S push gateway-armv7-musl /data/local/tmp/hm-direct/audio_b
adb -s $S shell 'chmod 755 /data/local/tmp/hm-direct/audio_a /data/local/tmp/hm-direct/audio_b'
# 切换到直占（init 槽位换脚本）
adb -s $S push start_server.sh /data/local/tmp/s.sh
adb -s $S shell "su -c 'cp /data/local/tmp/s.sh /data/local/bin/start_server.sh; chmod 755 /data/local/bin/start_server.sh; rm /data/local/tmp/s.sh; stop echomuse; start echomuse'"
# 不要把 start_server.echomuse.sh 拷回 start_server.sh。
# 失败时的自动路径是固件 A/B 槽回滚，见 ../emos/ROLLBACK.md。
```

## 实测记录（2026-11-08）

- **ioctl ABI 破解**（详见设计文档 §5）：厂商内核 hw_params＝604/608 字节（任务位宽相关）、
  布局按系统 libtinyalsa 解码、**必须 init→HW_REFINE→钉值→HW_PARAMS**、S24_3LE＝bit32（采集侧枚举移位）、
  generic ioctl 编码、被占 PCM open 阻塞而非 EBUSY、**原生 64 位路径对 D24c 不可用**（系统 tinycap 同败）→固件定 armv7。
- **上机回归全绿**：mic 流 12.9 chunk/s（80ms 节拍）＋电平校准（`>>4` 增益＝G4 基线 −50dB）、
  唤醒自回环 **9/9＋0 误唤醒**（优于共存形态 5/6）、TTS 探针 device_confirmed＋mic 自听 +19~26dB＝可听、
  LED 全环 speaking 青（006e96×12）/回暗、音量软件增益 0.25 vs 0.9 mic 电平差 18dB＋持久化。
- **开机自启**：init `echomuse` 槽位（/data 脚本，零 Magisk 依赖）——重启单次拉起（up=5s）；
  wake_lock "hm-direct" 在 init 上下文持有（G4 的 su 写入障碍就此清除）。
- **回滚演练通过**：恢复原版脚本→重启→EchoMuse server 回归并持有 pcm24c（owner 可查）。
- **监督降级链**：固件快退×3→换槽→再×3→exec 原版 EchoMuse 脚本（自动回共存形态）。
