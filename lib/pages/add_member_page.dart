import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:couple_split_app/pages/home_page.dart';

class AddMemberPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const AddMemberPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<AddMemberPage> createState() => _AddMemberPageState();
}

class _AddMemberPageState extends State<AddMemberPage> {
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    // デフォルトで2人分のコントローラーを用意
    _controllers.add(TextEditingController());
    _controllers.add(TextEditingController());
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addField() {
    setState(() {
      _controllers.add(TextEditingController());
    });
  }

  void _removeField(int index) {
    if (_controllers.length <= 2) {
      // 最低2人は必要
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('グループには最低2人のメンバーが必要です')));
      return;
    }

    setState(() {
      _controllers.removeAt(index);
    });
  }

  Future<void> _saveMembers() async {
    // 空の名前をチェック
    final names = _controllers.map((c) => c.text.trim()).toList();
    if (names.any((name) => name.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('全てのメンバー名を入力してください')));
      return;
    }

    try {
      // グループ情報を更新
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('settings')
          .doc('groupInfo')
          .set({
            'name': widget.groupName,
            'members':
                names
                    .asMap()
                    .entries
                    .map((e) => {'id': e.key, 'name': e.value})
                    .toList(),
          });

      // ローカル設定を保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('member1Name', names[0]);
      if (names.length > 1) {
        await prefs.setString('member2Name', names[1]);
      }

      // ホームページに遷移
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage(groupId: widget.groupId)),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // メンバーが3人以上かどうかをチェック
    final bool showDeleteButtons = _controllers.length > 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('メンバーを追加'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'グループ "${widget.groupName}" のメンバーを追加してください',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _controllers.length,
                itemBuilder: (ctx, idx) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controllers[idx],
                            decoration: InputDecoration(
                              labelText: 'メンバー ${idx + 1}',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        // 3人以上の場合のみ削除ボタンを表示
                        /* 2人のみモードのため、削除ボタンを非表示
                        if (showDeleteButtons)
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _removeField(idx),
                          ),
                        */
                      ],
                    ),
                  );
                },
              ),
            ),
            /* 2人のみモードのため、メンバー追加ボタンを無効化
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('メンバーを追加'),
              onPressed: _addField,
            ),
            */
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                '現在は2人モードに制限されています',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _saveMembers,
              child: const Text('保存してグループを作成', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
