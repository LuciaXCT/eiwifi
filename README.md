# eiwifi

**Android/Termux WiFi doctor.** It measures the radio link, the local network and the internet
path, then tells you which one is actually holding you back — with numbers, not vibes.

```
[1] LINK          band, channel, PHY link rate, signal, gateway
[2] NEIGHBOURHOOD every AP in range, band split, channel congestion
[3] LATENCY       router RTT, internet RTT, and latency while saturated
[4] SPEED         parallel-stream throughput (the way fast.com measures it)
[5] VERDICT       the bottleneck, and the exact fix
```

Built because "my WiFi is slow" is almost never a WiFi problem, and guessing wastes an evening.

---

## Install

In Termux:

```bash
pkg install git
git clone https://github.com/LuciaXCT/eiwifi.git
cd eiwifi
bash install.sh
```

Then, for full link data (band/channel/signal), install the **Termux:API app** from F-Droid and:

```bash
pkg install termux-api
```

Without it the tool still does latency and speed tests — it just can't see the radio state,
because Android does not expose it to unprivileged apps.

## Usage

```bash
eiwifi                 # full report
eiwifi link            # radio state only
eiwifi scan            # nearby APs + best channel
eiwifi ping [host]     # latency
eiwifi speed [n] [s]   # parallel download test, e.g. eiwifi speed 8 20
eiwifi check           # dependencies
```

Flags/hooks: `NO_COLOR=1` disables colour, `EIWIFI_IF=wlan0` picks the interface.

## Reading the output

| Field | What it means |
|---|---|
| **Band** | 2.4 GHz caps out around 100–150 Mbps no matter what you pay for. 5 GHz does not. |
| **Link rate (PHY)** | The radio's ceiling, **not** your speed. 300 Mbps PHY ≈ 150–180 Mbps real. |
| **Signal** | ≥ −50 excellent, ≥ −60 good, ≥ −70 fair, below that weak. |
| **Router RTT** | Under ~20 ms means the local WiFi hop is fine. |
| **Internet RTT** | High + jittery means a mobile/congested uplink. |
| **Loaded RTT** | If it explodes under load, that's bufferbloat — the reason everything feels sticky. |

The verdict compares throughput against the PHY rate:

- throughput **low, router RTT low, PHY high** → the **internet** is the bottleneck, not WiFi
- throughput **near the PHY ceiling** → the **radio** is the bottleneck, move to 5 GHz / get closer
- **broadband numbers up, band 2.4 GHz** → the band is capping you

## Honest limits

- **An unprivileged Android app cannot change radio settings.** Not this one, not any other.
  `cmd wifi`, `iw`, `settings put` and friends need root or the shell UID. This tool measures
  and prescribes; the router applies the cure.
- **You cannot beat your plan.** If the router answers in 3 ms and the link carries 300 Mbps
  while you pull 90, more WiFi tuning changes nothing.
- **Mobile/fixed-wireless uplinks move.** Time-of-day variance of 2x is normal. Same spot,
  same server, several runs.
- Both `ping` and `termux-wifi-*` are optional — the tool degrades instead of dying.

## The checklist that actually moves the needle

1. **Separate the 5 GHz SSID.** Band steering parks devices on 2.4 GHz. A distinct `_5G` network
   lets you pin the phone where you want it.
2. **5 GHz: 80 MHz width, WPA2/WPA3-AES, UNII-3 channels (149–165).** Full transmit power, no DFS waiting.
3. **2.4 GHz: 20 MHz on channel 1, 6 or 11.** 40 MHz on 2.4 GHz overlaps everything and usually
   makes things worse in a residential area.
3. **Developer options → turn OFF "Wi-Fi scan throttling".**
4. **Battery → "Unrestricted"** for the app you test with, and disable vendor "Adaptive Wi-Fi"/"Wi-Fi power saving".
5. **Fix bufferbloat at the router** (SQM/QoS at ~90% of measured speed). This is what makes a
   connection *feel* fast, and no phone setting can do it.

## Case study — the measurement that ended the argument

A laptop on a 300 Mbps plan, complaining about ~90 Mbps:

| | on 2.4 GHz | after moving to 5 GHz |
|---|---|---|
| Band / channel | 2.4 GHz, ch 11 | 5 GHz, ch 161 |
| PHY link rate | 216–300 Mbps | 325–780 Mbps |
| Router RTT | 3 ms | 5 ms |
| Throughput | 54–86 Mbps | 55–97 Mbps |
| Verdict | internet-limited | internet-limited |

The WiFi link got **2–3x faster** and the speed test barely moved. The bottleneck was the
uplink, which no amount of radio tuning touches. `eiwifi` reaches that verdict in one command
instead of an evening of guessing — and it would have told you the same thing on the first run.

## Testing

```bash
bash tests/test-eiwifi.sh
```

41 assertions covering JSON parsing (including the last-array-element trap), band/channel maths,
signal grading, degraded/vendor-specific fixtures, and all four verdict branches. Termux:API
commands are stubbed, so the suite runs on any Linux box; measurements are injected via
`EIWIFI_FAKE_*` env vars so results are deterministic.

## License

MIT
