import 'package:cloud_firestore/cloud_firestore.dart';

/// groupInfo から全てのメンバー名を取得し、Map で返す
/// member1, member2 は後方互換性のために残し、追加メンバーは member3, member4... として返す
Future<Map<String, String>> fetchMemberNames(String groupId) async {
  final doc =
      await FirebaseFirestore.instance
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
  final Map<String, String> result = {};

  // メンバーをIDでソートして順番に取得
  final sortedMembers = List<Map<String, dynamic>>.from(membersRaw);
  sortedMembers.sort(
    (a, b) =>
        int.parse(a['id'].toString()).compareTo(int.parse(b['id'].toString())),
  );

  // 各メンバーをマップに追加
  for (int i = 0; i < sortedMembers.length; i++) {
    final mem = sortedMembers[i];
    final name = mem['name'] ?? '';
    result['member${i + 1}'] = name;
  }

  // member1, member2 が存在しない場合は空文字を設定（後方互換性のため）
  if (!result.containsKey('member1')) result['member1'] = '';
  if (!result.containsKey('member2')) result['member2'] = '';

  return result;
}

/// 全メンバーの名前をリストで返す
Future<List<String>> fetchMemberNamesList(String groupId) async {
  final doc =
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('settings')
          .doc('groupInfo')
          .get();
  final data = doc.data();
  if (data == null || !data.containsKey('members')) {
    return ['', ''];
  }

  final membersRaw = data['members'] as List<dynamic>;
  final sortedMembers = List<Map<String, dynamic>>.from(membersRaw);
  sortedMembers.sort(
    (a, b) =>
        int.parse(a['id'].toString()).compareTo(int.parse(b['id'].toString())),
  );

  return sortedMembers.map<String>((m) => m['name']?.toString() ?? '').toList();
}
