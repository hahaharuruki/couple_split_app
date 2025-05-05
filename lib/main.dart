import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'dart:math';

// タグクラス
class Tag {
  final String name;
  final Map<int, int> ratios;
  final Color color;
  final int order;

  Tag({required this.name, required this.ratios, required this.color, this.order = 0});

  Map<String, dynamic> toMap() => {
        'name': name,
        'ratios': ratios.map((key, value) => MapEntry(key.toString(), value)),
        'color': color.value,
        'order': order,
      };

  factory Tag.fromMap(Map<String, dynamic> map) => Tag(
        name: map['name'],
        ratios: Map<String, dynamic>.from(map['ratios'] ?? {}).map((k, v) => MapEntry(int.parse(k), (v ?? 1) as int)),
        color: Color(map['color']),
        order: map['order'] ?? 0,
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
      home: const GroupSelectionPage(),
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
  final Map<int, int> ratios;
  final String category;
  DateTime date;

  Payment({
    required this.item,
    required this.amount,
    required this.payer,
    required this.ratios,
    required this.category,
    required this.date,
  });

  double get myShare {
    if (!ratios.containsKey(1) || ratios[1] == null) return 0.0;
    final totalUnits = ratios.values.fold(0, (a, b) => a + b);
    final myRatio = ratios[1];
    return (myRatio != null && totalUnits > 0) ? amount * (myRatio / totalUnits) : 0.0;
  }

  double get partnerShare {
    if (!ratios.containsKey(2) || ratios[2] == null) return 0.0;
    final totalUnits = ratios.values.fold(0, (a, b) => a + b);
    final partnerRatio = ratios[2];
    return (partnerRatio != null && totalUnits > 0) ? amount * (partnerRatio / totalUnits) : 0.0;
  }

  double getMySettlement() {
    if (!ratios.containsKey(1) || ratios[1] == null) return 0.0;
    final totalUnits = ratios.values.fold(0, (a, b) => a + b);
    final myRatio = ratios[1];
    final myShare = (myRatio != null && totalUnits > 0) ? amount * (myRatio / totalUnits) : 0.0;
    if (payer == 1) {
      return amount - myShare;
    } else {
      return -myShare;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'item': item,
      'amount': amount,
      'payer': payer,
      'ratios': ratios.map((key, value) => MapEntry(key.toString(), value)),
      'category': category,
      'date': date.toIso8601String(),
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      item: map['item'],
      amount: map['amount'],
      payer: map['payer'] is String ? int.parse(map['payer']) : map['payer'],
      ratios: Map<String, dynamic>.from(map['ratios'] ?? {}).map((k, v) => MapEntry(int.parse(k), v)),
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
  late String _groupId;
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
    _loadGroupId().then((_) {
      _loadSettings();
      _loadPayments();
      _loadTags();
    });
  }

  Future<void> _loadGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    _groupId = prefs.getString('groupId') ?? 'defaultGroup';
  }

  Future<void> _loadTags() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('groups')
        .doc(_groupId)
        .collection('tags')
        .get();
    setState(() {
      _tags = snapshot.docs.map((doc) => Tag.fromMap(doc.data())).toList();
      _tags.sort((a, b) => a.order.compareTo(b.order));
    });
  }

  Future<void> _loadSettings() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('groups')
        .doc(_groupId)
        .collection('settings')
        .doc('names')
        .get();
    String member1Name = '';
    String member2Name = '';
    if (snapshot.exists) {
      final data = snapshot.data()!;
      member1Name = data['member1Name'] ?? '';
      member2Name = data['member2Name'] ?? '';
    }
    setState(() {
      _member1Name = member1Name.isNotEmpty ? member1Name : 'メンバー1';
      _member2Name = member2Name.isNotEmpty ? member2Name : 'メンバー2';
    });
    // Firestore取得できた場合はSharedPreferencesにも保存
    if (member1Name.isNotEmpty && member2Name.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('member1Name', member1Name);
      await prefs.setString('member2Name', member2Name);
    }
  }



  @pragma('vm:entry-point')
  Future<void> _savePayments() async {
    // Firestore保存のみ
    // 既存のpaymentsコレクションを一旦全削除してから再追加（単純化のため）
    final batch = FirebaseFirestore.instance.batch();
    final paymentsCollection = FirebaseFirestore.instance
        .collection('groups')
        .doc(_groupId)
        .collection('payments');
    final snapshot = await paymentsCollection.get();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    for (final p in payments) {
      batch.set(paymentsCollection.doc(), p.toMap());
    }
    await batch.commit();
    // 精算月情報もFirestoreに保存
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(_groupId)
        .collection('settings')
        .doc('settled')
        .set({
      'months': _settledMonths.toList(),
    });
  }

  Future<void> _loadPayments() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('groups')
        .doc(_groupId)
        .collection('payments')
        .get();
    setState(() {
      payments = snapshot.docs.map((doc) => Payment.fromMap(doc.data())).toList();
    });

    final settings = await FirebaseFirestore.instance
        .collection('groups')
        .doc(_groupId)
        .collection('settings')
        .doc('settled')
        .get();
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
      appBar: AppBar(
        title: FutureBuilder<SharedPreferences>(
          future: SharedPreferences.getInstance(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Text('読み込み中...');
            final prefs = snapshot.data!;
            final groupId = prefs.getString('groupId') ?? '';
            final groupName = prefs.getString('groupName_$groupId') ?? 'グループ';
            return Text(groupName);
          },
        ),
        actions: [
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
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.pink),
              child: Text('メニュー', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('メンバー'),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NameSettingsPage(
                      member1Name: _member1Name,
                      member2Name: _member2Name,
                    ),
                  ),
                );
                await _loadSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.label),
              title: const Text('タグ'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TagSettingsPage(
                      myName: _member1Name,
                      partnerName: _member2Name,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.payment),
              title: const Text('デフォルト支払者'),
              onTap: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                final current = prefs.getInt('defaultPayer') ?? 1;
                final selected = await Navigator.push<int>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DefaultPayerSettingsPage(
                      current,
                      _member1Name,
                      _member2Name,
                    ),
                  ),
                );
                if (selected != null) {
                  await prefs.setInt('defaultPayer', selected);
                }
              },
            ),
            // グループ情報タイル
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('グループ情報'),
              onTap: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                final currentGroupId = prefs.getString('groupId') ?? '不明';
                final currentGroupName = prefs.getString('groupName_$currentGroupId') ?? 'グループ';
                final nameController = TextEditingController(text: currentGroupName);

                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('グループ情報'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'グループ名'),
                        ),
                        const SizedBox(height: 12),
                        SelectableText('グループID: $currentGroupId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'コピー',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: currentGroupId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('グループIDをコピーしました')),
                            );
                          },
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('キャンセル'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final newName = nameController.text.trim();
                          if (newName.isNotEmpty) {
                            await FirebaseFirestore.instance
                                .collection('groups')
                                .doc(currentGroupId)
                                .collection('settings')
                                .doc('groupInfo')
                                .set({'name': newName});
                            await prefs.setString('groupName_$currentGroupId', newName);
                          }
                          Navigator.pop(context);
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('他のグループ', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final savedGroupIds = snapshot.data!.getStringList('savedGroupIds') ?? [];
                return Column(
                  children: [
                    ...savedGroupIds.map((groupId) {
                      final groupName = snapshot.data!.getString('groupName_$groupId') ?? 'グループ';
                      return ListTile(
                        title: Text(groupName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(groupId, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('groupId', groupId);
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
                        },
                      );
                    }),
                    // ここにグループの編集・追加タイルを追加
                    ListTile(
                      leading: const Icon(Icons.edit),
                      title: const Text('グループの編集・追加'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const GroupSelectionPage()),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // 年表示はListView内に移動したので削除
                      // Text(
                      //   "${_selectedMonth.split('-')[0]}年",
                      //   style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      // ),
                      // const SizedBox(width: 12),
                    ],
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
                      // 削除: Rowの編集ボタン（AppBarに移動）
                      // IconButton(
                      //   icon: Icon(_isEditingMode ? Icons.check : Icons.edit),
                      //   tooltip: _isEditingMode ? '編集終了' : '編集',
                      //   onPressed: () {
                      //     setState(() {
                      //       _isEditingMode = !_isEditingMode;
                      //       if (!_isEditingMode) _selectedIndexes.clear();
                      //     });
                      //   },
                      // ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Text(
                        "${_selectedMonth.split('-')[0]}年",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Expanded(
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
                ],
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
                    // Compute shares for display
                    final ratios = p.ratios;
                    final totalUnits = ratios.values.fold(0, (a, b) => a + b);
                    final myShare = (ratios.containsKey(1) && ratios[1] != null && totalUnits > 0)
                        ? p.amount * (ratios[1]! / totalUnits)
                        : 0;
                    final partnerShare = (ratios.containsKey(2) && ratios[2] != null && totalUnits > 0)
                        ? p.amount * (ratios[2]! / totalUnits)
                        : 0;
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
                                orElse: () => Tag(name: '', ratios: {1: 1, 2: 1}, color: Colors.grey),
                              ).color,
                              child: Text(
                                p.category.characters.first,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                      title: Text('${p.item} - ${p.amount}円'),
                      subtitle: Text('$formattedDate｜${p.category}｜支払者: $payerDisplay'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final result = await Navigator.push<PaymentAction>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddPaymentPage(initial: p, myName: _member1Name, partnerName: _member2Name, groupId: _groupId),
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
              builder: (_) => AddPaymentPage(myName: _member1Name, partnerName: _member2Name, groupId: _groupId),
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
    );
  }
}

class AddPaymentPage extends StatefulWidget {
  final Payment? initial;
  final bool isEditing;
  final String member1Name;
  final String member2Name;
  final String groupId;

  const AddPaymentPage({
    super.key,
    this.initial,
    required String myName,
    required String partnerName,
    required this.groupId,
  })  : member1Name = myName,
        member2Name = partnerName,
        isEditing = initial != null;

  @override
  State<AddPaymentPage> createState() => _AddPaymentPageState();
}

class _AddPaymentPageState extends State<AddPaymentPage> {
  final _formKey = GlobalKey<FormState>();
  String _item = '';
  int _amount = 0;
  int _payer = 1;
  DateTime _date = DateTime.now();
  final List<String> _categories = ['食費', '水道光熱費', '旅行代'];
  String _selectedCategory = '食費';
  // Tag selection variables
  List<Tag> _tags = [];
  Tag? _selectedTag;
  Map<int, int> _ratios = {1: 1, 2: 1};
  final TextEditingController _ratio1Controller = TextEditingController();
  final TextEditingController _ratio2Controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _item = widget.initial?.item ?? '';
    _amount = widget.initial?.amount ?? 0;
    _payer = widget.initial?.payer ?? 1;
    _date = widget.initial?.date ?? DateTime.now();
    _selectedCategory = widget.initial?.category ?? '-';
    if (widget.initial != null) {
      _ratios = Map<int, int>.from(widget.initial!.ratios);
    }
    _ratio1Controller.text = _ratios[1]?.toString() ?? '1';
    _ratio2Controller.text = _ratios[2]?.toString() ?? '1';

    // Always use widget.groupId to fetch tags
    final snapshot = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('tags')
        .get();

    final tags = snapshot.docs.map((doc) => Tag.fromMap(doc.data())).toList();
    tags.sort((a, b) => a.order.compareTo(b.order));

    setState(() {
      _tags = tags;
      if (_tags.isNotEmpty) {
        if (widget.initial != null) {
          _selectedTag = _tags.firstWhere(
            (tag) => tag.name == _selectedCategory,
            orElse: () => _tags.first,
          );
        } else {
          _selectedTag = _tags.first;
          _selectedCategory = _selectedTag!.name;
          _ratios = Map<int, int>.from(_selectedTag!.ratios);
          _ratio1Controller.text = _ratios[1]?.toString() ?? '1';
          _ratio2Controller.text = _ratios[2]?.toString() ?? '1';
        }
      }
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
    final totalUnits = _ratios.values.fold(0, (a, b) => a + b);
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
                onChanged: (v) {
                  setState(() {
                    _amount = int.tryParse(v) ?? 0;
                  });
                },
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
                          _selectedCategory = tag.name;
                          _ratios = Map<int, int>.from(tag.ratios);
                          _ratio1Controller.text = _ratios[1]?.toString() ?? '1';
                          _ratio2Controller.text = _ratios[2]?.toString() ?? '1';
                        });
                      },
                      backgroundColor: tag.color.withOpacity(0.4),
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
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ratio1Controller,
                      decoration: InputDecoration(labelText: '${widget.member1Name}の割合'),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _updateRatiosFromText(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _ratio2Controller,
                      decoration: InputDecoration(labelText: '${widget.member2Name}の割合'),
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
            ListTile(
              title: const Text('デフォルト支払者'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                final current = prefs.getInt('defaultPayer') ?? 1;
                final selected = await Navigator.push<int>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DefaultPayerSettingsPage(
                      current,
                      widget.member1Name,
                      widget.member2Name,
                    ),
                  ),
                );
                if (selected != null) {
                  await prefs.setInt('defaultPayer', selected);
                }
              },
            ),
            // --- グループID設定タイル追加ここから ---
            ListTile(
              title: const Text('グループID設定'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                final current = prefs.getString('groupId') ?? '不明';
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('グループID'),
                    content: Row(
                      children: [
                        Expanded(child: Text(current, style: const TextStyle(fontSize: 16))),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: current));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('グループIDをコピーしました')),
                            );
                          },
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('閉じる'),
                      ),
                    ],
                  ),
                );
              },
            ),
            // --- グループID設定タイル追加ここまで ---
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
  late String _groupId;
  bool _isReorderMode = false;

  @override
  void initState() {
    super.initState();
    _loadGroupIdAndTags();
  }

  Future<void> _loadGroupIdAndTags() async {
    final prefs = await SharedPreferences.getInstance();
    _groupId = prefs.getString('groupId') ?? 'defaultGroup';
    // Firestoreからタグを取得
    FirebaseFirestore.instance
        .collection('groups')
        .doc(_groupId)
        .collection('tags')
        .get()
        .then((snapshot) {
      setState(() {
        _tags = snapshot.docs.map((doc) => Tag.fromMap(doc.data())).toList();
      });
    });
  }

  Future<void> _saveTags() async {
    // Firestoreにタグを保存
    final prefs = await SharedPreferences.getInstance();
    final groupId = prefs.getString('groupId') ?? 'defaultGroup';
    final tagsCollection = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('tags');
    // 既存タグ全削除と新しいタグ追加を同一バッチで
    final snapshot = await tagsCollection.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    for (int i = 0; i < _tags.length; i++) {
      final t = _tags[i];
      batch.set(tagsCollection.doc(), Tag(name: t.name, ratios: t.ratios, color: t.color, order: i).toMap());
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('タグ設定'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.sort,
              color: _isReorderMode ? Colors.grey : Colors.black,
            ),
            tooltip: _isReorderMode ? '並び替え終了' : '並び替え',
            onPressed: () {
              setState(() {
                _isReorderMode = !_isReorderMode;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _isReorderMode
              ? Expanded(
                  child: ReorderableListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final entry in _tags.asMap().entries)
                        Container(
                          key: ValueKey('tag_${entry.key}_${entry.value.name}'),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.drag_handle),
                                const SizedBox(width: 8),
                                CircleAvatar(backgroundColor: entry.value.color),
                              ],
                            ),
                            title: Text(entry.value.name),
                          ),
                        ),
                    ],
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final tag = _tags.removeAt(oldIndex);
                        _tags.insert(newIndex, tag);
                      });
                      _saveTags();
                    },
                  ),
                )
              :
              // ListView.builder with "タグを追加" button at the end
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tags.length + 1,
                  itemBuilder: (context, idx) {
                    if (idx < _tags.length) {
                      final tag = _tags[idx];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: tag.color),
                          title: Text(tag.name),
                          onTap: () async {
                            final result = await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (_) => _TagDialog(
                                initial: tag,
                                myName: widget.myName,
                                partnerName: widget.partnerName,
                              ),
                            );
                            if (result != null && result['tag'] != null) {
                              setState(() {
                                _tags[idx] = result['tag'] as Tag;
                              });
                              await _saveTags();
                            }
                          },
                        ),
                      );
                    } else {
                      // タグを追加ボタン
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ElevatedButton(
                          onPressed: () async {
                            final result = await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (_) => _TagDialog(
                                myName: widget.myName,
                                partnerName: widget.partnerName,
                              ),
                            );
                            if (result != null && result['tag'] != null) {
                              setState(() {
                                _tags.add(result['tag'] as Tag);
                              });
                              _saveTags();
                            }
                          },
                          child: const Text('タグを追加'),
                        ),
                      );
                    }
                  },
                ),
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
  const _TagDialog({this.initial, required this.myName, required this.partnerName});
  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late Map<int, int> _ratios;
  late Color _color;
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
    final totalUnits = _ratios.values.reduce((a, b) => a + b);
    final percent1 = totalUnits > 0 ? (_ratios[1]! / totalUnits * 100).round() : 50;
    final percent2 = totalUnits > 0 ? (_ratios[2]! / totalUnits * 100).round() : 50;
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
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ratio1Controller,
                    decoration: InputDecoration(labelText: '${widget.myName}の割合'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateRatiosFromText(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _ratio2Controller,
                    decoration: InputDecoration(labelText: '${widget.partnerName}の割合'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateRatiosFromText(),
                  ),
                ),
              ],
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
          ],
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () async {
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
              });
            }
          },
        ),
      ],
    );
  }
}
// デフォルト支払者設定ページ
class DefaultPayerSettingsPage extends StatefulWidget {
  final int current;
  final String member1Name;
  final String member2Name;

  const DefaultPayerSettingsPage(this.current, this.member1Name, this.member2Name, {super.key});

  @override
  State<DefaultPayerSettingsPage> createState() => _DefaultPayerSettingsPageState();
}

class _DefaultPayerSettingsPageState extends State<DefaultPayerSettingsPage> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('デフォルト支払者')),
      body: Column(
        children: [
          RadioListTile<int>(
            title: Text(widget.member1Name),
            value: 1,
            groupValue: _selected,
            onChanged: (val) => setState(() => _selected = val!),
          ),
          RadioListTile<int>(
            title: Text(widget.member2Name),
            value: 2,
            groupValue: _selected,
            onChanged: (val) => setState(() => _selected = val!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
// グループ選択ページ
class GroupSelectionPage extends StatefulWidget {
  const GroupSelectionPage({super.key});
  @override
  State<GroupSelectionPage> createState() => _GroupSelectionPageState();
}

class _GroupSelectionPageState extends State<GroupSelectionPage> {
  List<String> _savedGroups = [];
  String _generateRandomGroupId({int length = 32}) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rand = Random.secure();
  return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
}

  @override
  void initState() {
    super.initState();
    _loadSavedGroups();
  }

  Future<void> _loadSavedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final groups = prefs.getStringList('savedGroupIds') ?? [];
    setState(() {
      _savedGroups = groups;
    });
  }

  Future<void> _addGroup(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_savedGroups.contains(groupId)) {
      _savedGroups.add(groupId);
      await prefs.setStringList('savedGroupIds', _savedGroups);
    }
    await prefs.setString('groupId', groupId);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  Future<void> _promptForGroupId({required bool isNew}) async {
  if (isNew) {
    final newGroupId = _generateRandomGroupId();
    final nameController = TextEditingController();
    final groupName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('グループ名を入力'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: 'グループ名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, nameController.text.trim()), child: const Text('作成')),
        ],
      ),
    );
    if (groupName != null && groupName.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(newGroupId)
          .collection('settings')
          .doc('groupInfo')
          .set({'name': groupName});

      final prefs = await SharedPreferences.getInstance();
      final groupIds = prefs.getStringList('savedGroupIds') ?? [];
      if (!groupIds.contains(newGroupId)) {
        groupIds.add(newGroupId);
        await prefs.setStringList('savedGroupIds', groupIds);
      }
      await prefs.setString('groupId', newGroupId);
      await prefs.setString('groupName_$newGroupId', groupName);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('グループを選択')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._savedGroups.map((groupId) {
            return FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final prefs = snapshot.data!;
                final groupName = prefs.getString('groupName_$groupId') ?? 'グループ';
                return ListTile(
                  title: Text(groupName),
                  subtitle: Text(groupId, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () async {
                    await prefs.setString('groupId', groupId);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const HomePage()),
                    );
                  },
                );
              },
            );
          }),
          const Divider(),
          ElevatedButton(
            onPressed: () => _promptForGroupId(isNew: true),
            child: const Text('新しいグループを作成'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _promptForGroupId(isNew: false),
            child: const Text('グループに参加'),
          ),
        ],
      ),
    );
  }
}