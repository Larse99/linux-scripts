#!/usr/bin/python3
# Checks if the VPN connection is alive, by checking a public source. If the connection is 'dead', you can specify actions
# In this case, all containers from a specific compose file will be stopped/killed. E.g. you can also restart the VPN service if the connection is dead.
# Author: Lars Eissink
#

import time
import urllib.request
import http.client
import urllib.parse
import subprocess
from datetime import datetime

# Variables - Change these to your likings
publicIP            = 'Public_IP'
checkInterval       = 15 # in Seconds
logFile             = '/place/you/want/to/have/your/log.log'
dockerComposeFile   = '/place/you/have/your/docker/compose.yml'
dockerWorkingDir    = '/the/working/directory/of/the/docker/containers'

# PushOver Settings
poToken             = '' # PushOver token
poUserkey           = '' # PushOver Userkey

# Functions - Only change if you know what you're doing
def log(message: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    logline = f'{timestamp} - {message}'
    print(logline)

    with open(logFile, 'a') as f:
        f.write(logline + "\n")

def sendPushover(poToken, poUserkey, message, title=None, url=None, url_title=None, priority=-1):
    conn = http.client.HTTPSConnection("api.pushover.net")
    post_data = {
        "token": poToken,
        "user": poUserkey,
        "message": message,
        "priority": priority,
    }

    if title:
        post_data["title"] = title
    if url:
        post_data["url"] = url
    if url_title:
        post_data["url_title"] = url_title

    post_data_encoded = urllib.parse.urlencode(post_data)
    headers = {"Content-type": "application/x-www-form-urlencoded"}
    conn.request("POST", "/1/messages.json", post_data_encoded, headers)

    response = conn.getresponse()

    return response.status, response.reason

def killContainers(dockerComposeFile: str, dockerWorkingDir: str):
    try:
        result = subprocess.run(
            ['docker', 'compose', '-f', dockerComposeFile, 'down'],
            cwd=dockerWorkingDir,
            capture_output=True,
            text=True
        )
    except Exception as e:
        print(f'Something happened: {e}')

def checkIP(ip: str):
    # Get current IP via icanhazip.com
    with urllib.request.urlopen("https://icanhazip.com") as response:
        currentIP = response.read().decode("utf-8").strip()

    # Check if you're still connected to VPN
    if ip == currentIP:
        return False
    return True

def main():
    log("[ INFO  ] Starting VPN monitor...")
    while True:
        try:
            if checkIP(publicIP):
                pass
            else:
                log("[ ERROR ] VPN connection is NOT active. Activating killswitch!")
                killContainers(dockerComposeFile, dockerWorkingDir)
                log("[ INFO ] Sending PushOver...")
                sendPushover(poToken, poUserkey, "VPN connection dead.")
                quit()

        except Exception as e:
            log(f"[ ERROR ] Unexpected error in main loop: {e}")
            sendPushover(poToken, poUserkey, "Unexpected error in Mainloop, please check server.")

        time.sleep(checkInterval)

if __name__ == '__main__':
    main()
