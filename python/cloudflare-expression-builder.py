# Cloudflare Expression builder
# Creates a Cloudflare Expression based on a list of IPs which are downloaded from a external URL.
# JSON support is a little bit funky right now, but will be fixed in the future.
# Author: Lars Eissink
# Github: https://github.com/Larse99
# Repo: https://github.com/Larse99/linux-scripts

import requests
import json

class cloudflareExpressionBuilder:
    def __init__(self, url, json=False):
        self.url        = url
        self.json       = json
        self.ipList     = []

    def _fetchIpList(self):
        """
            Fetches a list of IPs and converts it to a format we can work with
        """
        try:
            response = requests.get(self.url)
            response.raise_for_status()

            # Check if json
            if self.json:
                self.ipList = response.json()
            else:
                # Split each line and filter out empty ones
                self.ipList = [line.strip() for line in response.text.splitlines() if line.strip()]

        except Exception as e:
            print(f'Something happened.. {e}')
            self.ipList = []

    def _constructFilterExp(self):
        """
            Constructs a filter expression based on the output of fetchIpList
        """
        if not self.ipList:
            return ""

        return f'(ip.src in {{{' '.join(self.ipList)}}})'

    def main(self):
        self._fetchIpList()
        return self._constructFilterExp()

# Main logic
def main():
    IPURL = 'https://site.com/ouripv4s'

    builder = cloudflareExpressionBuilder(IPURL)
    expression = builder.main()

    if expression:
        print("Cloudflare expression:")
        print(expression)
    else:
        print("No expression generated.")

if __name__ == '__main__':
    main()
