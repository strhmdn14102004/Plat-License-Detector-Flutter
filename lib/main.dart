import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vehicle_identification_number/module/home/home_page.dart';
import 'package:vehicle_identification_number/module/plat%20capture/plat_capture_bloc.dart';
import 'package:vehicle_identification_number/module/plat%20gallery/plat_gallery_bloc.dart';
import 'package:vehicle_identification_number/module/plat%20gallery/plat_gallery_page.dart';
import 'package:vehicle_identification_number/module/plat%20realtime/plat_realtime_bloc.dart';
import 'package:vehicle_identification_number/service/gemini_ocr_service.dart';
import 'package:vehicle_identification_number/service/yolo_isolate_pool.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('plates');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final modelBytes = await rootBundle.load(
    'assets/models/license_plate_detector_float16.tflite',
  );
  final bytes = modelBytes.buffer.asUint8List();

  final yoloPool = YoloIsolatePool();
  await yoloPool.init(bytes, 640, 0.5);

  const geminiApiKey = 'AIzaSyAaXIBhfrhi2lwwiekFdTsdKt-8RWVCZGI';
  final geminiOcr = GeminiOcrService(apiKey: geminiApiKey);

  runApp(MyApp(yoloPool: yoloPool, geminiOcr: geminiOcr));
}

class MyApp extends StatelessWidget {
  final YoloIsolatePool yoloPool;
  final GeminiOcrService geminiOcr;

  const MyApp({super.key, required this.yoloPool, required this.geminiOcr});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (BuildContext context) =>
              PlateRealtimeBloc(yoloPool: yoloPool, geminiOcr: geminiOcr),
        ),
        BlocProvider(
          create: (BuildContext context) =>
              PlateCameraCaptureBloc(yolo: yoloPool, geminiOcr: geminiOcr),
        ),
        BlocProvider(
          create: (_) => PlateGalleryBloc(yolo: yoloPool, geminiOcr: geminiOcr),
          child: const PlateGalleryPage(),
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
