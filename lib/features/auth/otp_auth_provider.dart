import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';

enum VerificationChannel { email, phone }

// Provider setup is deferred for this internal build. Enable a channel only
// after its hosted provider and code template have been configured and checked.
final otpDeliveryChannelsProvider = Provider<Set<VerificationChannel>>((ref) => {
  if (const bool.fromEnvironment('VORTICE_EMAIL_OTP_ENABLED')) VerificationChannel.email,
  if (const bool.fromEnvironment('VORTICE_SMS_OTP_ENABLED')) VerificationChannel.phone,
});

class OtpContact {
  const OtpContact(this.channel, this.value);
  final VerificationChannel channel;
  final String value;
  static OtpContact? parse(VerificationChannel channel, String input) {
    final value = input.trim();
    if (channel == VerificationChannel.email) {
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) return null;
      return OtpContact(channel, value.toLowerCase());
    }
    final phone = value.replaceAll(RegExp(r'[\s()\-]'), '');
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) return null;
    return OtpContact(channel, phone);
  }
}

class OtpAuthRepository {
  Future<void> send(OtpContact contact, {required String language}) async {
    await supabase.auth.signInWithOtp(
      email: contact.channel == VerificationChannel.email
          ? contact.value
          : null,
      phone: contact.channel == VerificationChannel.phone
          ? contact.value
          : null,
      shouldCreateUser: true,
      data: {'onboarding_v2': true, 'preferred_language': language},
    );
  }

  Future<void> verify(OtpContact contact, String code) async {
    await supabase.auth.verifyOTP(
      email: contact.channel == VerificationChannel.email
          ? contact.value
          : null,
      phone: contact.channel == VerificationChannel.phone
          ? contact.value
          : null,
      token: code.trim(),
      type: contact.channel == VerificationChannel.email
          ? OtpType.email
          : OtpType.sms,
    );
  }
}

final otpAuthRepositoryProvider = Provider<OtpAuthRepository>(
  (ref) => OtpAuthRepository(),
);
