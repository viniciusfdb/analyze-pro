import 'package:shared_preferences/shared_preferences.dart';

/// VALIDA EM CACHE QUANDO FOI A ÚLTIMA VERIFICAÇÃO // controle de acesso 7 dias days:7 se estiver 7 segundos é apenas para teste
const Duration validationCacheDuration = Duration(days: 7);

Future<DateTime?> getLastValidationTime() async {
  final prefs = await SharedPreferences.getInstance();
  final ts = prefs.getInt("lastValidationTimestamp");
  if (ts != null) {
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }
  return null;
}

Future<bool> getCachedAccessAuthorized() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool("accessAuthorized") ?? false;
}

Future<void> updateValidationResult(bool authorized) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool("accessAuthorized", authorized);
  int now = DateTime.now().millisecondsSinceEpoch;
  await prefs.setInt("lastValidationTimestamp", now);
  print('Cache atualizado: accessAuthorized = $authorized, lastValidationTimestamp = $now');
}

const Duration maxAccessDuration = Duration(days: 37);

Future<void> saveAccessGrantedAt(DateTime grantedAt) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt("accessGrantedAt", grantedAt.millisecondsSinceEpoch);
}

Future<DateTime?> getAccessGrantedAt() async {
  final prefs = await SharedPreferences.getInstance();
  final ts = prefs.getInt("accessGrantedAt");
  if (ts != null) {
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }
  return null;
}

Future<bool> isAccessStillWithinAllowedPeriod() async {
  final grantedAt = await getAccessGrantedAt();
  if (grantedAt == null) return false;
  return DateTime.now().isBefore(grantedAt.add(maxAccessDuration));
}
