/// 한국어 문자열 상수
class KoreanStrings {
  KoreanStrings._();

  // ============================================================
  // 앱 일반
  // ============================================================

  static const appName = '건강 측정';
  static const appDescription = 'BLE 건강 기기 데이터 수집';

  // ============================================================
  // 탭 / 네비게이션
  // ============================================================

  static const tabHome = '홈';
  static const tabDevices = '기기';
  static const tabHistory = '기록';
  static const tabSettings = '설정';

  // ============================================================
  // 기기 관련
  // ============================================================

  static const deviceScale = '체중계';
  static const deviceBloodPressure = '혈압계';
  static const deviceGlucose = '혈당계';

  static const deviceXiaomiScale = '샤오미 체중계';
  static const deviceIHealthBP = 'iHealth 혈압계';
  static const deviceIHealthGlucose = 'iHealth 혈당계';

  static const deviceConnected = '연결됨';
  static const deviceDisconnected = '연결 끊김';
  static const deviceConnecting = '연결 중...';
  static const deviceSearching = '검색 중...';
  static const deviceNotFound = '기기를 찾을 수 없습니다';

  static const scanForDevices = '기기 검색';
  static const stopScan = '검색 중지';
  static const connectDevice = '연결';
  static const disconnectDevice = '연결 해제';

  // ============================================================
  // 측정 데이터 라벨
  // ============================================================

  // 체중계
  static const labelWeight = '체중';
  static const labelBmi = 'BMI';
  static const labelBodyFat = '체지방률';
  static const labelMuscleMass = '근육량';
  static const labelWaterPercentage = '체수분';
  static const labelBoneMass = '골격량';
  static const labelVisceralFat = '내장지방';
  static const labelBasalMetabolism = '기초대사량';
  static const labelMetabolicAge = '대사 연령';
  static const labelProteinPercentage = '단백질';

  // 혈압계
  static const labelSystolic = '수축기';
  static const labelDiastolic = '이완기';
  static const labelPulse = '맥박';
  static const labelIrregularPulse = '불규칙 맥박';
  static const labelMeanArterialPressure = '평균 동맥압';

  // 혈당계
  static const labelGlucose = '혈당';
  static const labelMealContext = '식사 상태';
  static const labelFasting = '공복';
  static const labelPostprandial = '식후';
  static const labelCasual = '무관';

  // ============================================================
  // 단위
  // ============================================================

  static const unitKg = 'kg';
  static const unitLb = 'lb';
  static const unitPercent = '%';
  static const unitKcal = 'kcal';
  static const unitMmHg = 'mmHg';
  static const unitBpm = 'bpm';
  static const unitMgDl = 'mg/dL';
  static const unitMmolL = 'mmol/L';
  static const unitYears = '세';

  // ============================================================
  // 상태 메시지
  // ============================================================

  static const statusReady = '측정 준비';
  static const statusMeasuring = '측정 중...';
  static const statusComplete = '측정 완료';
  static const statusFailed = '측정 실패';
  static const statusSyncing = '동기화 중...';
  static const statusSynced = '동기화 완료';
  static const statusOffline = '오프라인';

  // ============================================================
  // 에러 메시지
  // ============================================================

  static const errorBleDisabled = '블루투스가 꺼져 있습니다. 설정에서 블루투스를 켜주세요.';
  static const errorBleNotSupported = '이 기기는 블루투스 LE를 지원하지 않습니다.';
  static const errorLocationPermission = '위치 권한이 필요합니다. 설정에서 권한을 허용해주세요.';
  static const errorBluetoothPermission = '블루투스 권한이 필요합니다. 설정에서 권한을 허용해주세요.';
  static const errorConnectionTimeout = '연결 시간이 초과되었습니다. 다시 시도해주세요.';
  static const errorConnectionFailed = '연결에 실패했습니다. 기기가 켜져 있는지 확인해주세요.';
  static const errorDeviceNotFound = '기기를 찾을 수 없습니다. 기기가 켜져 있고 가까이 있는지 확인해주세요.';
  static const errorMeasurementFailed = '측정에 실패했습니다. 다시 시도해주세요.';
  static const errorDataParseFailed = '데이터 파싱에 실패했습니다.';
  static const errorNetworkFailed = '네트워크 오류가 발생했습니다.';
  static const errorUnknown = '알 수 없는 오류가 발생했습니다.';

  // ============================================================
  // 버튼 / 액션
  // ============================================================

  static const actionRetry = '다시 시도';
  static const actionCancel = '취소';
  static const actionConfirm = '확인';
  static const actionSave = '저장';
  static const actionDelete = '삭제';
  static const actionSync = '동기화';
  static const actionOpenSettings = '설정 열기';
  static const actionGrantPermission = '권한 허용';

  // ============================================================
  // 권한 요청 메시지
  // ============================================================

  static const permissionBluetoothTitle = '블루투스 권한';
  static const permissionBluetoothMessage = '건강 기기와 연결하기 위해 블루투스 권한이 필요합니다.';
  static const permissionLocationTitle = '위치 권한';
  static const permissionLocationMessage = 'BLE 기기를 검색하기 위해 위치 권한이 필요합니다.';

  // ============================================================
  // 화면 제목
  // ============================================================

  static const screenHomeTitle = '대시보드';
  static const screenDevicesTitle = '기기 관리';
  static const screenScanTitle = '기기 검색';
  static const screenHistoryTitle = '측정 기록';
  static const screenSettingsTitle = '설정';
  static const screenDetailTitle = '상세 정보';

  // ============================================================
  // 빈 상태 메시지
  // ============================================================

  static const emptyDevices = '연결된 기기가 없습니다.\n기기 검색 버튼을 눌러 기기를 추가하세요.';
  static const emptyHistory = '측정 기록이 없습니다.\n기기를 연결하고 측정을 시작하세요.';
  static const emptySearchResults = '검색된 기기가 없습니다.\n기기가 켜져 있는지 확인하세요.';

  // ============================================================
  // 시간 관련
  // ============================================================

  static const today = '오늘';
  static const yesterday = '어제';
  static const lastMeasurement = '최근 측정';
  static const measurementTime = '측정 시간';
}
