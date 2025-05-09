import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_split_app/models/payment.dart';
import 'package:couple_split_app/models/tag.dart';
import 'package:intl/intl.dart';

/// 支払い追加／編集ページ
/// onSave: 保存時に呼ばれるコールバック
/// onDelete: 編集時に削除時コールされるコールバック（新規追加なら null）
class AddPaymentPage extends StatefulWidget {
  final String groupId;
  final String myName;
  final String partnerName;
  final void Function(Payment payment) onSave;
  final VoidCallback? onDelete;
  final Payment? initial;

  const AddPaymentPage({
    super.key,
    required this.groupId,
    required this.myName,
    required this.partnerName,
    required this.onSave,
    this.onDelete,
    this.initial,
  });

  @override
  State<AddPaymentPage> createState() => _AddPaymentPageState();
}

class _AddPaymentPageState extends State<AddPaymentPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _itemController;
  late TextEditingController _amountController;
  int _payer = 1;
  Map<int, int> _ratios = {1: 1, 2: 1};
  DateTime _date = DateTime.now();
  String _category = '';
  List<Tag> _tags = [];
  Tag? _selectedTag;

  @override
  void initState() {
    super.initState();
    _loadTags();
    final init = widget.initial;
    _itemController = TextEditingController(text: init?.item ?? '');
    _amountController = TextEditingController(
      text: init != null ? '${init.amount}' : '',
    );
    _payer = init?.payer ?? 1;
    _ratios = init?.ratios ?? {1: 1, 2: 1};
    _date = init?.date ?? DateTime.now();
    _category = init?.category ?? '';
  }

  @override
  void dispose() {
    _itemController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    final snap =
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('tags')
            .orderBy('order')
            .get();
    setState(() {
      _tags = snap.docs.map((d) => Tag.fromMap(d.data())).toList();
      if (_tags.isNotEmpty) {
        _category = _tags.first.name;
        _selectedTag = _tags.first;
      }
    });
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    final payment = Payment(
      item: _itemController.text.trim(),
      amount: int.parse(_amountController.text),
      payer: _payer,
      ratios: Map.from(_ratios),
      category: _category,
      date: DateTime.now(),
    );
    widget.onSave(payment);
    Navigator.pop(context);
  }

  void _delete() {
    if (widget.onDelete != null) {
      widget.onDelete!();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '支払いを追加' : '支払いを編集'),
        actions: [
          if (widget.initial != null && widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder:
                      (_) => AlertDialog(
                        title: const Text('削除確認'),
                        content: const Text('この支払いを削除しますか？'),
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
                if (ok == true) _delete();
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _itemController,
                decoration: const InputDecoration(labelText: '項目名'),
                validator: (v) => v?.isEmpty == true ? '項目名を入力してください' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '金額'),
                validator:
                    (v) =>
                        (v == null || int.tryParse(v) == null)
                            ? '正しい金額を入力してください'
                            : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _payer,
                decoration: const InputDecoration(labelText: '支払者'),
                items: [
                  DropdownMenuItem(value: 1, child: Text(widget.myName)),
                  DropdownMenuItem(value: 2, child: Text(widget.partnerName)),
                ],
                onChanged: (v) => setState(() => _payer = v!),
              ),
              const SizedBox(height: 8),
              // 日付ピッカー
              ListTile(
                title: Text('日付: ${DateFormat.yMd().format(_date)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              const SizedBox(height: 8),
              // 割合入力
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: '${_ratios[1]}',
                      decoration: InputDecoration(
                        labelText: '${widget.myName} 単位',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged:
                          (v) =>
                              setState(() => _ratios[1] = int.tryParse(v) ?? 1),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: '${_ratios[2]}',
                      decoration: InputDecoration(
                        labelText: '${widget.partnerName} 単位',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged:
                          (v) =>
                              setState(() => _ratios[2] = int.tryParse(v) ?? 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // カテゴリ（タグ）選択をタイル形式で表示
              if (_tags.isNotEmpty)
                Wrap(
                  spacing: 8.0,
                  children:
                      _tags.map((tag) {
                        return ChoiceChip(
                          label: Text(tag.name),
                          selected: _category == tag.name,
                          selectedColor: tag.color,
                          backgroundColor: tag.color.withOpacity(0.3),
                          onSelected: (selected) {
                            setState(() {
                              _category = selected ? tag.name : _category;
                              _selectedTag = selected ? tag : _selectedTag;
                            });
                          },
                        );
                      }).toList(),
                ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _save, child: const Text('保存')),
            ],
          ),
        ),
      ),
    );
  }
}
