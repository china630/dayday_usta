import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bolt_usta/services/logger_service.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({Key? key}) : super(key: key);

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  @override
  Widget build(BuildContext context) {
    final logs = Log.logs;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Debug Logs"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Логи скопированы!")));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              Log.clear();
              setState(() {});
            },
          )
        ],
      ),
      backgroundColor: Colors.black,
      body: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: logs.length,
        separatorBuilder: (_, __) => const Divider(color: Colors.white24, height: 1),
        itemBuilder: (context, index) {
          final log = logs[index];
          Color color = Colors.greenAccent;
          if (log.contains('WARN')) color = Colors.yellowAccent;
          if (log.contains('ERROR')) color = Colors.redAccent;
          if (log.contains('INFO')) color = Colors.white;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              log,
              style: TextStyle(color: color, fontFamily: 'Courier', fontSize: 12),
            ),
          );
        },
      ),
    );
  }
}