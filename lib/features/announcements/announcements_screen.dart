import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/coordination/coordination_repository.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'announcements_repository.dart';
import 'announcement_write_screen.dart';

class OrganizationAnnouncementsScreen extends ConsumerStatefulWidget {
  const OrganizationAnnouncementsScreen({super.key});
  @override
  ConsumerState<OrganizationAnnouncementsScreen> createState() =>
      _OrganizationAnnouncementsScreenState();
}

class _OrganizationAnnouncementsScreenState
    extends ConsumerState<OrganizationAnnouncementsScreen> {
  AnnouncementQuery _query = firstAnnouncementPage;
  final _pages = <AnnouncementQuery>[];
  void _refresh() {
    ref.invalidate(announcementsFeedProvider);
    ref.invalidate(notificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          es ? 'Anuncios de la organización' : 'Organization announcements',
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: es ? 'Actualizar' : 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ref
          .watch(announcementsFeedProvider(_query))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AppErrorState(error: error, onRetry: _refresh),
            data: (data) {
              final posts = coordinationRows(data['posts']);
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    data['organization_name'] as String? ?? '',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${data['unread_count'] ?? 0} ${es ? 'sin leer' : 'unread'}',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.groups_outlined),
                      label: Text(
                        '${data['participant_count'] ?? 0} ${es ? 'participantes' : 'participants'}',
                      ),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(es ? 'Participantes' : 'Participants'),
                          content: SizedBox(
                            width: 400,
                            height: 400,
                            child: ListView(
                              children: [
                                for (final member in coordinationRows(
                                  data['participants'],
                                ))
                                  ListTile(
                                    title: Text(
                                      member['name'] as String? ?? '',
                                    ),
                                  ),
                                if ((data['participant_count'] as num? ?? 0) >
                                    coordinationRows(
                                      data['participants'],
                                    ).length)
                                  Text(
                                    es
                                        ? 'Se muestran los primeros 200 participantes.'
                                        : 'Showing the first 200 participants.',
                                  ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(es ? 'Cerrar' : 'Close'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (data['can_publish'] == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: FilledButton.icon(
                        icon: const Icon(Icons.campaign_outlined),
                        label: Text(
                          es ? 'Publicar anuncio' : 'Publish announcement',
                        ),
                        onPressed: () async {
                          final sent = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AnnouncementWriteScreen(
                                organization: data['organization_id'] as String,
                                organizationName:
                                    data['organization_name'] as String? ?? '',
                              ),
                            ),
                          );
                          if (sent == true && mounted) {
                            setState(() {
                              _query = firstAnnouncementPage;
                              _pages.clear();
                            });
                            _refresh();
                          }
                        },
                      ),
                    ),
                  if (posts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        es ? 'Aún no hay anuncios.' : 'No announcements yet.',
                      ),
                    ),
                  for (final post in posts)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          post['read_at'] == null
                              ? Icons.mark_email_unread_outlined
                              : Icons.campaign_outlined,
                          semanticLabel: post['read_at'] == null
                              ? (es ? 'Sin leer' : 'Unread')
                              : null,
                        ),
                        title: Text(
                          post['title'] as String? ?? '',
                          style: TextStyle(
                            fontWeight: post['read_at'] == null
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post['body'] as String? ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${post['author_name']} · ${fleetDate(context, DateTime.tryParse(post['created_at'] as String? ?? ''))}',
                            ),
                          ],
                        ),
                        onTap: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrganizationAnnouncementDetailScreen(
                                    id: post['id'] as String,
                                  ),
                            ),
                          );
                          if (mounted) _refresh();
                        },
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (_pages.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              setState(() => _query = _pages.removeLast()),
                          child: Text(es ? 'Más recientes' : 'Newer'),
                        ),
                      if (data['has_more'] == true && posts.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() {
                            _pages.add(_query);
                            _query = (
                              before: posts.last['created_at'] as String,
                              beforeId: posts.last['id'] as String,
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
    );
  }
}

class OrganizationAnnouncementDetailScreen extends ConsumerStatefulWidget {
  const OrganizationAnnouncementDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<OrganizationAnnouncementDetailScreen> createState() =>
      _OrganizationAnnouncementDetailScreenState();
}

class _OrganizationAnnouncementDetailScreenState
    extends ConsumerState<OrganizationAnnouncementDetailScreen> {
  bool _marking = false, _marked = false;
  AnnouncementsRepository? _readRepository;
  Future<void> _markRead() async {
    if (_marking || _marked) return;
    _marking = true;
    final repository = _readRepository!;
    try {
      await repository.markRead(widget.id);
      if (mounted && identical(repository, _readRepository)) {
        _marked = true;
        ref.invalidate(announcementsFeedProvider);
        ref.invalidate(notificationsProvider);
      }
    } catch (_) {
      /* Keep unread while offline; reopening retries. */
    } finally {
      if (identical(repository, _readRepository)) _marking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(announcementsRepositoryProvider);
    if (!identical(repository, _readRepository)) {
      _readRepository = repository;
      _marked = false;
      _marking = false;
    }
    final es = isSpanish(context);
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Anuncio' : 'Announcement')),
      body: ref
          .watch(announcementProvider(widget.id))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AppErrorState(
              error: error,
              onRetry: () => ref.invalidate(announcementProvider(widget.id)),
            ),
            data: (post) {
              if (!_marked && !_marking) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _markRead();
                });
              }
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    post['organization_name'] as String? ?? '',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    post['title'] as String? ?? '',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${post['author_name']} · ${fleetDate(context, DateTime.tryParse(post['created_at'] as String? ?? ''))}',
                  ),
                  const SizedBox(height: 24),
                  SelectableText(post['body'] as String? ?? ''),
                  for (final photo in coordinationRows(post['attachments']))
                    AnnouncementPhoto(
                      path: photo['path'] as String,
                      name: photo['name'] as String? ?? '',
                    ),
                ],
              );
            },
          ),
    );
  }
}

class AnnouncementPhoto extends ConsumerWidget {
  const AnnouncementPhoto({super.key, required this.path, required this.name});
  final String path, name;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: ref
        .watch(announcementPhotoProvider(path))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => TextButton(
            onPressed: () => ref.invalidate(announcementPhotoProvider(path)),
            child: Text(isSpanish(context) ? 'Reintentar foto' : 'Retry photo'),
          ),
          data: (bytes) => Column(
            children: [
              Text(name),
              InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined),
                ),
              ),
            ],
          ),
        ),
  );
}
