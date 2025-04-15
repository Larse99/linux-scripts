#!/usr/bin/env python3
# Actively scans the HAProxy logs for 418 and 429 status codes.
# Author: Lars Eissink

# Small READ ME:
# In my own setup, 429 is used for ratelimiting and 418 for 404 error tracking. Abusers get blocked by HAProxy when triggering the ratelimiter or 404s.
# This script goes even further to check how many of those are triggered. If the amount is above the threshold, in this case a silent-drop is introduced.
# The silent-drop can easily be exchanged with adding the IP to a IPSET for example.
# 
# To make this work, you need to add the according ACLs and DENY rules. E.g:
# acl banned_ips src -f /etc/haproxy/acl/banned.acl
# http-request silent-drop if banned_ips

import time
import re
from collections import defaultdict
import subprocess
import ipaddress

# Variables - Save to edit.
LOGFILE = "/var/log/haproxy.log"
ACL_FILE = "/etc/haproxy/acl/banned.acl"
IP_WHITELIST = "/etc/haproxy/acl/whitelist.acl"
STATUS_CODES = {"429", "418"}
THRESHOLD = 5 # Amount of occurrences
CHECK_INTERVAL = 10 # Time in seconds

# Functions - do not edit below this line.
def readLog(logfile):
    """
        This function takes a logfile and tails the log. 
        The function is similair to 'tail -f' in Linux.
    """
    with open(logfile, 'r') as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if not line:
                time.sleep(1)
                continue
            yield line

def parseLine(line):
    """
        This function parses each line to check it status code and source IP.
    """
    # This matches lines that have a IP:PORt and Status_code. 
    match = re.search(r'(?P<ip>\d+\.\d+\.\d+\.\d+).*?\s(?P<status>\d{3})\b', line)
    if match:
        return match.group("ip"), match.group("status")
    return None, None

def checkDuplicateIp():
    """
        Checks if a IP is already in the banned list. This to avoid duplicate IPs in the list.
    """
    try:
        with open(ACL_FILE, 'r') as f:
            return set(line.strip() for line in f if line.strip())
    except FileNotFoundError:
        return set()

def isWhitelisted(ip, whitelist):
    """
        Checks if a IP-address is whitelisted
    """
    ip_obj = ipaddress.ip_address(ip)
    for net in whitelist:
        if ip_obj in net:
            return True
    return False

def loadWhitelist():
    """
        Load the whitelist
    """
    whitelist = set()
    try:
        with open(IP_WHITELIST, 'r') as f:
            for line in f:
                entry = line.strip()
                if entry:
                    whitelist.add(ipaddress.ip_network(entry, strict=False))
    except FileNotFoundError:
        pass
    return whitelist

def appendBan(ip):
    """
        Appends the Ban. Bad Actor IP to ACL file
    """
    with open(ACL_FILE, 'a') as f:
        f.write(f"{ip}\n")
    subprocess.run(["systemctl", "reload", "haproxy"])

# Main function
def main():
    print("[*] Start banwatch...")

    ipCounters = defaultdict(int)
    whitelistNets = loadWhitelist()

    for line in readLog(LOGFILE):
        ip, status = parseLine(line)

        if not ip or not status:
            continue

        if isWhitelisted(ip, whitelistNets):
            print(f"[-] IP {ip} is in whitelist, skipping.")
            continue

        bannedIps = checkDuplicateIp()
        if status in STATUS_CODES and ip not in bannedIps:
            ipCounters[ip] += 1
            if ipCounters[ip] == THRESHOLD:
                print(f"[+] Banning IP {ip} after {ipCounters[ip]} hits. Status: {status}")
                appendBan(ip)
                ipCounters[ip] = 0

# Run main function
if __name__ == "__main__":
    main()
