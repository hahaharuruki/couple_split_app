class Payment {
  final String item;
  final int amount;
  final int payer;
  final Map<int, int> ratios;
  final String category;
  final DateTime date;
  final String memo;

  Payment({
    required this.item,
    required this.amount,
    required this.payer,
    required this.ratios,
    required this.category,
    required this.date,
    this.memo = '',
  });

  // 総負担率の合計を計算
  int get totalRatio => ratios.values.fold(0, (a, b) => a + b);

  // 特定メンバーの負担額を計算
  double getMemberShare(int memberId) {
    if (totalRatio <= 0 || !ratios.containsKey(memberId)) return 0;
    return amount * (ratios[memberId] ?? 0) / totalRatio;
  }

  // 後方互換性のために残す
  double get myShare => getMemberShare(1);
  double get partnerShare => getMemberShare(2);

  // 特定メンバーの精算額を計算（正：受け取る、負：支払う）
  double getMemberSettlement(int memberId) {
    if (payer == memberId) {
      // 支払者の場合は、支払額から自分の負担額を引いた額を受け取る
      return amount - getMemberShare(memberId);
    } else {
      // 支払者でない場合は、自分の負担額を支払う（負の値）
      return -getMemberShare(memberId);
    }
  }

  // 後方互換性のために残す
  double getMySettlement() => getMemberSettlement(1);

  // 全メンバー間の精算情報を計算
  // 戻り値: {memberId: settlementAmount, ...} - 正の値は受け取る額、負の値は支払う額
  Map<int, double> calculateAllSettlements() {
    final Map<int, double> settlements = {};

    // 各メンバーの精算額を計算
    for (final memberId in ratios.keys) {
      settlements[memberId] = getMemberSettlement(memberId);
    }

    return settlements;
  }

  Map<String, dynamic> toMap() => {
    'item': item,
    'amount': amount,
    'payer': payer,
    'ratios': ratios.map((k, v) => MapEntry(k.toString(), v)),
    'category': category,
    'date': date.toIso8601String(),
    'memo': memo,
  };

  factory Payment.fromMap(Map<String, dynamic> m) => Payment(
    item: m['item'] ?? '',
    amount: m['amount'] ?? 0,
    payer: m['payer'] ?? 1,
    ratios: Map<String, dynamic>.from(
      m['ratios'] ?? {},
    ).map((k, v) => MapEntry(int.parse(k), v)),
    category: m['category'] ?? '',
    date: DateTime.parse(m['date']),
    memo: m['memo'] ?? '',
  );
}
