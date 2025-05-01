import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const CoupleSplitApp());

class CoupleSplitApp extends StatelessWidget {
  const CoupleSplitApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Couple Split App',
      theme: ThemeData(primarySwatch: Colors.pink),
      home: const HomePage(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja', '')],
    );
  }
}

class Payment {
  final String item;
  final int amount;
  final String payer;
  final double myRatio;
  DateTime date;

  Payment({
    required this.item,
    required this.amount,
    required this.payer,
    required this.myRatio,
    required this.date,
  });

  double get myShare => amount * myRatio;
  double get partnerShare => amount * (1 - myRatio);
  double getMySettlement() {
    // Positive: you should receive money; Negative: you owe money
    if (payer == '自分') {
      // You paid the full amount, so partner owes you: amount minus your share
      return amount - myShare;
    } else {
      // Partner paid, so you owe your share as a negative settlement
      return -myShare;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'item': item,
      'amount': amount,
      'payer': payer,
      'myRatio': myRatio,
      'date': date.toIso8601String(),
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      item: map['item'],
      amount: map['amount'],
      payer: map['payer'],
      myRatio: map['myRatio'],
      date: map.containsKey('date') ? DateTime.parse(map['date']) : DateTime.now(),
    );
  }
}

class PaymentAction {
  final bool delete;
  final Payment? updated;
  PaymentAction({required this.delete, this.updated});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Payment> payments = [];
  String _myName = '自分';
  String _partnerName = '相手';
  Set<int> _selectedIndexes = {};
  bool _isEditingMode = false;
  String _selectedMonth = "${DateTime.now().year.toString().padLeft(4, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}";
  Set<String> _settledMonths = {};

  List<String> _generatePastMonths() {
    final now = DateTime.now();
    List<String> months = [];
    for (int i = 0; i < 13; i++) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add("${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}");
    }
    return months;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPayments();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myName = prefs.getString('myName') ?? '自分';
      _partnerName = prefs.getString('partnerName') ?? '相手';
    });
  }

  Future<void> _saveSettings(String myName, String partnerName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('myName', myName);
    await prefs.setString('partnerName', partnerName);
    setState(() {
      _myName = myName;
      _partnerName = partnerName;
    });
  }

  Future<void> _loadPayments() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('payments') ?? [];
    final settledData = prefs.getStringList('settledMonths') ?? [];
    setState(() {
      payments = data.map((p) => Payment.fromMap(jsonDecode(p) as Map<String, dynamic>)).toList();
      _settledMonths = settledData.toSet();
    });
  }

  Future<void> _savePayments() async {
    final prefs = await SharedPreferences.getInstance();
    final data = payments.map((p) => jsonEncode(p.toMap())).toList();
    await prefs.setStringList('payments', data);
    await prefs.setStringList('settledMonths', _settledMonths.toList());
  }

  void _addPayment(Payment payment) {
    setState(() {
      payments.add(payment);
    });
    _savePayments();
  }

  void _updatePayment(int index, Payment updated) {
    setState(() {
      payments[index] = updated;
    });
    _savePayments();
  }

  void _removePayment(int index) {
    setState(() {
      payments.removeAt(index);
    });
    _savePayments();
  }

  void _removeSelectedPayments() {
    setState(() {
      final selected = _selectedIndexes.toList()..sort((a, b) => b.compareTo(a));
      for (var i in selected) {
        payments.removeAt(i);
      }
      _selectedIndexes.clear();
    });
    _savePayments();
  }

  double get totalAmount => payments
      .where((p) => p.date.year.toString().padLeft(4, '0') + '-' + p.date.month.toString().padLeft(2, '0') == _selectedMonth)
      .fold(0, (sum, p) => sum + p.amount);

  double get totalSettlement => payments
      .where((p) => p.date.year.toString().padLeft(4, '0') + '-' + p.date.month.toString().padLeft(2, '0') == _selectedMonth)
      .fold(0, (sum, p) => sum + p.getMySettlement());

  @override
  Widget build(BuildContext context) {
    final roundedSettlement = totalSettlement.round();
    final isSettled = _settledMonths.contains(_selectedMonth);
    final settlementMessage = isSettled
        ? '精算済み'
        : roundedSettlement == 0
            ? '精算は不要です'
            : roundedSettlement < 0
                ? 'あなたは$_partnerNameに ${-roundedSettlement} 円支払う必要があります'
                : 'あなたは$_partnerNameから ${roundedSettlement} 円もらう必要があります';

    final monthly = payments.where((p) => p.date.year.toString().padLeft(4, '0') + '-' + p.date.month.toString().padLeft(2, '0') == _selectedMonth);
    final myShareTotal = monthly.fold(0.0, (sum, p) => sum + p.myShare);
    final partnerShareTotal = monthly.fold(0.0, (sum, p) => sum + p.partnerShare);

    return Scaffold(
      appBar: AppBar(
        title: const Text('カップル割り勘アプリ'),
        actions: [
          if (!_isEditingMode)
            IconButton(icon: const Icon(Icons.edit), tooltip: '編集', onPressed: () => setState(() => _isEditingMode = true)),
          if (_isEditingMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全選択',
              onPressed: () => setState(() {
                if (_selectedIndexes.length == payments.length) {
                  _selectedIndexes.clear();
                } else {
                  _selectedIndexes = Set<int>.from(List.generate(payments.length, (i) => i));
                }
              }),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: '選択削除',
              onPressed: _selectedIndexes.isEmpty
                  ? null
                  : () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('確認'),
                          content: const Text('選択した履歴を削除しますか？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                            TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _removeSelectedPayments();
                                },
                                child: const Text('削除')),
                          ],
                        ),
                      ),
            ),
            IconButton(icon: const Icon(Icons.edit), tooltip: '編集終了', onPressed: () => setState(() {
                  _isEditingMode = false;
                  _selectedIndexes.clear();
                })),
          ],
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () async {
              final result = await Navigator.push<Map<String, String>>(
                context,
                MaterialPageRoute(builder: (_) => SettingsPage(myName: _myName, partnerName: _partnerName)),
              );
              if (result != null) {
                _saveSettings(result['myName'] ?? _myName, result['partnerName'] ?? _partnerName);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text("${_selectedMonth.split('-')[0]}年", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _generatePastMonths().map((m) {
                final monthNum = int.parse(m.split('-')[1]);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text("$monthNum月"),
                    selected: m == _selectedMonth,
                    onSelected: (_) => setState(() => _selectedMonth = m),
                  ),
                );
              }).toList(),
            ),
          ),
          Text('合計支出：${totalAmount.round()} 円', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          Text('$_myName：${myShareTotal.round()}円　$_partnerName：${partnerShareTotal.round()}円',
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
          Text(settlementMessage, style: const TextStyle(fontSize: 16)),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: monthly.length + 1,
              itemBuilder: (context, idx) {
                if (idx < monthly.length) {
                  final entry = monthly.elementAt(idx);
                  final index = payments.indexOf(entry);
                  final p = entry;
                  final payerDisplay = p.payer == '自分' ? _myName : p.payer == '相手' ? _partnerName : p.payer;
                  final isThisYear = p.date.year == DateTime.now().year;
                  final formattedDate = isThisYear
                      ? "${p.date.month}月${p.date.day}日"
                      : "${p.date.year}年${p.date.month}月${p.date.day}日";
                  final myShare = p.myShare.round();
                  final settlement = p.getMySettlement().round();
                  return ListTile(
                    leading: _isEditingMode
                        ? Checkbox(
                            value: _selectedIndexes.contains(index),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selectedIndexes.add(index);
                              } else {
                                _selectedIndexes.remove(index);
                              }
                            }),
                          )
                        : null,
                    title: Text('${p.item} - ${p.amount}円'),
                    subtitle: Text('$formattedDate｜支払者: $payerDisplay｜自分の負担: ${myShare}円｜差額: ${settlement}円'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final result = await Navigator.push<PaymentAction>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddPaymentPage(initial: p, myName: _myName, partnerName: _partnerName),
                        ),
                      );
                      if (result != null) {
                        setState(() {
                          if (result.delete) {
                            _removePayment(index);
                          } else if (result.updated != null) {
                            _updatePayment(index, result.updated!);
                          }
                        });
                      }
                    },
                  );
                }
                // Custom: 精算済みにする or 未精算に戻すボタン
                else if (!_settledMonths.contains(_selectedMonth)) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('精算確認'),
                            content: const Text('この月を「精算済み」にしますか？\n後から「未精算」に戻すこともできます。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('キャンセル'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  setState(() {
                                    _settledMonths.add(_selectedMonth);
                                  });
                                  _savePayments();
                                },
                                child: const Text('精算する'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('この月を精算済みにする'),
                    ),
                  );
                }
                else if (_settledMonths.contains(_selectedMonth)) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('未精算に戻す確認'),
                            content: const Text('この月の「精算済み」状態を取り消して、未精算に戻しますか？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('キャンセル'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  setState(() {
                                    _settledMonths.remove(_selectedMonth);
                                  });
                                  _savePayments();
                                },
                                child: const Text('未精算に戻す'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('未精算に戻す'),
                    ),
                  );
                }
                else {
                  return const SizedBox.shrink();
                }
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton(
          child: const Text('支払いを追加'),
          onPressed: () async {
            final result = await Navigator.push<PaymentAction>(
              context,
              MaterialPageRoute(builder: (_) => AddPaymentPage(myName: _myName, partnerName: _partnerName)),
            );
            if (result != null && !result.delete && result.updated != null) {
              final payment = result.updated!..date = DateTime.now();
              _addPayment(payment);
            }
          },
        ),
      ),
    );
  }
}

class AddPaymentPage extends StatefulWidget {
  final Payment? initial;
  final bool isEditing;
  final String myName;
  final String partnerName;

  const AddPaymentPage({super.key, this.initial, required this.myName, required this.partnerName})
      : isEditing = initial != null;

  @override
  State<AddPaymentPage> createState() => _AddPaymentPageState();
}

class _AddPaymentPageState extends State<AddPaymentPage> {
  final _formKey = GlobalKey<FormState>();
  late String _item;
  late int _amount;
  late String _payer;
  late double _myRatio;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _item = widget.initial?.item ?? '';
    _amount = widget.initial?.amount ?? 0;
    _payer = widget.initial?.payer ?? '自分';
    _myRatio = widget.initial?.myRatio ?? 0.7;
    _date = widget.initial?.date ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
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
              DropdownButtonFormField<String>(
                value: _payer,
                items: [
                  DropdownMenuItem(value: '自分', child: Text(widget.myName)),
                  DropdownMenuItem(value: '相手', child: Text(widget.partnerName)),
                ],
                onChanged: (v) => setState(() => _payer = v ?? '自分'),
                decoration: const InputDecoration(labelText: '支払者'),
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
              Slider(
                label: '負担割合: ${(_myRatio * 100).round()}%',
                value: _myRatio,
                min: 0,
                max: 1,
                divisions: 10,
                onChanged: (v) => setState(() => _myRatio = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.isEditing)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete),
                      label: const Text('削除'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, PaymentAction(delete: true)),
                    ),
                  ElevatedButton(
                    child: Text(widget.isEditing ? '保存' : '追加'),
                    onPressed: () {
                      _formKey.currentState?.save();
                      if (_item.isNotEmpty && _amount > 0) {
                        final payment = Payment(item: _item, amount: _amount, payer: _payer, myRatio: _myRatio, date: _date);
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

class SettingsPage extends StatefulWidget {
  final String myName;
  final String partnerName;
  const SettingsPage({super.key, required this.myName, required this.partnerName});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _myNameController;
  late final TextEditingController _partnerNameController;

  @override
  void initState() {
    super.initState();
    _myNameController = TextEditingController(text: widget.myName);
    _partnerNameController = TextEditingController(text: widget.partnerName);
  }

  @override
  void dispose() {
    _myNameController.dispose();
    _partnerNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _myNameController, decoration: const InputDecoration(labelText: 'あなたの名前')),
            TextField(controller: _partnerNameController, decoration: const InputDecoration(labelText: '相手の名前')),
            const SizedBox(height: 20),
            ElevatedButton(
              child: const Text('保存'),
              onPressed: () {
                final myName = _myNameController.text.trim();
                final partnerName = _partnerNameController.text.trim();
                if (myName.isEmpty || partnerName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('名前を入力してください')));
                  return;
                }
                Navigator.pop(context, {'myName': myName, 'partnerName': partnerName});
              },
            ),
          ],
        ),
      ),
    );
  }
}