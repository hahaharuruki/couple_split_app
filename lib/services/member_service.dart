import 'package:cloud_firestore/cloud_firestore.dart';

/// groupInfo から id='0','1' のメンバー名を取って Map で返す
Future<Map<String,String>> fetchMemberNames(String groupId) async {
  final doc = await FirebaseFirestore.instance
    .collection('groups')
    .doc(groupId)
    .collection('settings')
    .doc('groupInfo')
    .get();
  final data = doc.data();
  if (data == null || !data.containsKey('members')) {
    return {'member1': '', 'member2': ''};
  }

  final membersRaw = data['members'] as List<dynamic>;
  String m1 = '', m2 = '';

  for (final m in membersRaw) {
    final mem = Map<String, dynamic>.from(m);
    final id = mem['id'].toString();
    if (id == '0') m1 = mem['name'] ?? '';
    if (id == '1') m2 = mem['name'] ?? '';
  }
  return {'member1': m1, 'member2': m2};
}

Future<List<String>> fetchMemberNamesList(String groupId) async {
  final map = await fetchMemberNames(groupId);
  return [map['member1'] ?? '', map['member2'] ?? ''];
}