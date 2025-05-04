import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tag.dart';
import '../models/payment.dart';

class AddPaymentPage extends StatefulWidget {
  final Payment? initial;
  final bool isEditing;
  final String member1Name;
  final String member2Name;

  const AddPaymentPage({
    super.key,
    this.initial,
    required String myName,
    required String partnerName,
  })  : member1Name = myName,
        member2Name = partnerName,
        isEditing = initial != null;

  @override
  State<AddPaymentPage> createState() => _AddPaymentPageState();
}

class _AddPaymentPageState extends State<AddPaymentPage> {
  final _formKey = GlobalKey<FormState>();
  late String _item;
  late int _amount;
  late int _payer;
  late DateTime _date;
  List<Tag> _tags = [];
  Tag? _selectedTag;
  Map<int, int> _ratios = {1: 1, 2: 1};
  final TextEditingController _ratio1Controller = TextEditingController();
  final TextEditingController _ratio2Controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _item = widget.initial?.item ?? '';
    _amount = widget.initial?.amount ?? 0;
    _payer = widget.initial?.payer ?? 1;
    _date = widget.initial?.date ?? DateTime.now();
    if (widget.initial != null) {
      _ratios = Map<int, int>.from(widget.initial!.ratios);
    }
    _ratio1Controller.text = _ratios[1]?.toString() ?? '1';
    _ratio2Controller.text = _ratios[2]?.toString() ?? '1';
    FirebaseFirestore.instance.collection('tags').get().then((snapshot) {
      final tags = snapshot.docs.map((doc) => Tag.fromMap(doc.data())).toList();
      setState(() {
        _tags = tags;
        if (_tags.isNotEmpty) {
          _selectedTag = widget.initial != null
              ? _tags.firstWhere(
                  (tag) => tag.name == widget.initial!.category,
                  orElse: () => _tags.first,
                )
              : _tags.first;
        }
      });
    });
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
    final totalUnits = _ratios.values.reduce((a, b) => a + b);
    final myShare = totalUnits > 0 ? (_amount * (_ratios[1]! / totalUnits)).round() : 0;
    final partnerShare = totalUnits > 0 ? (_amount * (_ratios[2]! / totalUnits)).round() : 0;
    final diff = _payer == 1 ? (_amount - myShare) : -myShare;

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? '支払いを編集' : '支払いを追加')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                initialValue: _item,
                decoration: const InputDecoration(labelText: '項目名'),
                onSaved: (v) => _item = v ?? '',
              ),
              TextFormField(
                initialValue: _amount == 0 ? '' : '$_amount',
                decoration: const InputDecoration(labelText: '金額'),
                keyboardType: TextInputType.number,
                onSaved: (v) => _amount = int.tryParse(v ?? '0') ?? 0,
              ),
              DropdownButtonFormField<int>(
                value: _payer,
                items: [
                  DropdownMenuItem(value: 1, child: Text(widget.member1Name)),
                  DropdownMenuItem(value: 2, child: Text(widget.member2Name)),
                ],
                onChanged: (v) => setState(() => _payer = v ?? 1),
                decoration: const InputDecoration(labelText: '支払者'),
              ),
              if (_tags.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: _tags.map((tag) {
                    final isSelected = _selectedTag?.name == tag.name;
                    return ChoiceChip(
                      label: Text(tag.name, style: const TextStyle(color: Colors.white)),
                      selectedColor: tag.color,
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedTag = tag;
                          _ratios = Map<int, int>.from(tag.ratios);
                          _ratio1Controller.text = _ratios[1]?.toString() ?? '1';
                          _ratio2Controller.text = _ratios[2]?.toString() ?? '1';
                        });
                      },
                      backgroundColor: tag.color.withOpacity(0.4),
                    );
                  }).toList(),
                ),
              ListTile(
                title: Text('日付: ${_date.year}年${_date.month}月${_date.day}日'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    locale: const Locale('ja'),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ratio1Controller,
                      decoration: InputDecoration(labelText: '${widget.member1Name}の単位'),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _updateRatiosFromText(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _ratio2Controller,
                      decoration: InputDecoration(labelText: '${widget.member2Name}の単位'),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _updateRatiosFromText(),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                child: Text(
                  '${widget.member1Name}の負担額: $myShare 円\n'
                  '${widget.member2Name}の負担額: $partnerShare 円\n'
                  '差額（${widget.member1Name}基準）: $diff 円',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.isEditing)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete),
                      label: const Text('削除'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('削除の確認'),
                            content: const Text('この支払いを削除してもよろしいですか？'),
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
                          Navigator.pop(context, PaymentAction(delete: true));
                        }
                      },
                    ),
                  ElevatedButton(
                    child: Text(widget.isEditing ? '保存' : '追加'),
                    onPressed: () {
                      _formKey.currentState?.save();
                      _updateRatiosFromText();
                      if (_item.isNotEmpty && _amount > 0 && _ratios[1]! > 0 && _ratios[2]! > 0) {
                        final payment = Payment(
                          item: _item,
                          amount: _amount,
                          payer: _payer,
                          ratios: Map<int, int>.from(_ratios),
                          category: _selectedTag?.name ?? 'その他',
                          date: _date,
                        );
                        Navigator.pop(context, PaymentAction(delete: false, updated: payment));
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
