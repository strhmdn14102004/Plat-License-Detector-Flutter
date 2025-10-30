import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ViewDataPage extends StatefulWidget {
  const ViewDataPage({super.key});

  @override
  State<ViewDataPage> createState() => _ViewDataPageState();
}

class _ViewDataPageState extends State<ViewDataPage> {
  late Box _box;

  @override
  void initState() {
    super.initState();
    _box = Hive.box('plates');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1621),
      appBar: AppBar(
        title: const Text("Data Hasil Scan"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: ValueListenableBuilder(
        valueListenable: _box.listenable(),
        builder: (context, Box box, _) {
          final List<String> scannedData = List<String>.from(
            box.get('data', defaultValue: []),
          );

          if (scannedData.isEmpty) {
            return const Center(
              child: Text(
                "Belum ada data hasil scan",
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: scannedData.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, i) {
              final data = scannedData[i];
              final parts = data.split('\n');
              final plate = parts.first;
              final time = parts.length > 1 ? parts[1] : '';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plate,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (time.isNotEmpty)
                          Text(
                            time,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 16,
                            ),
                          ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_forever,
                        color: Colors.redAccent,
                      ),
                      onPressed: () async {
                        final List<String> updated = List<String>.from(
                          scannedData,
                        );
                        updated.removeAt(i);
                        await box.put('data', updated);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: ValueListenableBuilder(
        valueListenable: _box.listenable(),
        builder: (context, Box box, _) {
          final List<String> scannedData = List<String>.from(
            box.get('data', defaultValue: []),
          );
          if (scannedData.isEmpty) return const SizedBox.shrink();

          return FloatingActionButton.extended(
            backgroundColor: Colors.redAccent,
            onPressed: () async {
              await box.delete('data');
            },
            icon: const Icon(Icons.delete_forever),
            label: const Text("Hapus Semua"),
          );
        },
      ),
    );
  }
}
