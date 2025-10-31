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
        elevation: 0,
        centerTitle: true,

        title: const Text(
          "Riwayat Hasil Scan",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Stack(
        children: [
          const _AnimatedBackground(),
          SafeArea(
            child: ValueListenableBuilder(
              valueListenable: _box.listenable(),
              builder: (context, Box box, _) {
                final List<String> data = List<String>.from(
                  box.get('data', defaultValue: []),
                );

                if (data.isEmpty) return const _EmptyState();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                      child: _GlassCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.history_rounded,
                              color: Colors.tealAccent,
                              size: 26,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Total hasil scan: ${data.length}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _ActionButton(
                              icon: Icons.copy_all_rounded,
                              label: "Salin semua",
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: data.join('\n\n')),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        itemCount: data.length,
                        itemBuilder: (context, i) {
                          final raw = data[i];
                          final parts = raw.split('\n');
                          final plate = parts.isNotEmpty ? parts[0] : raw;
                          final time = parts.length > 1 ? parts[1] : '';

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Dismissible(
                              key: ValueKey("plate_${i}_$raw"),
                              direction: DismissDirection.endToStart,
                              background: _deleteBg(),
                              onDismissed: (_) async {
                                final updated = List<String>.from(data);
                                updated.removeAt(i);
                                await box.put('data', updated);
                                _toast(context, "Item dihapus");
                              },
                              child: _GlassCard(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _PlateBadge(plate: plate),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            plate,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.schedule_rounded,
                                                size: 14,
                                                color: Colors.white70,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                time.isEmpty ? "-" : time,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      tooltip: "Salin",
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        color: Colors.white70,
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
                                        final updated = List<String>.from(data);
                                        updated.removeAt(i);
                                        await box.put('data', updated);
                                        _toast(context, "Dihapus");
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
          final List<String> data = List<String>.from(
            box.get('data', defaultValue: []),
          );
          if (data.isEmpty) return const SizedBox.shrink();

          return _DeleteAllButton(
            onConfirm: () async {
              final ok = await _confirm(
                context,
                title: "Hapus semua data?",
                subtitle:
                    "Tindakan ini tidak dapat dibatalkan. Semua hasil scan akan hilang.",
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
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black.withOpacity(0.8),
      ),
    );
  }

  Widget _deleteBg() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFE11D48).withOpacity(0.9),
      borderRadius: BorderRadius.circular(18),
    ),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    child: const Icon(
      Icons.delete_forever_rounded,
      color: Colors.white,
      size: 30,
    ),
  );
}

class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground();

  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0B1220), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -50 + 50 * _controller.value,
            left: -60,
            child: _Blob(
              color: const Color(0xFF22D3EE).withOpacity(0.35),
              size: 200,
            ),
          ),
          Positioned(
            bottom: -30 - 30 * _controller.value,
            right: -40,
            child: _Blob(
              color: const Color(0xFF34D399).withOpacity(0.3),
              size: 180,
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
  Widget build(BuildContext context) => ClipOval(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: Container(width: size, height: size, color: color),
    ),
  );
}

class _GlassCard extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;
  const _GlassCard({required this.padding, required this.child});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: child,
      ),
    ),
  );
}

class _PlateBadge extends StatelessWidget {
  final String plate;
  const _PlateBadge({required this.plate});

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF16A34A), Color(0xFF4ADE80)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF16A34A).withOpacity(0.3),
          blurRadius: 15,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: const Icon(
      Icons.directions_car_rounded,
      color: Colors.white,
      size: 26,
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 18, color: Colors.white),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}

class _DeleteAllButton extends StatelessWidget {
  final VoidCallback onConfirm;
  const _DeleteAllButton({required this.onConfirm});

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    backgroundColor: Colors.transparent,
    elevation: 0,
    onPressed: onConfirm,
    label: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE11D48), Color(0xFFFB7185)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE11D48).withOpacity(0.4),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_forever_rounded, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text(
            "Hapus Semua",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_rounded, size: 80, color: Colors.white30),
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
          const SizedBox(height: 10),
          Opacity(
            opacity: 0.85,
            child: Text(
              "Mulai dari halaman scan untuk menangkap plat kendaraan dan menyimpannya ke riwayat.",
              style: const TextStyle(color: Colors.white60, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );
}
