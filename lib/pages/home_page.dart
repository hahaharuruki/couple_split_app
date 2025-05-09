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
import 'package:couple_split_app/pages/group_selection_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/scroll_controller.dart';

class HomePage extends StatefulWidget {
  final String groupId;
  const HomePage({Key? key, required this.groupId}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

// 月選択ウィジェットを分離
class MonthSelector extends StatefulWidget {
  final String selectedMonth;
  final Function(String) onMonthSelected;
  final List<String> months;

  const MonthSelector({
    super.key,
    required this.selectedMonth,
    required this.onMonthSelected,
    required this.months,
  });

  @override
  State<MonthSelector> createState() => _MonthSelectorState();
}

class _MonthSelectorState extends State<MonthSelector> {
  final ScrollController _monthScrollController = ScrollController();

  @override
  void dispose() {
    _monthScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                "${widget.selectedMonth.split('-')[0]}年",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView(
                key: const PageStorageKey('monthListView'),
                controller: _monthScrollController,
                scrollDirection: Axis.horizontal,
                children:
                    widget.months.map((m) {
                      final num = int.parse(m.split('-')[1]);
                      return ChoiceChip(
                        label: Text("$num月"),
                        selected: m == widget.selectedMonth,
                        onSelected: (_) => widget.onMonthSelected(m),
                      );
                    }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomePageState extends State<HomePage> {
  List<Payment> payments = [];
  String _member1Name = '';
  String _member2Name = '';
  Set<int> _selectedIndexes = {};
  bool _isEditingMode = false;
  String _selectedMonth =
      "${DateTime.now().year.toString().padLeft(4, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}";
  Set<String> _settledMonths = {};
  List<Tag> _tags = [];
  bool _showCategoryBreakdown = false;
  final ScrollController _monthScrollController = ScrollController();
  String _groupName = 'グループ';
  String _category = '';
  Tag _selectedTag = Tag(name: '', ratios: {}, color: Colors.grey);

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPayments();
    _loadTags();
    _loadGroupName();
  }

  @override
  void dispose() {
    _monthScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGroupName() async {
    final prefs = await SharedPreferences.getInstance();
    final gname = prefs.getString('groupName_${widget.groupId}') ?? 'グループ';
    setState(() {
      _groupName = gname;
    });
  }

  Future<void> _loadTags() async {
    final snap = await FirebaseFirestore.instance
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_groupName),
        actions: [
          if (_isEditingMode)
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全選択',
              onPressed: () {
                setState(() {
                  if (_selectedIndexes.length == payments.length) {
                    _selectedIndexes.clear();
                  } else {
                    _selectedIndexes = Set<int>.from(
                      List.generate(payments.length, (i) => i),
                    );
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
                  builder:
                      (_) => AlertDialog(
                        title: const Text('削除の確認'),
                        content: const Text(
                          '選択した明細を削除してもよろしいですか？',
                        ),
                        actions: [
                          TextButton(
                            onPressed:
                                () => Navigator.pop(
                                  context,
                                  false,
                                ),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed:
                                () => Navigator.pop(
                                  context,
                                  true,
                                ),
                            child: const Text('削除'),
                          ),
                        ],
                      ),
                );
                if (confirm == true) {
                  setState(() {
                    final sorted =
                        _selectedIndexes.toList()
                          ..sort((b, a) => a.compareTo(b));
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
            onPressed: () => setState(() {
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
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => MemberSettingsPage(groupId: widget.groupId),
                  ),
                );
                final names = await fetchMemberNamesList(widget.groupId);
                setState(() {
                  _member1Name = names[0];
                  _member2Name = names[1];
                });
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
            // グループ情報タイル
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('グループ情報'),
              onTap: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                final currentGroupId = prefs.getString('groupId') ?? '不明';
                final currentGroupName =
                    prefs.getString('groupName_$currentGroupId') ?? 'グループ';
                final nameController = TextEditingController(
                  text: currentGroupName,
                );

                await showDialog(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('グループ情報'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: nameController,
                              decoration: const InputDecoration(
                                labelText: 'グループ名',
                              ),
                            ),
                            const SizedBox(height: 12),
                            SelectableText(
                              'グループID: $currentGroupId',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'コピー',
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: currentGroupId),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('グループIDをコピーしました'),
                                  ),
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
                                await prefs.setString(
                                  'groupName_$currentGroupId',
                                  newName,
                                );
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
              child: Text(
                '他のグループ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final savedGroupIds =
                    snapshot.data!.getStringList('savedGroupIds') ?? [];
                return Column(
                  children: [
                    ...savedGroupIds.map((groupId) {
                      final groupName =
                          snapshot.data!.getString('groupName_$groupId') ??
                          'グループ';
                      return ListTile(
                        title: Text(
                          groupName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          groupId,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        onTap: () async {
                          final prefs =
                              await SharedPreferences.getInstance();
                          await prefs.setString('groupId', groupId);
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HomePage(groupId: groupId),
                            ),
                          );
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
                          MaterialPageRoute(
                            builder: (_) => const GroupSelectionPage(),
                          ),
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
              padding: const EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // 削除：全選択ボタンと削除ボタンはAppBarに移動したため、ここからは削除
                    ],
                  ),
                ],
              ),
            ),
            MonthSelector(
              selectedMonth: _selectedMonth,
              onMonthSelected: (m) => setState(() => _selectedMonth = m),
              months: _generatePastMonths(),
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
              '$_member1Name: ${myTotal.round()} 円　$_member2Name: ${partnerTotal.round()} 円',
              style: const TextStyle(color: Colors.grey),
            ),
            Text(
              isSettled
                  ? '精算済み'
                  : rounded == 0
                  ? '精算は不要です'
                  : rounded < 0
                  ? '精算時：$_member1Name から $_member2Name に ${-rounded}円払う'
                  : '精算時：$_member2Name から $_member1Name に ${rounded}円払う',
              style: const TextStyle(fontSize: 16),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: monthly.length + 1,
                itemBuilder: (ctx, idx) {
                  if (idx < monthly.length) {
                    final entry = monthly.elementAt(idx);
                    final index = payments.indexOf(entry);
                    final p = entry;
                    final pd = p.payer == 1 ? _member1Name : _member2Name;
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
                      onTap: () async {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddPaymentPage(
                              groupId: widget.groupId,
                              myName: _member1Name,
                              partnerName: _member2Name,
                              initial: p,
                              onSave: (updated) => _updatePayment(index, updated),
                              onDelete: () => _removePayment(index),
                            ),
                          ),
                        );
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
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('精算確認'),
                                  content: const Text(
                                    'この月を「精算済み」にしますか？\n後から「未精算」に戻すこともできます。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.of(context).pop(),
                                      child: const Text('キャンセル'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        setState(() {
                                          _settledMonths.add(
                                            _selectedMonth,
                                          );
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
                  } else if (_settledMonths.contains(_selectedMonth)) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('未精算に戻す確認'),
                                  content: const Text(
                                    'この月の「精算済み」状態を取り消して、未精算に戻しますか？',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.of(context).pop(),
                                      child: const Text('キャンセル'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        setState(() {
                                          _settledMonths.remove(
                                            _selectedMonth,
                                          );
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
                  } else {
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddPaymentPage(
              groupId: widget.groupId,
              myName: _member1Name,
              partnerName: _member2Name,
              onSave: (newP) => _addPayment(newP),
            ),
          ),
        ),
        child: const Icon(Icons.add),
        tooltip: '支払いを追加',
        backgroundColor: Colors.pink,
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
    );
  }
}
