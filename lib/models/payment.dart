class Payment {
  final String item;
  final int amount;
  final int payer;
  final Map<int,int> ratios;
  final String category;
  final DateTime date;

  Payment({required this.item, required this.amount, required this.payer, required this.ratios, required this.category, required this.date});

  double get myShare {
    final total=ratios.values.fold(0,(a,b)=>a+b);
    return total>0?amount*ratios[1]!/total:0;
  }

  double get partnerShare {
    final total=ratios.values.fold(0,(a,b)=>a+b);
    return total>0?amount*ratios[2]!/total:0;
  }

  double getMySettlement() => payer==1?amount-myShare:-myShare;

  Map<String,dynamic> toMap()=>{
    'item':item,'amount':amount,'payer':payer,'ratios':ratios.map((k,v)=>MapEntry(k.toString(),v)),'category':category,'date':date.toIso8601String(),
  };

  factory Payment.fromMap(Map<String,dynamic> m)=>Payment(
    item:m['item'],amount:m['amount'],payer:m['payer'],ratios:Map<String,dynamic>.from(m['ratios'] ?? {}).map((k,v)=>MapEntry(int.parse(k),v)),category:m['category'],date:DateTime.parse(m['date']),
  );
}