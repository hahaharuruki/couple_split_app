

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NameSettingsPage extends StatefulWidget {
  final String member1Name;
  final String member2Name;

  const NameSettingsPage({super.key, required this.member1Name, required this.member2Name});

  @override
  State<NameSettingsPage> createState() => _NameSettingsPageState();
}

class _NameSettingsPageState extends State<NameSettingsPage> {
  late final TextEditingController _member1NameController;
  late final TextEditingController _member2NameController;

  @override
  void initState() {
    super.initState();
    _member1NameController = TextEditingController(text: widget.member1Name);
    _member2NameController = TextEditingController(text: widget.member2Name);
  }

  @override
  void dispose() {
    _member1NameController.dispose();
    _member2NameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('名前の設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _member1NameController,
              decoration: const InputDecoration(labelText: 'メンバー1の名前'),
            ),
            TextField(
              controller: _member2NameController,
              decoration: const InputDecoration(labelText: 'メンバー2の名前'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final member1Name = _member1NameController.text.trim();
                final member2Name = _member2NameController.text.trim();
                if (member1Name.isEmpty || member2Name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('名前を入力してください')));
                  return;
                }

                await FirebaseFirestore.instance.collection('settings').doc('names').set({
                  'member1Name': member1Name,
                  'member2Name': member2Name,
                });

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('member1Name', member1Name);
                await prefs.setString('member2Name', member2Name);

                Navigator.pop(context, {
                  'member1Name': member1Name,
                  'member2Name': member2Name,
                });
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}