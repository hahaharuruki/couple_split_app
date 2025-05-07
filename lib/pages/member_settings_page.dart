import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/member_service.dart';

/// メンバー設定ページ
/// groupId 配下の settings/groupInfo/members を読み書きします。
class MemberSettingsPage extends StatefulWidget {
  final String groupId;
  const MemberSettingsPage({super.key, required this.groupId});

  @override
  State<MemberSettingsPage> createState() => _MemberSettingsPageState();
}

class _MemberSettingsPageState extends State<MemberSettingsPage> {
  List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    _loadExistingMembers();
  }

  Future<void> _loadExistingMembers() async {
    final memberList = await fetchMemberNames(widget.groupId);
    final members = [memberList['member1'] ?? '', memberList['member2'] ?? ''];

    setState(() {
      _controllers = members.map<TextEditingController>((name) {
        return TextEditingController(text: name);
      }).toList();
    });
  }

  void _addField() {
    setState(() {
      _controllers.add(TextEditingController());
    });
  }

  void _removeField(int index) {
    setState(() {
      _controllers.removeAt(index);
    });
  }

  Future<void> _saveMembers() async {
    final names = _controllers.map((c) => c.text.trim()).where((n) => n.isNotEmpty).toList();
    if (names.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('メンバーは2人以上必要です')));
      return;
    }

    // Firestore に保存
    final membersData = names.asMap().entries.map((e) => {
      'id': e.key,
      'name': e.value,
    }).toList();

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('settings')
        .doc('groupInfo')
        .set({'members': membersData}, SetOptions(merge: true));

    // SharedPreferences にキャッシュ
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('members_${widget.groupId}', names);

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('メンバー設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _controllers.length,
                itemBuilder: (ctx, idx) {
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controllers[idx],
                          decoration: InputDecoration(labelText: 'メンバー${idx + 1}'),
                        ),
                      ),
                      if (idx >= 2)
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _removeField(idx),
                        ),
                    ],
                  );
                },
              ),
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('メンバー追加'),
                  onPressed: _addField,
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _saveMembers,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}