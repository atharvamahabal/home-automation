# Raspberry Pi Zero W Setup Guide for Home Automation

This guide explains how to set up your Raspberry Pi Zero W to receive MQTT commands ('START'/'STOP') from your Flutter app and control a physical device (like an LED or Relay).

## 1. Prerequisites
*   **Raspberry Pi Zero W** (with headers pre-soldered is easier).
*   **Micro SD Card** (8GB or larger).
*   **Micro USB Power Supply**.
*   **LED** and **Resistor (220Ω)** OR a **Relay Module**.
*   **Jumper Wires**.

## 2. Flashing the OS (Headless Setup)
Since you might not have a mini-HDMI monitor/adapter, we'll set it up "headless" (access via WiFi/SSH).

1.  Download **Raspberry Pi Imager** on your computer.
2.  Insert your SD Card into your computer.
3.  Open Raspberry Pi Imager:
    *   **OS**: Choose "Raspberry Pi OS Lite (32-bit)" (Lite is faster/lighter).
    *   **Storage**: Select your SD Card.
    *   **Settings (Gear Icon)**:
        *   Check **Enable SSH** -> Use password authentication.
        *   Check **Set username and password** (e.g., `pi` / `raspberry`).
        *   Check **Configure wireless LAN**: Enter your WiFi SSID and Password. **IMPORTANT**: Both your Pi and Phone must be on the internet (if using public broker) or same network (if using local broker).
4.  Click **WRITE**.

## 3. First Boot & SSH
1.  Insert the SD card into the Pi and power it up. Wait ~2-3 minutes.
2.  Open a terminal (Command Prompt/PowerShell) on your computer.
3.  Connect via SSH:
    ```bash
    ssh pi@raspberrypi.local
    ```
    *(Enter the password you set earlier).*

## 4. Install Dependencies
Once logged in to the Pi, update it and install Python MQTT libraries.

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install python3-pip gpiozero -y
pip3 install paho-mqtt
```

## 5. The Python Script
Create the script that listens for your App's commands.

1.  Create a file named `home_automation.py`:
    ```bash
    nano home_automation.py
    ```

2.  Paste the following code (Right-click to paste in PuTTY/Terminal):

    ```python
    import paho.mqtt.client as mqtt
    from gpiozero import LED
    from time import sleep

    # --- CONFIGURATION ---
    BROKER = "broker.hivemq.com"  # Using the same public broker as your app
    PORT = 1883
    TOPIC = "flutter/home_automation"
    DEVICE_PIN = 17  # GPIO 17 (Physical Pin 11)

    # Setup GPIO (LED or Relay)
    device = LED(DEVICE_PIN)

    def on_connect(client, userdata, flags, rc):
        print(f"Connected with result code {rc}")
        client.subscribe(TOPIC)

    def on_message(client, userdata, msg):
        payload = msg.payload.decode().strip()
        print(f"Received: {payload}")

        if payload == "START":
            device.on()
            print("Device turned ON")
        elif payload == "STOP":
            device.off()
            print("Device turned OFF")

    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message

    print(f"Connecting to {BROKER}...")
    client.connect(BROKER, PORT, 60)

    # Blocking call that processes network traffic, dispatches callbacks and handles reconnecting.
    client.loop_forever()
    ```

3.  Save and exit: Press `Ctrl+X`, then `Y`, then `Enter`.

## 6. Wiring (Example with LED)
*   **Positive (Long Leg) of LED** -> Resistor -> **GPIO 17** (Physical Pin 11).
*   **Negative (Short Leg) of LED** -> **GND** (Physical Pin 6 or 9).

*(If using a Relay, connect VCC to 5V, GND to GND, and IN to GPIO 17).*

## 7. Running the Script
Run the script manually to test:

```bash
python3 home_automation.py
```

Now, open your Flutter App:
1.  Connect to `broker.hivemq.com`.
2.  Press **START**. The LED should turn ON.
3.  Press **STOP**. The LED should turn OFF.

## 8. Run on Boot (Optional)
To make the script run automatically when you plug in the Pi:

1.  Open crontab:
    ```bash
    crontab -e
    ```
2.  Add this line at the bottom:
    ```bash
    @reboot python3 /home/pi/home_automation.py &
    ```
3.  Save and exit.

---

### Note on Public vs. Local Broker
*   **Current Setup**: Uses `broker.hivemq.com` (Public). This is easiest because it works over the internet.
*   **Local Setup (Advanced)**: If you want to run your *own* broker on the Pi (faster, more private, no internet needed), install Mosquitto:
    ```bash
    sudo apt install mosquitto mosquitto-clients -y
    sudo systemctl enable mosquitto
    ```
    *   Then, in your App and Python script, change `BROKER` to the Pi's local IP address (e.g., `192.168.1.X`).
