import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Automation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeAutomationPage(),
    );
  }
}

class Device {
  String id;
  String name;
  String type; // 'fan', 'light', 'other'
  bool isOn;

  Device({
    required this.id,
    required this.name,
    required this.type,
    this.isOn = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'isOn': isOn,
  };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'],
    name: json['name'],
    type: json['type'],
    isOn: json['isOn'] ?? false,
  );
}

class HomeAutomationPage extends StatefulWidget {
  const HomeAutomationPage({super.key});

  @override
  State<HomeAutomationPage> createState() => _HomeAutomationPageState();
}

class _HomeAutomationPageState extends State<HomeAutomationPage> {
  // MQTT Client
  MqttServerClient? client;

  // Connection state
  bool isConnected = false;
  String statusMessage = 'Disconnected';
  List<String> logs = [];
  List<String> receivedMessages = [];

  // Devices
  List<Device> devices = [];

  // Controllers
  final TextEditingController ipController = TextEditingController(
    text: 'broker.hivemq.com',
  );
  final TextEditingController portController = TextEditingController(
    text: '1883',
  );
  final TextEditingController topicController = TextEditingController(
    text: 'flutter/home_automation',
  );
  final TextEditingController customMsgController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await _loadDevices();
    await _loadConnectionSettings();
  }

  Future<void> _loadConnectionSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      ipController.text = prefs.getString('broker') ?? 'broker.hivemq.com';
      portController.text = prefs.getString('port') ?? '1883';
      topicController.text =
          prefs.getString('topic') ?? 'flutter/home_automation';
      bool shouldAutoConnect = prefs.getBool('shouldAutoConnect') ?? false;
      if (shouldAutoConnect) {
        _connect();
      }
    });
  }

  Future<void> _saveConnectionSettings(bool autoConnect) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('broker', ipController.text.trim());
    await prefs.setString('port', portController.text.trim());
    await prefs.setString('topic', topicController.text.trim());
    await prefs.setBool('shouldAutoConnect', autoConnect);
  }

  @override
  void dispose() {
    client?.disconnect();
    ipController.dispose();
    portController.dispose();
    topicController.dispose();
    customMsgController.dispose();
    super.dispose();
  }

  // --- Persistence ---
  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String? devicesJson = prefs.getString('devices');
    if (devicesJson != null) {
      final List<dynamic> decoded = jsonDecode(devicesJson);
      setState(() {
        devices = decoded.map((item) => Device.fromJson(item)).toList();
      });
    }
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(devices.map((d) => d.toJson()).toList());
    await prefs.setString('devices', encoded);
  }

  // --- Logic ---
  void _addDevice(String name, String type) {
    // Auto-increment name logic
    String finalName = name;
    int count = 1;
    while (devices.any(
      (d) => d.name.toLowerCase() == finalName.toLowerCase(),
    )) {
      finalName = '$name $count';
      count++;
    }

    setState(() {
      devices.add(
        Device(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: finalName,
          type: type,
        ),
      );
    });
    _saveDevices();
  }

  void _removeDevice(String id) {
    setState(() {
      devices.removeWhere((d) => d.id == id);
    });
    _saveDevices();
  }

  void _log(String message) {
    setState(() {
      logs.insert(0, '${DateTime.now().toString().split('.').first}: $message');
      statusMessage = message;
    });
  }

  // --- MQTT ---
  Future<void> _connect() async {
    if (client != null &&
        client!.connectionStatus!.state == MqttConnectionState.connected) {
      _log('Already connected');
      return;
    }

    final String broker = ipController.text.trim();
    final int port = int.tryParse(portController.text.trim()) ?? 1883;

    client = MqttServerClient.withPort(
      broker,
      'flutter_client_${DateTime.now().millisecondsSinceEpoch}',
      port,
    );

    client!.logging(on: false);
    client!.keepAlivePeriod = 20;
    client!.autoReconnect = true;
    client!.onDisconnected = _onDisconnected;
    client!.onConnected = _onConnected;
    client!.onSubscribed = _onSubscribed;
    client!.onAutoReconnect = _onAutoReconnect;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(
          'flutter_client_${DateTime.now().millisecondsSinceEpoch}',
        )
        .withWillTopic('willtopic')
        .withWillMessage('My Will message')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client!.connectionMessage = connMess;

    try {
      _log('Connecting to $broker:$port...');
      await client!.connect();
      _saveConnectionSettings(true);
    } on NoConnectionException catch (e) {
      _log('Client exception: $e');
      client!.disconnect();
    } on SocketException catch (e) {
      _log('Socket exception: $e');
      client!.disconnect();
    } catch (e) {
      _log('Error connecting: $e');
      client!.disconnect();
    }
  }

  void _onConnected() {
    setState(() {
      isConnected = true;
    });
    _log('Connected');

    final topic = topicController.text.trim();
    _log('Subscribing to $topic...');
    client!.subscribe(topic, MqttQos.atLeastOnce);

    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final recMess = c![0].payload as MqttPublishMessage;
      final pt = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );

      _log('Received message: $pt from topic: ${c[0].topic}');
      setState(() {
        receivedMessages.insert(
          0,
          '${DateTime.now().toString().split('.').first}: $pt',
        );
      });
    });
  }

  void _onDisconnected() {
    setState(() {
      isConnected = false;
    });
    _log('Disconnected');
  }

  void _onAutoReconnect() {
    _log('Auto-reconnecting...');
  }

  void _onSubscribed(String topic) {
    _log('Subscribed to $topic');
  }

  void _disconnect() {
    client?.disconnect();
    _saveConnectionSettings(false);
  }

  void _publish(String message) {
    if (client?.connectionStatus?.state != MqttConnectionState.connected) {
      _log('Not connected, cannot send command');
      // For testing UI without connection, you might want to uncomment this:
      // _log('Fake sent: $message');
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    final topic = topicController.text.trim();

    try {
      client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      _log('Sent: $message');
    } catch (e) {
      _log('Error publishing: $e');
    }
  }

  void _toggleDevice(Device device) {
    setState(() {
      device.isOn = !device.isOn;
    });
    _saveDevices();
    final command = '${device.name} ${device.isOn ? "ON" : "OFF"}';
    _publish(command);
  }

  // --- UI Helpers ---
  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'fan':
        return Icons.mode_fan_off;
      case 'light':
        return Icons.lightbulb;
      default:
        return Icons.devices;
    }
  }

  Color _getColorForType(String type, bool isOn) {
    if (!isOn) return Colors.grey;
    switch (type.toLowerCase()) {
      case 'fan':
        return Colors.blue;
      case 'light':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  void _showAddDeviceDialog() {
    String name = '';
    String type = 'Fan'; // Default

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Device'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(labelText: 'Device Name'),
                    onChanged: (value) => name = value,
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    value: type,
                    isExpanded: true,
                    items: ['Fan', 'Light', 'Other']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => type = value);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (name.isNotEmpty) {
                      _addDevice(name, type);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Automation'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddDeviceDialog,
            tooltip: 'Configure Button',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status Bar
          Container(
            padding: const EdgeInsets.all(8.0),
            color: isConnected ? Colors.green[100] : Colors.red[100],
            child: Row(
              children: [
                Icon(
                  isConnected ? Icons.check_circle : Icons.error,
                  color: isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusMessage,
                    style: TextStyle(
                      color: isConnected ? Colors.green[900] : Colors.red[900],
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Connection Settings'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: ipController,
                              decoration: const InputDecoration(
                                labelText: 'Broker',
                              ),
                              enabled: !isConnected,
                            ),
                            TextField(
                              controller: portController,
                              decoration: const InputDecoration(
                                labelText: 'Port',
                              ),
                              enabled: !isConnected,
                            ),
                            TextField(
                              controller: topicController,
                              decoration: const InputDecoration(
                                labelText: 'Topic',
                              ),
                              enabled: !isConnected,
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                          if (!isConnected)
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _connect();
                              },
                              child: const Text('Connect'),
                            )
                          else
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _disconnect();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Disconnect'),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Tabs
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.grid_view), text: 'Controls'),
                      Tab(icon: Icon(Icons.monitor), text: 'Monitor'),
                      Tab(icon: Icon(Icons.list), text: 'Logs'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Tab 1: Controls
                        Column(
                          children: [
                            // Custom Message Area
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: customMsgController,
                                      decoration: const InputDecoration(
                                        hintText: 'Enter custom message...',
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                    onPressed: () {
                                      if (customMsgController.text.isNotEmpty) {
                                        _publish(customMsgController.text);
                                        // Optional: clear text after send
                                        // customMsgController.clear();
                                      }
                                    },
                                    icon: const Icon(Icons.send),
                                  ),
                                ],
                              ),
                            ),
                            // Devices Grid
                            Expanded(
                              child: devices.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text('No devices added yet.'),
                                          ElevatedButton(
                                            onPressed: _showAddDeviceDialog,
                                            child: const Text('Add Device'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : GridView.builder(
                                      padding: const EdgeInsets.all(8.0),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 2,
                                            crossAxisSpacing: 10,
                                            mainAxisSpacing: 10,
                                            childAspectRatio: 1.2,
                                          ),
                                      itemCount: devices.length,
                                      itemBuilder: (context, index) {
                                        final device = devices[index];
                                        return Card(
                                          elevation: 4,
                                          color: _getColorForType(
                                            device.type,
                                            device.isOn,
                                          ).withOpacity(0.1),
                                          child: InkWell(
                                            onTap: () => _toggleDevice(device),
                                            onLongPress: () {
                                              // Confirm delete
                                              showDialog(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('Delete?'),
                                                  content: Text(
                                                    'Remove ${device.name}?',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(ctx),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () {
                                                        Navigator.pop(ctx);
                                                        _removeDevice(
                                                          device.id,
                                                        );
                                                      },
                                                      child: const Text(
                                                        'Delete',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  _getIconForType(device.type),
                                                  size: 40,
                                                  color: _getColorForType(
                                                    device.type,
                                                    device.isOn,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  device.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                Text(
                                                  device.isOn ? 'ON' : 'OFF',
                                                  style: TextStyle(
                                                    color: device.isOn
                                                        ? Colors.green
                                                        : Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),

                        // Tab 2: Monitor
                        Container(
                          color: Colors.black12,
                          child: receivedMessages.isEmpty
                              ? const Center(
                                  child: Text('No messages received yet'),
                                )
                              : ListView.builder(
                                  itemCount: receivedMessages.length,
                                  itemBuilder: (context, index) {
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                        vertical: 4.0,
                                      ),
                                      child: ListTile(
                                        leading: const Icon(Icons.message),
                                        title: Text(receivedMessages[index]),
                                      ),
                                    );
                                  },
                                ),
                        ),

                        // Tab 3: Logs
                        Container(
                          color: Colors.grey[200],
                          child: ListView.builder(
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 2.0,
                                ),
                                child: Text(
                                  logs[index],
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
