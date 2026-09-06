import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';

class FormBackButton extends StatelessWidget {
  const FormBackButton({super.key, required this.fallbackRoute});
  final String fallbackRoute;
  @override
  Widget build(BuildContext context) => BackButton(
    onPressed: () async {
      final handled = await Navigator.of(context).maybePop();
      if (!handled && context.mounted) context.go(fallbackRoute);
    },
  );
}

/// Used for forms without persistent drafts. Saved report drafts keep their own
/// persistence flow instead of showing a misleading discard prompt.
class UnsavedFormGuard extends StatefulWidget {
  const UnsavedFormGuard({
    super.key,
    required this.child,
    required this.isDirty,
    required this.controllers,
    required this.fallbackRoute,
    this.busy = false,
  });
  final Widget child;
  final bool Function() isDirty;
  final List<TextEditingController> controllers;
  final String fallbackRoute;
  final bool busy;
  @override
  State<UnsavedFormGuard> createState() => _UnsavedFormGuardState();
}

class _UnsavedFormGuardState extends State<UnsavedFormGuard> {
  bool _leaving = false, _asking = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(widget.controllers),
    builder: (context, _) => PopScope(
      canPop: _leaving || (!widget.busy && !widget.isDirty()),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _asking || widget.busy) return;
        _asking = true;
        final es = isSpanish(context);
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(es ? '¿Descartar cambios?' : 'Discard changes?'),
            content: Text(
              es
                  ? 'Todavía no se han enviado. Puedes seguir editando.'
                  : 'Your changes have not been sent. You can keep editing.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(es ? 'Seguir editando' : 'Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(es ? 'Descartar' : 'Discard'),
              ),
            ],
          ),
        );
        _asking = false;
        if (!mounted || discard != true) return;
        setState(() => _leaving = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!context.mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(result);
        } else {
          context.go(widget.fallbackRoute);
        }
      },
      child: widget.child,
    ),
  );
}
