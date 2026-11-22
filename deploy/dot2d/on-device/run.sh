#!/system/bin/sh
# Retired. This launcher started the EchoMuse adapter and dialed a core at
# 192.168.1.20. That path is not the shipping firmware.
#
# Use deploy/dot2d/emos/start_server.sh with core 127.0.0.1:8932.
echo "retired: on-device EchoMuse adapter / LAN core 192.168.1.20 is not the shipping path" >&2
echo "use deploy/dot2d/emos/start_server.sh (127.0.0.1:8932)" >&2
exit 1
