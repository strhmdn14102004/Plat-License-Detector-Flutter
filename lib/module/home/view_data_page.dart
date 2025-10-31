// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0E1621),
      appBar: AppBar(
        title: const Text("Data Hasil Scan"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const _Background(),
          SafeArea(
            child: ValueListenableBuilder(
              valueListenable: _box.listenable(),
              builder: (context, Box box, _) {
                final List<String> scannedData = List<String>.from(
                  box.get('data', defaultValue: []),
                );

                if (scannedData.isEmpty) {
                  return const _EmptyState();
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: _GlassCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.fact_check_rounded,
                              color: Colors.lightGreenAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Total hasil scan: ${scannedData.length}",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _ActionTextButton(
                              icon: Icons.copy_all_rounded,
                              label: "Salin semua",
                              onTap: () async {
                                final text = scannedData.join('\n\n');
                                await Clipboard.setData(
                                  ClipboardData(text: text),
                                );
                                _toast(context, "Disalin ke clipboard");
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: scannedData.length,
                        itemBuilder: (context, i) {
                          final raw = scannedData[i];
                          final parts = raw.split('\n');
                          final plate = parts.isNotEmpty ? parts[0] : raw;
                          final time = parts.length > 1 ? parts[1] : '';

                          return Dismissible(
                            key: ValueKey("plate_${i}_$raw"),
                            direction: DismissDirection.endToStart,
                            background: _deleteBg(),
                            onDismissed: (_) async {
                              final updated = List<String>.from(scannedData);
                              updated.removeAt(i);
                              await box.put('data', updated);
                              _toast(context, "Item dihapus");
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _GlassCard(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _PlateBadge(text: plate),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            plate,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.schedule_rounded,
                                                size: 16,
                                                color: Colors.white70,
                                              ),
                                              const SizedBox(width: 6),
                                              Text("Register : "),
                                              const SizedBox(width: 6),

                                              Text(
                                                time.isEmpty ? "-" : time,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: "Salin",
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        color: Colors.white,
                                      ),
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: raw),
                                        );
                                        _toast(context, "Disalin");
                                      },
                                    ),
                                    IconButton(
                                      tooltip: "Hapus",
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () async {
                                        final updated = List<String>.from(
                                          scannedData,
                                        );
                                        updated.removeAt(i);
                                        await box.put('data', updated);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder(
        valueListenable: _box.listenable(),
        builder: (context, Box box, _) {
          final List<String> scannedData = List<String>.from(
            box.get('data', defaultValue: []),
          );
          if (scannedData.isEmpty) return const SizedBox.shrink();

          return FloatingActionButton.extended(
            backgroundColor: const Color(0xFFE11D48),
            icon: const Icon(Icons.delete_forever_rounded, color: Colors.white),
            label: const Text(
              "Hapus Semua",
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () async {
              final ok = await _confirm(
                context,
                title: "Hapus semua data?",
                subtitle:
                    "Tindakan ini tidak dapat dibatalkan. Semua hasil scan akan dihapus.",
              );
              if (ok) {
                await box.delete('data');
                _toast(context, "Semua data dihapus");
              }
            },
          );
        },
      ),
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) async {
    bool result = false;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              result = true;
              Navigator.pop(context);
            },
            child: const Text("Hapus"),
          ),
        ],
      ),
    );
    return result;
  }

  Widget _deleteBg() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF7F1D1D).withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: const Icon(
        Icons.delete_forever_rounded,
        size: 30,
        color: Colors.white,
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.grey,
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B1220), Color(0xFF111827), Color(0xFF0B1220)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -60,
            top: -40,
            child: _Blob(
              color: const Color(0xFF22D3EE).withOpacity(0.35),
              size: 180,
            ),
          ),
          Positioned(
            right: -50,
            bottom: -40,
            child: _Blob(
              color: const Color(0xFF34D399).withOpacity(0.3),
              size: 160,
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Container(width: size, height: size, color: color),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;
  const _GlassCard({required this.padding, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PlateBadge extends StatelessWidget {
  final String text;
  const _PlateBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(Icons.directions_car_rounded, color: Colors.white),
    );
  }
}

class _ActionTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionTextButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withOpacity(0.95),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 72, color: Colors.white30),
            const SizedBox(height: 14),
            const Text(
              "Belum ada data hasil scan",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: 0.85,
              child: Text(
                "Mulai dari halaman Scan untuk menangkap plat "
                "dan menyimpannya ke riwayat.",
                style: const TextStyle(color: Colors.white60, fontSize: 14.5),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
