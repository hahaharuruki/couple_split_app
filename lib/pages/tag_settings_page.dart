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

    // タグの情報をFirestoreに保存（並び順は保存しない）
    for (final tag in _tags) {
      batch.set(
        tagsRef.doc(),
        Tag(name: tag.name, ratios: tag.ratios, color: tag.color, order: 0).toMap(),
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

  // タグを一括削除
  Future<void> _deleteSelectedTags() async {
    if (_selectedTagIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('タグの削除'),
        content: Text('${_selectedTagIds.length}個のタグを削除してもよろしいですか？'),
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
                onPressed: () => setState(() {
                  _isEditMode = !_isEditMode;
                  if (!_isEditMode) {
                    _selectedTagIds.clear();
                  }
                }),
              ),
            ],
          ),
          body: _buildTagList(member1, member2),
        );
      },
    );
  }

  Widget _buildTagList(String member1, String member2) {
    return _isEditMode
        ? ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _tags.length,
            onReorder: _reorderTags,
            itemBuilder: (context, index) {
              final tagId = _tagOrder[index];
              final tag = _tags[index];
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
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _tags.length + 1,
            itemBuilder: (ctx, idx) {
              if (idx < _tags.length) {
                final tag = _tags[idx];
                final tagId = _tagOrder[idx];
                return ListTile(
                  leading: CircleAvatar(backgroundColor: tag.color),
                  title: Text(tag.name),
                  onTap: () async {
                    final result = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => _TagDialog(
                        initial: tag,
                        myName: member1,
                        partnerName: member2,
                      ),
                    );
                    if (result != null) {
                      if (result['delete'] == true) {
                        setState(() {
                          // タグを削除
                          _tagOrder.removeAt(idx);
                          _tagsMap.remove(tagId);
                          _tags.removeAt(idx);
                        });
                        _saveTagOrder();
                        _saveTags();
                      } else if (result['tag'] != null) {
                        setState(() {
                          // タグを更新
                          _tags[idx] = result['tag'] as Tag;
                          _tagsMap[tagId] = result['tag'] as Tag;
                        });
                        _saveTags();
                      }
                    }
                  },
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => _TagDialog(myName: member1, partnerName: member2),
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
                );
              }
            },
          );
  }
}

class _TagDialog extends StatefulWidget {
  final Tag? initial;
  final String myName;
  final String partnerName;
  const _TagDialog({
    this.initial,
    required this.myName,
    required this.partnerName,
  });

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late Map<int, int> _ratios;
  late Color _color;
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();

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
    Colors.grey,
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();
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
    _c1.text = _ratios[1].toString();
    _c2.text = _ratios[2].toString();
  }

  // 最も近い色を見つける関数
  Color _findClosestColor(Color targetColor) {
    if (_colorOptions.contains(targetColor)) return targetColor;

    // デフォルトで青を返す
    return Colors.blue;
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  void _updateRatios() {
    setState(() {
      _ratios = {
        1: int.tryParse(_c1.text) ?? 1,
        2: int.tryParse(_c2.text) ?? 1,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial != null ? 'タグ編集' : 'タグ追加'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: _name,
              decoration: const InputDecoration(labelText: 'タグ名'),
              onSaved: (v) => _name = v ?? '',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _c1,
                    decoration: InputDecoration(
                      labelText: '${widget.myName}の割合',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateRatios(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _c2,
                    decoration: InputDecoration(
                      labelText: '${widget.partnerName}の割合',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateRatios(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder:
                    (_) => AlertDialog(
                      title: const Text('削除しますか？'),
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
              if (ok == true) Navigator.pop(context, {'delete': true});
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
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
              Navigator.pop(context, {
                'tag': Tag(name: _name, ratios: _ratios, color: _color),
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
    if (color == Colors.grey) return 'グレー';
    if (color == Colors.blueGrey) return 'ブルーグレー';
    return '色';
  }
}
