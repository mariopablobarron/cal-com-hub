#!/usr/bin/env python3
"""Recrear cal-web con labels Traefik añadidas (Coolify v3 las strip del yml)."""
import json
import shlex
import subprocess

CONTAINER = "cmpaiat5n0004qfa4r6m8l8rl-cal-web"
IMAGE = "calcom/cal.com:v6.2.0"
FQDN = "cal.hubstartidea.es"

# Leer snapshot del container actual para preservar envs
with open("/tmp/cal-web-snapshot.json") as f:
    d = json.load(f)[0]

envs = [e for e in d["Config"]["Env"] if "=" in e]
coolify_labels = {
    k: v for k, v in d["Config"]["Labels"].items()
    if k.startswith("coolify.") or k.startswith("com.docker.compose.")
}

traefik_labels = {
    "traefik.enable": "true",
    "traefik.docker.network": "coolify",
    "traefik.http.routers.cal-web.rule": f"Host(`{FQDN}`)",
    "traefik.http.routers.cal-web.entrypoints": "websecure",
    "traefik.http.routers.cal-web.tls": "true",
    "traefik.http.routers.cal-web.tls.certresolver": "letsencrypt",
    "traefik.http.routers.cal-web.service": "cal-web",
    "traefik.http.services.cal-web.loadbalancer.server.port": "3000",
    "traefik.http.middlewares.cal-web-redirect.redirectscheme.scheme": "https",
    "traefik.http.middlewares.cal-web-redirect.redirectscheme.permanent": "true",
    "traefik.http.routers.cal-web-http.rule": f"Host(`{FQDN}`)",
    "traefik.http.routers.cal-web-http.entrypoints": "web",
    "traefik.http.routers.cal-web-http.middlewares": "cal-web-redirect",
}

all_labels = {**coolify_labels, **traefik_labels}

# Stop + remove existing
subprocess.run(["docker", "stop", CONTAINER], check=False)
subprocess.run(["docker", "rm", CONTAINER], check=False)

# Build docker run command
args = [
    "docker", "run", "-d",
    "--name", CONTAINER,
    "--network", "coolify",
    "--restart", "unless-stopped",
    "--health-cmd", "wget --quiet --tries=1 --spider http://localhost:3000/",
    "--health-interval", "30s",
    "--health-timeout", "10s",
    "--health-retries", "5",
    "--health-start-period", "120s",
]
for e in envs:
    args.extend(["-e", e])
for k, v in all_labels.items():
    args.extend(["-l", f"{k}={v}"])
args.append(IMAGE)

print("Running:", " ".join(shlex.quote(a) for a in args[:6]) + " ... (full cmd hidden)")
result = subprocess.run(args, capture_output=True, text=True)
print("STDOUT:", result.stdout.strip())
print("STDERR:", result.stderr.strip())
print("CODE:", result.returncode)
