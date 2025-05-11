import 'package:flutter/material.dart';
import 'package:couple_split_app/services/member_service.dart';

class DefaultPayerSettingsPage extends StatefulWidget {
  final int currentPayer;
  final String groupId;

  const DefaultPayerSettingsPage({
    super.key,
    required this.currentPayer,
    required this.groupId,
  });

  @override
  State<DefaultPayerSettingsPage> createState() =>
      _DefaultPayerSettingsPageState();
}

class _DefaultPayerSettingsPageState extends State<DefaultPayerSettingsPage> {
  late int _selected;
  bool _isLoading = true;
  List<String> _memberNames = [];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentPayer;
    _loadMemberNames();
  }

  Future<void> _loadMemberNames() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final membersList = await fetchMemberNamesList(widget.groupId);
      setState(() {
        _memberNames = membersList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _memberNames = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('デフォルト支払者')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _memberNames.isEmpty
              ? const Center(child: Text('メンバー情報が読み込めませんでした'))
              : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _memberNames.length,
                      itemBuilder: (context, index) {
                        final memberId = index + 1; // メンバーIDは1から始まる
                        final memberName = _memberNames[index];

                        return RadioListTile<int>(
                          title: Text(memberName),
                          value: memberId,
                          groupValue: _selected,
                          onChanged: (val) => setState(() => _selected = val!),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
    );
  }
}
