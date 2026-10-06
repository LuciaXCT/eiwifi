#!/usr/bin/env bash
# Test harness for eiwifi. Stubs the Termux:API commands so the whole thing runs
# on any Linux box, and injects measurements so results are deterministic.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../eiwifi"
STUB="$(mktemp -d)"
PASS=0; FAIL=0

cleanup() { rm -rf "$STUB"; }
trap cleanup EXIT

# ---------- stubs ----------
cat >"$STUB/termux-wifi-connectioninfo" <<'EOF'
#!/usr/bin/env bash
case "${EIWIFI_TEST_FIXTURE:-5g}" in
  5g)  echo '{"BSSID":"b8:d4:bc:91:52:00","SSID":"ZTE_875200","supplicant_state":"COMPLETED","rssi":-72,"link_speed_mbps":325,"frequency_mhz":5745,"ip":"192.168.0.42","mac_address":"aa:f6:f0:58:6f:3f","hidden_ssid":false,"network_id":0}' ;;
  24g) echo '{"BSSID":"b8:d4:bc:87:52:00","SSID":"ZTE_875200","rssi":-54,"link_speed_mbps":300,"frequency_mhz":2437,"ip":"192.168.0.8","hidden_ssid":false,"network_id":0}' ;;
  weak) echo '{"BSSID":"b8:d4:bc:91:52:00","SSID":"HiddenHome","rssi":-83,"link_speed_mbps":54,"frequency_mhz":5180,"ip":"192.168.0.99","hidden_ssid":true,"network_id":0}' ;;
  strong) echo '{"BSSID":"b8:d4:bc:91:52:00","SSID":"ZTE_875200","rssi":-45,"link_speed_mbps":866,"frequency_mhz":5805,"ip":"192.168.0.42","hidden_ssid":false,"network_id":0}' ;;
  nosignal) echo '{"BSSID":"b8:d4:bc:91:52:00","SSID":"ZTE_875200","supplicant_state":"COMPLETED"}' ;;
esac
EOF

cat >"$STUB/termux-wifi-scaninfo" <<'EOF'
#!/usr/bin/env bash
if [ "${EIWIFI_TEST_SCAN_FAIL:-0}" = 1 ]; then exit 0; fi
echo '[{"bssid":"b8:d4:bc:87:52:00","frequency_mhz":2437,"rssi":-54,"ssid":"ZTE_875200","timestamp":1},
{"bssid":"b8:d4:bc:91:52:00","frequency_mhz":5745,"rssi":-72,"ssid":"ZTE_875200","timestamp":1},
{"bssid":"aa:bb:cc:dd:ee:01","frequency_mhz":2412,"rssi":-80,"ssid":"Neighbour","timestamp":1},
{"bssid":"aa:bb:cc:dd:ee:02","frequency_mhz":5805,"rssi":-85,"ssid":"Neighbour_5G","timestamp":1}]'
EOF
chmod +x "$STUB"/*

export PATH="$STUB:$PATH"
export EIWIFI_FORCE_TERMUX=1

run() { "$SCRIPT" "$@" 2>&1; }

check() { # name expected actual
  if printf '%s' "$3" | grep -qF -- "$2"; then
    printf '  ok   %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  FAIL %s\n       expected to contain: %s\n       got: %s\n' "$1" "$2" "$(printf '%s' "$3" | head -c 400)"
    FAIL=$((FAIL+1))
  fi
}

check_re() { # name regex actual
  if printf '%s' "$3" | grep -qE -- "$2"; then
    printf '  ok   %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  FAIL %s\n       expected to match: %s\n       got: %s\n' "$1" "$2" "$(printf '%s' "$3" | head -c 400)"
    FAIL=$((FAIL+1))
  fi
}

check_not() { # name needle actual
  if printf '%s' "$3" | grep -qF -- "$2"; then
    printf '  FAIL %s\n       should NOT contain: %s\n' "$1" "$2"; FAIL=$((FAIL+1))
  else
    printf '  ok   %s\n' "$1"; PASS=$((PASS+1))
  fi
}

echo '== version / help =='
out="$(run version)";    check "version prints" "eiwifi 1.0.0" "$out"
out="$(run help)";       check "help lists commands" "report" "$out"; check "help mentions speed" "speed [n] [secs]" "$out"
out="$(run bogus 2>&1)"; check "unknown command exits 2" "unknown command" "$out"

echo '== check =='
out="$(run check)";      check "detects Termux" "Termux detected" "$out"
                         check "sees termux-api" "termux-api present" "$out"
                         check "sees curl" "curl present" "$out"

echo '== link: 5 GHz =='
out="$(EIWIFI_TEST_FIXTURE=5g run link)"
check "ssid parsed"            "ZTE_875200" "$out"
check "bssid with colons kept" "b8:d4:bc:91:52:00" "$out"
check "band is 5 GHz"          "5 GHz" "$out"
check "channel 149 from 5745"  "channel 149" "$out"
check "phy rate"               "325 Mbps" "$out"
check "rssi -72 is Weak"       "Weak" "$out"
check "gateway line"           "Gateway" "$out"

echo '== link: 2.4 GHz =='
out="$(EIWIFI_TEST_FIXTURE=24g run link)"
check "band is 2.4 GHz" "2.4 GHz" "$out"
check "channel 6 from 2437" "channel 6" "$out"
check "rssi -54 is Good" "Good" "$out"

echo '== link: weak signal + hidden ssid =='
out="$(EIWIFI_TEST_FIXTURE=weak run link)"
check "weak rssi"      "Weak" "$out"
check "hidden ssid ok" "HiddenHome" "$out"

echo '== link: missing fields degrade gracefully =='
out="$(EIWIFI_TEST_FIXTURE=nosignal run link)"
check "no phy -> unknown"  "unknown" "$out"

echo '== scan =='
out="$(run scan)"
check_re "counts 2.4 GHz"  '2\.4 GHz +2 AP\(s\)' "$out"
check_re "counts 5 GHz"    '5 GHz +2 AP\(s\)' "$out"
check "lists ch161"     "ch161" "$out"      # last AP in the array must not be dropped
check "lists ch6"       "ch6" "$out"
check "neighbour shown" "Neighbour" "$out"

echo '== scan with no data =='
out="$(EIWIFI_TEST_SCAN_FAIL=1 run scan)"
check "warns when scan empty" "No scan data" "$out"

echo '== verdict: 2.4 GHz, internet-limited =='
out="$(EIWIFI_TEST_FIXTURE=24g EIWIFI_FAKE_MBPS=90 EIWIFI_FAKE_GW_RTT=3 \
        EIWIFI_FAKE_INET_RTT=43 EIWIFI_FAKE_LOADED_RTT=230 EIWIFI_FAKE_HAS5G=2 \
        run report)"
check "flags 2.4 GHz band"        "You are on 2.4 GHz" "$out"
check "detects internet limit"    "The internet side is the bottleneck." "$out"
check "detects bufferbloat"       "Bufferbloat" "$out"
check "prescribes 5 GHz"          "Put this device on 5 GHz." "$out"
check "reports the number"        "RESULT mbps=90" "$out"

echo '== verdict: 2.4 GHz, wifi-limited (bad router rtt) =='
out="$(EIWIFI_TEST_FIXTURE=24g EIWIFI_FAKE_MBPS=60 EIWIFI_FAKE_GW_RTT=45 \
        EIWIFI_FAKE_INET_RTT=60 EIWIFI_FAKE_LOADED_RTT=90 EIWIFI_FAKE_HAS5G=0 \
        run report)"
check "blames local wifi path" "local WiFi path is struggling" "$out"
check "tells you 5 GHz is off" "No 5 GHz network is visible" "$out"

echo '== verdict: 5 GHz healthy link =='
out="$(EIWIFI_TEST_FIXTURE=5g EIWIFI_FAKE_MBPS=90 EIWIFI_FAKE_GW_RTT=5 \
        EIWIFI_FAKE_INET_RTT=40 EIWIFI_FAKE_LOADED_RTT=45 EIWIFI_FAKE_HAS5G=2 \
        run report)"
check_not "no 2.4 GHz nag"      "You are on 2.4 GHz" "$out"
check "still finds the limit"   "The internet side is the bottleneck." "$out"
check_not "no bufferbloat noise" "Bufferbloat" "$out"

echo '== verdict: link keeps up, no findings =='
out="$(EIWIFI_TEST_FIXTURE=strong EIWIFI_FAKE_MBPS=460 EIWIFI_FAKE_GW_RTT=3 \
        EIWIFI_FAKE_INET_RTT=25 EIWIFI_FAKE_LOADED_RTT=40 EIWIFI_FAKE_HAS5G=2 \
        run report)"
check "clean bill of health" "all look consistent" "$out"
check "strong signal not flagged" "Excellent" "$out"
check "channel 161 on 5 GHz" "channel 161" "$out"

echo '== tune (channel preset from the scan fixture) =='
out="$(run tune)"
# fixture APs: ch6 -54, ch1 -80 (2.4 GHz); ch149 -72, ch161 -85 (5 GHz)
check "2.4 GHz picks least-overlapped ch11" "use channel 11" "$out"
check "5 GHz picks the empty UNII-1 block"   "use channel 36" "$out"
check "shows the 80 MHz choice"              "80 MHz" "$out"
check "names the band blocks"                "UNII-3" "$out"
check "warns off DFS"                        "52-144" "$out"
check "tells you to split the SSID"          "OWN SSID" "$out"
check "honest about app limits"              "No app can change the radio" "$out"
check "points at watch"                      "eiwifi watch" "$out"

out="$(EIWIFI_TEST_SCAN_FAIL=1 run tune)"
check "tune degrades without a scan" "Needs a scan" "$out"

# unit-test the scoring functions against the real script source, minus the
# `main "$@"` line, so the channel maths is checked directly and not via output.
LIB="$STUB/eiwifi-lib"
sed '$d' "$SCRIPT" > "$LIB"
# shellcheck disable=SC1090
. "$LIB"

f24="$(printf 'a|b|2437|-54\nc|d|2412|-80\ne|f|2462|-84')"
check "score_24 ranks by weighted overlap" "11 16" "$(score_24 "$f24" | pick_min)"
check "score_24 scores ch6 highest"        "6 46"  "$(score_24 "$f24" | awk '$1==6')"

f5_clear="$(printf 'a|b|5745|-72\nc|d|5805|-85')"
f5_busy="$(printf 'a|b|5180|-40\nc|d|5745|-72')"
f5_dfs="$(printf 'a|b|5500|-40')"
f24_empty="$(printf 'a|b|0|0')"

# score_5 puts the weight in column 3, so pick_min must be told so
check "score_5 prefers the empty block" "36 48 0" "$(score_5 "$f5_clear" | pick_min 3)"
check "score_5 moves off a busy block" "149 165 28" "$(score_5 "$f5_busy" | pick_min 3)"
check "score_5 ignores DFS-band APs" "36 48 0" "$(score_5 "$f5_dfs" | pick_min 3)"
check "pick_min defaults to column 2" "11 16" "$(score_24 "$f24" | pick_min)"
check "unknown-band APs score nothing" "3" "$(score_24 "$f24_empty" | awk '$2 == 0' | wc -l | tr -d ' ')"

# 2437 -> ch6, 5180 -> ch36, 5745 -> ch149, 5805 -> ch161, 5500 -> ch100
check "channel maths 2437->6"   "6"   "$(freq_channel 2437)"
check "channel maths 5180->36"  "36"  "$(freq_channel 5180)"
check "channel maths 5745->149" "149" "$(freq_channel 5745)"
check "channel maths 5805->161" "161" "$(freq_channel 5805)"
check "band maths 5500->5 GHz"  "5 GHz" "$(freq_band 5500)"
check "band maths 5955->6 GHz"  "6 GHz" "$(freq_band 5955)"
check "signal grading -45"      "Excellent" "$(rssi_word -45)"
check "signal grading -55"      "Good"      "$(rssi_word -55)"
check "signal grading -65"      "Fair"      "$(rssi_word -65)"
check "signal grading -75"      "Weak"      "$(rssi_word -75)"

echo '== watch (live, 2 samples x 4s) =='
out="$(run watch 2 4 1)"; st=$?
if [ "$st" -eq 0 ]; then printf '  ok   watch exit status 0\n'; PASS=$((PASS+1))
else printf '  FAIL watch exit status %s\n' "$st"; FAIL=$((FAIL+1)); fi
check "watch prints samples"     "sample 2/2" "$out"
check "watch summarises"         "avg" "$out"
check "watch gives a verdict"    "Verdict:" "$out"

out="$(run watch 0 1 1)"
check "watch handles zero samples" "No samples completed" "$out"

echo '== speed (live, 3 streams x 5s) =='
out="$(run speed 3 5)"
check "speed returns a result line" "RESULT mbps=" "$out"
res_mbps="$(printf '%s' "$out" | sed -n 's/.*RESULT mbps=\([0-9.]*\).*/\1/p' | head -1)"
if awk -v m="${res_mbps:-0}" 'BEGIN{exit !(m > 0)}'; then
  printf '  ok   speed measured %s Mbps\n' "$res_mbps"; PASS=$((PASS+1))
else
  printf '  FAIL speed returned %s\n' "${res_mbps:-nothing}"; FAIL=$((FAIL+1))
fi

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
