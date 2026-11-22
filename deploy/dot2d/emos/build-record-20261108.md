# G6 · emOS nocache 候选构建记录（2026-11-08，dot2-d 本机专用）

**跨机复用禁止**：本镜像输入锁定 dot2-d（G090L91072732EXG）本机 p10 SHA
`fa5e512cbdf90a451fd16ca7edfeb6f52bf603e7976d3ece941c6e8f0dff64cf`。
任何其他设备（含客厅机）不得刷写本目录产物——其 p10 与本机不同。

## 产物

| 产物 | 字节 | SHA-256 |
|---|---:|---|
| emos-v0.10-hm.1-nocache-p16m.img（dd 写 p10 的完整垫盘镜像） | 16777216 | `4fa975187891337320abf62c37be3e4092b5c03f12791211e010471962138a0c` |
| emos-boot.img（未垫盘 OS 镜像，本地 build-staging） | 6932480 | `84e83eeaa2af644ffd579d3f2b9942ed2efede995b084a0a21244b59b46547df` |
| init-aarch64-static（ramdisk 内 PID1，同上独立存档） | 4065232 | `2dc1e8e27e4622a10ee8e3e0d5bf7f22b539fe37113afdc2b7b03d699411020b` |

版本标识（os-release，构建期钉入）：`emos-v0.10-hm.1-nocache`／BUILD_ID
`hm-nocache-20261108-01`。md5（未垫盘）：`dee7a1406b26b44551abb066ce40c954`。

## 输入与配方（复现路径）

1. **源码**：上游 `wilbowes/EchoMuse@6a7f6625ed3023a0d5a7a1990cef77a4a13081f1`
   （emos-v0.10）＋`echomuse-dot2-ref/patches/emos-v0.10/` 两 patch
   （0001 去 cache 裸写、0002 boot-trail 进 /run tmpfs）。
   patch 后 `emos/init/init.c` SHA-256
   `a00b09e689085ec534d45b907a77841cb5a58d6479c4d05f3fa169e7cef8fa4d`
   ——与 EMOS-CANDIDATE-20261104 金标逐字节一致（源码锚定通过）。
2. **编译器**：钉版 `ghcr.io/binozo/echogo@sha256:c9456551c639290b1cc3e1df891177beadb5d0d7621a5c2ec81079a276019147`
   （NDK 21.4.7075529，linux/amd64 经 Rosetta），`--pull=never --network=none`、
   源目录只读挂载、输出独立目录。显式
   `aarch64-linux-android21-clang -static -O2 -Wall`（三坑之二：默认 CC＝armv7＝死镜像）。
   init 较 RUI 同源构建差 32B（4,065,232 vs 4,065,264）＝DWARF 路径差异，
   源码 SHA 已锚定，不构成偏差。
3. **构建输入**：本机 p10 16MiB 备份（`device-backups/dot2d-20261108/boot_a_x.img`，
   SHA=fa5e512c…，与 11-04 NAS 权威集逐字节一致）。header 声明 8,237,056 字节
   （kernel 5,792,865＋ramdisk 2,439,287＋second 0），尾部 8,540,160 字节
   逐字节验零后裁出 header-sized 输入
   `8c36e1b66da9d19475c5fabf567b13ad120d68a28bf4067617c2264fd9466cf2`。
4. **官方 packer**：上游 `controller/em_emos_build.py::build_emos_image`
   （unmodified），`system_part=13`、`sbin={"em-wifi": emos/device/em-wifi}`
   （FireOS5 官方 helper，15,827B）。cmdline 追加 ramoops 块＋
   `emos.system=/dev/block/mmcblk0p13`；kernel load addr `0x40080000`（引用自带）。

## 离线核验（全过，2026-11-08）

| 项 | 结果 |
|---|---|
| 参考内核 arch 判定 | arm64（AArch64 init 正确） |
| strict roundtrip（ignore_id，装机门） | PASS |
| 完整 roundtrip 含 image id | PASS（本机 p10 的 id 本身可复现） |
| init ELF | 64-bit LSB、EM_AARCH64、ET_EXEC（静态）、无解释器 |
| 内核区（MTK header+zImage+DTB）与 p10 逐字节一致 | True |
| Android image id 重算 vs 存储 | 一致 |
| ramdisk 内容 | 6 挂载点＋os-release（hm 版本串）＋init＋sbin/em-wifi（#!/system/bin/sh） |
| 自反 roundtrip（emOS 镜像可原地重建） | PASS |
| 16MiB 垫盘尾部 | 全零 |

## 刷写与回滚（与一页纸 §1 演练同路径）

- 刷：TWRP 内 `dd if=…p16m.img of=/dev/block/mmcblk0p10`＋读回校验
  `4fa97518…`，重启即 emOS。
- 回滚：TWRP 内 `dd if=boot_a_x.img of=/dev/block/mmcblk0p10`（0.8s，
  已演练）；物理兜底门＝Mute 键断电按住上电 5s（装前必须本机实测，见
  docs/g6 记录）。
- 本镜像不含 Go 固件、凭证或设备配置；ramdisk 仅 init＋em-wifi＋挂载点。

## 2026-11-14：uart0-off 镜像（**不上机，保留为反面证据**）

M8b 门禁 1（去调试串口 console）的一次尝试。工具＝`tools/emos_uart_off.py`。
原理与全部证据见主仓 [docs/d/m8b-image-20261114.md](../../../home%20mate%20b/docs/d/m8b-image-20261114.md)，
摘要：

- `console=ttyMT0/ttyS0` 来自 **LK（p3/p5）**；本目录镜像的 boot header 里没有 console。
- p10 的 DTB 有三份，各含 `soc/uart0@11002000 status="okay"`；uart1–3 为 `disable` 且从不注册 console。
- 本工具把三处的 `okay` 原地改成同长度的 `off`，用官方 packer 重打包（重算 image id）：
  与 `emos-v0.10-hm.1-nocache-p16m.img` 相比**只差 29 字节**（3×3 status ＋ 20 字节 id）。
- 产物 `emos-v0.10-hm.2-uartoff-DOES-NOT-BOOT-p16m.img`（md5 `e79eb969450911b995dc3f1f2ad5e362`）
  写入 p10 并读回校验后，**设备未进系统**（HTTP 无响应、USB 串口不回来）。
- 回滚：用户按物理兜底门（Mute 按住 ~30 s → 白灯 → TWRP）→ adb 推回原镜像 → `dd` 写 p10
  → 读回 `8b9004f8d24ec5127bc5f6675f6672f7` → `adb reboot` → 恢复正常（约 2 分钟）。
- **失败原因：未证明；「灯圈在转」不等于 init 起来了。** 本仓 `emos/init/init.c:9-11` 写明灯环是
  **内核 is31fl3236 驱动的 `boot_animation`** 画的，直到 userspace 清掉它（「reports nothing about our
  progress」）；init 接管后刻意画同一个动画（`init.c:104-112`）。init 的终端是 **`/dev/ttyGS0`**（`init.c:48`），
  USB gadget 是**第 8 阶段**（`init.c:2647`）——失败那次 ttyGS0 从未出现，所以 **init 没走到第 8 阶段**。
  最可能的读法是内核侧失败（`console=ttyMT0` 指向被禁用节点 → panic，而 panic 没有 console 可打，静默挂住）；
  但没有内核日志，仍未证明。细节与「一个观察就能分辨」的那条（灯圈是一直均匀转，还是停住/变红）见主仓文档 §4。
  **路线 C（用户 2026-11-14）**：不重试、不改 LK，门禁 1 记为未达成；若要重启，前提＝先演练 MTK 下载模式恢复
  ＋只改 LK cmdline、DTB 的 uart0 保持 okay。

**不要刷这个 .img。** 保留它是为了让"只重算 image id、不改字节"的对照实验能直接复用同一份产物。
原始镜像 `emos-v0.10-hm.1-nocache-p16m.img` 仍是 p10 的权威副本（与设备逐字节一致，2026-11-14 复核）。
