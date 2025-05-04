import 'package:flutter/material.dart';
import 'package:couple_split_app/pages/name_settings_page.dart';
import 'package:couple_split_app/pages/tag_settings_page.dart';
import 'package:couple_split_app/pages/default_payer_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsPage extends StatelessWidget {
  final String member1Name;
  final String member2Name;

  const SettingsPage({
    Key? key,
    required this.member1Name,
    required this.member2Name,
  }) : super(key: key);

  Future<void> _updateNames(BuildContext context) async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => NameSettingsPage(
          member1Name: member1Name,
          member2Name: member2Name,
        ),
      ),
    );
    if (result != null) {
      // Firestoreに名前情報を保存
      await FirebaseFirestore.instance.collection('settings').doc('names').set({
        'member1Name': result['member1Name'] ?? member1Name,
        'member2Name': result['member2Name'] ?? member2Name,
      });
      // SharedPreferencesにも保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('member1Name', result['member1Name']!);
      await prefs.setString('member2Name', result['member2Name']!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            ListTile(
              title: const Text('名前'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _updateNames(context),
            ),
            ListTile(
              title: const Text('タグ'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TagSettingsPage(
                      myName: member1Name,
                      partnerName: member2Name,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              title: const Text('デフォルト支払者'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DefaultPayerSettingsPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
