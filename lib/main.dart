import 'package:flutter/material.dart';
import 'pages/home_page.dart';

class PaymentList extends StatelessWidget {
  final String myName;

  const PaymentList({Key? key, required this.myName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          title: Text('Payment 1 for $myName'),
        ),
        ListTile(
          title: Text('Payment 2 for $myName'),
        ),
      ],
    );
  }
}

void main() {
  runApp(const MyApp());
}

class HomePage extends StatelessWidget {
  final String myName;

  const HomePage({Key? key, required this.myName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Page'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              // Removed settings screen navigation due to missing implementation
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Text('Welcome, $myName!'),
          PaymentList(myName: myName), // Added myName parameter here
        ],
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const HomePage(myName: 'User'),
    );
  }
}