import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_split_app/pages/home_page.dart';
import 'dart:math';

class GroupSelectionPage extends StatefulWidget {
  const GroupSelectionPage({super.key});
  @override
  State<GroupSelectionPage> createState() => _GroupSelectionPageState();
}

class _GroupSelectionPageState extends State<GroupSelectionPage> {
  List<String> _savedGroups = [];
  String _generateRandomGroupId({int length = 32}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  @override
  void initState() {
    super.initState();
    _loadSavedGroups();
  }

  Future<void> _loadSavedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final groups = prefs.getStringList('savedGroupIds') ?? [];
    setState(() {
      _savedGroups = groups;
    });
  }

  // Future<void> _addGroup(String groupId) async {
  //   final prefs = await SharedPreferences.getInstance();
  //   if (!_savedGroups.contains(groupId)) {
  //     _savedGroups.add(groupId);
  //     await prefs.setStringList('savedGroupIds', _savedGroups);
  //   }
  //   await prefs.setString('groupId', groupId);
  //   Navigator.pushReplacement(
  //     context,
  //     MaterialPageRoute(builder: (_) => const HomePage(groupId: _groupId)),
  //   );
  // }

  Future<void> _promptForGroupId({required bool isNew}) async {
    if (isNew) {
      final newGroupId = _generateRandomGroupId();
      final nameController = TextEditingController();
      final groupName = await showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('グループ名を入力'),
              content: TextField(
                controller: nameController,
                decoration: const InputDecoration(hintText: 'グループ名'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed:
                      () => Navigator.pop(context, nameController.text.trim()),
                  child: const Text('作成'),
                ),
              ],
            ),
      );
      if (groupName != null && groupName.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(newGroupId)
            .collection('settings')
            .doc('groupInfo')
            .set({'name': groupName});

        final prefs = await SharedPreferences.getInstance();
        final groupIds = prefs.getStringList('savedGroupIds') ?? [];
        if (!groupIds.contains(newGroupId)) {
          groupIds.add(newGroupId);
          await prefs.setStringList('savedGroupIds', groupIds);
        }
        await prefs.setString('groupId', newGroupId);
        await prefs.setString('groupName_$newGroupId', groupName);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomePage(groupId: newGroupId)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('グループを選択')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._savedGroups.map((groupId) {
            return FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final prefs = snapshot.data!;
                final groupName =
                    prefs.getString('groupName_$groupId') ?? 'グループ';
                return ListTile(
                  title: Text(groupName),
                  subtitle: Text(
                    groupId,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await prefs.setString('groupId', groupId);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HomePage(groupId: groupId),
                      ),
                    );
                  },
                );
              },
            );
          }),
          const Divider(),
          ElevatedButton(
            onPressed: () => _promptForGroupId(isNew: true),
            child: const Text('新しいグループを作成'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _promptForGroupId(isNew: false),
            child: const Text('グループに参加'),
          ),
        ],
      ),
    );
  }
}
