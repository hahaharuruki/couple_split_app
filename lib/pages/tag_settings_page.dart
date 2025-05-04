

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tag.dart';

class TagSettingsPage extends StatefulWidget {
  final String myName;
  final String partnerName;

  const TagSettingsPage({super.key, required this.myName, required this.partnerName});

  @override
  State<TagSettingsPage> createState() => _TagSettingsPageState();
}

class _TagSettingsPageState extends State<TagSettingsPage> {
  List<Tag> _tags = [];
  String? _defaultTagName;

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('tags').get().then((snapshot) {
      setState(() {
        _tags = snapshot.docs.map((doc) => Tag.fromMap(doc.data())).toList();
      });
    });
    FirebaseFirestore.instance.collection('settings').doc('defaultTag').get().then((doc) {
      if (doc.exists && doc.data() != null) {
        setState(() {
          _defaultTagName = doc.data()!['name'];
        });
      }
    });
  }

  Future<void> _saveTags() async {
    final batch = FirebaseFirestore.instance.batch();
    final tagsCollection = FirebaseFirestore.instance.collection('tags');
    final snapshot = await tagsCollection.get();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    for (final t in _tags) {
      batch.set(tagsCollection.doc(), t.toMap());
    }
    await batch.commit();
    await FirebaseFirestore.instance.collection('settings').doc('defaultTag').set({
      'name': _defaultTagName ?? '',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('タグ設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._tags.asMap().entries.map((entry) {
            final index = entry.key;
            final tag = entry.value;
            return ListTile(
              leading: CircleAvatar(backgroundColor: tag.color),
              title: Row(
                children: [
                  Text(tag.name),
                  if (_defaultTagName == tag.name)
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Text('デフォルト', style: TextStyle(fontSize: 12, color: Colors.pink)),
                    ),
                ],
              ),
              onTap: () async {
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => TagDialog(
                    initial: tag,
                    myName: widget.myName,
                    partnerName: widget.partnerName,
                    isDefault: _defaultTagName == tag.name,
                  ),
                );
                if (result != null) {
                  if (result['delete'] == true) {
                    setState(() {
                      _tags.removeAt(index);
                    });
                    _saveTags();
                  } else if (result['tag'] != null) {
                    setState(() {
                      _tags[index] = result['tag'] as Tag;
                      if (result['makeDefault'] == true) {
                        _defaultTagName = (result['tag'] as Tag).name;
                      }
                    });
                    _saveTags();
                  }
                }
              },
              onLongPress: () async {
                if (_defaultTagName == tag.name) {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('削除できません'),
                      content: Text('デフォルトのタグ「${tag.name}」は削除できません。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                  return;
                }
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('削除の確認'),
                    content: Text('タグ「${tag.name}」を削除しますか？'),
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
                if (confirm == true) {
                  setState(() {
                    _tags.removeAt(index);
                  });
                  _saveTags();
                }
              },
            );
          }),
          ElevatedButton(
            onPressed: () async {
              final result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => TagDialog(
                  myName: widget.myName,
                  partnerName: widget.partnerName,
                  isDefault: false,
                ),
              );
              if (result != null && result['tag'] != null) {
                setState(() {
                  _tags.add(result['tag'] as Tag);
                  if (result['makeDefault'] == true) {
                    _defaultTagName = (result['tag'] as Tag).name;
                  }
                });
                _saveTags();
              }
            },
            child: const Text('タグを追加'),
          ),
        ],
      ),
    );
  }
}

class TagDialog extends StatefulWidget {
  final Tag? initial;
  final String myName;
  final String partnerName;
  final bool isDefault;
  const TagDialog({this.initial, required this.myName, required this.partnerName, this.isDefault = false});

  @override
  State<TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<TagDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late Map<int, int> _ratios;
  late Color _color;
  late bool makeDefault;
  final TextEditingController _ratio1Controller = TextEditingController();
  final TextEditingController _ratio2Controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _name = widget.initial!.name;
      _ratios = Map<int, int>.from(widget.initial!.ratios);
      _color = widget.initial!.color;
    } else {
      _name = '';
      _ratios = {1: 1, 2: 1};
      _color = Colors.blue;
    }
    makeDefault = widget.isDefault;
    _ratio1Controller.text = _ratios[1]?.toString() ?? '1';
    _ratio2Controller.text = _ratios[2]?.toString() ?? '1';
  }

  @override
  void dispose() {
    _ratio1Controller.dispose();
    _ratio2Controller.dispose();
    super.dispose();
  }

  void _updateRatiosFromText() {
    final r1 = int.tryParse(_ratio1Controller.text) ?? 1;
    final r2 = int.tryParse(_ratio2Controller.text) ?? 1;
    setState(() {
      _ratios = {1: r1, 2: r2};
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> predefinedColors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.yellow,
      Colors.brown,
    ];
    return AlertDialog(
      title: Text(widget.initial != null ? 'タグを編集' : 'タグを追加'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: _name,
              decoration: const InputDecoration(labelText: '名前'),
              onSaved: (v) => _name = v ?? '',
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ratio1Controller,
                    decoration: InputDecoration(labelText: '${widget.myName}の単位'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateRatiosFromText(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _ratio2Controller,
                    decoration: InputDecoration(labelText: '${widget.partnerName}の単位'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateRatiosFromText(),
                  ),
                ),
              ],
            ),
            DropdownButton<Color>(
              value: _color,
              onChanged: (v) => setState(() => _color = v!),
              items: predefinedColors.map((color) {
                return DropdownMenuItem<Color>(
                  value: color,
                  child: Row(
                    children: [
                      CircleAvatar(backgroundColor: color, radius: 8),
                      const SizedBox(width: 8),
                      Text(
                        {
                          Colors.red: '赤',
                          Colors.green: '緑',
                          Colors.blue: '青',
                          Colors.orange: 'オレンジ',
                          Colors.purple: '紫',
                          Colors.yellow: '黄',
                          Colors.brown: '茶',
                        }[color] ?? '色',
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            CheckboxListTile(
              value: makeDefault,
              title: const Text('デフォルトにする'),
              onChanged: (v) => setState(() => makeDefault = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () async {
              if (widget.isDefault) {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('削除できません'),
                    content: Text('デフォルトのタグ「${widget.initial?.name ?? ''}」は削除できません。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
                return;
              }
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('削除の確認'),
                  content: const Text('このタグを削除してもよろしいですか？'),
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
              if (confirm == true) {
                Navigator.pop(context, {
                  'delete': true,
                  'tag': widget.initial,
                });
              }
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          child: Text(widget.initial != null ? '保存' : '追加'),
          onPressed: () {
            _formKey.currentState?.save();
            _updateRatiosFromText();
            if (_name.isNotEmpty && _ratios[1]! > 0 && _ratios[2]! > 0) {
              Navigator.pop(context, {
                'tag': Tag(name: _name, ratios: Map<int, int>.from(_ratios), color: _color),
                'makeDefault': makeDefault,
              });
            }
          },
        ),
      ],
    );
  }
}