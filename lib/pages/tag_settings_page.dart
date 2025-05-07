import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/member_service.dart';
import '../models/tag.dart';

class TagSettingsPage extends StatefulWidget {
  final String groupId;

  const TagSettingsPage({
    super.key,
    required this.groupId,
  });

  @override
  State<TagSettingsPage> createState() => _TagSettingsPageState();
}

class _TagSettingsPageState extends State<TagSettingsPage> {
  List<Tag> _tags = [];
  bool _isReorderMode = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final snapshot = await FirebaseFirestore.instance
      .collection('groups')
      .doc(widget.groupId)
      .collection('tags')
      .orderBy('order')
      .get();
    setState(() {
      _tags = snapshot.docs.map((d) => Tag.fromMap(d.data())).toList();
    });
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

    // 新しい順序で書き込み
    for (int i = 0; i < _tags.length; i++) {
      final t = _tags[i];
      batch.set(tagsRef.doc(), Tag(
        name: t.name,
        ratios: t.ratios,
        color: t.color,
        order: i,
      ).toMap());
    }
    await batch.commit();
    _loadTags();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: fetchMemberNamesList(widget.groupId),
      builder: (ctx, snap) {
        final memberNames = snap.data ?? [];
        final member1 = memberNames[0];
        final member2 = memberNames[1];

        return Scaffold(
          appBar: AppBar(
            title: const Text('タグ設定'),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.sort,
                  color: _isReorderMode ? Colors.blue : Colors.white,
                ),
                tooltip: _isReorderMode ? '並び替え終了' : '並び替え開始',
                onPressed: () => setState(() => _isReorderMode = !_isReorderMode),
              ),
            ],
          ),
          body: _isReorderMode
              ? _buildReorderableList()
              : _buildTagList(member1, member2),
        );
      },
    );
  }

  Widget _buildReorderableList() {
    return ReorderableListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in _tags.asMap().entries)
          ListTile(
            key: ValueKey('tag_${entry.key}_${entry.value.name}'),
            leading: const Icon(Icons.drag_handle),
            title: Text(entry.value.name),
          ),
      ],
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final tag = _tags.removeAt(oldIndex);
          _tags.insert(newIndex, tag);
        });
        _saveTags();
      },
    );
  }

  Widget _buildTagList(String member1, String member2) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tags.length + 1,
      itemBuilder: (ctx, idx) {
        if (idx < _tags.length) {
          final tag = _tags[idx];
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
                  setState(() => _tags.removeAt(idx));
                } else if (result['tag'] != null) {
                  setState(() => _tags[idx] = result['tag'] as Tag);
                }
                _saveTags();
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
                  builder: (_) => _TagDialog(
                    myName: member1,
                    partnerName: member2,
                  ),
                );
                if (result != null && result['tag'] != null) {
                  setState(() => _tags.add(result['tag'] as Tag));
                  _saveTags();
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
  const _TagDialog({this.initial, required this.myName, required this.partnerName});

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late Map<int,int> _ratios;
  late Color _color;
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _name   = widget.initial!.name;
      _ratios = Map.from(widget.initial!.ratios);
      _color  = widget.initial!.color;
    } else {
      _name   = '';
      _ratios = {1:1,2:1};
      _color  = Colors.blue;
    }
    _c1.text = _ratios[1].toString();
    _c2.text = _ratios[2].toString();
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            initialValue: _name,
            decoration: const InputDecoration(labelText: 'タグ名'),
            onSaved: (v) => _name = v ?? '',
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _c1,
                decoration: InputDecoration(labelText: '${widget.myName}割合'),
                keyboardType: TextInputType.number,
                onChanged: (_) => _updateRatios(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _c2,
                decoration: InputDecoration(labelText: '${widget.partnerName}割合'),
                keyboardType: TextInputType.number,
                onChanged: (_) => _updateRatios(),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          DropdownButton<Color>(
            value: _color,
            onChanged: (v) => setState(() => _color = v!),
            items: [Colors.red, Colors.green, Colors.blue, Colors.orange, Colors.purple]
              .map((c) => DropdownMenuItem(
                value: c,
                child: Row(children: [
                  CircleAvatar(backgroundColor: c, radius: 8),
                  const SizedBox(width: 8),
                  Text(c.toString().split('.').last),
                ]),
              ))
              .toList(),
          ),
        ]),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('削除しますか？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
                  ],
                ),
              );
              if (ok == true) Navigator.pop(context, {'delete': true});
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        ElevatedButton(
          onPressed: () {
            _formKey.currentState?.save();
            _updateRatios();
            if (_name.isNotEmpty) {
              Navigator.pop(context, {'tag': Tag(name: _name, ratios: _ratios, color: _color)});
            }
          },
          child: Text(widget.initial != null ? '保存' : '追加'),
        ),
      ],
    );
  }
}