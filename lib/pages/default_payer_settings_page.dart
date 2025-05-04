

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DefaultPayerSettingsPage extends StatefulWidget {
  final String member1Name;
  final String member2Name;

  const DefaultPayerSettingsPage({
    super.key,
    required this.member1Name,
    required this.member2Name,
  });

  @override
  State<DefaultPayerSettingsPage> createState() => _DefaultPayerSettingsPageState();
}

class _DefaultPayerSettingsPageState extends State<DefaultPayerSettingsPage> {
  int _defaultPayer = 1;

  @override
  void initState() {
    super.initState();
    _loadDefaultPayer();
  }

  Future<void> _loadDefaultPayer() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _defaultPayer = prefs.getInt('defaultPayer') ?? 1;
    });
  }

  Future<void> _saveDefaultPayer(int payer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('defaultPayer', payer);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('デフォルト支払者設定')),
      body: Column(
        children: [
          RadioListTile<int>(
            title: Text(widget.member1Name),
            value: 1,
            groupValue: _defaultPayer,
            onChanged: (value) {
              if (value != null) {
                setState(() => _defaultPayer = value);
                _saveDefaultPayer(value);
              }
            },
          ),
          RadioListTile<int>(
            title: Text(widget.member2Name),
            value: 2,
            groupValue: _defaultPayer,
            onChanged: (value) {
              if (value != null) {
                setState(() => _defaultPayer = value);
                _saveDefaultPayer(value);
              }
            },
          ),
        ],
      ),
    );
  }
}