import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';

String membershipError(BuildContext context, Object error) {
  final message = error is PostgrestException ? error.message : '';
  const translations = <String, (String, String, String)>{
    'Invitation not found': (
      'Check the invitation code and try again.',
      'Revisa el código de invitación e inténtalo de nuevo.',
      'Vérifiez le code d’invitation et réessayez.',
    ),
    'Invitation expired': (
      'This invitation expired. Ask your administrator for a new code.',
      'La invitación ha vencido. Pide otro código a tu administrador.',
      'Cette invitation a expiré. Demandez un nouveau code à votre administrateur.',
    ),
    'Invitation revoked': (
      'This invitation was revoked. Ask your administrator for a new code.',
      'La invitación fue revocada. Pide otro código a tu administrador.',
      'Cette invitation a été révoquée. Demandez un nouveau code à votre administrateur.',
    ),
    'Invitation already used': (
      'This invitation was already used. Ask for your own invitation.',
      'La invitación ya fue utilizada. Pide una invitación para ti.',
      'Cette invitation a déjà été utilisée. Demandez une invitation personnelle.',
    ),
    'Use the email or phone named in this invitation': (
      'Sign in with the email or phone named in this invitation.',
      'Accede con el correo o teléfono de esta invitación.',
      'Connectez-vous avec l’adresse courriel ou le numéro de téléphone indiqué dans cette invitation.',
    ),
    'You already belong to this company': (
      'You already belong to this company. Choose it from Your company.',
      'Ya perteneces a esta empresa. Selecciónala en Tu empresa.',
      'Vous faites déjà partie de cette entreprise. Sélectionnez-la dans « Votre entreprise ».',
    ),
    'Keep at least one active Company Owner': (
      'Keep at least one active Company Owner. Add another owner before removing this one.',
      'Debe quedar un propietario activo. Añade otro antes de quitar a este.',
      'Au moins un propriétaire doit rester actif. Ajoutez-en un autre avant de retirer celui-ci.',
    ),
    'Team administration required': (
      'Your access changed. Ask a Company Owner for team administration permission.',
      'Tu acceso ha cambiado. Pide permiso de administración a un propietario.',
      'Votre accès a changé. Demandez à un propriétaire l’autorisation d’administrer l’équipe.',
    ),
    'Only a Company Owner can delegate permissions or change an owner': (
      'Only a Company Owner can change these permissions or another owner.',
      'Solo un propietario puede cambiar estos permisos u otro propietario.',
      'Seul un propriétaire peut modifier ces autorisations ou les accès d’un autre propriétaire.',
    ),
    'Inviter no longer has team access': (
      'Your inviter no longer has access. Ask a current administrator for a new code.',
      'Quien te invitó ya no tiene acceso. Pide otro código a un administrador actual.',
      'La personne qui vous a invité n’a plus accès. Demandez un nouveau code à un administrateur actuel.',
    ),
    'Inviter can no longer delegate these permissions': (
      'Your inviter can no longer grant these permissions. Ask a Company Owner for a new code.',
      'Quien te invitó ya no puede conceder estos permisos. Pide otro código a un propietario.',
      'La personne qui vous a invité ne peut plus accorder ces autorisations. Demandez un nouveau code à un propriétaire.',
    ),
  };
  final translated = translations[message];
  if (translated != null) {
    return localizedText(context, translated.$1, translated.$2, translated.$3);
  }
  return friendlyError(context, error);
}
