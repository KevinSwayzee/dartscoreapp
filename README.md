# DartScore 🎯

LAN darts scoring app: Dart backend (shelf), plain HTML/JS tablet UI.
Games: **301 / 501**, double- or single-out checkout, best of **3 or 5 sets**,
1–4 players.

## Run (dev)

```bash
git clone https://github.com/KevinSwayzee/dartscoreapp.git
cd dartscoreapp
dart pub get
dart run bin/server.dart        # listens on 0.0.0.0:8080 (override: PORT=xxxx)
```

Open `http://<host>:8080` on any device in your network. Multiple tablets stay
in sync (state is scored against the server, which is authoritative).

**Idle timeout:** if nothing is scored/undone/reconfigured for 30 minutes, the
server discards the game and every tablet falls back to the config screen
(tablet *viewing* — the state polling — does not keep a game alive).
Override with `IDLE_TIMEOUT_MIN=<minutes>`.

## How to score

Keypad enters **one dart at a time**, press **OK**; a visit ends after
3 darts, on a bust, or on a checkout.

- **Segment toggle** cycles `S → D → T`: type the board number, so triple 20
  is `T` + `20`. It starts at `S` and resets to `S` after every throw.
  `D` + `25` = Bull (50).
- Values only reachable as a double (22, 26, 28, 32, 34, 38, 40, 50) are
  treated as doubles automatically (32 = D16, 50 = Bull).
- **Double out** toggle on the setup screen (on by default). Off = single-out:
  reaching 0 with any dart wins the set.
- **Bust**: double-out — below 0, landing on 1, or 0 without a double;
  single-out — only below 0. The whole visit is voided and the score returns
  to the visit start.
- **Undo** removes the last dart (works across busts, sets, even un-wins a match).
- Keyboard shortcuts (desktop): digits, Enter = OK, Backspace, `s`/`d`/`t` =
  segment, `u` = undo.

## Raspberry Pi deployment

1. Install the Dart SDK (64-bit Raspberry Pi OS):
   ```bash
   curl -O https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-arm64-release.zip
   sudo unzip dartsdk-linux-arm64-release.zip -d /opt     # → /opt/dart-sdk
   ```
   (32-bit OS: use `dartsdk-linux-armhf-release.zip` instead.)
2. Get the code onto the Pi:
   ```bash
   sudo git clone https://github.com/KevinSwayzee/dartscoreapp.git /opt/dartscore
   sudo chown -R pi:pi /opt/dartscore    # so the pi user can git pull later
   ```
   (No network/git on the Pi? `scp -r dartscoreapp pi@raspberrypi.local:/opt/dartscore`
   still works — just skip the `git pull` updates below.)
3. `cd /opt/dartscore && /opt/dart-sdk/bin/dart pub get`
4. Install the service:
   ```bash
   sudo cp deploy/dartscore.service /etc/systemd/system/
   sudo systemctl enable --now dartscore
   ```
5. Tablet browser: `http://raspberrypi.local:8080`

Later, after pushing a change: `cd /opt/dartscore && git pull &&
/opt/dart-sdk/bin/dart pub get && sudo systemctl restart dartscore`.

### Pretty names (http://dartboard.local, no port, multiple apps)

One nginx instance owns port 80 and routes by name; every app keeps its own
internal port. Needs a **stable Pi IP** (router DHCP reservation), since the
extra Avahi names announce a fixed address.

```bash
# 1) advertise the extra names
sudo cp deploy/avahi-hosts /etc/avahi/hosts    # EDIT the IPs/names first!
sudo systemctl restart avahi-daemon

# 2) nginx front door
sudo apt install -y nginx
sudo cp deploy/nginx-dartscore.conf /etc/nginx/sites-available/dartscore
sudo ln -s /etc/nginx/sites-available/dartscore /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Check from the Pi (the `Host:` header is what nginx routes on):

```bash
curl -s -H 'Host: dartboard.local' http://localhost/api/state
```

Then open `http://dartboard.local` on the tablet. For another app, add its
name to `/etc/avahi/hosts` and a matching `server` block in the nginx config,
and `dartboard.local` keeps working for DartScore — one machine, many names.

## Smart-home integration (placeholder)

The engine already emits events (`score180`, `checkout`, `setWon`, `matchWon`,
`visitCompleted`). `lib/src/smart_home.dart` contains the `SmartHomeService`
interface and a no-op implementation plus a commented Home Assistant sketch —
implement it and wire it up in `bin/server.dart`. Nothing else needs to change.

## Tests

```bash
dart test        # pure engine tests: scoring, bust, checkout, undo, sets
```
