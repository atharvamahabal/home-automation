# App Features & Developer Guide

This document outlines the current features of the Home Automation app and provides a guide for extending its functionality.

## 📱 Current Features

### 1. Connection Management
- **MQTT Support**: Connect to any MQTT broker (default: `broker.hivemq.com`).
- **Auto-Connect**: Automatically connects on app startup if previously connected.
- **Auto-Reconnect**: Automatically attempts to reconnect if the connection is lost.
- **Persistence**: Remembers broker details (IP, Port, Topic) across app restarts.
- **Status Feedback**: Visual indicators for connection status (Green/Red) and real-time logs.

### 2. Device Control (Dynamic Grid)
*   **Dynamic Device Addition**: Add devices of different types without coding.
    *   **Fan**: Blue fan icon.
    *   **Light**: Orange lightbulb icon.
    *   **Other**: Generic device icon.
*   **Auto-Naming**: Automatically handles duplicate names (e.g., "Fan", "Fan 1", "Fan 2").
*   **Persistence**: Devices are saved locally using `shared_preferences` and restored on app launch.
*   **Interactive Grid**:
    *   **Tap**: Toggles device ON/OFF and publishes MQTT message (e.g., `Fan 1 ON`).
    *   **Long Press**: Deletes the device.

### 3. Monitor & Logs
*   **Monitor Tab**: View incoming MQTT messages in real-time.
*   **Logs Tab**: Debug connection issues and track sent commands.
*   **Custom Messages**: Send manual text messages to the MQTT topic for testing.

---

## 🛠 Developer Guide: How to Extend

This app is designed to be "dynamic" — you can add new features by following these patterns.

### 1. How to Add a New Device Type
To add a new device type (e.g., "Heater" or "Garage Door"), follow these steps in `lib/main.dart`:

1.  **Update the Add Dialog**:
    Locate `_showAddDeviceDialog` and add your new type to the list:
    ```dart
    items: ['Fan', 'Light', 'Heater', 'Other'] // Added 'Heater'
    ```

2.  **Define Icon**:
    Update `_getIconForType` to assign an icon:
    ```dart
    IconData _getIconForType(String type) {
      switch (type.toLowerCase()) {
        case 'heater': return Icons.local_fire_department; // New Icon
        // ... existing cases
      }
    }
    ```

3.  **Define Color**:
    Update `_getColorForType` to assign a color:
    ```dart
    Color _getColorForType(String type, bool isOn) {
      if (!isOn) return Colors.grey;
      switch (type.toLowerCase()) {
        case 'heater': return Colors.red; // New Color
        // ... existing cases
      }
    }
    ```

### 2. How Persistence Works
The app uses a simple JSON structure stored in `shared_preferences` key `devices`.
*   **Load**: `_loadDevices()` reads the JSON string and converts it to `List<Device>`.
*   **Save**: `_saveDevices()` converts the list back to JSON and writes it to disk whenever a device is added, removed, or toggled.

### 3. Adding New Features
If you want to add a completely new feature (e.g., a "Timer"), follow the **Dynamic Document** pattern:
1.  **Model It**: Create a class (like `Device`) to hold the data.
2.  **Persist It**: Add `toJson()` and `fromJson()` methods and save it to `shared_preferences`.
3.  **Display It**: Use a `ListView` or `GridView` (like the Controls tab) to render the data dynamically.
