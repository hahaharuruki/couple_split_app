import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/member_service.dart';
import '../models/tag.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TagSettingsPage extends StatefulWidget {
  final String groupId;

  const TagSettingsPage({super.key, required this.groupId});

  @override
  State<TagSettingsPage> createState() => _TagSettingsPageState();
}

class _TagSettingsPageState extends State<TagSettingsPage> {
  List<Tag> _tags = [];
  bool _isEditMode = false;
  // タグIDとタグオブジェクトのマッピングを保持
  Map<String, Tag> _tagsMap = {};
  // タグの並び順を保持するリスト（タグID）
  List<String> _tagOrder = [];
  // 選択されたタグIDのセット
  Set<String> _selectedTagIds = {};
  // アーカイブされたタグを表示するかどうか
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('tags')
            .get();

    // タグの情報をマップに保存
    final Map<String, Tag> tagsMap = {};
    for (final doc in snapshot.docs) {
      final tag = Tag.fromMap(doc.data());
      tagsMap[doc.id] = tag;
    }

    // 保存されている並び順を取得
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList('tag_order_${widget.groupId}') ?? [];

    // 保存されている順番に基づいてタグを並べる
    List<String> tagOrder = List.from(savedOrder);

    // 新しいタグを追加（保存されていない場合）
    for (final id in tagsMap.keys) {
      if (!tagOrder.contains(id)) {
        tagOrder.add(id);
      }
    }

    // 削除されたタグを除外
    tagOrder.removeWhere((id) => !tagsMap.containsKey(id));

    setState(() {
      _tagsMap = tagsMap;
      _tagOrder = tagOrder;
      // 並び順に基づいてタグリストを生成
      _tags = _tagOrder.map((id) => tagsMap[id]!).toList();
    });

    // 並び順を保存
    await _saveTagOrder();
  }

  // タグの並び順だけをローカルに保存
  Future<void> _saveTagOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('tag_order_${widget.groupId}', _tagOrder);
  }

  Future<void> _saveTags() async {
    final batch = FirebaseFirestore.instance.batch();
    final tagsRef = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('tags');

    // 既存ドキュメントを全削除
    final existing = await tagsRef.get();
    for (final doc in existing.docs) batch.delete(doc.reference);

    // タグの情報をFirestoreに保存（アーカイブ情報も含める）
    for (final tagId in _tagOrder) {
      final tag = _tagsMap[tagId]!;
      batch.set(
        tagsRef.doc(),
        Tag(
          name: tag.name,
          ratios: tag.ratios,
          color: tag.color,
          order: 0,
          archived: tag.archived,
        ).toMap(),
      );
    }

    await batch.commit();
    await _loadTags();
  }

  // タグの順番を変更
  void _reorderTags(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final tagId = _tagOrder.removeAt(oldIndex);
      _tagOrder.insert(newIndex, tagId);
      // 並び順に基づいてタグリストを再生成
      _tags = _tagOrder.map((id) => _tagsMap[id]!).toList();
    });
    _saveTagOrder();
  }

  // タグが支払い記録で使用されているかどうかをチェック
  Future<bool> _isTagUsedInPayments(String tagName) async {
    final paymentsSnapshot =
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('payments')
            .where('category', isEqualTo: tagName)
            .limit(1)
            .get();

    return paymentsSnapshot.docs.isNotEmpty;
  }

  // タグの削除確認と実行
  Future<void> _confirmAndDeleteTag(String tagId, String tagName) async {
    // タグが支払い記録で使用されているかチェック
    final isUsed = await _isTagUsedInPayments(tagName);

    // 警告メッセージを設定
    final message =
        isUsed
            ? 'このタグは支払い記録で使用されています。使用されている支払い記録に色の表示がなくなりますが、削除しますか？'
            : 'このタグを削除してもよろしいですか？';

    // 確認ダイアログを表示
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('タグの削除'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('削除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      setState(() {
        // タグを削除
        _tagOrder.remove(tagId);
        _tagsMap.remove(tagId);
        _tags = _tagOrder.map((id) => _tagsMap[id]!).toList();
      });
      await _saveTagOrder();
      await _saveTags();
    }
  }

  // タグを一括削除
  Future<void> _deleteSelectedTags() async {
    if (_selectedTagIds.isEmpty) return;

    // 選択されたタグのうち、使用されているものをカウント
    int usedTagsCount = 0;
    for (final tagId in _selectedTagIds) {
      final tagName = _tagsMap[tagId]?.name ?? '';
      if (await _isTagUsedInPayments(tagName)) {
        usedTagsCount++;
      }
    }

    // 警告メッセージを設定
    String message;
    if (usedTagsCount > 0) {
      message =
          '${_selectedTagIds.length}個のタグを削除しようとしています。\n'
          'そのうち$usedTagsCount個のタグは支払い記録で使用されています。\n\n'
          '削除すると、既存の支払い記録からも削除されます。よろしいですか？';
    } else {
      message = '${_selectedTagIds.length}個のタグを削除してもよろしいですか？';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('タグの削除'),
            content: Text(message),
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
      setState(() {
        // 選択されたタグを削除
        _tagOrder.removeWhere((id) => _selectedTagIds.contains(id));
        for (final id in _selectedTagIds) {
          _tagsMap.remove(id);
        }
        _tags = _tagOrder.map((id) => _tagsMap[id]!).toList();
        _selectedTagIds.clear();
      });
      await _saveTagOrder();
      await _saveTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: fetchMemberNamesList(widget.groupId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final memberNames = snap.data ?? ['メンバー1', 'メンバー2'];
        final member1 = memberNames.isNotEmpty ? memberNames[0] : 'メンバー1';
        final member2 = memberNames.length > 1 ? memberNames[1] : 'メンバー2';

        // アクティブなタグとアーカイブされたタグに分ける
        final activeTags = <String>[];
        final archivedTags = <String>[];

        for (final tagId in _tagOrder) {
          if (_tagsMap[tagId]?.archived == true) {
            archivedTags.add(tagId);
          } else {
            activeTags.add(tagId);
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('タグ設定'),
            actions: [
              // 一括削除ボタン（編集モード時のみ表示）
              if (_isEditMode && _selectedTagIds.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: '選択したタグを削除',
                  onPressed: _deleteSelectedTags,
                ),
              // 編集モード切替ボタン
              IconButton(
                icon: Icon(
                  _isEditMode ? Icons.check : Icons.edit,
                  color: _isEditMode ? Colors.blue : null,
                ),
                tooltip: _isEditMode ? '完了' : '編集',
                onPressed:
                    () => setState(() {
                      _isEditMode = !_isEditMode;
                      if (!_isEditMode) {
                        _selectedTagIds.clear();
                      }
                    }),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // アクティブなタグのセクション
                const Text(
                  'アクティブなタグ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildTagSection(activeTags, member1, member2),

                // 新規タグ追加ボタン
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder:
                            (_) => _TagDialog(
                              myName: member1,
                              partnerName: member2,
                              groupId: widget.groupId,
                            ),
                      );
                      if (result != null && result['tag'] != null) {
                        final newTag = result['tag'] as Tag;
                        // 新しいタグをFirestoreに保存し、IDを取得
                        final docRef = await FirebaseFirestore.instance
                            .collection('groups')
                            .doc(widget.groupId)
                            .collection('tags')
                            .add(newTag.toMap());

                        setState(() {
                          // タグリストとマップを更新
                          _tagsMap[docRef.id] = newTag;
                          _tagOrder.add(docRef.id);
                          _tags.add(newTag);
                        });
                        _saveTagOrder();
                      }
                    },
                    child: const Text('タグを追加'),
                  ),
                ),

                // アーカイブされたタグのセクション（ヘッダー）
                if (archivedTags.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _showArchived = !_showArchived),
                    child: Row(
                      children: [
                        Text(
                          'アーカイブしたタグ (${archivedTags.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _showArchived
                              ? Icons.arrow_drop_up
                              : Icons.arrow_drop_down,
                        ),
                      ],
                    ),
                  ),

                // アーカイブされたタグのリスト（展開時のみ表示）
                if (archivedTags.isNotEmpty && _showArchived)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: _buildTagSection(archivedTags, member1, member2),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // タグセクションを構築するヘルパーメソッド
  Widget _buildTagSection(List<String> tagIds, String member1, String member2) {
    if (_isEditMode) {
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tagIds.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final tagId = tagIds.removeAt(oldIndex);
            tagIds.insert(newIndex, tagId);

            // 全体の順序リストも更新
            _tagOrder.clear();
            for (final activeTagId in tagIds.where(
              (id) => _tagsMap[id]?.archived == false,
            )) {
              _tagOrder.add(activeTagId);
            }
            for (final archivedTagId in tagIds.where(
              (id) => _tagsMap[id]?.archived == true,
            )) {
              _tagOrder.add(archivedTagId);
            }

            // タグリストを更新
            _tags = _tagOrder.map((id) => _tagsMap[id]!).toList();
          });
          _saveTagOrder();
        },
        itemBuilder: (context, index) {
          final tagId = tagIds[index];
          final tag = _tagsMap[tagId]!;
          final isSelected = _selectedTagIds.contains(tagId);

          return ListTile(
            key: ValueKey(tagId),
            leading: Checkbox(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedTagIds.add(tagId);
                  } else {
                    _selectedTagIds.remove(tagId);
                  }
                });
              },
            ),
            title: Text(tag.name),
            trailing: const Icon(Icons.drag_handle),
          );
        },
      );
    } else {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tagIds.length,
        itemBuilder: (ctx, idx) {
          final tagId = tagIds[idx];
          final tag = _tagsMap[tagId]!;
          return ListTile(
            leading: CircleAvatar(backgroundColor: tag.color),
            title: Text(tag.name),
            trailing:
                tag.archived
                    ? IconButton(
                      icon: const Icon(Icons.unarchive),
                      tooltip: 'アーカイブから戻す',
                      onPressed: () => _toggleArchive(tagId, false),
                    )
                    : IconButton(
                      icon: const Icon(Icons.archive),
                      tooltip: 'アーカイブする',
                      onPressed: () => _toggleArchive(tagId, true),
                    ),
            onTap: () async {
              final result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder:
                    (_) => _TagDialog(
                      initial: tag,
                      myName: member1,
                      partnerName: member2,
                      groupId: widget.groupId,
                    ),
              );
              if (result != null) {
                if (result['delete'] == true) {
                  // 削除確認ダイアログを表示
                  _confirmAndDeleteTag(tagId, tag.name);
                } else if (result['tag'] != null) {
                  setState(() {
                    // タグを更新
                    _tagsMap[tagId] = result['tag'] as Tag;
                    _tags = _tagOrder.map((id) => _tagsMap[id]!).toList();
                  });
                  _saveTags();
                } else if (result['archive'] != null) {
                  _toggleArchive(tagId, result['archive'] as bool);
                }
              }
            },
          );
        },
      );
    }
  }

  // タグのアーカイブ状態を切り替える
  Future<void> _toggleArchive(String tagId, bool archive) async {
    setState(() {
      // タグをアーカイブ状態に更新
      final currentTag = _tagsMap[tagId]!;
      _tagsMap[tagId] = Tag(
        name: currentTag.name,
        ratios: currentTag.ratios,
        color: currentTag.color,
        order: currentTag.order,
        archived: archive,
      );

      // タグリストを更新
      _tags = _tagOrder.map((id) => _tagsMap[id]!).toList();
    });

    // Firestoreに保存
    await _saveTags();
  }
}

class _TagDialog extends StatefulWidget {
  final Tag? initial;
  final String myName;
  final String partnerName;
  final String groupId;

  const _TagDialog({
    this.initial,
    required this.myName,
    required this.partnerName,
    required this.groupId,
  });

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late Map<int, int> _ratios;
  late Color _color;

  // 各メンバーの負担割合のコントローラー
  Map<int, TextEditingController> _ratioControllers = {};

  // メンバーのチェック状態 (有効/無効)
  Map<int, bool> _memberEnabled = {};

  // メンバーリスト
  List<String> _memberNames = [];

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
    // グレーは支払い記録の削除されたタグの場合のみ使用
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();

    // 基本的なメンバー情報を設定（最低でも2人）
    _memberNames = [widget.myName, widget.partnerName];

    // 必要に応じてFutureBuilderから追加のメンバー名を取得
    _loadMembers();

    if (widget.initial != null) {
      _name = widget.initial!.name;
      _ratios = Map.from(widget.initial!.ratios);
      _color = widget.initial!.color;

      // 色がリストにない場合はデフォルト色を使用
      if (!_colorOptions.contains(_color)) {
        _color = _findClosestColor(_color);
      }
    } else {
      _name = '';
      _ratios = {1: 1, 2: 1};
      _color = Colors.blue;
    }

    // 負担割合コントローラーとメンバー有効状態を初期化
    _initControllers();
  }

  // メンバー情報を読み込む
  Future<void> _loadMembers() async {
    try {
      final members = await fetchMemberNamesList(widget.groupId);
      if (members.length > _memberNames.length) {
        setState(() {
          _memberNames = members;
          // 新しいメンバーの負担割合を初期化
          for (int i = 0; i < members.length; i++) {
            final memberId = i + 1;
            if (!_ratios.containsKey(memberId)) {
              _ratios[memberId] = 1;
            }
          }
          // コントローラーを再初期化
          _initControllers();
        });
      }
    } catch (e) {
      // エラー時は何もしない（基本的なメンバー情報はすでに設定済み）
    }
  }

  // 負担割合コントローラーとメンバー有効状態を初期化
  void _initControllers() {
    // 既存のコントローラーを破棄
    for (final controller in _ratioControllers.values) {
      controller.dispose();
    }

    _ratioControllers = {};
    _memberEnabled = {};

    // 各メンバーのコントローラーと有効状態を初期化
    for (int i = 0; i < _memberNames.length; i++) {
      final memberId = i + 1;
      final ratio = _ratios[memberId] ?? 0;

      _ratioControllers[memberId] = TextEditingController(
        text: ratio.toString(),
      );

      // 比率が0より大きい場合は有効、それ以外は無効
      _memberEnabled[memberId] = ratio > 0;
    }
  }

  // メンバーの有効/無効を切り替える
  void _toggleMemberEnabled(int memberId, bool enabled) {
    setState(() {
      _memberEnabled[memberId] = enabled;
      if (enabled) {
        // 有効化された場合、前回の値または1を設定
        int ratio = _ratios[memberId] ?? 0;
        _ratios[memberId] = ratio == 0 ? 1 : ratio;
        _ratioControllers[memberId]?.text = '${_ratios[memberId]}';
      } else {
        // 無効化された場合、0を設定
        _ratios[memberId] = 0;
        _ratioControllers[memberId]?.text = '0';
      }
    });
  }

  // 最も近い色を見つける関数
  Color _findClosestColor(Color targetColor) {
    if (_colorOptions.contains(targetColor)) return targetColor;

    // デフォルトで青を返す
    return Colors.blue;
  }

  @override
  void dispose() {
    // すべてのコントローラーを破棄
    for (final controller in _ratioControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // 各メンバーの負担割合を更新
  void _updateRatios() {
    setState(() {
      _ratios = {};
      // 各メンバーの負担割合を更新
      for (final entry in _ratioControllers.entries) {
        final memberId = entry.key;
        final isEnabled = _memberEnabled[memberId] ?? true;
        if (isEnabled) {
          _ratios[memberId] = int.tryParse(entry.value.text) ?? 1;
        } else {
          _ratios[memberId] = 0;
        }
      }
    });
  }

  // メンバーの負担割合入力ウィジェットを生成
  Widget _buildMemberRatioInput(int memberId) {
    if (memberId > _memberNames.length) return const SizedBox();

    final memberName = _memberNames[memberId - 1];
    final isEnabled = _memberEnabled[memberId] ?? true;
    final hasThreeOrMoreMembers = _memberNames.length >= 3;

    return Row(
      children: [
        // メンバーが3人以上の場合のみチェックボックスを表示
        if (hasThreeOrMoreMembers)
          Checkbox(
            value: isEnabled,
            onChanged: (value) => _toggleMemberEnabled(memberId, value ?? true),
          ),
        // メンバー名（有効/無効で色を変える）
        Expanded(
          flex: 3,
          child: Text(
            memberName,
            style: TextStyle(
              color: isEnabled ? Colors.black : Colors.grey,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        const Text(': '),
        // 負担割合入力フィールド
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _ratioControllers[memberId],
            enabled: isEnabled,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              // v が null や空文字列、または整数以外の場合は 1 or 0 をデフォルトとする
              int value = 1;
              if (v != null && v.isNotEmpty) {
                value = int.tryParse(v) ?? (isEnabled ? 1 : 0);
              }
              setState(() {
                _ratios[memberId] = value;
              });
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial != null ? 'タグ編集' : 'タグ追加'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: 'タグ名'),
                onSaved: (v) => _name = v ?? '',
              ),
              const SizedBox(height: 16),
              const Text(
                '負担割合:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // 各メンバーの負担割合入力フィールドを2列表示で生成
              for (int i = 0; i < (_memberNames.length + 1) ~/ 2; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      // 左側のメンバー
                      Expanded(child: _buildMemberRatioInput(i * 2 + 1)),
                      const SizedBox(width: 16),
                      // 右側のメンバー（存在する場合）
                      Expanded(
                        child:
                            (i * 2 + 2) <= _memberNames.length
                                ? _buildMemberRatioInput(i * 2 + 2)
                                : const SizedBox(), // 空のウィジェットで2列目を埋める
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),
              DropdownButton<Color>(
                value: _color,
                onChanged: (v) => setState(() => _color = v!),
                items:
                    _colorOptions
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Row(
                              children: [
                                CircleAvatar(backgroundColor: c, radius: 8),
                                const SizedBox(width: 8),
                                Text(_getColorName(c)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initial != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // アーカイブボタン
              TextButton.icon(
                icon: Icon(
                  widget.initial!.archived ? Icons.unarchive : Icons.archive,
                ),
                label: Text(widget.initial!.archived ? 'アーカイブから戻す' : 'アーカイブする'),
                onPressed:
                    () => Navigator.pop(context, {
                      'archive': !widget.initial!.archived,
                    }),
              ),
              // 削除ボタン
              TextButton(
                onPressed: () => Navigator.pop(context, {'delete': true}),
                child: const Text('削除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () {
            _formKey.currentState?.save();
            _updateRatios();
            if (_name.isNotEmpty) {
              final archived = widget.initial?.archived ?? false;
              Navigator.pop(context, {
                'tag': Tag(
                  name: _name,
                  ratios: _ratios,
                  color: _color,
                  archived: archived,
                ),
              });
            }
          },
          child: Text(widget.initial != null ? '保存' : '追加'),
        ),
      ],
    );
  }

  // 色の名前を取得する関数
  String _getColorName(Color color) {
    if (color == Colors.red) return '赤';
    if (color == Colors.pink) return 'ピンク';
    if (color == Colors.purple) return '紫';
    if (color == Colors.deepPurple) return '濃い紫';
    if (color == Colors.indigo) return 'インディゴ';
    if (color == Colors.blue) return '青';
    if (color == Colors.lightBlue) return '水色';
    if (color == Colors.cyan) return 'シアン';
    if (color == Colors.teal) return 'ティール';
    if (color == Colors.green) return '緑';
    if (color == Colors.lightGreen) return '薄緑';
    if (color == Colors.lime) return 'ライム';
    if (color == Colors.yellow) return '黄色';
    if (color == Colors.amber) return '琥珀色';
    if (color == Colors.orange) return 'オレンジ';
    if (color == Colors.deepOrange) return '濃いオレンジ';
    if (color == Colors.brown) return '茶色';
    if (color == Colors.blueGrey) return 'ブルーグレー';
    return '色';
  }
}
