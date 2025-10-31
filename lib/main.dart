import 'package:face_recognition/module/home/home_page.dart';
import 'package:face_recognition/module/plat/plat_bloc.dart';
import 'package:face_recognition/service/ocr_isolate_pool.dart';
import 'package:face_recognition/service/yolo_isolate_pool.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('plates');

  final modelBytes = await rootBundle.load(
    'assets/models/license_plate_detector_float16.tflite',
  );
  final bytes = modelBytes.buffer.asUint8List();

  final yoloPool = YoloIsolatePool();
  await yoloPool.init(bytes, 640, 0.5);

  final ocrPool = OcrIsolatePool();
  ocrPool.start();

  runApp(MyApp(yoloPool: yoloPool, ocrPool: ocrPool));
}

class MyApp extends StatelessWidget {
  final YoloIsolatePool yoloPool;
  final OcrIsolatePool ocrPool;

  const MyApp({super.key, required this.yoloPool, required this.ocrPool});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PlateBloc>(
          create: (_) => PlateBloc(yoloPool: yoloPool, ocrPool: ocrPool),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Plat License Scanner',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0E1621),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
