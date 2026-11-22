# 固件槽回滚（不再进入 EchoMuse）

监督器在本仓库里有两份，逻辑相同：

- `deploy/dot2d/emos/start_server.sh`（现役 emOS 脚本，核心 `127.0.0.1:8932`）
- `deploy/dot2d/direct/start_server.sh`（更早的 FireOS 直占脚本）

决策在 `slot_decision.sh`，两份脚本都 source 它。新槽连续快退达到上限后，切到另一个固件槽（`audio_a` ↔ `audio_b`）。那个槽也烧完预算后，停在当前槽，写一行 `not starting EchoMuse`，并在灯节点可写时把 12 灯画成错误红。不会 `exec` `start_server.echomuse.sh`。

仓库里没有别的 init/监督脚本再跳进 EchoMuse。设备上的 init 服务名仍可能叫 `echomuse`，它执行的是 `/data/local/bin/start_server.sh`，名字是历史遗留。

## 本机演练（不需要音箱）

```bash
sh deploy/dot2d/emos/slot_decision_test.sh
```

断言：`audio_b` 第一轮耗尽 → `swap audio_a`；再耗尽 → `stay-error audio_a`；两份 `start_server.sh` 都不再 `exec` EchoMuse。

## 上机时要手工做的（本 PR 不会连设备）

1. 把新的 `start_server.sh` 和同目录的 `slot_decision.sh` 装到 `/data/local/bin/`（init 实际跑的就是这一份，不是仓库路径）。只更新脚本、不更新的话，设备上的旧脚本仍会在两轮失败后进入 EchoMuse。
2. 不要在这一步删除设备上的 EchoMuse 三件套（`/data/local/bin/server_a`、`server_b`、`start_server.echomuse.sh` 等）。新脚本不再调用它们。删除是另一次上机操作。

上机对照（可选）：把 `audio_b` 换成一个立即 `exit 1` 的脚本，`current` 指向它，重启监督器。日志应出现 `slot rollback ... -> audio_a`，进程应是 `audio_a` 里的固件，而不是 `start_server.echomuse.sh`。两槽都立即退出时，日志应出现 `staying on` 和 `not starting EchoMuse`。
