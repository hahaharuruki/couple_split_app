import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_split_app/pages/home_page.dart';
import 'package:couple_split_app/pages/add_member_page.dart';
import 'dart:math';

class GroupSelectionPage extends StatefulWidget {
  const GroupSelectionPage({super.key});
  @override
  State<GroupSelectionPage> createState() => _GroupSelectionPageState();
}

class _GroupSelectionPageState extends State<GroupSelectionPage> {
  List<String> _savedGroups = [];
  bool _isEditMode = false;
  Set<String> _selectedGroups = {};
  // 起動時に自動で開くグループID
  String? _defaultGroupId;

  // ランダムなグループIDを生成し、Firestoreで重複チェックを行う
  Future<String> _generateUniqueGroupId({
    int length = 32,
    int maxAttempts = 5,
  }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // ランダムなグループIDを生成
      final groupId = _generateRandomGroupId(length: length);

      // Firestoreでそのグループが存在するかチェック
      final docSnapshot =
          await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .get();

      // 存在しなければそのIDを使用
      if (!docSnapshot.exists) {
        return groupId;
      }

      // 存在する場合は次のイテレーションで新しいIDを試す
    }

    // 最大試行回数を超えた場合、タイムスタンプを付加したIDを生成（ほぼ確実にユニーク）
    return '${_generateRandomGroupId(length: length ~/ 2)}-${DateTime.now().millisecondsSinceEpoch}';
  }

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
    _loadDefaultGroup();
  }

  // 起動時に自動で開くグループを読み込む
  Future<void> _loadDefaultGroup() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _defaultGroupId = prefs.getString('default_group_id');
    });
  }

  // 起動時に自動で開くグループを保存する
  Future<void> _saveDefaultGroup(String? groupId) async {
    final prefs = await SharedPreferences.getInstance();
    if (groupId != null) {
      await prefs.setString('default_group_id', groupId);
    } else {
      await prefs.remove('default_group_id');
    }
    setState(() {
      _defaultGroupId = groupId;
    });
  }

  Future<void> _loadSavedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final groups = prefs.getStringList('savedGroupIds') ?? [];

    // 保存されている順序を取得
    final orderedGroups = prefs.getStringList('groupOrder') ?? [];

    // 保存されている順序に基づいてグループを並べ替え
    List<String> sortedGroups = List.from(groups);
    sortedGroups.sort((a, b) {
      final indexA = orderedGroups.indexOf(a);
      final indexB = orderedGroups.indexOf(b);
      if (indexA == -1 && indexB == -1) return 0;
      if (indexA == -1) return 1;
      if (indexB == -1) return -1;
      return indexA.compareTo(indexB);
    });

    setState(() {
      _savedGroups = sortedGroups;
    });
  }

  // グループの順序を保存する
  Future<void> _saveGroupOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('groupOrder', _savedGroups);
  }

  // グループの順序を変更する
  void _reorderGroups(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _savedGroups.removeAt(oldIndex);
      _savedGroups.insert(newIndex, item);
    });
    _saveGroupOrder();
  }

  Future<void> _promptForGroupId({required bool isNew}) async {
    // 2人モードでは1グループのみ使用可能
    if (_savedGroups.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('現在は1グループのみ使用可能です。既存のグループをご利用ください。'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (isNew) {
      // 重複チェック付きのユニークなグループIDを生成
      final newGroupId = await _generateUniqueGroupId();
      final nameController = TextEditingController();

      // グループ名だけを入力するダイアログを表示
      final groupName = await showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('新しいグループの作成'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'グループ名',
                      hintText: 'グループの名前を入力してください',
                    ),
                    autofocus: true,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () {
                    if (nameController.text.trim().isNotEmpty) {
                      Navigator.pop(context, nameController.text.trim());
                    }
                  },
                  child: const Text('次へ'),
                ),
              ],
            ),
      );

      if (groupName != null) {
        // グループの基本情報をFirestoreに保存
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(newGroupId)
            .set({'created_at': FieldValue.serverTimestamp()});

        // ローカル設定を保存
        final prefs = await SharedPreferences.getInstance();
        final groupIds = prefs.getStringList('savedGroupIds') ?? [];
        if (!groupIds.contains(newGroupId)) {
          groupIds.add(newGroupId);
          await prefs.setStringList('savedGroupIds', groupIds);
        }
        await prefs.setString('groupId', newGroupId);
        await prefs.setString('groupName_$newGroupId', groupName);

        // メンバー追加ページに遷移
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => AddMemberPage(groupId: newGroupId, groupName: groupName),
          ),
        );
      }
    } else {
      // グループ参加のためのダイアログを表示
      final groupIdController = TextEditingController();

      final groupId = await showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('グループに参加'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: groupIdController,
                    decoration: const InputDecoration(
                      hintText: 'グループID',
                      helperText: '参加したいグループのIDを入力してください',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () {
                    if (groupIdController.text.trim().isNotEmpty) {
                      Navigator.pop(context, groupIdController.text.trim());
                    }
                  },
                  child: const Text('参加'),
                ),
              ],
            ),
      );

      if (groupId != null) {
        try {
          // グループが存在するか確認
          final groupDoc =
              await FirebaseFirestore.instance
                  .collection('groups')
                  .doc(groupId)
                  .get();

          if (!groupDoc.exists) {
            // グループが存在しない場合
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('指定されたグループが見つかりませんでした')),
            );
            return;
          }

          // グループ情報を取得
          final settingsDoc =
              await FirebaseFirestore.instance
                  .collection('groups')
                  .doc(groupId)
                  .collection('settings')
                  .doc('groupInfo')
                  .get();

          if (!settingsDoc.exists) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('グループ情報が不完全です')));
            return;
          }

          final groupData = settingsDoc.data()!;
          final groupName = groupData['name'] as String? ?? 'グループ';

          // メンバー情報を取得
          final membersList = groupData['members'] as List<dynamic>? ?? [];

          if (membersList.isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('メンバー情報が見つかりませんでした')));
            return;
          }

          // 端末に情報を保存
          final prefs = await SharedPreferences.getInstance();
          final groupIds = prefs.getStringList('savedGroupIds') ?? [];

          if (!groupIds.contains(groupId)) {
            groupIds.add(groupId);
            await prefs.setStringList('savedGroupIds', groupIds);
          }

          await prefs.setString('groupId', groupId);
          await prefs.setString('groupName_$groupId', groupName);

          // メンバー1と2の情報を保存（存在する場合）
          if (membersList.length >= 1) {
            final member1 = membersList[0];
            final member1Name = member1['name'] as String? ?? 'メンバー1';
            await prefs.setString('member1Name', member1Name);
          }

          if (membersList.length >= 2) {
            final member2 = membersList[1];
            final member2Name = member2['name'] as String? ?? 'メンバー2';
            await prefs.setString('member2Name', member2Name);
          }

          // グループのホームページに遷移
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomePage(groupId: groupId)),
          );
        } catch (e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('グループを選択'),
        actions: [
          // 編集ボタン
          IconButton(
            icon: Icon(_isEditMode ? Icons.check : Icons.edit),
            onPressed: () {
              setState(() {
                _isEditMode = !_isEditMode;
                if (!_isEditMode) {
                  _selectedGroups.clear();
                }
              });
            },
          ),
          // 削除ボタン（選択時のみ表示）
          if (_isEditMode && _selectedGroups.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('グループ削除の確認'),
                        content: const Text(
                          'グループを端末から削除します。もう一度グループIDを入力することで再参加できます。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text(
                              '削除',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                );

                if (result == true) {
                  final prefs = await SharedPreferences.getInstance();
                  final updatedGroups =
                      _savedGroups
                          .where((g) => !_selectedGroups.contains(g))
                          .toList();
                  await prefs.setStringList('savedGroupIds', updatedGroups);

                  // 削除されるグループが起動時に開くグループとして設定されている場合、その設定も削除
                  for (final groupId in _selectedGroups) {
                    if (_defaultGroupId == groupId) {
                      await _saveDefaultGroup(null);
                    }
                  }

                  setState(() {
                    _savedGroups = updatedGroups;
                    _selectedGroups.clear();
                  });
                  _saveGroupOrder();
                }
              },
            ),
        ],
      ),
      body:
          _isEditMode
              ? ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount:
                    _savedGroups.length + 1, // +1 for buttons at the bottom
                onReorder: _reorderGroups,
                itemBuilder: (context, index) {
                  // 最後の要素はボタン
                  if (index == _savedGroups.length) {
                    return Column(
                      key: const ValueKey('buttons'),
                      children: [
                        const Divider(),
                        // 2人モードではグループ数を1に制限
                        if (_savedGroups.isEmpty) ...[
                          ElevatedButton(
                            onPressed: () => _promptForGroupId(isNew: true),
                            child: const Text('新しいグループを作成'),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => _promptForGroupId(isNew: false),
                            child: const Text('グループに参加'),
                          ),
                        ] else ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Text(
                              '現在は1グループのみ使用可能です。',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                        /* 複数グループ対応時に復活
                        ElevatedButton(
                          onPressed: () => _promptForGroupId(isNew: true),
                          child: const Text('新しいグループを作成'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => _promptForGroupId(isNew: false),
                          child: const Text('グループに参加'),
                        ),
                        */
                      ],
                    );
                  }

                  final groupId = _savedGroups[index];
                  return FutureBuilder<SharedPreferences>(
                    key: ValueKey(groupId),
                    future: SharedPreferences.getInstance(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();
                      final prefs = snapshot.data!;
                      final groupName =
                          prefs.getString('groupName_$groupId') ?? 'グループ';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          leading: Checkbox(
                            value: _selectedGroups.contains(groupId),
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedGroups.add(groupId);
                                } else {
                                  _selectedGroups.remove(groupId);
                                }
                              });
                            },
                          ),
                          title: Text(
                            groupName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            groupId,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          trailing: const Icon(Icons.drag_handle),
                          onTap: () {
                            setState(() {
                              if (_selectedGroups.contains(groupId)) {
                                _selectedGroups.remove(groupId);
                              } else {
                                _selectedGroups.add(groupId);
                              }
                            });
                          },
                        ),
                      );
                    },
                  );
                },
              )
              : ListView(
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
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            // 「起動時に開く」ラジオボタンを追加
                            leading: InkWell(
                              onTap: () {
                                // 同じグループを選択した場合は選択解除
                                if (_defaultGroupId == groupId) {
                                  _saveDefaultGroup(null);
                                } else {
                                  _saveDefaultGroup(groupId);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  _defaultGroupId == groupId
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color:
                                      _defaultGroupId == groupId
                                          ? Theme.of(context).primaryColor
                                          : Colors.grey,
                                ),
                              ),
                            ),
                            title: Text(
                              groupName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  groupId,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (_defaultGroupId == groupId)
                                  const Text(
                                    '起動時に開く',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
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
                          ),
                        );
                      },
                    );
                  }),
                  const Divider(),
                  // 2人モードではグループ数を1に制限
                  if (_savedGroups.isEmpty)
                    ElevatedButton(
                      onPressed: () => _promptForGroupId(isNew: true),
                      child: const Text('新しいグループを作成'),
                    ),
                  if (_savedGroups.isEmpty) const SizedBox(height: 12),
                  if (_savedGroups.isEmpty)
                    ElevatedButton(
                      onPressed: () => _promptForGroupId(isNew: false),
                      child: const Text('グループに参加'),
                    ),
                  // グループが1つ以上ある場合は説明を表示
                  if (_savedGroups.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Text(
                        '現在は1グループのみ使用可能です。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  /* 複数グループ対応時に復活
                  ElevatedButton(
                    onPressed: () => _promptForGroupId(isNew: true),
                    child: const Text('新しいグループを作成'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _promptForGroupId(isNew: false),
                    child: const Text('グループに参加'),
                  ),
                  */
                ],
              ),
    );
  }
}
