import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';


class MyHealthCheckApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'API Health Check',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HealthCheckPage(),
    );
  }
}

class HealthCheckPage extends StatefulWidget {
  @override
  _HealthCheckPageState createState() => _HealthCheckPageState();
}

class _HealthCheckPageState extends State<HealthCheckPage> {
  // API endpoint - REPLACE WITH YOUR ACTUAL ENDPOINT
  final String apiUrl = 'http://192.168.30.190:8000/api/health';
  
  // Connection status enum moved outside the class
  ConnectionStatus _connectionStatus = ConnectionStatus.initial;
  String _responseBody = '';
  int _statusCode = 0;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Automatically check health when page loads
    checkApiHealth();
  }

  Future<void> checkApiHealth() async {
    setState(() {
      _connectionStatus = ConnectionStatus.loading;
      _responseBody = '';
      _errorMessage = '';
    });

    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/json',
          'Connection': 'keep-alive',
        }
      ).timeout(
        Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Connection timeout');
        }
      );

      setState(() {
        _statusCode = response.statusCode;
        _responseBody = response.body;
        _connectionStatus = response.statusCode == 200 
          ? ConnectionStatus.success 
          : ConnectionStatus.error;
      });
    } catch (e) {
      setState(() {
        _connectionStatus = ConnectionStatus.error;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('API Health Check'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Connection Status Indicator
              _buildConnectionStatusWidget(),
              
              SizedBox(height: 20),
              
              // Status Code
              Text(
                'Status Code: $_statusCode',
                style: TextStyle(fontSize: 16),
              ),
              
              SizedBox(height: 10),
              
              // Response or Error Message
              _buildResponseWidget(),
              
              SizedBox(height: 20),
              
              // Retry Button
              ElevatedButton(
                onPressed: checkApiHealth,
                child: Text('Retry Connection'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget to show connection status
  Widget _buildConnectionStatusWidget() {
    IconData icon;
    Color color;
    String text;

    switch (_connectionStatus) {
      case ConnectionStatus.initial:
        icon = Icons.help_outline;
        color = Colors.grey;
        text = 'Initializing';
        break;
      case ConnectionStatus.loading:
        return CircularProgressIndicator();
      case ConnectionStatus.success:
        icon = Icons.check_circle;
        color = Colors.green;
        text = 'Connected Successfully';
        break;
      case ConnectionStatus.error:
        icon = Icons.error_outline;
        color = Colors.red;
        text = 'Connection Failed';
        break;
    }

    return Column(
      children: [
        Icon(icon, color: color, size: 60),
        SizedBox(height: 10),
        Text(
          text,
          style: TextStyle(color: color, fontSize: 18),
        ),
      ],
    );
  }

  // Widget to display response or error
  Widget _buildResponseWidget() {
    if (_connectionStatus == ConnectionStatus.error) {
      return Text(
        'Error: $_errorMessage',
        style: TextStyle(color: Colors.red, fontSize: 16),
        textAlign: TextAlign.center,
      );
    }

    return Text(
      'Response: ${_responseBody.isNotEmpty ? _responseBody : "No response"}',
      style: TextStyle(fontSize: 16),
      textAlign: TextAlign.center,
    );
  }
}

// Enum defined outside of any class
enum ConnectionStatus {
  initial,
  loading,
  success,
  error
}