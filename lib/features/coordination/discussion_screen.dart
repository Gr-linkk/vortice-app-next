import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'coordination_repository.dart';
import 'coordination_labels.dart';
import 'discussion_write_screen.dart';

class DiscussionScreen extends ConsumerStatefulWidget {
  const DiscussionScreen({
    super.key,
    required this.kind,
    required this.subjectId,
    this.focusPost,
  });
  final String kind, subjectId;
  final String? focusPost;
  @override
  ConsumerState<DiscussionScreen> createState() => _DiscussionScreenState();
}

class _DiscussionScreenState extends ConsumerState<DiscussionScreen> {
  late ThreadQuery _query = (
    subject: (kind: widget.kind, id: widget.subjectId),
    before: null,
    beforeId: null,
    focus: widget.focusPost,
  );
  final _pages = <ThreadQuery>[];
  void _refresh() {
    ref.invalidate(coordinationThreadProvider);
    ref.invalidate(assetHistoryProvider);
    ref.invalidate(notificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Conversación y relevo' : 'Discussion & handover'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ref
            .watch(coordinationThreadProvider(_query))
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => FleetError(error: error, onRetry: _refresh),
              data: (page) {
                final posts = coordinationRows(page['posts']);
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      page['title'] as String? ?? '',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(page['asset_name'] as String? ?? ''),
                    const SizedBox(height: 16),
                    Text(
                      es
                          ? 'Las notas del equipo son privadas para tu equipo. Las actualizaciones compartidas llegan a los participantes autorizados de ambos equipos.'
                          : 'Team notes stay within your team. Shared updates are visible to authorized participants from both teams.',
                    ),
                    const SizedBox(height: 16),
                    if (page['can_post'] == true)
                      FilledButton.icon(
                        icon: const Icon(Icons.add_comment_outlined),
                        label: Text(
                          es
                              ? 'Escribir nota o relevo'
                              : 'Write a note or handover',
                        ),
                        onPressed: () async {
                          final sent = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => DiscussionWriteScreen(
                                subject: _query.subject,
                                title: page['title'] as String? ?? '',
                                providerTeam: page['team'] == 'provider',
                              ),
                            ),
                          );
                          if (sent == true && mounted) {
                            setState(() {
                              _pages.clear();
                              _query = (
                                subject: _query.subject,
                                before: null,
                                beforeId: null,
                                focus: null,
                              );
                            });
                            _refresh();
                          }
                        },
                      )
                    else
                      Text(
                        es
                            ? 'Puedes leer el historial. No tienes permiso para publicar aquí.'
                            : 'History is available to read. You do not have permission to post here.',
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/history/assets/${page['asset_id']}'),
                      icon: const Icon(Icons.history),
                      label: Text(
                        es
                            ? 'Historial completo del activo'
                            : 'Full asset history',
                      ),
                    ),
                    if (_query.focus != null || _pages.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() {
                          _pages.clear();
                          _query = (
                            subject: _query.subject,
                            before: null,
                            beforeId: null,
                            focus: null,
                          );
                        }),
                        child: Text(
                          es
                              ? 'Ir a las notas más recientes'
                              : 'Go to newest notes',
                        ),
                      ),
                    if (posts.isEmpty)
                      FleetEmpty(
                        title: es ? 'Todavía no hay notas' : 'No notes yet',
                        message: es
                            ? 'Registra un hallazgo o prepara el próximo turno.'
                            : 'Record a finding or prepare the next shift.',
                      ),
                    for (final post in posts)
                      DiscussionPost(
                        post: post,
                        canPost: page['can_post'] == true,
                        highlighted: post['id'] == widget.focusPost,
                        onChanged: _refresh,
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        if (_pages.isNotEmpty)
                          OutlinedButton(
                            onPressed: () =>
                                setState(() => _query = _pages.removeLast()),
                            child: Text(es ? 'Más recientes' : 'Newer'),
                          ),
                        if (page['has_more'] == true)
                          FilledButton(
                            onPressed: () => setState(() {
                              _pages.add(_query);
                              final last = posts.last;
                              _query = (
                                subject: _query.subject,
                                before: last['created_at'] as String,
                                beforeId: last['id'] as String,
                                focus: null,
                              );
                            }),
                            child: Text(es ? 'Más antiguos' : 'Older'),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }
}

class DiscussionPost extends ConsumerStatefulWidget {
  const DiscussionPost({
    super.key,
    required this.post,
    required this.canPost,
    required this.onChanged,
    this.highlighted = false,
  });
  final Map<String, dynamic> post;
  final bool canPost, highlighted;
  final VoidCallback onChanged;
  @override
  ConsumerState<DiscussionPost> createState() => _DiscussionPostState();
}

class _DiscussionPostState extends ConsumerState<DiscussionPost> {
  bool _busy = false;
  Object? _error;
  Future<void> _acknowledge() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(coordinationRepositoryProvider)
          .acknowledge(widget.post['id'] as String);
      if (mounted) widget.onChanged();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context), post = widget.post;
    final user = ref.watch(profileProvider).valueOrNull?.id;
    final acknowledgements = coordinationRows(post['acknowledgements']);
    final handover = post['kind'] == 'handover';
    final shared = post['visibility'] == 'shared';
    return Card(
      margin: const EdgeInsets.only(top: 16),
      shape: widget.highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              handover
                  ? (es ? 'Relevo de turno' : 'Shift handover')
                  : (es ? 'Nota' : 'Note'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${post['author_name']} · ${fleetDate(context, DateTime.tryParse(post['created_at'] as String? ?? ''))}',
            ),
            const SizedBox(height: 8),
            Text(
              shared
                  ? (es ? 'Compartida entre equipos' : 'Shared across teams')
                  : post['team'] == 'provider'
                  ? (es ? 'Solo equipo del proveedor' : 'Provider team only')
                  : (es ? 'Solo equipo de la empresa' : 'Company team only'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            SelectableText(post['body'] as String? ?? ''),
            if (handover) ...[
              const SizedBox(height: 16),
              Text(
                '${es ? 'Aislamiento' : 'Isolation'}: ${coordinationLabel(isolationStates, post['isolation'] as String? ?? 'unknown', es)}',
              ),
              const SizedBox(height: 12),
              Text(
                es
                    ? 'Próximo turno / trabajo pendiente'
                    : 'Next shift / outstanding work',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              SelectableText(post['next_steps'] as String? ?? ''),
            ],
            if (coordinationRows(post['mentions']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${es ? 'Menciones' : 'Mentions'}: ${coordinationRows(post['mentions']).map((p) => p['name']).join(', ')}',
                ),
              ),
            for (final file in coordinationRows(post['attachments']))
              CoordinationPhoto(
                path: file['path'] as String,
                name: file['name'] as String? ?? '',
              ),
            if (acknowledgements.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  '${es ? 'Confirmado por' : 'Acknowledged by'}: ${acknowledgements.map((a) => '${a['name']} (${fleetDate(context, DateTime.tryParse(a['created_at'] as String? ?? ''))})').join(', ')}',
                ),
              ),
            if (_error != null)
              FleetError(error: _error!, onRetry: _acknowledge),
            if (handover &&
                widget.canPost &&
                post['author_id'] != user &&
                !acknowledgements.any((a) => a['user_id'] == user))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _acknowledge,
                  icon: const Icon(Icons.done_all),
                  label: Text(
                    _busy
                        ? (es ? 'Guardando…' : 'Saving…')
                        : (es
                              ? 'Confirmar recepción del relevo'
                              : 'Acknowledge handover'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CoordinationPhoto extends ConsumerWidget {
  const CoordinationPhoto({super.key, required this.path, required this.name});
  final String path, name;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: ref
        .watch(coordinationPhotoProvider(path))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => FleetError(
            error: error,
            onRetry: () => ref.invalidate(coordinationPhotoProvider(path)),
          ),
          data: (url) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: name,
                button: true,
                child: InkWell(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => Dialog(
                      child: SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: IconButton(
                                tooltip: fleetText(ctx, 'Close', 'Cerrar'),
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                            Flexible(
                              child: InteractiveViewer(
                                child: Image.network(
                                  url,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      height: 180,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => TextButton.icon(
                        onPressed: () =>
                            ref.invalidate(coordinationPhotoProvider(path)),
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          fleetText(context, 'Reload photo', 'Recargar foto'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(name, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
  );
}
