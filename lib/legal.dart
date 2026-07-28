import 'package:shared_preferences/shared_preferences.dart';

const privacyPolicyUrl = 'https://lumen-launch.vercel.app/privacy';
const supportEmail = 'talhaashraf81@gmail.com';

class LegalAcceptance {
  static const _key = 'lumen_legal_acceptance_v1';

  static Future<bool> isAccepted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key) ?? false;
  }

  static Future<void> accept() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, true);
  }
}
