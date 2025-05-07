import 'package:flutter/material.dart';

class Tag {
  final String name;
  final Map<int,int> ratios;
  final Color color;
  final int order;

  Tag({required this.name, required this.ratios, required this.color, this.order=0});

  Map<String,dynamic> toMap() => {
    'name': name,
    'ratios': ratios.map((k,v)=>MapEntry(k.toString(),v)),
    'color': color.value,
    'order': order,
  };

  factory Tag.fromMap(Map<String,dynamic> m) => Tag(
    name: m['name'],
    ratios: Map<String,dynamic>.from(m['ratios'] ?? {}).map((k,v)=>MapEntry(int.parse(k),(v as int))),
    color: Color(m['color']),
    order: m['order'] ?? 0,
  );
}