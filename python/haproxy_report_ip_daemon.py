#!/usr/bin/env python3
# Author  : Lars Eissink
# GitHub  : github.com/larse99
# Website : https://larrs.nl
#
# Automatically reports malicious IPs to AbuseIPDB based on HAProxy log
# activity, configurable rules, and AbuseIPDB threat scores.
#
# Key features:
#   - Whitelist: ensures trusted and private IP ranges are never reported.
#   - Cache: prevents the same IP from being reported more than once per day.
#   - Scan mode (--scan): processes the full log file retroactively instead
#     of tailing it in real time.
#   - Requires 'ipcheck' to be installed.
#
# Systemd unit file - for live tailing and reporting malicious IPs
#
# [Unit]
# Description=IP Reporter Daemon
# After=network.target
#
# [Service]
# ExecStart=/usr/bin/python3 /path/to/script_directory/haproxy_report_ip_daemon.py
# Restart=on-failure
# RestartSec=5
# User=root
# StandardOutput=journal
# StandardError=journal
#
# [Install]
# WantedBy=multi-user.target

import argparse
import ipaddress
import subprocess
import time
import json
import os
from datetime import datetime
from threading import Thread
from queue import Queue

# --- CLASSES ---
# Cache (persistent, TTL)
class IPCache:
    def __init__(self, file="/var/lib/ipreporter_cache.json", ttl=86400):
        self.file = file
        self.ttl = ttl
        self.cache = {}
        self._load()

    def _load(self):
        if os.path.exists(self.file):
            try:
                with open(self.file) as f:
                    self.cache = json.load(f)
            except Exception:
                self.cache = {}

    def _save(self):
        tmp_file = self.file + ".tmp"
        with open(tmp_file, "w") as f:
            json.dump(self.cache, f)
        os.replace(tmp_file, self.file)

    def seen_recently(self, ip):
        now = time.time()

        if ip in self.cache:
            if now - self.cache[ip] < self.ttl:
                return True

        self.cache[ip] = now
        self._save()
        return False


# Reporter (async worker)
class IPReporter:
    def __init__(self, log_file, reason, protected_ips):
        self.log_file = log_file
        self.reason = reason
        self.protected_networks = self._parse_protected_ips(protected_ips)

        self.queue = Queue()
        self.worker = Thread(target=self._worker, daemon=True)
        self.worker.start()

    def _parse_protected_ips(self, protected_ips):
        networks = []
        for net in protected_ips:
            try:
                if "/" in net:
                    networks.append(ipaddress.ip_network(net, strict=False))
                else:
                    networks.append(ipaddress.ip_address(net))
            except ValueError:
                continue
        return networks

    def log(self, msg):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"{timestamp} {msg}"
        print(line)
        with open(self.log_file, "a") as f:
            f.write(line + "\n")

    def is_protected(self, ip_str):
        ip = ipaddress.ip_address(ip_str)
        for net in self.protected_networks:
            if isinstance(net, (ipaddress.IPv4Network, ipaddress.IPv6Network)):
                if ip in net:
                    return True
            else:
                if ip == net:
                    return True
        return False

    def report_ip(self, ip):
        self.queue.put(ip)

    def get_abuse_score(self, ip):
        try:
            result = subprocess.run(
                ["ipcheck", "-s", ip],
                capture_output=True,
                text=True,
            )
            return int(result.stdout.strip())
        except (ValueError, Exception) as e:
            self.log(f"Error fetching abuse score for {ip}: {e}")
            return None

    def _worker(self):
        while True:
            ip = self.queue.get()
            try:
                subprocess.run(
                    ["ipcheck", "-r", "-c", "14,15", "-m", self.reason, "-i", ip],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                self.log(f"Reported {ip}")
            except Exception as e:
                self.log(f"Error reporting {ip}: {e}")
            finally:
                self.queue.task_done()


# HAProxy log follower
class HAProxyLogParser:
    def __init__(self, logfile="/var/log/haproxy.log"):
        self.logfile = logfile

    def follow(self):
        f = open(self.logfile)
        f.seek(0, 2)  # jump to end of file
        current_ino = os.fstat(f.fileno()).st_ino

        while True:
            line = f.readline()
            if line:
                yield line
                continue

            time.sleep(0.2)

            # Detect log rotation: reopen the file if its inode changed
            try:
                new_ino = os.stat(self.logfile).st_ino
            except FileNotFoundError:
                continue

            if new_ino != current_ino:
                f.close()
                f = open(self.logfile)
                current_ino = new_ino

    def read_all(self):
        with open(self.logfile) as f:
            for line in f:
                yield line

    def needs_abuse_score_check(self, line):
        return (
            "no_backend_selected" in line
            and "block_404" not in line
            and "ratelimited" not in line
        )

    def extract_ip_from_line(self, line):
        if not any(k in line for k in ("block_404", "ratelimited", "no_backend_selected")):
            return None

        parts = line.split()
        if len(parts) < 4:
            return None

        ip = parts[3]

        # IPv6 with brackets: [2001:db8::1]:443
        if ip.startswith("[") and "]" in ip:
            ip = ip[1:].split("]")[0]

        # IPv4 with port: 1.2.3.4:12345
        elif ":" in ip and ip.count(":") == 1:
            ip = ip.split(":")[0]

        # IPv6 without brackets, possibly with port suffix: ::ffff:1.2.3.4:56789
        elif ip.count(":") > 1:
            try:
                ipaddress.ip_address(ip)
            except ValueError:
                ip = ip.rsplit(":", 1)[0]

        try:
            addr = ipaddress.ip_address(ip)
            # Unwrap IPv4-mapped IPv6 (::ffff:1.2.3.4 -> 1.2.3.4)
            if isinstance(addr, ipaddress.IPv6Address) and addr.ipv4_mapped:
                return str(addr.ipv4_mapped)
            return str(addr)
        except ValueError:
            return None


# --- MAIN ---
# Config
LOGFILE = "/var/log/ipcheck_report.log"
REASON = "Detected Scanning / Hacking activity"

PROTECTED_IPS = [
    "127.0.0.1",
    "::1",
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "fc00::/7",
    "fe80::/10",
]

CACHE_FILE = "/var/lib/ipreporter_cache.json"
CACHE_TTL = 86400  # 1 day

ABUSE_SCORE_THRESHOLD = 50

def process_lines(lines, parser, reporter, cache):
    for line in lines:
        ip = parser.extract_ip_from_line(line)
        if not ip:
            continue

        if reporter.is_protected(ip):
            continue

        if cache.seen_recently(ip):
            continue

        if parser.needs_abuse_score_check(line):
            score = reporter.get_abuse_score(ip)
            if score is None or score <= ABUSE_SCORE_THRESHOLD:
                continue

        reporter.report_ip(ip)


# Main loop
def main():
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument(
        "--scan",
        action="store_true",
        help="Scan the current haproxy log file from the start instead of following it, "
             "and report any matching IPs (one-shot, for retroactive reporting).",
    )
    args = arg_parser.parse_args()

    reporter = IPReporter(LOGFILE, REASON, PROTECTED_IPS)
    parser = HAProxyLogParser()
    cache = IPCache(CACHE_FILE, CACHE_TTL)

    if args.scan:
        reporter.log("--- Scanning existing log file ---")
        process_lines(parser.read_all(), parser, reporter, cache)
        reporter.queue.join()
        reporter.log("--- Scan complete ---")
        return

    reporter.log("--- Daemon started ---")
    process_lines(parser.follow(), parser, reporter, cache)


if __name__ == "__main__":
    main()