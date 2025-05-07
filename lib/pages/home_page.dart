// lib/pages/home_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_split_app/services/member_service.dart';
import 'package:couple_split_app/models/payment.dart';
import 'package:couple_split_app/models/tag.dart';
import 'package:couple_split_app/pages/add_payment_page.dart';
import 'package:couple_split_app/pages/default_payer_settings_page.dart';
import 'package:couple_split_app/pages/member_settings_page.dart';
import 'package:couple_split_app/pages/tag_settings_page.dart';

class HomePage extends StatefulWidget {
  final String groupId;
  const HomePage({Key? key, required this.groupId}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Payment> payments = [];
  String _member1Name = 'メンバー1';
  String _member2Name = 'メンバー2';
  Set<int> _selectedIndexes = {};
  bool _isEditingMode = false;
  String _selectedMonth =
      "${DateTime.now().year.toString().padLeft(4, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}";
  Set<String> _settledMonths = {};
  List<Tag> _tags = [];
  bool _showCategoryBreakdown = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPayments();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('tags')
            .get();
    setState(() {
      _tags =
          snapshot.docs.map((d) => Tag.fromMap(d.data())).toList()
            ..sort((a, b) => a.order.compareTo(b.order));
    });
  }

  Future<void> _loadSettings() async {
    final names = await fetchMemberNames(widget.groupId);
    setState(() {
      _member1Name = names['member1']!;
      _member2Name = names['member2']!;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('member1Name', _member1Name);
    await prefs.setString('member2Name', _member2Name);
  }

  @pragma('vm:entry-point')
  Future<void> _savePayments() async {
    final batch = FirebaseFirestore.instance.batch();
    final col = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('payments');
    final snap = await col.get();
    for (var doc in snap.docs) batch.delete(doc.reference);
    for (var p in payments) batch.set(col.doc(), p.toMap());
    await batch.commit();
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('settings')
        .doc('settled')
        .set({'months': _settledMonths.toList()});
  }

  Future<void> _loadPayments() async {
    final snap =
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('payments')
            .get();
    setState(() {
      payments = snap.docs.map((d) => Payment.fromMap(d.data())).toList();
    });
    final sett =
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('settings')
            .doc('settled')
            .get();
    if (sett.exists) {
      _settledMonths = Set<String>.from(sett.data()?['months'] ?? []);
    }
  }

  void _addPayment(Payment p) {
    setState(() => payments.add(p));
    _savePayments();
  }

  void _updatePayment(int i, Payment p) {
    setState(() => payments[i] = p);
    _savePayments();
  }

  void _removePayment(int i) {
    setState(() => payments.removeAt(i));
    _savePayments();
  }

  List<String> _generatePastMonths() {
    final now = DateTime.now();
    return List.generate(13, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}";
    });
  }

  double get totalAmount => payments
      .where((p) => p.date.toIso8601String().startsWith(_selectedMonth))
      .fold(0, (s, p) => s + p.amount);

  double get totalSettlement => payments
      .where((p) => p.date.toIso8601String().startsWith(_selectedMonth))
      .fold(0, (s, p) => s + p.getMySettlement());

  @override
  Widget build(BuildContext context) {
    final rounded = totalSettlement.round();
    final isSettled = _settledMonths.contains(_selectedMonth);
    final monthly = payments.where(
      (p) => p.date.toIso8601String().startsWith(_selectedMonth),
    );
    final myTotal = monthly.fold(0.0, (a, p) => a + p.myShare);
    final partnerTotal = monthly.fold(0.0, (a, p) => a + p.partnerShare);

    return FutureBuilder<List<String>>(
      future: fetchMemberNamesList(widget.groupId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(body: Center(child: Text('メンバー名の取得に失敗しました')));
        }
        final names = snap.data!;
        final m1 = names[0].isEmpty ? _member1Name : names[0];
        final m2 = names[1].isEmpty ? _member2Name : names[1];
        final message =
            isSettled
                ? '精算済み'
                : rounded == 0
                ? '精算は不要です'
                : rounded < 0
                ? '精算時：$m1 から $m2 に ${-rounded}円払う'
                : '精算時：$m2 から $m1 に ${rounded}円払う';

        return Scaffold(
          appBar: AppBar(
            title: FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (_, psnap) {
                if (!psnap.hasData) return const Text('…');
                final prefs = psnap.data!;
                final gid = prefs.getString('groupId') ?? '';
                final gname = prefs.getString('groupName_$gid') ?? 'グループ';
                return Text(gname);
              },
            ),
            actions: [
              IconButton(
                icon: Icon(_isEditingMode ? Icons.check : Icons.edit),
                onPressed:
                    () => setState(() {
                      _isEditingMode = !_isEditingMode;
                      if (!_isEditingMode) _selectedIndexes.clear();
                    }),
              ),
            ],
          ),
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const DrawerHeader(
                  decoration: BoxDecoration(color: Colors.pink),
                  child: Text(
                    'メニュー',
                    style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('メンバー'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => MemberSettingsPage(groupId: widget.groupId),
                      ),
                    );
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
                        builder:
                            (_) => TagSettingsPage(groupId: widget.groupId),
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
                    final sel = await Navigator.push<int>(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => DefaultPayerSettingsPage(
                              currentPayer: current,
                              groupId: widget.groupId,
                            ),
                      ),
                    );
                    if (sel != null) prefs.setInt('defaultPayer', sel);
                  },
                ),
                // ... other drawer items ...
              ],
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        "${_selectedMonth.split('-')[0]}年",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children:
                                _generatePastMonths().map((m) {
                                  final num = int.parse(m.split('-')[1]);
                                  return ChoiceChip(
                                    label: Text("$num月"),
                                    selected: m == _selectedMonth,
                                    onSelected:
                                        (_) => setState(() => _selectedMonth = m),
                                  );
                                }).toList(),
                          ),
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
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _showCategoryBreakdown
                            ? Icons.arrow_drop_up
                            : Icons.arrow_drop_down,
                      ),
                      onPressed:
                          () => setState(
                            () =>
                                _showCategoryBreakdown =
                                    !_showCategoryBreakdown,
                          ),
                    ),
                  ],
                ),
                if (_showCategoryBreakdown)
                  Column(
                    children:
                        monthly
                            .fold<Map<String, int>>({}, (map, p) {
                              map[p.category] =
                                  (map[p.category] ?? 0) + p.amount;
                              return map;
                            })
                            .entries
                            .map((e) => Text('${e.key}: ${e.value} 円'))
                            .toList(),
                  ),
                Text(
                  '$m1: ${myTotal.round()} 円　$m2: ${partnerTotal.round()} 円',
                  style: const TextStyle(color: Colors.grey),
                ),
                Text(message, style: const TextStyle(fontSize: 16)),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: monthly.length + 1,
                    itemBuilder: (ctx, idx) {
                      if (idx < monthly.length) {
                        final entry = monthly.elementAt(idx);
                        final index = payments.indexOf(entry);
                        final p = entry;
                        final pd = p.payer == 1 ? m1 : m2;
                        final dt = p.date;
                        final weekday =
                            ['月', '火', '水', '木', '金', '土', '日'][dt.weekday - 1];
                        final fmt =
                            dt.year == DateTime.now().year
                                ? "${dt.month}/${dt.day}($weekday)"
                                : "${dt.year}/${dt.month}/${dt.day}($weekday)";
                        return ListTile(
                          leading:
                              _isEditingMode
                                  ? Checkbox(
                                    value: _selectedIndexes.contains(index),
                                    onChanged:
                                        (v) => setState(() {
                                          if (v == true)
                                            _selectedIndexes.add(index);
                                          else
                                            _selectedIndexes.remove(index);
                                        }),
                                  )
                                  : CircleAvatar(
                                    backgroundColor:
                                        _tags
                                            .firstWhere(
                                              (t) => t.name == p.category,
                                              orElse:
                                                  () => Tag(
                                                    name: '',
                                                    ratios: {},
                                                    color: Colors.grey,
                                                  ),
                                            )
                                            .color,
                                    child: Text(
                                      p.category.characters.first,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                          title: Text('${p.item} - ${p.amount}円'),
                          subtitle: Text('$fmt｜${p.category}｜支払者: $pd'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => AddPaymentPage(
                                      myName: m1,
                                      partnerName: m2,
                                      initial: p,
                                      onSave:
                                          (updated) =>
                                              _updatePayment(index, updated),
                                      onDelete: () => _removePayment(index),
                                    ),
                              ),
                            );
                          },
                        );
                      }
                      // ... settlement buttons ...
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => AddPaymentPage(
                          myName: m1,
                          partnerName: m2,
                          onSave: (newP) => _addPayment(newP),
                        ),
                  ),
                ),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
