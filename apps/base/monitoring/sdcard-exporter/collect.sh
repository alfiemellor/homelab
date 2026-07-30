#!/bin/sh
# Exports MMC/SD card health metrics for the node-exporter textfile collector.
#
# SD cards expose no SMART data and no wear-levelling registers (unlike eMMC,
# which has life_time/pre_eol_info in EXT_CSD), so there is nothing to read that
# says "this card is 60% worn". The signals we can get are:
#
#   * the SDHCI host controller's error counters from debugfs - CRC and timeout
#     errors are the earliest hardware-level warning a card is going bad
#   * the card's manufacture date, which bounds its age
#   * cumulative bytes written, tracked in a state file because /proc/diskstats
#     resets on every reboot
#
# life_time/pre_eol_info are parsed when present so this keeps working if an
# eMMC-backed node (CM4, or a USB-boot Pi) joins the cluster.
set -u
umask 022

SYSFS=${SYSFS:-/host/sys}
PROCFS=${PROCFS:-/host/proc}
DEBUGFS=${DEBUGFS:-/host/debug}
OUTDIR=${OUTDIR:-/host/textfile}
INTERVAL=${INTERVAL:-60}

OUT="$OUTDIR/sdcard.prom"

# Reads a sysfs attribute, printing nothing when it is absent.
attr() {
  [ -r "$1" ] || return 0
  tr -d '\n' <"$1" 2>/dev/null
}

# Strips characters that would break Prometheus label quoting.
label() {
  printf '%s' "$1" | tr -d '"\\' | tr -d '\n'
}

# Converts 0x-prefixed hex to decimal, printing nothing if it does not parse.
hex2dec() {
  awk -v h="$1" 'BEGIN {
    sub(/^0[xX]/, "", h)
    if (h !~ /^[0-9a-fA-F]+$/) exit
    n = 0
    for (i = 1; i <= length(h); i++)
      n = n * 16 + index("0123456789abcdef", tolower(substr(h, i, 1))) - 1
    printf "%d", n
  }'
}

# Epoch seconds for the first of a MM/YYYY month (days-from-civil algorithm).
month_epoch() {
  printf '%s' "$1" | awk -F/ 'NF == 2 {
    m = $1 + 0; y = $2 + 0
    if (m < 1 || m > 12 || y < 1970) exit
    if (m <= 2) y -= 1
    era = int(y / 400)
    yoe = y - era * 400
    doy = int((153 * ((m + 9) % 12) + 2) / 5)
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    printf "%.0f", (era * 146097 + doe - 719468) * 86400
  }'
}

# Field 10 of /proc/diskstats is sectors written; the kernel always reports
# these in 512-byte units regardless of the device's real block size.
sectors_written() {
  awk -v d="$1" '$3 == d { print $10; exit }' "$PROCFS/diskstats"
}

# Accumulates lifetime bytes written across reboots. /proc/diskstats restarts
# from zero each boot, so a drop versus the previous reading means the node
# rebooted and the current value is the whole of this boot's writes.
track_written() {
  dev=$1
  cur=$2
  now=$3
  state="$OUTDIR/sdcard-$dev.state"

  cum=0
  prev=0
  since=$now
  if [ -r "$state" ]; then
    read -r cum prev since <"$state" 2>/dev/null || true
    case "$cum$prev$since" in
      *[!0-9]* | '') cum=0; prev=0; since=$now ;;
    esac
  fi

  cum=$(awk -v cum="$cum" -v prev="$prev" -v cur="$cur" 'BEGIN {
    if (cur >= prev) cum += cur - prev; else cum += cur
    printf "%.0f", cum
  }')

  printf '%s %s %s\n' "$cum" "$cur" "$since" >"$state.tmp" && mv -f "$state.tmp" "$state"
  printf '%s %s' "$cum" "$since"
}

emit_err_stats() {
  dev=$1
  host=$2
  f="$DEBUGFS/$host/err_stats"
  [ -r "$f" ] || return 0
  awk -v dev="$dev" -v host="$host" '/^#/ {
    value = $NF
    sub(/^#[ \t]*/, "")
    sub(/:.*$/, "")
    name = tolower($0)
    gsub(/[^a-z0-9]+/, "_", name)
    gsub(/^_+|_+$/, "", name)
    if (name == "" || value !~ /^[0-9]+$/) next
    printf "sdcard_mmc_errors_total{device=\"%s\",host=\"%s\",type=\"%s\"} %s\n", dev, host, name, value
  }' "$f"
}

collect() {
  now=$(date +%s)
  devices=0

  cat <<'EOF'
# HELP sdcard_info Static identity of the MMC/SD card backing this node.
# TYPE sdcard_info gauge
# HELP sdcard_capacity_bytes Raw capacity of the card as reported by the block layer.
# TYPE sdcard_capacity_bytes gauge
# HELP sdcard_manufacture_timestamp_seconds Card manufacture date (first of the month encoded in the CID).
# TYPE sdcard_manufacture_timestamp_seconds gauge
# HELP sdcard_health_registers_supported Whether the card exposes eMMC wear registers (life_time/pre_eol_info). Plain SD cards report 0 and can only be judged by error counters and age.
# TYPE sdcard_health_registers_supported gauge
# HELP sdcard_life_time_used_percent Upper bound of the estimated lifetime consumed, per eMMC estimate type. 110 means the vendor limit is exceeded.
# TYPE sdcard_life_time_used_percent gauge
# HELP sdcard_pre_eol_info eMMC pre-EOL state: 1 normal, 2 warning (80% of reserved blocks consumed), 3 urgent.
# TYPE sdcard_pre_eol_info gauge
# HELP sdcard_mmc_errors_total Cumulative host controller errors since boot, from the MMC debugfs error counters.
# TYPE sdcard_mmc_errors_total counter
# HELP sdcard_written_bytes_total Bytes written to the card, accumulated across reboots by this exporter.
# TYPE sdcard_written_bytes_total counter
# HELP sdcard_written_bytes_tracking_since_seconds When this exporter started accumulating writes for this card.
# TYPE sdcard_written_bytes_tracking_since_seconds gauge
EOF

  for devpath in "$SYSFS"/block/mmcblk*; do
    [ -d "$devpath" ] || continue
    dev=$(basename "$devpath")
    # boot0/boot1/rpmb are eMMC hardware partitions exposed as separate block
    # devices; they are not the card's main data area.
    case "$dev" in *boot* | *rpmb*) continue ;; esac
    devices=$((devices + 1))

    name=$(label "$(attr "$devpath/device/name")")
    type=$(label "$(attr "$devpath/device/type")")
    manfid=$(label "$(attr "$devpath/device/manfid")")
    oemid=$(label "$(attr "$devpath/device/oemid")")
    serial=$(label "$(attr "$devpath/device/serial")")
    fwrev=$(label "$(attr "$devpath/device/fwrev")")
    hwrev=$(label "$(attr "$devpath/device/hwrev")")
    made=$(label "$(attr "$devpath/device/date")")

    printf 'sdcard_info{device="%s",card_name="%s",card_type="%s",manfid="%s",oemid="%s",serial="%s",fwrev="%s",hwrev="%s",manufactured="%s"} 1\n' \
      "$dev" "$name" "$type" "$manfid" "$oemid" "$serial" "$fwrev" "$hwrev" "$made"

    size=$(attr "$devpath/size")
    case "${size:-}" in
      '' | *[!0-9]*) ;;
      *) printf 'sdcard_capacity_bytes{device="%s"} %s\n' "$dev" \
        "$(awk -v s="$size" 'BEGIN { printf "%.0f", s * 512 }')" ;;
    esac

    epoch=$(month_epoch "$made")
    [ -n "$epoch" ] && printf 'sdcard_manufacture_timestamp_seconds{device="%s"} %s\n' "$dev" "$epoch"

    lifetime=$(attr "$devpath/device/life_time")
    preeol=$(attr "$devpath/device/pre_eol_info")
    if [ -n "$lifetime" ] || [ -n "$preeol" ]; then
      printf 'sdcard_health_registers_supported{device="%s"} 1\n' "$dev"
    else
      printf 'sdcard_health_registers_supported{device="%s"} 0\n' "$dev"
    fi

    if [ -n "$lifetime" ]; then
      est=a
      for raw in $lifetime; do
        dec=$(hex2dec "$raw")
        [ -n "$dec" ] && printf 'sdcard_life_time_used_percent{device="%s",estimate="%s"} %s\n' \
          "$dev" "$est" "$((dec * 10))"
        [ "$est" = a ] && est=b || break
      done
    fi

    if [ -n "$preeol" ]; then
      dec=$(hex2dec "$preeol")
      [ -n "$dec" ] && printf 'sdcard_pre_eol_info{device="%s"} %s\n' "$dev" "$dec"
    fi

    host=$(readlink -f "$devpath/device" 2>/dev/null | sed -n 's|.*/mmc_host/\(mmc[0-9]*\)/.*|\1|p')
    [ -n "$host" ] && emit_err_stats "$dev" "$host"

    sectors=$(sectors_written "$dev")
    case "${sectors:-}" in
      '' | *[!0-9]*) ;;
      *)
        bytes=$(awk -v s="$sectors" 'BEGIN { printf "%.0f", s * 512 }')
        set -- $(track_written "$dev" "$bytes" "$now")
        printf 'sdcard_written_bytes_total{device="%s"} %s\n' "$dev" "$1"
        printf 'sdcard_written_bytes_tracking_since_seconds{device="%s"} %s\n' "$dev" "$2"
        ;;
    esac
  done

  cat <<EOF
# HELP sdcard_exporter_devices Number of MMC/SD cards found on this node.
# TYPE sdcard_exporter_devices gauge
sdcard_exporter_devices $devices
# HELP sdcard_exporter_last_run_timestamp_seconds When this exporter last wrote metrics.
# TYPE sdcard_exporter_last_run_timestamp_seconds gauge
sdcard_exporter_last_run_timestamp_seconds $now
EOF
}

[ -d "$OUTDIR" ] || mkdir -p "$OUTDIR"

while :; do
  # The textfile collector reads whole files, so swap it in atomically to avoid
  # node-exporter ever parsing a half-written set of metrics.
  if collect >"$OUT.tmp" 2>/dev/null; then
    mv -f "$OUT.tmp" "$OUT"
  else
    rm -f "$OUT.tmp"
    echo "sdcard-exporter: collection failed" >&2
  fi
  sleep "$INTERVAL"
done
