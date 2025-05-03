import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// タグクラス
class Tag {
  final String name;
  final double ratio;
  final Color color;

  Tag({required this.name, required this.ratio, required this.color});

  Map<String, dynamic> toMap() => {
        'name': name,
        'ratio': ratio,
        'color': color.value,
      };

  factory Tag.fromMap(Map<String, dynamic> map) => Tag(
        name: map['name'],
        ratio: map['ratio'] is int
            ? (map['ratio'] as int).toDouble()
            : map['ratio'],
        color: Color(map['color']),
      );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const CoupleSplitApp());
}

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
  final int payer;
  final double myRatio;
  final String category;
  DateTime date;

  Payment({
    required this.item,
    required this.amount,
    required this.payer,
    required this.myRatio,
    required this.category,
    required this.date,
  });

  double get myShare => amount * myRatio;
  double get partnerShare => amount * (1 - myRatio);
  double getMySettlement() {
    // Positive: you should receive money; Negative: you owe money
    if (payer == 1) {
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
      'category': category,
      'date': date.toIso8601String(),
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      item: map['item'],
      amount: map['amount'],
      payer: map['payer'] is String ? int.parse(map['payer']) : map['payer'],
      myRatio: map['myRatio'],
      category: map['category'] ?? '食費',
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
  String _member1Name = 'メンバー1';
  String _member2Name = 'メンバー2';
  Set<int> _selectedIndexes = {};
  bool _isEditingMode = false;
  String _selectedMonth = "${DateTime.now().year.toString().padLeft(4, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}";
  Set<String> _settledMonths = {};
  List<Tag> _tags = [];
  bool _showCategoryBreakdown = false;

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
    _loadTags();
  }
  Future<void> _loadTags() async {
    final snapshot = await FirebaseFirestore.instance.collection('tags').get();
    setState(() {
      _tags = snapshot.docs.map((doc) => Tag.fromMap(doc.data())).toList();
    });
  }

  Future<void> _loadSettings() async {
    final snapshot = await FirebaseFirestore.instance.collection('settings').doc('names').get();
    String member1Name = '';
    String member2Name = '';
    if (snapshot.exists) {
      final data = snapshot.data()!;
      member1Name = data['member1Name'] ?? '';
      member2Name = data['member2Name'] ?? '';
    }
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _member1Name = member1Name.isNotEmpty ? member1Name : (prefs.getString('member1Name') ?? 'メンバー1');
      _member2Name = member2Name.isNotEmpty ? member2Name : (prefs.getString('member2Name') ?? 'メンバー2');
    });
    // Firestore取得できた場合はSharedPreferencesにも保存
    if (member1Name.isNotEmpty && member2Name.isNotEmpty) {
      await prefs.setString('member1Name', member1Name);
      await prefs.setString('member2Name', member2Name);
    }
  }



  @pragma('vm:entry-point')
  Future<void> _savePayments() async {
    // Firestore保存のみ
    // 既存のpaymentsコレクションを一旦全削除してから再追加（単純化のため）
    final batch = FirebaseFirestore.instance.batch();
    final paymentsCollection = FirebaseFirestore.instance.collection('payments');
    final snapshot = await paymentsCollection.get();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    for (final p in payments) {
      batch.set(paymentsCollection.doc(), p.toMap());
    }
    await batch.commit();
    // 精算月情報もFirestoreに保存
    await FirebaseFirestore.instance.collection('settings').doc('settled').set({
      'months': _settledMonths.toList(),
    });
  }

  Future<void> _loadPayments() async {
    final snapshot = await FirebaseFirestore.instance.collection('payments').get();
    setState(() {
      payments = snapshot.docs.map((doc) => Payment.fromMap(doc.data())).toList();
    });

    final settings = await FirebaseFirestore.instance.collection('settings').doc('settled').get();
    if (settings.exists) {
      _settledMonths = Set<String>.from(settings.data()?['months'] ?? []);
    }
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

  @pragma('vm:entry-point')
  void _removePayment(int index) {
    setState(() {
      payments.removeAt(index);
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
                ? '精算時：$_member1Name から $_member2Name に ${-roundedSettlement}円払う'
                : '精算時：$_member2Name から $_member1Name に ${roundedSettlement}円払う';

    final monthly = payments.where((p) => p.date.year.toString().padLeft(4, '0') + '-' + p.date.month.toString().padLeft(2, '0') == _selectedMonth);
    final myShareTotal = monthly.fold(0.0, (sum, p) => sum + p.myShare);
    final partnerShareTotal = monthly.fold(0.0, (sum, p) => sum + p.partnerShare);

    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${_selectedMonth.split('-')[0]}年",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      if (_isEditingMode)
                        IconButton(
                          icon: const Icon(Icons.select_all),
                          tooltip: '全選択',
                          onPressed: () {
                            setState(() {
                              if (_selectedIndexes.length == payments.length) {
                                _selectedIndexes.clear();
                              } else {
                                _selectedIndexes = Set<int>.from(List.generate(payments.length, (i) => i));
                              }
                            });
                          },
                        ),
                      if (_isEditingMode && _selectedIndexes.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: '削除',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('削除の確認'),
                                content: const Text('選択した明細を削除してもよろしいですか？'),
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
                                final sorted = _selectedIndexes.toList()..sort((b, a) => a.compareTo(b));
                                for (final i in sorted) {
                                  payments.removeAt(i);
                                }
                                _selectedIndexes.clear();
                              });
                              _savePayments();
                            }
                          },
                        ),
                      IconButton(
                        icon: Icon(_isEditingMode ? Icons.check : Icons.edit),
                        tooltip: _isEditingMode ? '編集終了' : '編集',
                        onPressed: () {
                          setState(() {
                            _isEditingMode = !_isEditingMode;
                            if (!_isEditingMode) _selectedIndexes.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '合計支出：${totalAmount.round()} 円',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(_showCategoryBreakdown ? Icons.arrow_drop_up : Icons.arrow_drop_down),
                  onPressed: () {
                    setState(() {
                      _showCategoryBreakdown = !_showCategoryBreakdown;
                    });
                  },
                )
              ],
            ),
            if (_showCategoryBreakdown)
              Column(
                children: monthly
                    .fold<Map<String, int>>({}, (map, p) {
                      map[p.category] = (map[p.category] ?? 0) + p.amount;
                      return map;
                    })
                    .entries
                    .map((e) => Text('${e.key}: ${e.value} 円'))
                    .toList(),
              ),
            Text(
              '$_member1Name: ${myShareTotal.round()} 円　$_member2Name: ${partnerShareTotal.round()} 円',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Text(settlementMessage, style: const TextStyle(fontSize: 16)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: monthly.length + 1,
                itemBuilder: (context, idx) {
                  if (idx < monthly.length) {
                    final entry = monthly.elementAt(idx);
                    final index = payments.indexOf(entry);
                    final p = entry;
                final payerDisplay = switch (p.payer) {
                  1 => _member1Name,
                  2 => _member2Name,
                  _ => '不明',
                };
                    final isThisYear = p.date.year == DateTime.now().year;
                    final weekday = ['月', '火', '水', '木', '金', '土', '日'][p.date.weekday - 1];
                    final formattedDate = isThisYear
                        ? "${p.date.month}/${p.date.day}($weekday)"
                        : "${p.date.year}/${p.date.month}/${p.date.day}($weekday)";
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
                          : CircleAvatar(
                              backgroundColor: _tags.firstWhere(
                                (tag) => tag.name == p.category,
                                orElse: () => Tag(name: '', ratio: 0.5, color: Colors.grey),
                              ).color,
                              child: Text(
                                p.category.characters.first,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                      title: Text('${p.item} - ${p.amount}円'),
                      subtitle: Text(
                        '$formattedDate｜${p.category}｜支払者: $payerDisplay'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final result = await Navigator.push<PaymentAction>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddPaymentPage(initial: p, myName: _member1Name, partnerName: _member2Name),
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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push<PaymentAction>(
            context,
            MaterialPageRoute(
              builder: (_) => AddPaymentPage(myName: _member1Name, partnerName: _member2Name),
            ),
          );
          if (result != null && !result.delete && result.updated != null) {
            final payment = result.updated!..date = DateTime.now();
            _addPayment(payment);
          }
        },
        child: const Icon(Icons.add),
        tooltip: '支払いを追加',
        backgroundColor: Colors.pink,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 12.0,
        child: SizedBox(
          height: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: IconButton(
                    icon: const Icon(Icons.home),
                    padding: EdgeInsets.zero,
                    iconSize: 28,
                    onPressed: () {},
                  ),
                ),
              ),
              const SizedBox(width: 48), // space for FAB
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: IconButton(
                    icon: const Icon(Icons.settings),
                    padding: EdgeInsets.zero,
                    iconSize: 28,
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettingsPage(
                            myName: _member1Name,
                            partnerName: _member2Name,
                          ),
                        ),
                      );
                      // 設定画面から戻ってきた後、名前を再取得
                      await _loadSettings();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddPaymentPage extends StatefulWidget {
  final Payment? initial;
  final bool isEditing;
  final String member1Name;
  final String member2Name;

  const AddPaymentPage({super.key, this.initial, required String myName, required String partnerName})
      : member1Name = myName,
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
  late double _myRatio;
  late DateTime _date;
  final List<String> _categories = ['食費', '水道光熱費', '旅行代'];
  late String _selectedCategory;

  // Tag selection variables
  List<Tag> _tags = [];
  Tag? _selectedTag;

  @override
  void initState() {
    super.initState();
    _item = widget.initial?.item ?? '';
    _amount = widget.initial?.amount ?? 0;
    _payer = widget.initial?.payer ?? 1;
    _myRatio = widget.initial?.myRatio ?? 0.7;
    _date = widget.initial?.date ?? DateTime.now();
    _selectedCategory = widget.initial?.category ?? '食費';

    // Load tags from Firestore
    FirebaseFirestore.instance.collection('tags').get().then((snapshot) {
      final tags = snapshot.docs.map((doc) => Tag.fromMap(doc.data())).toList();
      setState(() {
        _tags = tags;
        // Set selectedTag based on initial category if editing, otherwise first tag if exists
        if (_tags.isNotEmpty) {
          if (widget.initial != null) {
            _selectedTag = _tags.firstWhere(
              (tag) => tag.name == _selectedCategory,
              orElse: () => _tags.first,
            );
          } else {
            _selectedTag = _tags.first;
          }
          _myRatio = _selectedTag!.ratio;
          _selectedCategory = _selectedTag!.name;
        }
      });
    });
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
              DropdownButtonFormField<int>(
                value: _payer,
                items: [
                  DropdownMenuItem(value: 1, child: Text(widget.member1Name)),
                  DropdownMenuItem(value: 2, child: Text(widget.member2Name)),
                ],
                onChanged: (v) => setState(() => _payer = v ?? 1),
                decoration: const InputDecoration(labelText: '支払者'),
              ),
              // Tag selection (color chips)
              if (_tags.isNotEmpty) ...[
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
                          _myRatio = tag.ratio;
                          _selectedCategory = tag.name;
                        });
                      },
                      backgroundColor: tag.color.withOpacity(0.4),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ]
              else ...[
                // Fallback: category selection if no tags
                Wrap(
                  spacing: 8,
                  children: _categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
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
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                child: Text(
                  '${widget.member1Name}の負担額: ${( _amount * _myRatio ).round()} 円\n'
                  '差額（${widget.member1Name}基準）: ${_payer == 1 ? (_amount * (1 - _myRatio)).round() : -( _amount * _myRatio ).round()} 円',
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
                      if (_item.isNotEmpty && _amount > 0) {
                        final payment = Payment(
                          item: _item,
                          amount: _amount,
                          payer: _payer,
                          myRatio: _myRatio,
                          category: _selectedCategory,
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

class SettingsPage extends StatefulWidget {
  final String member1Name;
  final String member2Name;
  const SettingsPage({super.key, required String myName, required String partnerName})
      : member1Name = myName,
        member2Name = partnerName;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            ListTile(
              title: const Text('名前'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final result = await Navigator.push<Map<String, String>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NameSettingsPage(
                      member1Name: widget.member1Name,
                      member2Name: widget.member2Name,
                    ),
                  ),
                );
                if (result != null) {
                  // Firestoreに名前情報を保存
                  await FirebaseFirestore.instance.collection('settings').doc('names').set({
                    'member1Name': result['member1Name'] ?? widget.member1Name,
                    'member2Name': result['member2Name'] ?? widget.member2Name,
                  });
                  // SharedPreferencesにも保存
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('member1Name', result['member1Name']!);
                  await prefs.setString('member2Name', result['member2Name']!);
                }
              },
            ),
            ListTile(
              title: const Text('タグ'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TagSettingsPage(
                      myName: widget.member1Name,
                      partnerName: widget.member2Name,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class NameSettingsPage extends StatefulWidget {
  final String member1Name;
  final String member2Name;
  const NameSettingsPage({super.key, required this.member1Name, required this.member2Name});

  @override
  State<NameSettingsPage> createState() => _NameSettingsPageState();
}

class _NameSettingsPageState extends State<NameSettingsPage> {
  late final TextEditingController _member1NameController;
  late final TextEditingController _member2NameController;

  @override
  void initState() {
    super.initState();
    _member1NameController = TextEditingController(text: widget.member1Name);
    _member2NameController = TextEditingController(text: widget.member2Name);
  }

  @override
  void dispose() {
    _member1NameController.dispose();
    _member2NameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('名前の設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _member1NameController,
              decoration: const InputDecoration(labelText: 'メンバー1の名前'),
            ),
            TextField(
              controller: _member2NameController,
              decoration: const InputDecoration(labelText: 'メンバー2の名前'),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                final member1Name = _member1NameController.text.trim();
                final member2Name = _member2NameController.text.trim();
                if (member1Name.isEmpty || member2Name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('名前を入力してください')));
                  return;
                }
                Navigator.pop(context, {'member1Name': member1Name, 'member2Name': member2Name});
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

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
    // Firestoreからタグを取得
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
    // Firestoreにタグを保存
    final batch = FirebaseFirestore.instance.batch();
    final tagsCollection = FirebaseFirestore.instance.collection('tags');
    // 既存タグ全削除
    final snapshot = await tagsCollection.get();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    // 新しいタグを追加
    for (final t in _tags) {
      batch.set(tagsCollection.doc(), t.toMap());
    }
    await batch.commit();
    // デフォルトタグもFirestoreに保存
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
                      child: Text(
                        'デフォルト',
                        style: TextStyle(fontSize: 12, color: Colors.pink),
                      ),
                    ),
                ],
              ),
              subtitle: Text('割合: ${(tag.ratio * 100).round()}%'),
              onTap: () async {
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => _TagDialog(
                    initial: tag,
                    myName: widget.myName,
                    partnerName: widget.partnerName,
                    isDefault: _defaultTagName == tag.name,
                  ),
                );
                if (result != null) {
                  if (result['delete'] == true && result['tag'] != null) {
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
                // For deletion, keep the old logic for long press
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
                    content: Text('タグ「${tag.name}」を削除しますか？\nこのタグを使用している明細はデフォルトのタグに変更されます。'),
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
                builder: (_) => _TagDialog(
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

// タグ追加・編集ダイアログ
class _TagDialog extends StatefulWidget {
  final Tag? initial;
  final String myName;
  final String partnerName;
  final bool isDefault;
  const _TagDialog({this.initial, required this.myName, required this.partnerName, this.isDefault = false});
  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late double _ratio;
  late Color _color;
  late bool makeDefault;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _name = widget.initial!.name;
      _ratio = widget.initial!.ratio;
      _color = widget.initial!.color;
    } else {
      _name = '';
      _ratio = 0.5;
      _color = Colors.blue;
    }
    makeDefault = widget.isDefault;
  }

  @override
  Widget build(BuildContext context) {
    // 定義済み色リスト（Setだと順序保証がないのでListで）
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
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('負担割合'),
            ),
            Slider(
              label: '${widget.myName}: ${(_ratio * 100).round()}% / ${widget.partnerName}: ${(100 - _ratio * 100).round()}%',
              value: _ratio,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              onChanged: (v) => setState(() => _ratio = v),
            ),
            DropdownButton<Color>(
              value: predefinedColors.firstWhere((c) => c.value == _color.value, orElse: () => predefinedColors.first),
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
                        }[color] ?? '色'
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
            if (_name.isNotEmpty) {
              Navigator.pop(context, {
                'tag': Tag(name: _name, ratio: _ratio, color: _color),
                'makeDefault': makeDefault,
              });
            }
          },
        ),
      ],
    );
  }
}