import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_split_app/models/payment.dart';
import 'package:couple_split_app/models/tag.dart';
import 'package:couple_split_app/services/member_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late TextEditingController _memoController;

  // 各メンバーの負担割合コントローラー
  Map<int, TextEditingController> _ratioControllers = {};

  // チェックボックス状態を管理（メンバーが3人以上の場合用）
  Map<int, bool> _memberEnabled = {};

  int _payer = 1;
  Map<int, int> _ratios = {};
  DateTime _date = DateTime.now();
  String _category = '';
  List<Tag> _tags = [];
  Tag? _selectedTag;
  Map<String, Tag> _tagsMap = {};
  List<String> _tagOrder = [];

  // メンバー情報
  List<String> _memberNames = [];
  Map<int, String> _memberIdToName = {};

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadTags();

    final init = widget.initial;
    _itemController = TextEditingController(text: init?.item ?? '');
    _amountController = TextEditingController(
      text: init != null ? '${init.amount}' : '',
    );
    _payer = init?.payer ?? 1;
    _ratios = init?.ratios ?? {};
    _memoController = TextEditingController(text: init?.memo ?? '');
    _date = init?.date ?? DateTime.now();
    _category = init?.category ?? '';

    if (widget.initial == null) {
      _loadDefaultPayer();
    }
  }

  @override
  void dispose() {
    _itemController.dispose();
    _amountController.dispose();
    _memoController.dispose();

    // 各メンバーのコントローラーを破棄
    for (final controller in _ratioControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  // メンバー情報を読み込む
  Future<void> _loadMembers() async {
    try {
      final membersList = await fetchMemberNamesList(widget.groupId);

      setState(() {
        _memberNames = membersList;

        // メンバーIDと名前のマッピングを作成（ID は 1 から始まる）
        _memberIdToName = {};
        for (int i = 0; i < membersList.length; i++) {
          final memberId = i + 1;
          _memberIdToName[memberId] = membersList[i];

          // 各メンバーの負担割合を初期化
          if (!_ratios.containsKey(memberId)) {
            _ratios[memberId] = 1;
          }

          // 各メンバーのコントローラーを作成
          _ratioControllers[memberId] = TextEditingController(
            text: '${_ratios[memberId]}',
          );

          // 各メンバーのチェックボックス状態を初期化（デフォルトで有効）
          _memberEnabled[memberId] = true;
        }
      });
    } catch (e) {
      // エラー時は少なくとも2人のメンバーを用意
      setState(() {
        _memberNames = [widget.myName, widget.partnerName];
        _memberIdToName = {1: widget.myName, 2: widget.partnerName};

        // 負担割合を初期化
        _ratios = {1: 1, 2: 1};

        // コントローラーを作成
        _ratioControllers = {
          1: TextEditingController(text: '1'),
          2: TextEditingController(text: '1'),
        };

        // チェックボックス状態を初期化
        _memberEnabled = {1: true, 2: true};
      });
    }
  }

  // メンバーの有効/無効を切り替えるメソッド
  void _toggleMemberEnabled(int memberId, bool enabled) {
    setState(() {
      _memberEnabled[memberId] = enabled;
      if (enabled) {
        // 有効化された場合、1を設定
        _ratios[memberId] = 1;
        _ratioControllers[memberId]?.text = '1';
      } else {
        // 無効化された場合、0を設定
        _ratios[memberId] = 0;
        _ratioControllers[memberId]?.text = '0';
      }
    });
  }

  // タグ選択時に負担割合を更新するメソッド
  void _updateRatios(Tag tag) {
    setState(() {
      // タグの負担割合をコピー
      _ratios = Map.from(tag.ratios);

      // すべてのメンバーの負担割合を更新
      // タグに存在しないメンバーには1を設定
      for (final memberId in _memberIdToName.keys) {
        if (!_ratios.containsKey(memberId)) {
          _ratios[memberId] = 1;
        }

        // チェックボックス状態を更新（比率が0ならfalse、それ以外はtrue）
        _memberEnabled[memberId] = (_ratios[memberId] ?? 0) > 0;
      }

      // コントローラーの値を更新
      for (final memberId in _ratioControllers.keys) {
        _ratioControllers[memberId]?.text = '${_ratios[memberId] ?? 1}';
      }
    });
  }

  Future<void> _loadDefaultPayer() async {
    final prefs = await SharedPreferences.getInstance();
    final int? defaultPayer = prefs.getInt('default_payer_${widget.groupId}');
    if (defaultPayer != null) {
      setState(() {
        _payer = defaultPayer;
      });
    }
  }

  Future<void> _loadTags() async {
    final snap =
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('tags')
            .get();

    // タグの情報をマップに保存
    final Map<String, Tag> tagsMap = {};
    for (final doc in snap.docs) {
      final tag = Tag.fromMap(doc.data());
      tagsMap[doc.id] = tag;
    }

    // 保存されている並び順を取得
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList('tag_order_${widget.groupId}') ?? [];

    // 保存されている順番に基づいてタグを並べる
    List<String> tagOrder = List.from(savedOrder);

    // 新しいタグを追加（保存されていない場合）
    for (final id in tagsMap.keys) {
      if (!tagOrder.contains(id)) {
        tagOrder.add(id);
      }
    }

    // 削除されたタグを除外
    tagOrder.removeWhere((id) => !tagsMap.containsKey(id));

    setState(() {
      _tagsMap = tagsMap;
      _tagOrder = tagOrder;
      // 並び順に基づいてタグリストを生成
      _tags = _tagOrder.map((id) => tagsMap[id]!).toList();

      // 編集時は既存の支払いのカテゴリを選択、新規作成時は最初のタグを選択
      if (widget.initial != null && widget.initial?.category != null) {
        _category = widget.initial!.category;
        // 既存のカテゴリに一致するタグを見つける
        _selectedTag = _tags.firstWhere(
          (tag) => tag.name == _category,
          orElse:
              () =>
                  _tags.isNotEmpty
                      ? _tags.first
                      : Tag(name: '', ratios: {}, color: Colors.grey),
        );
        if (_selectedTag != null) {
          _updateRatios(_selectedTag!);
        }
      } else if (_tags.isNotEmpty) {
        _category = _tags.first.name;
        _selectedTag = _tags.first;
        _updateRatios(_selectedTag!);
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
      date: _date,
      memo: _memoController.text.trim(),
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
      body: _AdaptiveFormLayout(
        formKey: _formKey,
        itemController: _itemController,
        amountController: _amountController,
        memoController: _memoController,
        memberNames: _memberNames,
        memberIdToName: _memberIdToName,
        payer: _payer,
        date: _date,
        tags: _tags,
        selectedTag: _selectedTag,
        category: _category,
        ratioControllers: _ratioControllers,
        memberEnabled: _memberEnabled,
        onPayerChanged: (v) => setState(() => _payer = v!),
        onDateChanged: (d) => setState(() => _date = d),
        onCategoryChanged: (name, tag) {
          setState(() {
            _category = name;
            _selectedTag = tag;
            if (tag != null) {
              _updateRatios(tag);
            }
          });
        },
        onSave: _save,
        buildMemberRatioInput: _buildMemberRatioInput,
      ),
    );
  }

  // メンバーの負担割合入力ウィジェットを生成するメソッド
  Widget _buildMemberRatioInput(int memberId) {
    if (!_memberIdToName.containsKey(memberId)) return const SizedBox();

    final memberName = _memberIdToName[memberId] ?? 'メンバー$memberId';
    final isEnabled = _memberEnabled[memberId] ?? true;
    final hasThreeOrMoreMembers = _memberIdToName.length >= 3;

    return Row(
      children: [
        // メンバーが3人以上の場合のみチェックボックスを表示
        if (hasThreeOrMoreMembers)
          Checkbox(
            value: isEnabled,
            onChanged: (value) => _toggleMemberEnabled(memberId, value ?? true),
          ),
        // メンバー名（有効/無効で色を変える）
        Expanded(
          flex: 3,
          child: Text(
            memberName,
            style: TextStyle(
              color: isEnabled ? Colors.black : Colors.grey,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        const Text(': '),
        // 負担割合入力フィールド
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _ratioControllers[memberId],
            enabled: true,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged:
                (v) => setState(() {
                  // v が null や空文字列、または整数以外の場合は 1 or 0 をデフォルトとする
                  int value = 0;
                  if (v != null && v.isNotEmpty) {
                    value = int.tryParse(v) ?? 0;
                  }
                  _ratios[memberId] = value;

                  // 値が0より大きい場合はメンバーを有効化、0以下の場合は無効化
                  if (value > 0 && !(_memberEnabled[memberId] ?? false)) {
                    _memberEnabled[memberId] = true;
                  } else if (value <= 0 && (_memberEnabled[memberId] ?? true)) {
                    _memberEnabled[memberId] = false;
                  }
                }),
          ),
        ),
      ],
    );
  }
}

// 適応型レイアウトのためのウィジェット
class _AdaptiveFormLayout extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController itemController;
  final TextEditingController amountController;
  final TextEditingController memoController;
  final List<String> memberNames;
  final Map<int, String> memberIdToName;
  final int payer;
  final DateTime date;
  final List<Tag> tags;
  final Tag? selectedTag;
  final String category;
  final Map<int, TextEditingController> ratioControllers;
  final Map<int, bool> memberEnabled;
  final void Function(int?) onPayerChanged;
  final void Function(DateTime) onDateChanged;
  final void Function(String, Tag?) onCategoryChanged;
  final VoidCallback onSave;
  final Widget Function(int) buildMemberRatioInput;

  const _AdaptiveFormLayout({
    required this.formKey,
    required this.itemController,
    required this.amountController,
    required this.memoController,
    required this.memberNames,
    required this.memberIdToName,
    required this.payer,
    required this.date,
    required this.tags,
    required this.selectedTag,
    required this.category,
    required this.ratioControllers,
    required this.memberEnabled,
    required this.onPayerChanged,
    required this.onDateChanged,
    required this.onCategoryChanged,
    required this.onSave,
    required this.buildMemberRatioInput,
  });

  @override
  State<_AdaptiveFormLayout> createState() => _AdaptiveFormLayoutState();
}

class _AdaptiveFormLayoutState extends State<_AdaptiveFormLayout> {
  // フォームコンテンツの高さを保持する
  final GlobalKey _contentKey = GlobalKey();
  bool _showBottomButton = false;

  @override
  void initState() {
    super.initState();
    // ウィジェットのレイアウト完了後にコンテンツの高さを確認
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkContentHeight();
    });
  }

  // コンテンツの高さを確認し、画面内に収まるかチェック
  void _checkContentHeight() {
    final RenderBox? renderBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final contentSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final appBarHeight = AppBar().preferredSize.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const saveButtonHeight = 80.0; // 保存ボタンの高さ + パディング

    // 利用可能な高さ = スクリーンの高さ - AppBarの高さ - 下部の安全領域 - 保存ボタンの高さ
    final availableHeight = screenSize.height - appBarHeight - bottomPadding;

    // コンテンツの高さが利用可能な高さより大きい場合、ボトムボタンを表示
    setState(() {
      _showBottomButton =
          contentSize.height > availableHeight - saveButtonHeight;
    });
  }

  @override
  Widget build(BuildContext context) {
    // レイアウトが変わる可能性があるため、適宜高さをチェック
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkContentHeight();
    });

    return Stack(
      children: [
        // メインコンテンツ
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: widget.formKey,
              child: Column(
                key: _contentKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: widget.itemController,
                    decoration: const InputDecoration(labelText: '項目名'),
                    validator:
                        (v) => v?.isEmpty == true ? '項目名を入力してください' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: widget.amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '金額'),
                    validator:
                        (v) =>
                            (v == null || int.tryParse(v) == null)
                                ? '正しい金額を入力してください'
                                : null,
                  ),
                  const SizedBox(height: 8),

                  // 支払者選択（動的に生成）
                  if (widget.memberNames.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: widget.payer,
                      decoration: const InputDecoration(labelText: '支払者'),
                      items:
                          widget.memberIdToName.entries.map((entry) {
                            return DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            );
                          }).toList(),
                      onChanged: widget.onPayerChanged,
                    ),

                  const SizedBox(height: 8),
                  // 日付ピッカー
                  ListTile(
                    title: Text(
                      '日付: ${DateFormat('yyyy年MM月dd日').format(widget.date)}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: widget.date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) widget.onDateChanged(picked);
                    },
                  ),
                  const SizedBox(height: 8),

                  // 負担割合入力（動的に生成）
                  const Text('負担割合:', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),

                  // 各メンバーの負担割合入力フィールドを生成（2列表示）
                  for (
                    int i = 0;
                    i < (widget.memberIdToName.length + 1) ~/ 2;
                    i++
                  )
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          // 左側のメンバー
                          Expanded(
                            child: widget.buildMemberRatioInput(i * 2 + 1),
                          ),
                          const SizedBox(width: 16),
                          // 右側のメンバー（存在する場合）
                          Expanded(
                            child:
                                (i * 2 + 2) <= widget.memberIdToName.length
                                    ? widget.buildMemberRatioInput(i * 2 + 2)
                                    : const SizedBox(), // 空のウィジェットで2列目を埋める
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),
                  // カテゴリ（タグ）選択をタイル形式で表示
                  if (widget.tags.isNotEmpty)
                    Wrap(
                      spacing: 8.0,
                      children:
                          widget.tags.map((tag) {
                            return ChoiceChip(
                              label: Text(tag.name),
                              selected: widget.category == tag.name,
                              selectedColor: tag.color,
                              backgroundColor: tag.color.withOpacity(0.3),
                              onSelected: (selected) {
                                widget.onCategoryChanged(
                                  selected ? tag.name : widget.category,
                                  selected ? tag : widget.selectedTag,
                                );
                              },
                            );
                          }).toList(),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: widget.memoController,
                    decoration: const InputDecoration(
                      labelText: 'メモ',
                      hintText: '支払いに関するメモを入力（200字まで）',
                    ),
                    maxLength: 200,
                    maxLines: 3,
                    keyboardType: TextInputType.multiline,
                  ),

                  // 保存ボタン - 画面に余裕がある時のみ表示
                  if (!_showBottomButton)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: ElevatedButton(
                        onPressed: widget.onSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: const Text(
                          '保存',
                          style: TextStyle(fontSize: 18.0, color: Colors.white),
                        ),
                      ),
                    ),

                  // 下部ボタンが表示される場合に余白を追加
                  if (_showBottomButton) const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),

        // 画面に余裕がない場合のみ、下部に固定ボタンを表示
        if (_showBottomButton)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 8.0,
                bottom: 8.0 + MediaQuery.of(context).padding.bottom, // 安全領域を考慮
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: widget.onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, // ボタンの色を青に設定
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: const Text(
                  '保存',
                  style: TextStyle(fontSize: 18.0, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
