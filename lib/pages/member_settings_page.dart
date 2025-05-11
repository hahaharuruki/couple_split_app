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
  int _currentUserMemberId = 1; // デフォルトは最初のメンバー

  // 色の選択肢を拡張
  final List<Color> _colorOptions = [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    // Colors.grey, // グレーを削除
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingMembers();
    _loadCurrentUserMemberId();
  }

  // 現在のユーザーのメンバーIDを読み込む
  Future<void> _loadCurrentUserMemberId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserMemberId =
          prefs.getInt('current_user_member_id_${widget.groupId}') ?? 1;
    });
  }

  // 現在のユーザーのメンバーIDを保存する
  Future<void> _saveCurrentUserMemberId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'current_user_member_id_${widget.groupId}',
      _currentUserMemberId,
    );
  }

  Future<void> _loadExistingMembers() async {
    try {
      // 全メンバーのリストを取得
      final membersList = await fetchMemberNamesList(widget.groupId);

      setState(() {
        _controllers =
            membersList.map<TextEditingController>((name) {
              return TextEditingController(text: name);
            }).toList();

        // 最低2人のメンバーを確保
        if (_controllers.length < 2) {
          while (_controllers.length < 2) {
            _controllers.add(TextEditingController());
          }
        }
      });
    } catch (e) {
      // エラー時は空のコントローラーを2つ用意
      setState(() {
        _controllers = [TextEditingController(), TextEditingController()];
      });
    }
  }

  void _addField() {
    setState(() {
      _controllers.add(TextEditingController());
    });
  }

  // メンバーが支払い記録で使用されているか確認
  Future<bool> _isMemberUsedInPayments(int memberId) async {
    try {
      // memberId に該当する支払いを検索
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId)
              .collection('payments')
              .get();

      // いずれかの支払いでこのメンバーIDが使われているか確認
      for (var doc in querySnapshot.docs) {
        final data = doc.data();

        // 支払者として使用されているか確認
        if (data['payer'] == memberId) {
          return true;
        }

        // 負担者として使用されているか確認
        final ratios = Map<String, dynamic>.from(data['ratios'] ?? {});
        if (ratios.containsKey(memberId.toString()) &&
            ratios[memberId.toString()] > 0) {
          return true;
        }
      }

      return false;
    } catch (e) {
      // エラーが発生した場合、安全のためtrueを返す
      return true;
    }
  }

  // メンバーの削除を確認して実行
  Future<void> _confirmAndRemoveMember(int index) async {
    final memberId = index + 1;
    final memberName = _controllers[index].text.trim();

    // メンバー名が空の場合は確認なしで削除
    if (memberName.isEmpty) {
      _removeField(index);
      return;
    }

    // このメンバーが支払い記録で使用されているか確認
    final isUsed = await _isMemberUsedInPayments(memberId);

    if (isUsed) {
      // 使用されている場合は削除不可の警告を表示
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('メンバーを削除できません'),
              content: Text('$memberNameは支払い記録で使用されているため削除できません。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } else {
      // 使用されていない場合は削除確認ダイアログを表示
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('メンバーの削除'),
              content: Text('$memberNameを削除してもよろしいですか？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('削除'),
                ),
              ],
            ),
      );

      if (confirmed == true) {
        _removeField(index);
      }
    }
  }

  void _removeField(int index) {
    setState(() {
      _controllers.removeAt(index);
      // 削除されたメンバーが現在のユーザーだった場合、最初のメンバーに設定
      if (_currentUserMemberId == index + 1) {
        _currentUserMemberId = 1;
      }
      // 削除されたメンバーより後のIDを選択していた場合、IDを1つ減らす
      else if (_currentUserMemberId > index + 1) {
        _currentUserMemberId--;
      }
    });
  }

  Future<void> _saveMembers() async {
    final names =
        _controllers
            .map((c) => c.text.trim())
            .where((n) => n.isNotEmpty)
            .toList();
    if (names.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('メンバーは2人以上必要です')));
      return;
    }

    // 現在のユーザーのメンバーIDが有効範囲内かチェック
    if (_currentUserMemberId > names.length) {
      _currentUserMemberId = 1;
    }

    // Firestore に保存
    final membersData =
        names
            .asMap()
            .entries
            .map((e) => {'id': e.key, 'name': e.value})
            .toList();

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('settings')
        .doc('groupInfo')
        .set({'members': membersData}, SetOptions(merge: true));

    // SharedPreferences にキャッシュ
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('members_${widget.groupId}', names);

    // 現在のユーザーのメンバーIDを保存
    await _saveCurrentUserMemberId();

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bool showDeleteButtons = _controllers.length > 2;
    return Scaffold(
      appBar: AppBar(title: const Text('メンバー設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'この端末の使用者を選択してください。',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _controllers.length,
                itemBuilder: (ctx, idx) {
                  final memberId = idx + 1;
                  return Row(
                    children: [
                      // ラジオボタン
                      Radio<int>(
                        value: memberId,
                        groupValue: _currentUserMemberId,
                        onChanged: (value) {
                          setState(() {
                            _currentUserMemberId = value!;
                          });
                        },
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controllers[idx],
                          decoration: InputDecoration(
                            labelText: 'メンバー$memberId',
                          ),
                        ),
                      ),
                      /* 2人のみモードのため、削除ボタンを非表示
                      if (showDeleteButtons)
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _confirmAndRemoveMember(idx),
                        ),
                      */
                    ],
                  );
                },
              ),
            ),
            Row(
              children: [
                /* 2人のみモードのため、メンバー追加ボタンを無効化
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('メンバー追加'),
                  onPressed: _addField,
                ),
                */
                const Text(
                  '現在は2人モードに制限されています',
                  style: TextStyle(color: Colors.grey),
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
