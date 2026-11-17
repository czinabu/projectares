extends RefCounted
## Encrypted connections (DESIGN.md section 14): ENet's DTLS, with each
## server's own certificate remembered by the game the first time it joins
## (trust on first use, as ssh does), so no domain or paid certificate is
## needed.
##
## Server side: `identity(dir)` makes a key and a self-signed certificate on
## the first start and keeps them in `dir` (beside the accounts, so a Docker
## volume keeps them), shared by every session in the process.
##
## Client side: `attempts_for(host)` lists how `NetSession.join` tries to
## connect, in order:
## - "official": a server in `OFFICIAL_HOSTS` with a real certificate, checked
##   against the system's authorities and its host name. Never remembered and
##   never warned about: it either checks out or the join fails.
## - "pinned": a server this game has met before, checked against the
##   certificate it showed then. A different one fails the handshake.
## - "first": a server not met before (or this computer's own, `is_loopback`):
##   encrypted but not checked. Its certificate comes back in the sign-in's
##   answer and is remembered once it lets you in.
## - "probe": after "pinned" failed, an unchecked connection that sends no
##   secret, only to fetch the certificate the server shows now. A different
##   one is "this server changed", shown on the phone's Servers app.
## - "plain": an unencrypted connection that sends only the version, so a
##   server from before encryption can say it is out of date.
##
## Load with `const ServerTrust := preload("res://core/net/server_trust.gd")`.

## Hosts of official servers (none yet). They use real certificates.
const OFFICIAL_HOSTS: Array[String] = []
## The name every server's own certificate is made out to, and checked against.
const COMMON_NAME := "Project Ares server"
const KEY_FILE := "server.key"
const CERT_FILE := "server.crt"
## How long a server's own certificate lasts.
const CERT_YEARS := 20

## Where this game keeps the certificates of servers it has met: one
## ConfigFile, section "servers", host -> certificate (PEM).
static var known_path := "user://known_servers.cfg"
## This computer's own servers are encrypted but never pinned: nobody can
## stand between a game and a server on the same machine, and a dev server
## and a normal one keep different certificates. Tests turn it off.
static var trust_loopback := true

static var _identities := {} # dir -> [CryptoKey, X509Certificate]


## Server: this server's key and certificate, made and saved in `dir` on the
## first start. With `persist` false they are made in memory only.
static func identity(dir: String, persist := true) -> Array:
	if _identities.has(dir):
		return _identities[dir]
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	var key_path := dir.path_join(KEY_FILE)
	var cert_path := dir.path_join(CERT_FILE)
	if persist and FileAccess.file_exists(key_path) and FileAccess.file_exists(cert_path) \
			and key.load(key_path) == OK and cert.load(cert_path) == OK:
		print("Server: certificate %s" % fingerprint(pem_of(cert)))
		_identities[dir] = [key, cert]
		return _identities[dir]
	var crypto := Crypto.new()
	key = crypto.generate_rsa(2048)
	var now := Time.get_datetime_dict_from_system(true)
	var from := "%04d0101000000" % (int(now.year) - 1)
	var to := "%04d0101000000" % (int(now.year) + CERT_YEARS)
	cert = crypto.generate_self_signed_certificate(key, "CN=%s,O=Project Ares,C=US" % COMMON_NAME, from, to)
	if persist:
		DirAccess.make_dir_recursive_absolute(dir)
		if key.save(key_path) != OK or cert.save(cert_path) != OK:
			push_warning("ServerTrust: could not save the server's certificate in %s" % dir)
		else:
			print("Server: made a new certificate %s" % fingerprint(pem_of(cert)))
	_identities[dir] = [key, cert]
	return _identities[dir]


## A certificate as PEM text. Written out and read back, since
## `save_to_string` ends its text with a NUL the engine complains about.
static func pem_of(cert: X509Certificate) -> String:
	var path := OS.get_temp_dir().path_join("ares_cert_%d_%d.crt" % [OS.get_process_id(), randi()])
	if cert.save(path) != OK:
		return ""
	var pem := FileAccess.get_file_as_string(path).strip_edges() + "\n"
	DirAccess.remove_absolute(path)
	return pem


## Server: the DTLS setup for this server's identity.
static func server_options(dir: String, persist := true) -> TLSOptions:
	var pair := identity(dir, persist)
	return TLSOptions.server(pair[0], pair[1])


## Client: the connection modes `NetSession.join` tries for `host`, in order.
static func attempts_for(host: String) -> Array[String]:
	if host in OFFICIAL_HOSTS:
		return ["official"]
	if trust_loopback and is_loopback(host):
		return ["first"]
	if known(host) != "":
		return ["pinned", "probe", "plain"]
	return ["first", "plain"]


## Client: sets `peer` (made by `create_client`, not yet polled) up for
## `mode`. "plain" leaves it unencrypted.
static func setup_client(peer: ENetMultiplayerPeer, host: String, mode: String) -> Error:
	match mode:
		"official":
			return peer.host.dtls_client_setup(host, TLSOptions.client())
		"pinned":
			var cert := X509Certificate.new()
			if cert.load_from_string(known(host)) != OK:
				return ERR_INVALID_DATA
			return peer.host.dtls_client_setup(COMMON_NAME, TLSOptions.client(cert))
		"first", "probe":
			return peer.host.dtls_client_setup(host, TLSOptions.client_unsafe())
	return OK


## Whether `host` is this computer.
static func is_loopback(host: String) -> bool:
	return host == "localhost" or host == "::1" or host.begins_with("127.")


## The certificate remembered for `host` (PEM), or "".
static func known(host: String) -> String:
	var file := ConfigFile.new()
	if file.load(known_path) != OK:
		return ""
	return str(file.get_value("servers", host, ""))


## Remembers `pem` as the certificate of `host` from now on.
static func remember(host: String, pem: String) -> void:
	if host == "" or pem == "" or host in OFFICIAL_HOSTS:
		return
	var file := ConfigFile.new()
	file.load(known_path)
	if str(file.get_value("servers", host, "")) == pem:
		return
	file.set_value("servers", host, pem)
	file.save(known_path)


## Forgets the certificate of `host`.
static func forget(host: String) -> void:
	var file := ConfigFile.new()
	if file.load(known_path) != OK or not file.has_section_key("servers", host):
		return
	file.erase_section_key("servers", host)
	file.save(known_path)


## A short fingerprint of a certificate for people to compare: the first 16
## hex digits of its SHA-256, in groups of four.
static func fingerprint(pem: String) -> String:
	var cert := X509Certificate.new()
	if pem == "" or cert.load_from_string(pem) != OK:
		return "?"
	var der := Marshalls.base64_to_raw("".join(Array(pem.split("\n")).filter(
			func(line: String) -> bool: return line != "" and not line.begins_with("-----"))))
	if der.is_empty():
		return "?"
	var hex := _sha256(der)
	var groups: PackedStringArray = []
	for i in 4:
		groups.append(hex.substr(i * 4, 4).to_upper())
	return " ".join(groups)


static func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
