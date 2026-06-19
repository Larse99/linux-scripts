#!/usr/bin/python3
# Simple script to create and blacklist ASNs using Python and NFTables.
# Author: Lars Eissink
# Github.com/Larse99

import os
import subprocess
import argparse
import requests


class obtainIPs:
    def __init__(self, url):
        self.url    = url
        self.iplist = []

    def _fetchIPListFromASN(self):
        """Fetches the IP prefixes of any given ASN via the RIPE API"""
        try:
            response = requests.get(self.url)
            response.raise_for_status()

            data     = response.json()
            prefixes = data['data']['prefixes']

            self.iplist = [entry['prefix'] for entry in prefixes]

        except Exception as e:
            print(f'Something happened: {e}')
            self.iplist = []


class nftables:
    def __init__(self, asn, prefixes):
        self.asn      = asn
        self.prefixes = prefixes
        self.setName  = f"asn_{asn}_blacklist"
        self.table    = "inet filter"
        self.chain    = "input"

    def _run(self, cmd):
        """Executes an nft command as root using the -e flag to handle special characters"""

        # Ensure the script is run with root privileges
        if os.getuid() != 0:
            raise PermissionError("This script must be run as root due to nft privileges.")

        # Use '-e' so nft accepts the full command string, including braces
        result = subprocess.run(
            ["nft", "-e", cmd], capture_output=True, text=True
        )

        if result.returncode != 0:
            raise RuntimeError(f"nft error: {result.stderr.strip()}")

        return result.stdout

    def _setExists(self, set_name):
        """Checks whether a given nftables set already exists"""
        try:
            self._run(f"list set {self.table} {set_name}")
            return True
        except RuntimeError:
            return False

    def _getHandles(self):
        """Retrieves the handle numbers of DROP rules belonging to this ASN"""
        # -a flag must come before the subcommand to show handle numbers
        result = subprocess.run(
            ["nft", "-a", "list", "chain", "inet", "filter", self.chain],
            capture_output=True, text=True
        )

        output  = result.stdout
        handles = []

        for line in output.splitlines():
            if f"@{self.setName}" in line and "drop" in line:
                parts = line.strip().split("handle")
                if len(parts) > 1:
                    handles.append(parts[-1].strip())

        return handles


    def _createSet(self):
        """Creates separate nftables sets for IPv4 and IPv6 prefixes"""

        hasV4 = any('.' in p for p in self.prefixes)
        hasV6 = any(':' in p for p in self.prefixes)

        if hasV4:
            self._run(
                f"add set {self.table} {self.setName}_v4 "
                f"{{ type ipv4_addr; flags interval; }}"
            )

        if hasV6:
            self._run(
                f"add set {self.table} {self.setName}_v6 "
                f"{{ type ipv6_addr; flags interval; }}"
            )

        print(f"[+] Sets created for AS{self.asn}")

    def _populateSet(self):
        """Populates the IPv4 and IPv6 sets with the fetched prefixes"""

        v4 = [p for p in self.prefixes if '.' in p]
        v6 = [p for p in self.prefixes if ':' in p]

        if v4:
            elements = ", ".join(v4)
            self._run(f"add element {self.table} {self.setName}_v4 {{ {elements} }}")
            print(f"[+] {len(v4)} IPv4 prefixes added to set")

        if v6:
            elements = ", ".join(v6)
            self._run(f"add element {self.table} {self.setName}_v6 {{ {elements} }}")
            print(f"[+] {len(v6)} IPv6 prefixes added to set")

    def _addDropRules(self):
        """Adds DROP rules to the chain for both IPv4 and IPv6 sets"""

        v4 = [p for p in self.prefixes if '.' in p]
        v6 = [p for p in self.prefixes if ':' in p]

        if v4:
            self._run(
                f"add rule {self.table} {self.chain} "
                f"ip saddr @{self.setName}_v4 drop"
            )

        if v6:
            self._run(
                f"add rule {self.table} {self.chain} "
                f"ip6 saddr @{self.setName}_v6 drop"
            )

        print(f"[+] DROP rules added for AS{self.asn}")

    def apply(self):
        """Runs all steps to block an ASN: create sets, populate, and add DROP rules"""
        self._createSet()
        self._populateSet()
        self._addDropRules()

    def remove(self):
        """Removes the DROP rules and sets associated with this ASN"""

        # Remove DROP rules by handle number
        handles = self._getHandles()
        if handles:
            for handle in handles:
                self._run(f"delete rule {self.table} {self.chain} handle {handle}")
            print(f"[+] DROP rules removed for AS{self.asn}")
        else:
            print(f"[-] No DROP rules found for AS{self.asn}")

        # Remove sets if they exist
        for suffix in ["_v4", "_v6"]:
            set_name = f"{self.setName}{suffix}"
            if self._setExists(set_name):
                self._run(f"delete set {self.table} {set_name}")
                print(f"[+] Set {set_name} removed")
            else:
                print(f"[-] Set {set_name} not found, skipping")


def main():
    parser = argparse.ArgumentParser(description="Block or unblock an ASN using nftables")
    parser.add_argument("asn", type=int, help="The ASN to block or unblock (e.g. 112)")
    parser.add_argument("-d", "--delete", action="store_true", help="Remove the block for the given ASN")
    args = parser.parse_args()

    ASN = args.asn

    # Handle deletion flow — no API call needed
    if args.delete:
        print(f"[*] Removing block for AS{ASN}...")
        nft = nftables(ASN, [])
        nft.remove()
        print(f"[+] Done! AS{ASN} has been unblocked.")
        return

    # Normal flow: fetch prefixes and apply block
    APIURL = f"https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS{ASN}"

    print(f"[*] Obtaining prefixes for AS{ASN}...")
    ips = obtainIPs(APIURL)
    ips._fetchIPListFromASN()

    if not ips.iplist:
        print("[-] No prefixes found for the given ASN. Is the ASN correct?")
        return

    print(f"[*] {len(ips.iplist)} prefixes found. Applying block in nftables...")
    nft = nftables(ASN, ips.iplist)
    nft.apply()
    print(f"[+] Done! AS{ASN} has been blocked successfully.")


if __name__ == '__main__':
    main()