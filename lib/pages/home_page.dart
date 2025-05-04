import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/payment.dart';
import '../models/tag.dart';
import 'add_payment_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  final String myName;
  const HomePage({required this.myName, Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
    return List.generate(13, (i) {
      final date = DateTime(now.year, now.month - i, 1);
      return "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}";
    });
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPayments();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final snapshot = await FirebaseFirestore.instance.collection('tags').get();
    setState(() {
      _tags = snapshot.docs.map((doc) => Tag.fromMap(doc.data())).toList();
    });
  }

  Future<void> _loadSettings() async {
    final snapshot = await FirebaseFirestore.instance.collection('settings').doc('names').get();
    String member1Name = '';
    String member2Name = '';
    if (snapshot.exists) {
      final data = snapshot.data()!;
      member1Name = data['member1Name'] ?? '';
      member2Name = data['member2Name'] ?? '';
    }
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _member1Name = member1Name.isNotEmpty ? member1Name : (prefs.getString('member1Name') ?? 'メンバー1');
      _member2Name = member2Name.isNotEmpty ? member2Name : (prefs.getString('member2Name') ?? 'メンバー2');
    });
    if (member1Name.isNotEmpty && member2Name.isNotEmpty) {
      await prefs.setString('member1Name', member1Name);
      await prefs.setString('member2Name', member2Name);
    }
  }

  Future<void> _savePayments() async {
    final batch = FirebaseFirestore.instance.batch();
    final paymentsCollection = FirebaseFirestore.instance.collection('payments');
    final snapshot = await paymentsCollection.get();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    for (final p in payments) {
      batch.set(paymentsCollection.doc(), p.toMap());
    }
    await batch.commit();
    await FirebaseFirestore.instance.collection('settings').doc('settled').set({
      'months': _settledMonths.toList(),
    });
  }

  Future<void> _loadPayments() async {
    final snapshot = await FirebaseFirestore.instance.collection('payments').get();
    setState(() {
      payments = snapshot.docs.map((doc) => Payment.fromMap(doc.data())).toList();
    });
    final settings = await FirebaseFirestore.instance.collection('settings').doc('settled').get();
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

  void _removePayment(int index) {
    setState(() {
      payments.removeAt(index);
    });
    _savePayments();
  }

  @override
  Widget build(BuildContext context) {
    final roundedSettlement = payments.fold(0.0, (sum, p) {
      if ("${p.date.year}-${p.date.month.toString().padLeft(2, '0')}" == _selectedMonth) {
        return sum + p.getMySettlement();
      }
      return sum;
    }).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Couple Split App'),
      ),
      body: Center(
        child: Text('精算金額: $roundedSettlement 円'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push<PaymentAction>(
            context,
            MaterialPageRoute(
              builder: (_) => AddPaymentPage(partnerName: _member2Name),
            ),
          );
          if (result != null && !result.delete && result.updated != null) {
            final payment = result.updated!..date = DateTime.now();
            _addPayment(payment);
          }
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(myName: _member1Name, partnerName: _member2Name),
                  ),
                );
                await _loadSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}