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
import 'dart:math';
import 'package:intl/intl.dart'; // 数値フォーマット用

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
  List<String> _allMemberNames = []; // すべてのメンバー名を保持
  Map<int, String> _memberIdToName = {}; // メンバーIDと名前のマッピング
  Set<int> _selectedIndexes = {};
  bool _isEditingMode = false;
  String _selectedMonth =
      "${DateTime.now().year.toString().padLeft(4, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}";
  Set<String> _settledMonths = {};
  List<Tag> _tags = [];
  bool _showCategoryBreakdown = false;
  bool _showAllSettlements = false; // 全ての精算情報を表示するフラグ
  bool _showAllMembers = false; // 全てのメンバー負担額を表示するフラグ
  int _currentUserMemberId = 1; // 端末の使用者のメンバーID
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
    _loadCurrentUserMemberId();
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

  Future<void> _loadSettings() async {
    // メンバー名をMapとして取得
    final names = await fetchMemberNames(widget.groupId);
    // メンバー名をリストとして取得
    final membersList = await fetchMemberNamesList(widget.groupId);

    setState(() {
      _member1Name = names['member1']!;
      _member2Name = names['member2']!;
      _allMemberNames = membersList;

      // メンバーIDと名前のマッピングを作成（ID は 1 から始まる）
      _memberIdToName = {};
      for (int i = 0; i < membersList.length; i++) {
        _memberIdToName[i + 1] = membersList[i];
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('member1Name', _member1Name);
    await prefs.setString('member2Name', _member2Name);

    // メンバー設定変更後に現在のユーザーIDも再読み込み
    await _loadCurrentUserMemberId();
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

  // 端末の使用者のメンバーIDを読み込む
  Future<void> _loadCurrentUserMemberId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserMemberId =
          prefs.getInt('current_user_member_id_${widget.groupId}') ?? 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rounded = totalSettlement.round();
    final isSettled = _settledMonths.contains(_selectedMonth);
    final monthly = payments.where(
      (p) => p.date.toIso8601String().startsWith(_selectedMonth),
    );

    // 各メンバーの負担額を計算
    final Map<int, double> memberShares = {};
    for (final p in monthly) {
      for (final memberId in p.ratios.keys) {
        memberShares[memberId] =
            (memberShares[memberId] ?? 0) + p.getMemberShare(memberId);
      }
    }

    // 各メンバーの精算額を計算
    final Map<int, double> memberSettlements = {};
    for (final p in monthly) {
      for (final memberId in p.ratios.keys) {
        memberSettlements[memberId] =
            (memberSettlements[memberId] ?? 0) +
            p.getMemberSettlement(memberId);
      }
    }

    // 端末使用者の精算情報
    final double currentUserSettlement =
        memberSettlements[_currentUserMemberId] ?? 0;

    // 精算情報をもとに、誰が誰に支払うかの情報を構築
    final Map<int, Map<int, double>> settlementTransactions = {};

    // 受け取る人（settlement > 0）と支払う人（settlement < 0）に分ける
    final List<MapEntry<int, double>> receivers =
        memberSettlements.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value)); // 金額の大きい順にソート

    final List<MapEntry<int, double>> payers =
        memberSettlements.entries.where((e) => e.value < 0).toList()
          ..sort((a, b) => a.value.compareTo(b.value)); // 金額の絶対値が大きい順にソート

    // 支払い情報を計算
    double remainingToReceive = receivers.fold(0.0, (sum, e) => sum + e.value);

    for (final payer in payers) {
      double remainingToPay = payer.value.abs();
      settlementTransactions[payer.key] = {};

      for (final receiver in receivers) {
        if (remainingToPay <= 0 || remainingToReceive <= 0) break;

        double amountToTransfer = min(remainingToPay, receiver.value);
        if (amountToTransfer > 0) {
          settlementTransactions[payer.key]![receiver.key] = amountToTransfer;
          remainingToPay -= amountToTransfer;
          remainingToReceive -= amountToTransfer;
        }
      }
    }

    // 後方互換性のために残す
    final myTotal = memberShares[1] ?? 0;
    final partnerTotal = memberShares[2] ?? 0;

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
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MemberSettingsPage(groupId: widget.groupId),
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
                    builder: (_) => TagSettingsPage(groupId: widget.groupId),
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
                final current =
                    prefs.getInt('default_payer_${widget.groupId}') ?? 1;
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
                if (sel != null)
                  prefs.setInt('default_payer_${widget.groupId}', sel);
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
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          groupId,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
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
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
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
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        '合計支出：${NumberFormat("#,###").format(totalAmount.round())} 円',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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
                        () => _showCategoryBreakdown = !_showCategoryBreakdown,
                      ),
                ),
                // メンバーが3人以上の場合は負担額表示用の追加ボタン
                if (memberShares.length > 2)
                  IconButton(
                    icon: Icon(
                      _showAllMembers ? Icons.people : Icons.people_outline,
                    ),
                    onPressed:
                        () =>
                            setState(() => _showAllMembers = !_showAllMembers),
                    tooltip: _showAllMembers ? '負担額を隠す' : '負担額を表示',
                  ),
              ],
            ),
            if (_showCategoryBreakdown)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Wrap(
                  spacing: 12.0, // 横方向の間隔
                  runSpacing: 4.0, // 縦方向の間隔（行間）
                  alignment: WrapAlignment.start, // 左寄せにする
                  children:
                      monthly
                          .fold<Map<String, int>>({}, (map, p) {
                            map[p.category] = (map[p.category] ?? 0) + p.amount;
                            return map;
                          })
                          .entries
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2.0,
                              ),
                              child: Text(
                                '${e.key}: ${NumberFormat("#,###").format(e.value)}円',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),

            // メンバーが2人の場合は直接表示、3人以上の場合は折りたたみメニュー内に表示
            if (memberShares.length <= 2)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final entry in memberShares.entries)
                      if (_memberIdToName.containsKey(entry.key))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            '${_memberIdToName[entry.key]}: ${NumberFormat("#,###").format(entry.value.round())}円',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight:
                                  entry.key == _currentUserMemberId
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                        ),
                  ],
                ),
              ),

            // 3人以上で折りたたみが開いている場合に表示
            if (memberShares.length > 2 && _showAllMembers)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '各メンバーの負担額:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    // 2人ずつ横に並べて表示
                    for (int i = 0; i < memberShares.entries.length; i += 2)
                      Row(
                        children: [
                          Expanded(
                            child: _buildMemberShareText(
                              memberShares.entries.elementAt(i).key,
                              memberShares.entries.elementAt(i).value,
                            ),
                          ),
                          if (i + 1 < memberShares.entries.length)
                            Expanded(
                              child: _buildMemberShareText(
                                memberShares.entries.elementAt(i + 1).key,
                                memberShares.entries.elementAt(i + 1).value,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            // 精算情報を表示
            if (!isSettled && memberSettlements.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _buildSimpleSettlementText(
                              _currentUserMemberId,
                              currentUserSettlement,
                              settlementTransactions,
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                        // 他のメンバーがいる場合のみ三角ボタンを表示
                        if (memberSettlements.entries
                            .where((e) => e.value < 0)
                            .isNotEmpty)
                          IconButton(
                            icon: Icon(
                              _showAllSettlements
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                            ),
                            onPressed:
                                () => setState(
                                  () =>
                                      _showAllSettlements =
                                          !_showAllSettlements,
                                ),
                            tooltip: _showAllSettlements ? '詳細を隠す' : '詳細を表示',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),

                    // 他のメンバーの精算情報（展開時のみ表示）
                    if (_showAllSettlements)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...memberSettlements.entries
                                .where((e) => e.value < 0) // 支払う側のみフィルタリング
                                .map(
                                  (e) => _buildSimplePaymentInfo(
                                    e.key,
                                    settlementTransactions,
                                  ),
                                ),
                            // コピーボタンを追加
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: IconButton(
                                  icon: const Icon(Icons.copy),
                                  tooltip: '精算情報をコピー',
                                  onPressed: () {
                                    // 精算情報をテキストとして生成
                                    final settlementText =
                                        _buildSettlementTextForCopy(
                                          currentUserSettlement,
                                          memberSettlements,
                                          settlementTransactions,
                                        );

                                    // クリップボードにコピー
                                    Clipboard.setData(
                                      ClipboardData(text: settlementText),
                                    );

                                    // コピー成功のメッセージを表示
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('精算情報をコピーしました。'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              )
            else
              Text(
                isSettled ? '精算済み' : '精算は不要です',
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
                                backgroundColor: _getTagColor(p.category),
                                child: Text(
                                  p.category.isNotEmpty
                                      ? p.category.characters.first
                                      : '',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                      title: Text(
                        '${p.item} - ${NumberFormat("#,###").format(p.amount)}円',
                      ),
                      subtitle: Text('$fmt｜${p.category}｜支払者: $pd'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => AddPaymentPage(
                                  groupId: widget.groupId,
                                  myName: _member1Name,
                                  partnerName: _member2Name,
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
        onPressed:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => AddPaymentPage(
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  // メンバー負担額テキストを生成するメソッド
  Widget _buildMemberShareText(int memberId, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Text(
        '${_memberIdToName[memberId] ?? "メンバー$memberId"}: ${NumberFormat("#,###").format(amount.round())}円',
        style: TextStyle(
          color: Colors.black,
          fontWeight:
              memberId == _currentUserMemberId
                  ? FontWeight.bold
                  : FontWeight.normal,
        ),
      ),
    );
  }

  // 精算情報を簡潔に表示するメソッド - テキスト生成のみを行う
  String _buildSimpleSettlementText(
    int currentUserMemberId,
    double settlementAmount,
    Map<int, Map<int, double>> transactions,
  ) {
    final userName =
        _memberIdToName[currentUserMemberId] ?? 'メンバー$currentUserMemberId';
    String settlementText = '';

    if (settlementAmount > 0) {
      // 受け取る側の場合
      final fromMembers = <String>[];
      int payerCount = 0;
      double totalReceiving = 0;

      // このユーザーに支払うすべてのユーザーを探す
      for (final payerEntry in transactions.entries) {
        if (payerEntry.value.containsKey(currentUserMemberId)) {
          final payerName =
              _memberIdToName[payerEntry.key] ?? 'メンバー${payerEntry.key}';
          fromMembers.add(payerName);
          payerCount++;
          totalReceiving += payerEntry.value[currentUserMemberId]!;
        }
      }

      // 受け取る側の表示テキスト
      if (payerCount == 1) {
        settlementText =
            '精算：$userNameは${fromMembers[0]}から${NumberFormat("#,###").format(totalReceiving.round())}円もらう';
      } else if (payerCount > 1) {
        settlementText =
            '精算：$userNameは$payerCount人から${NumberFormat("#,###").format(totalReceiving.round())}円もらう';
      }
    } else if (settlementAmount < 0) {
      // 支払う側の場合
      final settlements = transactions[currentUserMemberId] ?? {};
      final toMembers = <String>[];
      double totalPaying = 0;

      for (final receiverEntry in settlements.entries) {
        final receiverName =
            _memberIdToName[receiverEntry.key] ?? 'メンバー${receiverEntry.key}';
        toMembers.add(receiverName);
        totalPaying += receiverEntry.value;
      }

      // 支払う側の表示テキスト
      if (toMembers.length == 1) {
        settlementText =
            '精算：$userNameは${toMembers[0]}に${NumberFormat("#,###").format(totalPaying.round())}円支払う';
      } else if (toMembers.length > 1) {
        settlementText =
            '精算：$userNameは${toMembers.length}人に${NumberFormat("#,###").format(totalPaying.round())}円支払う';
      }
    }

    return settlementText;
  }

  // 簡素な支払い情報を表示するメソッド
  Widget _buildSimplePaymentInfo(
    int payerId,
    Map<int, Map<int, double>> transactions,
  ) {
    final payerName = _memberIdToName[payerId] ?? 'メンバー$payerId';
    final settlements = transactions[payerId] ?? {};
    final List<Widget> paymentInfoWidgets = [];

    for (final receiverEntry in settlements.entries) {
      final receiverId = receiverEntry.key;
      final amount = receiverEntry.value;
      final receiverName = _memberIdToName[receiverId] ?? 'メンバー$receiverId';

      paymentInfoWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Text(
            '$payerName → $receiverName：${NumberFormat("#,###").format(amount.round())}円',
            style: const TextStyle(fontSize: 14, color: Colors.black),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paymentInfoWidgets,
    );
  }

  // タグの色を取得するヘルパーメソッド
  Color _getTagColor(String categoryName) {
    // タグリストから一致するものを探す
    for (var tag in _tags) {
      if (tag.name == categoryName) {
        return tag.color;
      }
    }
    // 見つからない場合はデフォルトの色を返す
    return Colors.grey;
  }

  // 精算情報をコピー用にフォーマットするメソッドを追加
  String _buildSettlementTextForCopy(
    double currentUserSettlement,
    Map<int, double> memberSettlements,
    Map<int, Map<int, double>> transactions,
  ) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('【精算情報】');

    // 現在のユーザーの情報
    final currentUserName =
        _memberIdToName[_currentUserMemberId] ?? 'メンバー$_currentUserMemberId';
    if (currentUserSettlement > 0) {
      // 受け取る側
      buffer.writeln(
        '$currentUserName: ${NumberFormat("#,###").format(currentUserSettlement.round())}円 受け取り',
      );
    } else if (currentUserSettlement < 0) {
      // 支払う側
      buffer.writeln(
        '$currentUserName: ${NumberFormat("#,###").format(currentUserSettlement.abs().round())}円 支払い',
      );
    }

    // 詳細な精算情報
    buffer.writeln('\n【詳細】');
    for (final payerEntry in transactions.entries) {
      final payerId = payerEntry.key;
      final payerName = _memberIdToName[payerId] ?? 'メンバー$payerId';

      for (final receiverEntry in payerEntry.value.entries) {
        final receiverId = receiverEntry.key;
        final amount = receiverEntry.value;
        final receiverName = _memberIdToName[receiverId] ?? 'メンバー$receiverId';

        buffer.writeln(
          '$payerName → $receiverName：${NumberFormat("#,###").format(amount.round())}円',
        );
      }
    }

    // 日付情報
    final now = DateTime.now();
    buffer.writeln('\n精算日: ${DateFormat('yyyy年MM月dd日').format(now)}');
    buffer.writeln(
      '対象月: ${_selectedMonth.split('-')[0]}年${_selectedMonth.split('-')[1]}月',
    );

    return buffer.toString();
  }
}
