

import 'package:flutter/material.dart';

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
    final totalUnits = ratios.values.reduce((a, b) => a + b);
    return amount * (ratios[1]! / totalUnits);
  }

  double get partnerShare {
    final totalUnits = ratios.values.reduce((a, b) => a + b);
    return amount * (ratios[2]! / totalUnits);
  }

  double getMySettlement() {
    final totalUnits = ratios.values.reduce((a, b) => a + b);
    final myShare = amount * (ratios[1]! / totalUnits);
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