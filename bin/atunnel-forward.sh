#!/bin/bash
# WSL aTrust 多端口透明转发
# 读 /etc/wsl-atrust-forward.conf, 为每个映射生成 iptables DNAT + socat 中转
# 支持增量操作: add/del 单条热更新, 无需重启全部
# 仅在 aTrust 网络环境 (eth7=aTrustVNIC 在线 且 eth4 有 IP) 下生效
# 作者: weiyufei

CONF=/etc/wsl-atrust-forward.conf
PIDFILE=/run/wsl-atrust-socats.pid
SOCAT_LOG=/var/log/wsl-atrust-socat.log

# 动态获取 eth4 IP (DHCP 变化自动适配)
get_local_ip() {
  ip -4 addr show eth4 2>/dev/null | awk '/inet /{gsub(/\/.*/,"",$2); print $2; exit}'
}

in_atrust_net() {
  ip link show eth7 2>/dev/null | grep -q "state UP" && [ -n "$(get_local_ip)" ]
}

add_rule() {
  local ip=$1 port=$2 lport=$3 local_ip=$(get_local_ip)
  /usr/sbin/iptables -t nat -C OUTPUT -d "$ip" -p tcp --dport "$port" -j DNAT --to-destination "${local_ip}:${lport}" 2>/dev/null || \
  /usr/sbin/iptables -t nat -A OUTPUT -d "$ip" -p tcp --dport "$port" -j DNAT --to-destination "${local_ip}:${lport}"
}

del_rule() {
  local ip=$1 port=$2 lport=$3 local_ip=$(get_local_ip)
  [ -n "$local_ip" ] && /usr/sbin/iptables -t nat -D OUTPUT -d "$ip" -p tcp --dport "$port" -j DNAT --to-destination "${local_ip}:${lport}" 2>/dev/null
}

add_one() {
  local ip=$1 port=$2 lport=$3
  [ -z "$(get_local_ip)" ] && { echo "eth4 无 IP, 跳过"; return 1; }
  add_rule "$ip" "$port" "$lport"
  [ -f "$PIDFILE" ] || : > "$PIDFILE"
  nohup /usr/bin/socat TCP-LISTEN:"${lport}",bind="$(get_local_ip)",reuseaddr,fork TCP:127.0.0.1:"${port}" >> "$SOCAT_LOG" 2>&1 &
  echo $! >> "$PIDFILE"
  echo "已热添加: $ip:$port -> 127.0.0.1:$port (socat $lport, pid $!)"
}

del_one() {
  local ip=$1 port=$2 lport=$3
  # 杀掉该映射对应的 socat (按监听端口匹配)
  pkill -f "socat TCP-LISTEN:${lport}," 2>/dev/null
  del_rule "$ip" "$port" "$lport"
  echo "已热删除: $ip:$port"
}

start_all() {
  : > "$PIDFILE"
  while read -r ip port lport; do
    [ -z "$ip" ] && continue
    case "$ip" in \#*) continue;; esac
    add_one "$ip" "$port" "$lport"
  done < "$CONF"
}

stop_all() {
  [ -f "$PIDFILE" ] && xargs -r kill < "$PIDFILE" 2>/dev/null
  rm -f "$PIDFILE"
  while read -r ip port lport; do
    [ -z "$ip" ] && continue
    case "$ip" in \#*) continue;; esac
    del_rule "$ip" "$port" "$lport"
  done < "$CONF"
}

case "$1" in
  start)
    if ! in_atrust_net; then
      echo "不在 aTrust 网络环境 (eth7 未在线或无 eth4 IP), 跳过"
      exit 0
    fi
    start_all
    wait
    ;;
  stop)
    stop_all
    ;;
  add)
    in_atrust_net || { echo "不在 aTrust 网络环境, 无法添加"; exit 1; }
    [ $# -eq 4 ] || { echo "用法: $0 add <目标IP> <目标端口> <socat端口>"; exit 1; }
    add_one "$2" "$3" "$4"
    ;;
  del)
    [ $# -eq 4 ] || { echo "用法: $0 del <目标IP> <目标端口> <socat端口>"; exit 1; }
    del_one "$2" "$3" "$4"
    ;;
  status)
    echo "LOCAL_IP: $(get_local_ip)"
    echo "eth7: $(ip link show eth7 2>/dev/null | grep -o 'state UP' || echo 'DOWN')"
    echo "--- iptables DNAT 规则 ---"
    /usr/sbin/iptables -t nat -S OUTPUT | grep 172.20
    echo "--- socat 进程 ---"
    ps aux | grep "socat TCP" | grep -v grep | awk '{print $2, $NF}' | head -10
    ;;
  *)
    echo "用法: $0 {start|stop|add|del|status}"
    exit 1
    ;;
esac
