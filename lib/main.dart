import 'package:face_recognition/module/home/home_page.dart';
import 'package:face_recognition/module/plat/plat_bloc.dart';
import 'package:face_recognition/service/yolo_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('plates');
  final yoloService = await YoloService.create(
    modelPath: 'assets/models/license_plate_detector_float16.tflite',
    inputSize: 640,
    scoreThreshold: 0.5,
  );
  runApp(MyApp(yoloService: yoloService));
}

class MyApp extends StatelessWidget {
  final YoloService yoloService;
  const MyApp({super.key, required this.yoloService});
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PlateBloc>(
          create: (_) => PlateBloc(yoloService: yoloService),
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
