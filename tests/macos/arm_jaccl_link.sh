#!/bin/sh
set -eu
# Use the run that staged this helper, independently of shell working directory.
trial=${0%/*}
case "$trial" in
  /private/tmp/fios-jaccl-model-*|/private/tmp/fios-moe-probe-*) ;;
  *) exit 1 ;;
esac
case "$(/bin/hostname -s)" in
  fios-edge-b) ;;
  *) exit 1 ;;
esac
test -d "$trial"
if [ -n "${SSH_CONNECTION:-}" ]; then
  set -- $SSH_CONNECTION
  case "$1" in
    *:*) family=-inet6 ;;
    *) family=-inet ;;
  esac
  interface=$(/sbin/route -n get "$family" "$1" | /usr/bin/awk '$1 == "interface:" {print $2}')
  test -n "$interface" && test "$interface" != en5 || exit 1
fi

printf '%s\n' 'Validating sudo on edge-b. Password characters are hidden.'
/usr/bin/sudo -v
/usr/bin/touch "$trial/link-armed"
printf '%s\n' 'Armed. This terminal can stay open while the paired test starts.'
while [ -d "$trial" ] && [ ! -f "$trial/link-ready" ]; do /bin/sleep 1; done
test -f "$trial/link-ready"
trap '/usr/bin/sudo -n /sbin/ifconfig en5 up' EXIT
trap 'exit 1' HUP INT TERM
/usr/bin/sudo -n /sbin/ifconfig en5 down
/bin/sleep 4
/usr/bin/sudo -n /sbin/ifconfig en5 up
trap - EXIT
printf '%s\n' 'Thunderbolt interface restored.'
