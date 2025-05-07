import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:couple_split_app/services/member_service.dart';
import 'package:couple_split_app/pages/default_payer_settings_page.dart';
import 'package:couple_split_app/pages/tag_settings_page.dart';
import 'package:couple_split_app/pages/member_settings_page.dart';
import 'package:couple_split_app/pages/group_selection_page.dart';
import 'package:couple_split_app/pages/add_payment_page.dart';
import 'package:couple_split_app/pages/home_page.dart';
import 'package:couple_split_app/models/payment.dart';

// タグクラス
class Tag {
  final String name;
  final Map<int, int> ratios;
  final Color color;
  final int order;

  Tag({
    required this.name,
    required this.ratios,
    required this.color,
    this.order = 0,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'ratios': ratios.map((key, value) => MapEntry(key.toString(), value)),
    'color': color.value,
    'order': order,
  };

  factory Tag.fromMap(Map<String, dynamic> map) => Tag(
    name: map['name'],
    ratios: Map<String, dynamic>.from(
      map['ratios'] ?? {},
    ).map((k, v) => MapEntry(int.parse(k), (v ?? 1) as int)),
    color: Color(map['color']),
    order: map['order'] ?? 0,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

class PaymentAction {
  final bool delete;
  final Payment? updated;
  PaymentAction({required this.delete, this.updated});
}
