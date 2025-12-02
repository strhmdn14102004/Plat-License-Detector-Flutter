// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:vehicle_identification_number/module/home/view_data_page.dart';
import 'package:vehicle_identification_number/module/plat%20capture/plat_capture_page.dart';
import 'package:vehicle_identification_number/module/plat_capture_mlkit/plat_capture_mlkit_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late final AnimationController _glowCtl;
  late final Animation<double> _glowAnim;

  bool isOnline = true;

  @override
  void initState() {
    super.initState();
    Connectivity().onConnectivityChanged.listen((_) async {
      final real = await _checkInternet();
      setState(() => isOnline = real);
    });

    _glowCtl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(
      begin: 0.7,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _glowCtl, curve: Curves.easeInOut));
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 2));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _glowCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;
    final accelText = isIOS ? "Metal GPU" : "Android NNAPI";

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AnimatedBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  FadeTransition(
                    opacity: _glowAnim,
                    child: const Text(
                      "License Plate\nScanner",
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        letterSpacing: -0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Vehicle Plate Detection with AI",
                    style: TextStyle(
                      fontSize: 15.5,
                      color: Colors.white70,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 24),

                  _FeatureChips(),
                  const SizedBox(height: 28),

                  _GlassCard(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.memory_rounded,
                          color: Colors.tealAccent,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Akselerasi $accelText diaktifkan — gunakan cahaya cukup dan posisi stabil untuk akurasi optimal.",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13.8,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  Opacity(
                    opacity: isOnline ? 1 : 0.45,
                    child: _MainButton(
                      title: "Scan dengan google gemini",
                      subtitle: "Scan menggunakan Google Gemini (ONLINE)",
                      icon: Icons.camera_front_rounded,
                      color1: const Color(0xFFF59E0B),
                      color2: const Color(0xFFFBBF24),
                      onTap: () {
                        if (!isOnline) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "⚠ Tidak ada internet — Gemini membutuhkan koneksi!",
                              ),
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PlateCameraCapturePage(),
                          ),
                        );
                      },
                    ),
                  ),
                  // const SizedBox(height: 18),

                  // _MainButton(
                  //   title: "Scan secara realtime",
                  //   subtitle:
                  //       "Scan secara realtime menggunakan Google ML Kit (OFFLINE)",
                  //   icon: Icons.adf_scanner_rounded,
                  //   color1: const Color.fromARGB(255, 172, 172, 172),
                  //   color2: const Color.fromARGB(255, 6, 5, 3),
                  //   onTap: () => Navigator.push(
                  //     context,
                  //     MaterialPageRoute(
                  //       builder: (_) => const PlateRealtimePage(),
                  //     ),
                  //   ),
                  // ),
                  const SizedBox(height: 18),

                  _MainButton(
                    title: "Scan dengan model local",
                    subtitle: "Scan menggunakan Google ML Kit (OFFLINE)",
                    icon: Icons.camera_enhance_rounded,
                    color1: const Color.fromARGB(255, 157, 144, 122),
                    color2: const Color.fromARGB(255, 114, 102, 72),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PlateMlkitCapturePage(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  _MainButton(
                    title: "Lihat Riwayat",
                    subtitle: "Hasil deteksi & OCR tersimpan",
                    icon: Icons.list_alt_rounded,
                    color1: const Color(0xFF3B82F6),
                    color2: const Color(0xFF60A5FA),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ViewDataPage()),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground();
  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _moveAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
    _moveAnim = Tween<double>(
      begin: -80,
      end: 80,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _moveAnim,
      builder: (context, _) {
        return Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              top: _moveAnim.value,
              left: _moveAnim.value * -1.2,
              child: _Blob(
                color: const Color(0xFF14B8A6).withOpacity(0.25),
                size: 220,
              ),
            ),
            Positioned(
              bottom: -_moveAnim.value,
              right: _moveAnim.value,
              child: _Blob(
                color: const Color(0xFF6366F1).withOpacity(0.28),
                size: 200,
              ),
            ),
          ],
        );
      },
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
        filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color),
        ),
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
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FeatureChips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      {'icon': Icons.flash_on_rounded, 'label': 'Realtime'},
      {'icon': Icons.document_scanner_rounded, 'label': 'Yolo v11'},
      {'icon': Icons.text_fields_rounded, 'label': 'Google ML Kit'},
      {'icon': Icons.memory_rounded, 'label': 'NNAPI / Metal'},
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items
          .map(
            (e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(e['icon'] as IconData, color: Colors.white, size: 15),
                  const SizedBox(width: 5),
                  Text(
                    e['label'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MainButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color1;
  final Color color2;
  final VoidCallback onTap;

  const _MainButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color1,
    required this.color2,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 140,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color1, color2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: color2.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: Colors.white, size: 34),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 28,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
