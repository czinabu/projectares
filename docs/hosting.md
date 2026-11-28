# Host a server online

This guide puts a Verge server on a rented cloud machine so friends can
join from anywhere, even when your own computer is off. It takes about 30
minutes the first time and costs a few dollars a month. Everything here runs
from PowerShell on Windows; you do not need to install anything on your PC.

The server is the same one the game starts when you walk out of your base's
door, only running on its own with no window (`--server` mode).

## What you need

- The online play code merged into `main` (the pull request that adds
  `core/net/`). Before that, there is no server to run.
- A credit card or PayPal for the cloud provider.
- Windows 10 or 11. PowerShell already includes `ssh`.

## Why Hetzner

This guide uses [Hetzner Cloud](https://www.hetzner.com/cloud). It is one of
the cheapest reliable providers, its smallest machines are plenty for a few
players, it has data centers in Europe and the US, and it bills by the hour
with a monthly cap, so you can delete the machine whenever you like and stop
paying. Prices change, so check the order page; expect roughly $5 to $8 a month
for the size below.

Any other provider that gives you an Ubuntu machine with a public address works
the same way from step 3 on.

## 1. Make an SSH key on your PC

The key lets you log in to the server without a password. Open **PowerShell**
and run:

```powershell
ssh-keygen -t ed25519
```

Press Enter at every question. Then print the public half of the key and copy
the whole line it shows (it starts with `ssh-ed25519`):

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub
```

## 2. Rent the server

1. Sign up at Hetzner Cloud and create a project, for example `ares`.
2. In the project, open **Firewalls**, create a firewall named `ares`, and give
   it two inbound rules:
   - **TCP, port 22** (so you can log in)
   - **UDP, ports 24565-24569** (so players can join: the plaza is on 24565
     and each raid world on the ports after it)
   - **UDP, port 24575** (the arena, ten ports above the plaza)
3. Open **Servers** and click **Add Server**:
   - **Location**: the one closest to you and your friends.
   - **Image**: Ubuntu 24.04.
   - **Type**: shared vCPU, **x86 (Intel or AMD)**, the cheapest one with at
     least **2 GB of memory**. Do not pick an Arm (Ampere) type: the server is
     built for x86.
   - **SSH keys**: click **Add SSH key** and paste the line you copied.
   - **Firewalls**: tick `ares`.
   - Leave everything else as it is and click **Create & Buy now**.
4. When it is running, copy its **IPv4 address**, for example `203.0.113.25`.
   That is the address your friends will type.

## 3. Log in

In PowerShell, using your server's address:

```powershell
ssh root@203.0.113.25
```

Type `yes` the first time it asks about the fingerprint. You are now typing
commands on the server. Steps 4 to 6 all run there.

## 4. Install Docker

Docker builds and runs the server in a box with everything it needs.

```bash
apt-get update && apt-get upgrade -y
curl -fsSL https://get.docker.com | sh
```

## 5. Get the game and start the server

```bash
git clone https://github.com/czinabu/verge.git
cd verge
docker compose up -d --build
```

The first build downloads Godot and its export templates (about 1.3 GB) and
exports the game, so give it a few minutes. Later builds are much faster.

## 6. Check that it runs

```bash
docker compose logs -f
```

You should see `Server: running ashfront on port 24566` and
`Server: running plaza on port 24565`. Press **Ctrl+C** to
stop watching the log; the server keeps running. It also restarts by itself if
it crashes or the machine reboots.

Type `exit` to leave the server.

## 7. Join it

Open your phone (**P**), go to the **Servers** app, type the server's address
under **A friend's server** and press **Join**. Your friends do the same. Your
base's door remembers it and leads there from then on. Each of you lands in the
server's lobby, picks a loadout from the stash the server keeps for you, and
presses **Deploy online**.

The server saves every player's stash. A player is known by their name plus a
private key their game creates the first time, so each of you needs a
different name, and nobody else can use yours. The stashes are kept in a
Docker volume called `ares-data`, so updating or restarting the server does
not lose them. They live in one database, `accounts.sqlite`; a server that
still has the older one-file-per-player saves imports them into it the first
time it starts and renames each old file to `.json.imported`.

Everyone must run the same version of the game as the server. The server
checks the version before anyone gets in. A player whose game is older is
told so, and the phone's Servers app gets a **Get the update** button that
opens the latest build's download page. A player whose game is newer is told
the server needs updating: pull and rebuild it (see below).

Every connection is encrypted. The server makes its own certificate the
first time it starts and keeps it in the same volume
(`/data/accounts/server_identity`), so no domain name or paid certificate is
needed. Its short code is in the log: `docker compose logs ares | grep
certificate`. Each player's game remembers that certificate the first time it
joins. If it ever changes (the volume was wiped, or someone is pretending to
be your server), their phone's Servers app says **This server changed** and
shows the code it had and the one it shows now. Tell your friends the code
from the log so they can compare before they press **Trust it and join**.
Keep the volume, and the certificate stays the same.

## Everyday tasks

Log in with `ssh root@<address>` and `cd verge` first.

| To | Run |
| --- | --- |
| Update to the latest code | `git pull && docker compose up -d --build` |
| See the log | `docker compose logs -f` |
| Restart the server | `docker compose restart` |
| Stop the server | `docker compose down` |
| Copy everyone's stash to the machine | `docker compose stop && docker compose cp ares:/data/accounts ./accounts-backup && docker compose start` (stop first: the stashes are a live database) |
| Copy the server's own backups to the machine | `docker compose cp ares:/data/accounts_backups ./backups` |
| Wipe every stash and start over | `docker compose down -v` |
| Start it again | `docker compose up -d` |

To change the world, the bot count, or turn on squad spawns, edit the
`command:` line in `compose.yaml` (for example with `nano compose.yaml`) and run
`docker compose up -d`. The options are:

- `--world ashfront` or `--world frostline`
- `--bots 4` to override the world's bot count
- `--squad-spawn` to put all players at one spawn point
- `--arena-port 24575` to move the arena (it defaults to the raid port plus
  10), or `--no-arena` to run without one
- leave out `--world` to run every raid world, each on its own port
- `--no-plaza` to run one world alone on the port, with no social plaza
- `--port 24565` to change the first port (then change the `ports:` line and the
  firewall rule to match, and join with `address:port`)
- `--only ashfront` (or `plaza`, `arena`, any world) to run just that one in
  this program; see "Every world as its own program" below

## Every world as its own program

`compose.yaml` runs every world in one program, which is all a server for
friends needs. A busy server can instead run each world as a program of its
own: each then has a processor core to itself, so a crowded Ashfront does
not slow the plaza, and a world that crashes is started again without the
others noticing. This is how official servers will run. It needs a machine
with about as many cores as worlds (four or more).

The worlds then share one set of accounts through the account service,
which also keeps the clans, the phone's records, the market and the list of
which world runs where. Two ways to start it:

- **With Docker**, one container per world:

  ```
  echo "ARES_SERVICE_KEY=$(openssl rand -hex 32)" > .env
  docker compose -f compose.official.yaml up -d --build
  ```

  The ports are the same as before (plaza 24565, the worlds after it, the
  arena on 24575), so the firewall rules stay as they are.

- **Without Docker**, one command that starts the account service and every
  world and restarts any world that stops:

  ```
  ares_server --headless -- --server --cluster --port 24565 --accounts /data/accounts
  ```

  It takes `--world`, `--bots`, `--squad-spawn`, `--no-arena` and
  `--health-log` like the single program does.

Accounts made on a one-program server are not carried over by themselves:
the account service reads the same `accounts.sqlite`, so point its
`--accounts` at the old folder to keep them. A world on another machine
adds `--public-host <its address>` so the plaza can send players there, and
needs a private network to the account service (`--account-url`).

## Backups

The server backs up every account, clan and phone record by itself: once
when it starts and then every hour, into a dated folder under
`/data/accounts_backups` (beside `/data/accounts`, in the same volume). It
keeps the newest 48, about two days. Accounts live in one SQLite database,
`accounts.sqlite`, where every save is all or nothing, so a crash never
leaves half an account or half a trade; each backup holds a clean copy of it
taken while the server runs. An account that still cannot be read is never
replaced by a new account, and its player is asked to have the host restore
it.

To put a backup back, stop the server, copy the backup's files over the
accounts folder and start it again:

```
docker compose down
docker compose run --rm --entrypoint sh ares -c "ls /data/accounts_backups"
docker compose run --rm --entrypoint sh ares -c "rm -f /data/accounts/accounts.sqlite-wal /data/accounts/accounts.sqlite-shm && cp -r /data/accounts_backups/<folder>/. /data/accounts/"
docker compose up -d
```

The `rm` matters: the database's `-wal` and `-shm` files belong to the copy
being replaced and must not be kept beside the restored one. A backup puts
back every account at once; there is no one-player restore yet.

A volume lives on the one machine, so copy the backups off it now and then
(the `docker compose cp` lines above).

## Stop paying

Stopping the server (`docker compose down`) or powering off the machine does
not stop the bill; Hetzner still charges for a machine that exists. To stop
paying, delete the server in the Hetzner console. Setting it up again later
takes the same steps.

## If something goes wrong

- **Friends cannot connect, but the log says it is running.** Check that the
  Hetzner firewall has the **UDP** rule for ports 24565-24569 (TCP is not enough) and
  that it is attached to the server.
- **The build stops with "Killed" or runs out of memory.** The machine is too
  small. Rebuild it with a 2 GB or larger type.
- **"exec format error"**. The machine is Arm. Use an x86 type.
- **`ssh` asks for a password.** The SSH key was not added when the server was
  created. In the console, use **Rescue** or rebuild the server with the key.

## Build the server without Docker

The project has a **Linux Server** export preset (`export_presets.cfg`). With
Godot 4.7 and its export templates installed, this produces a single file that
runs the server on any x86 Linux machine:

```
godot --headless --path . --export-release "Linux Server" build/server/ares_server.x86_64
./build/server/ares_server.x86_64 --headless -- --server --world ashfront --port 24565
```

## The account service (official servers only)

A friends' server needs none of this: it keeps its own accounts, as above.

Official servers share one set of accounts, so a player has the same stash
in every world. Those accounts live in one extra program, the account
service, and each game server is pointed at it instead of keeping accounts
itself (`docs/DESIGN.md` section 14). Players never connect to the service;
only game servers do.

```
# The service: no world, no players, just the accounts (and the market board).
./ares_server --headless -- --account-service --port 24700 --accounts /data/accounts

# A game server that uses it. Give each server its own --server-id and keep
# it the same every time that server starts.
./ares_server --headless -- --server --world ashfront --port 24565 \
    --account-url ws://127.0.0.1:24700 --server-id ashfront-1 \
    --accounts /data/ashfront-1 --service-key /data/accounts/service_key
```

- **The key.** On its first start the service writes a random key to
  `service_key` in its accounts folder. Every game server must hold the same
  key: point `--service-key` at that file, or put the key in the
  `ARES_SERVICE_KEY` environment variable on both sides. Neither side ever
  sends the key itself. Anyone with the key can change any account, so treat
  it like a password.
- **Where it listens.** Only on its own computer unless started with
  `--bind "*"`. Players' sign-ins pass over this connection, so across
  machines keep it on a private network, or put a TLS proxy in front and use
  a `wss://` address.
- **`--accounts` on a game server** is then only its own folder for its
  certificate, clans and phone records. The accounts, their backups
  (`accounts_backups` beside the service's folder) and the market board are
  the service's.
- **If the service stops**, game servers keep running. Lives being played
  carry on; what they earn is kept and delivered when the service is back.
  Signing in, equipping and deploying wait until then. If a game server
  itself stops, the lives it was running are handed their gear back the next
  time it starts, as on a friends' server.

Clans and the phone's contacts and messages are still kept by each game
server for now; they move to the service with one program per world.

## Windows build for friends

The **Windows client build** workflow exports the "Windows Client" preset on
Godot 4.7 and zips it. It runs on every push to `main` and replaces the zip on
the rolling **latest** pre-release on GitHub, so the newest merge is always one
download away. The zip's name ends in the commit (`Verge-windows-<sha>`):
the host and every friend must have the same one. If someone sees "The server
runs a different version of the game", they download the latest zip again (and
a host on their own PC pulls and relaunches). For a milestone, run the workflow
by hand with **release** ticked to get a draft release you can name and publish.
