import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialPortScreen extends StatefulWidget {
  @override
  _SerialPortScreenState createState() => _SerialPortScreenState();
}

class _SerialPortScreenState extends State<SerialPortScreen> {
  SerialPort? port;
  SerialPortReader? reader;
  String receivedData = '';

  void connectToArduino() {
    final availablePorts = SerialPort.availablePorts;
    print(availablePorts.toString());
    for (final portName in availablePorts) {
      if (portName.contains("/dev/cu.usbserial-10")) {  // Typical Arduino port name
        port = SerialPort(portName);
        if (port!.openReadWrite()) {
          print("Connected to $portName");
          reader = SerialPortReader(port!);
          reader!.stream.listen((data) {
            setState(() {
              receivedData += String.fromCharCodes(data);
            });
          });
          break;
        }
      }
    }
  }

  void sendData(String message) {
    if (port != null && port!.isOpen) {
      port!.write(Uint8List.fromList(message.codeUnits));
    }
  }

  @override
  void dispose() {
    port?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Arduino Serial Connection")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Received: $receivedData"),
            SizedBox(height: 20),
            TextField(
              onSubmitted: (text) => sendData(text),
              decoration: InputDecoration(labelText: "Send to Arduino"),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: connectToArduino,
              child: Text("Connect to Arduino"),
            ),
          ],
        ),
      ),
    );
  }
}