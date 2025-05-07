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
  State<DefaultPayerSettingsPage> createState() => _DefaultPayerSettingsPageState();
}

class _DefaultPayerSettingsPageState extends State<DefaultPayerSettingsPage> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentPayer;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: fetchMemberNamesList(widget.groupId),
      builder: (context, snapshot) {
        final memberList = snapshot.data ?? [];
        final member1 = memberList[0];
        final member2 = memberList[1];
        return Scaffold(
          appBar: AppBar(title: const Text('デフォルト支払者')),
          body: Column(
            children: [
              RadioListTile<int>(
                title: Text(member1),
                value: 1,
                groupValue: _selected,
                onChanged: (val) => setState(() => _selected = val!),
              ),
              RadioListTile<int>(
                title: Text(member2),
                value: 2,
                groupValue: _selected,
                onChanged: (val) => setState(() => _selected = val!),
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
      },
    );
  }
}