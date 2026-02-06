import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/app_strings.dart';
import 'presentation/screens/home_screen.dart';
import 'services/background_ble_service.dart';
import 'services/supabase_service.dart';

/// 헤드리스 백그라운드 엔트리포인트
///
/// 부팅 시 BleForegroundService가 FlutterEngine을 생성하여
/// 이 함수를 실행합니다. UI 없이 BLE 로직만 동작합니다.
@pragma('vm:entry-point')
void backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('>>> [backgroundMain] 헤드리스 BLE 서비스 시작');

  // Supabase 초기화 (측정 데이터 즉시 저장용)
  await SupabaseMeasurementService.instance.initialize();

  try {
    // 사용자 프로필 설정 (체성분 계산용)
    // TODO: SharedPreferences 등에서 저장된 프로필 로드
    BackgroundBleService.instance.setUserProfile(
      age: 45,
      height: 178.0,
      isMale: true,
    );

    await BackgroundBleService.instance.start();
    debugPrint('>>> [backgroundMain] BLE 서비스 시작 완료');
  } catch (e) {
    debugPrint('>>> [backgroundMain] BLE 서비스 시작 실패: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase 초기화 (측정 데이터 즉시 저장용)
  await SupabaseMeasurementService.instance.initialize();

  // Hive 초기화 (로컬 캐시용)
  await Hive.initFlutter();

  // 시스템 UI 설정.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // 화면 방향 고정 (180도 뒤집힌 세로 모드 - 충전 포트 위쪽)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: HealthMonitorApp()));

  // 앱 시작 후 백그라운드 BLE 서비스 자동 시작
  _initBackgroundService();
}

/// 백그라운드 BLE 서비스 자동 시작
Future<void> _initBackgroundService() async {
  // 잠시 대기 후 서비스 시작 (UI 렌더링 완료 대기)
  await Future.delayed(const Duration(seconds: 2));

  try {
    // 사용자 프로필 설정 (체성분 계산용)
    // TODO: 설정 화면에서 사용자가 입력한 값 사용
    BackgroundBleService.instance.setUserProfile(
      age: 45,
      height: 178.0,
      isMale: true,
    );

    await BackgroundBleService.instance.start();
    debugPrint('>>> 백그라운드 BLE 서비스 자동 시작됨');
  } catch (e) {
    debugPrint('>>> 백그라운드 BLE 서비스 시작 실패: $e');
  }
}

class HealthMonitorApp extends StatelessWidget {
  const HealthMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }

  ThemeData _buildLightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2196F3),
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Pretendard',
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2196F3),
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Pretendard',
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
