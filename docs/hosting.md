# Host a server online

This guide puts a Project Ares server on a rented cloud machine so friends can
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
git clone https://github.com/czinabu/projectares.git
cd projectares
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

At the **Uplink** console in your home base, type the server's address into
**Join the server at this address** and join. Your friends do the same. Your
base's door remembers it and leads there from then on. Each of you lands in the
server's lobby, picks a loadout from the stash the server keeps for you, and
presses **Deploy online**.

The server saves every player's stash. A player is known by their name plus a
private key their game creates the first time, so each of you needs a
different name, and nobody else can use yours. The stashes are kept in a
Docker volume called `ares-data`, so updating or restarting the server does
not lose them.

Everyone must run the same version of the game as the server. If someone sees
"The server runs a different version of the game", they need to update.

## Everyday tasks

Log in with `ssh root@<address>` and `cd projectares` first.

| To | Run |
| --- | --- |
| Update to the latest code | `git pull && docker compose up -d --build` |
| See the log | `docker compose logs -f` |
| Restart the server | `docker compose restart` |
| Stop the server | `docker compose down` |
| Back up everyone's stash | `docker compose cp ares:/data/accounts ./accounts-backup` |
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
